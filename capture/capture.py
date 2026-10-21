#!/usr/bin/env python3
"""
Capture proxy for the php-Honeypot (stdlib only, Python 3.11+).

Sits in front of the deliberately vulnerable shop container and
  * stores the complete RAW request bytes (captures/<sha256>.bin) before anything parses them
  * appends one JSON line per request to logs/events.jsonl with tags, fingerprints, IOCs and timings
  * forwards the request to UPSTREAM and relays the real response (so exploits really run there)
  * optionally terminates TLS (TLS_CERT / TLS_KEY) so HTTPS scanners are captured too

Exploit details were not public when this was written, so tags are heuristic.
Tighten RULES once real samples show up in captures/.
"""
import asyncio, base64, hashlib, json, math, os, re, ssl, time, uuid
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

HTTP_PORT = int(os.environ.get("HTTP_PORT", "8080"))
HTTPS_PORT = int(os.environ.get("HTTPS_PORT", "8443"))
UP_HOST, _, UP_PORT = os.environ.get("UPSTREAM", "realphp:80").partition(":")
UP_PORT = int(UP_PORT or 80)
TLS_CERT, TLS_KEY = os.environ.get("TLS_CERT", ""), os.environ.get("TLS_KEY", "")
HONEYTOKEN = os.environ.get("HONEYTOKEN_MARKER", "HT7f3a")
MAX_HEADER, MAX_BODY = 64 * 1024, 16 * 1024 * 1024
READ_TIMEOUT, UP_TIMEOUT = 20, 20

DATA = Path(os.environ.get("HP_DATA", "/data"))
CAP_DIR, LOG_DIR = DATA / "captures", DATA / "logs"
CAP_DIR.mkdir(parents=True, exist_ok=True)
LOG_DIR.mkdir(parents=True, exist_ok=True)

RULES = [(t, re.compile(p, re.I)) for t, p in [
    ("cmd-exec",      rb"\b(system|passthru|shell_exec|proc_open|popen|eval|assert)\s*\("),
    ("shell-strings", rb"(/bin/(ba)?sh|cmd\.exe|powershell|/dev/tcp/|mkfifo|\bnc\s+-e|certutil|\bwget\s|\bcurl\s)"),
    ("recon-cmd",     rb"\b(whoami|uname\s+-a|ipconfig|cat\s+/etc/passwd)\b"),
    ("php-wrapper",   rb"(php://(input|filter)|data://|expect://|phar://)"),
    ("php-cgi-arg",   rb"(auto_prepend_file|allow_url_include|%ad)"),
    ("webshell-drop", rb"<\?php|<\?=|filename=\"?[^\"\r\n]*\.(php|phtml|phar)"),
    ("path-probe",    rb"(phpinfo|wp-login|xmlrpc|vendor/phpunit|/cgi-bin/|shell\.php|eval-stdin|wp-config)"),
    ("bait-hit",      rb"^[A-Z]+ /(\.env|backup\.sql|\.git|admin-old|config\.php\.bak|db_backup)"),
]]
HT_RE = re.compile(re.escape(HONEYTOKEN).encode(), re.I)
URL_RE = re.compile(rb"https?://[^\s\"'<>\\|;&)]{4,200}", re.I)
IP_RE = re.compile(rb"\b(?:\d{1,3}\.){3}\d{1,3}\b")
# tags that mean "more than background scanning"
EXPLOIT_TAGS = {"cmd-exec", "shell-strings", "php-wrapper", "php-cgi-arg", "webshell-drop",
                "multipart-no-boundary", "multipart-long-boundary", "multipart-many-parts",
                "multipart-unterminated", "multipart-nested", "oversized-body",
                "content-length-mismatch", "te-cl-smuggling-shape", "honeytoken-reuse"}


def parse_request(raw: bytes):
    head, _, body = raw.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    reqline = lines[0].decode("latin-1", "replace") if lines else ""
    parts = reqline.split(" ")
    headers, order, dup = {}, [], []
    for ln in lines[1:]:
        k, sep, v = ln.partition(b":")
        k = k.decode("latin-1", "replace").strip().lower()
        if not sep:
            dup.append("malformed-header")
            continue
        order.append(k)
        if k in headers:
            dup.append("dup:" + k)
        headers[k] = v.decode("latin-1", "replace").strip()
    version = parts[2] if len(parts) > 2 else ""
    return (parts[0] if parts else ""), (parts[1] if len(parts) > 1 else ""), version, reqline, headers, order, dup, body


def analyze(method, path, headers, dup, body, truncated):
    tags, info = [], {}
    ct = headers.get("content-type", "")
    if "multipart/" in ct.lower():
        m = re.search(r'boundary="?([^";]+)"?', ct, re.I)
        if not m:
            tags.append("multipart-no-boundary")
        else:
            b = m.group(1).encode()
            info["boundary_len"] = len(b)
            info["parts"] = max(body.count(b"--" + b) - 1, 0)
            info["has_terminator"] = body.rstrip().endswith(b"--" + b + b"--")
            info["filenames"] = [f.decode("latin-1", "replace")[:120]
                                 for f in re.findall(rb'filename="?([^";\r\n]*)', body)[:20]]
            info["part_headers"] = sorted({h.decode("latin-1", "replace").lower()
                                           for h in re.findall(rb"\r\n([A-Za-z-]+):", body[:200_000])})[:12]
            if len(b) > 70:
                tags.append("multipart-long-boundary")
            if info["parts"] > 100:
                tags.append("multipart-many-parts")
            if not info["has_terminator"]:
                tags.append("multipart-unterminated")
            if b"multipart/" in body:
                tags.append("multipart-nested")
    if len(body) > 1_000_000 or truncated:
        tags.append("oversized-body")
    cl = headers.get("content-length", "")
    if cl.isdigit() and int(cl) != len(body) and not truncated:
        tags.append("content-length-mismatch")
    if "transfer-encoding" in headers and "content-length" in headers:
        tags.append("te-cl-smuggling-shape")
    tags += dup[:5]
    hay = (method + " " + path).encode("latin-1", "replace") + b"\r\n" + body[:2_000_000]
    tags += [t for t, rx in RULES if rx.search(hay)]
    if HT_RE.search(hay):
        tags.append("honeytoken-reuse")
    # credential attempts against login forms
    creds = {}
    if method == "POST" and "urlencoded" in ct.lower():
        q = parse_qs(body[:4096].decode("latin-1", "replace"))
        for k_user in ("log", "username", "user", "email", "user_login"):
            if k_user in q:
                creds["cred_user"] = q[k_user][0][:100]
                break
        for k_pw in ("pwd", "password", "pass", "user_pass"):
            if k_pw in q:
                creds["cred_pass"] = q[k_pw][0][:100]
                break
        if creds:
            tags.append("credential-attempt")
    return sorted(set(tags)), info, creds


def shape_hash(method, path, order, headers, info, body_len):
    """Fingerprint of the request *structure*, so variants of one exploit group together."""
    ct = re.sub(r"boundary=.*", "boundary=*", headers.get("content-type", ""), flags=re.I)
    parts = info.get("parts", 0)
    sig = "|".join([method, urlsplit(path).path, ct, ",".join(order),
                    str(int(math.log2(max(body_len, 1)))), str(min(parts, 1000) // 10),
                    str(info.get("has_terminator")), ",".join(info.get("part_headers", []))])
    return hashlib.sha256(sig.encode("latin-1", "replace")).hexdigest()[:16]


def extract_iocs(body: bytes, path: str):
    hay = body[:2_000_000] + b" " + path.encode("latin-1", "replace")
    urls = {u.decode("latin-1", "replace") for u in URL_RE.findall(hay)}
    ips = {i.decode() for i in IP_RE.findall(hay)
           if all(int(x) <= 255 for x in i.split(b"."))}
    return sorted(urls)[:10] + sorted(ips)[:10]


def force_close(raw: bytes, src_ip: str) -> bytes:
    """Forwarded copy only: close after response (so we can relay until EOF) and pass the real client IP."""
    head, sep, body = raw.partition(b"\r\n\r\n")
    head = re.sub(rb"\r\n(connection|x-forwarded-for):[^\r\n]*", b"", head, flags=re.I)
    head += b"\r\nConnection: close\r\nX-Forwarded-For: " + src_ip.encode()
    return head + sep + body


async def read_request(reader, writer):
    buf = b""
    while b"\r\n\r\n" not in buf and len(buf) < MAX_HEADER:
        chunk = await reader.read(8192)
        if not chunk:
            return buf, False
        buf += chunk
    head, _, rest = buf.partition(b"\r\n\r\n")
    if re.search(rb"expect:\s*100-continue", head, re.I):
        writer.write(b"HTTP/1.1 100 Continue\r\n\r\n")
        await writer.drain()
    m = re.search(rb"content-length:\s*(\d+)", head, re.I)
    want = min(int(m.group(1)), MAX_BODY) if m else 0
    chunked = re.search(rb"transfer-encoding:\s*chunked", head, re.I) is not None
    truncated = bool(m) and int(m.group(1)) > MAX_BODY
    while len(rest) < want or (chunked and not rest.endswith(b"0\r\n\r\n") and len(rest) < MAX_BODY):
        chunk = await reader.read(65536)
        if not chunk:
            break
        rest += chunk
    return head + b"\r\n\r\n" + rest, truncated


async def forward(raw: bytes, src_ip: str) -> bytes:
    try:
        r, w = await asyncio.wait_for(asyncio.open_connection(UP_HOST, UP_PORT), 5)
        w.write(force_close(raw, src_ip))
        await w.drain()
        out = b""
        async with asyncio.timeout(UP_TIMEOUT):
            while chunk := await r.read(65536):
                out += chunk
        w.close()
        return out
    except Exception:
        return b""   # upstream crashed or timed out: itself a signal (see php_crash events)


def make_handler(is_tls: bool):
    async def handle(reader, writer):
        t0 = time.monotonic()
        peer = writer.get_extra_info("peername") or ("?", 0)
        sslobj = writer.get_extra_info("ssl_object")
        try:
            raw, truncated = await asyncio.wait_for(read_request(reader, writer), READ_TIMEOUT)
        except Exception:
            raw, truncated = b"", False
        if raw:
            read_ms = int((time.monotonic() - t0) * 1000)
            method, path, version, reqline, headers, order, dup, body = parse_request(raw)
            tags, info, creds = analyze(method, path, headers, dup, body, truncated)
            sha = hashlib.sha256(raw).hexdigest()
            cap = CAP_DIR / f"{sha}.bin"          # .bin: never served, never executed
            if not cap.exists():
                cap.write_bytes(raw)
            t1 = time.monotonic()
            resp = await forward(raw, peer[0])
            up_ms = int((time.monotonic() - t1) * 1000)
            status = int(resp[9:12]) if resp[:5] == b"HTTP/" and resp[9:12].isdigit() else 0
            event = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + f".{int(time.time()*1000)%1000:03d}Z",
                "kind": "request", "req_id": uuid.uuid4().hex[:12],
                "src_ip": peer[0], "src_port": peer[1], "tls": is_tls,
                "tls_version": sslobj.version() if sslobj else None,
                "tls_cipher": sslobj.cipher()[0] if sslobj and sslobj.cipher() else None,
                "sni": getattr(sslobj, "sni_name", None) if sslobj else None,
                "http_version": version, "request_line": reqline[:500], "method": method, "path": path[:500],
                "host": headers.get("host", "")[:200], "ua": headers.get("user-agent", "")[:300],
                "content_type": headers.get("content-type", "")[:300],
                "header_count": len(order), "header_order": ",".join(order)[:400],
                "header_hash": hashlib.sha256(",".join(order).encode()).hexdigest()[:12],
                "headers": headers, "body_len": len(body), "resp_len": len(resp), "truncated": truncated,
                "multipart": info, "tags": tags, "exploit_like": bool(EXPLOIT_TAGS & set(tags)),
                "shape_hash": shape_hash(method, path, order, headers, info, len(body)),
                "iocs": extract_iocs(body, path), **creds,
                "read_ms": read_ms, "upstream_ms": up_ms, "upstream_status": status,
                "upstream_empty": not resp, "sha256": sha,
                "body_preview_b64": base64.b64encode(body[:512]).decode(),
            }
            with open(LOG_DIR / "events.jsonl", "a", encoding="utf-8") as f:
                f.write(json.dumps(event) + "\n")
            print(f"{event['ts']} {peer[0]} {method} {path[:60]} -> {status} tags={tags}", flush=True)
            try:
                if resp:
                    writer.write(resp)
                    await writer.drain()
            except Exception:
                pass
        writer.close()
    return handle


def tls_context():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(TLS_CERT, TLS_KEY)

    def sni(sslobj, name, _ctx):
        try:
            sslobj.sni_name = name
        except Exception:
            pass
    ctx.set_servername_callback(sni)
    return ctx


async def main():
    servers = [await asyncio.start_server(make_handler(False), "0.0.0.0", HTTP_PORT)]
    print(f"capture proxy http :{HTTP_PORT} -> {UP_HOST}:{UP_PORT}", flush=True)
    if TLS_CERT and TLS_KEY and Path(TLS_CERT).exists():
        servers.append(await asyncio.start_server(make_handler(True), "0.0.0.0", HTTPS_PORT, ssl=tls_context()))
        print(f"capture proxy https :{HTTPS_PORT}", flush=True)
    else:
        print("TLS disabled (no certificate found)", flush=True)
    await asyncio.gather(*(s.serve_forever() for s in servers))


if __name__ == "__main__":
    asyncio.run(main())
