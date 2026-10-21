#!/usr/bin/env python3
"""
Live dashboard backend (stdlib only). Serves index.html and /api/state, which runs aggregations
against the php2shell-* indices in T-Pot's Elasticsearch and returns everything the page needs.
Bound to 127.0.0.1 only: reach it through an SSH tunnel.

Everything (page and API) requires HTTP basic auth. LIVE_USER and LIVE_PASSWORD are mandatory: the server refuses
to start without them, so there is no unauthenticated mode. Basic auth is not encrypted on its own: keep using the
SSH tunnel, or put TLS in front, before exposing this beyond loopback.
"""
import base64, hmac, json, os, re, sys, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ES = os.environ.get("ES_URL", "http://127.0.0.1:64298")
PORT = int(os.environ.get("LIVE_PORT", "64300"))
USER = os.environ.get("LIVE_USER", "")
PASSWORD = os.environ.get("LIVE_PASSWORD", "")
MAX_FAILS, FAIL_WINDOW = 8, 300          # lock out after 8 failed logins within 5 minutes (global: behind a tunnel every client is 127.0.0.1)
_fails, _fails_lock = [], threading.Lock()
HERE = Path(__file__).parent
CAPTURE_DIR = Path(os.environ.get("CAPTURE_DIR", "/data/captures"))   # the capture proxy's raw request files (read-only mount)
VIEW_BYTES = 1_000_000          # how much of a request the inspector renders as text
HEX_BYTES = 16 * 1024           # how much it renders as a hex dump (the full file is always available as a download)
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
# IPs or CIDR ranges (e.g. your own, or your test machines) hidden from every number and list unless the toggle is switched off
IGNORE = [x.strip() for x in os.environ.get("LIVE_IGNORE_IPS", "").split(",") if re.match(r"^[0-9a-fA-F:.]+(/[0-9]{1,3})?$", x.strip())]
INDEX = "php2shell-*"
WINDOWS = {"1h": ("now-1h", "1m"), "24h": ("now-24h", "30m"), "7d": ("now-7d", "6h"), "30d": ("now-30d", "1d")}


def es(path, body, ndjson=False):
    data = body if ndjson else json.dumps(body)
    req = urllib.request.Request(ES + path, data=data.encode(), method="POST",
                                 headers={"Content-Type": "application/x-ndjson" if ndjson else "application/json"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read())


def terms(field, size=10, **sub):
    d = {"terms": {"field": field, "size": size}}
    if sub:
        d["aggs"] = sub
    return d


def show(b: bytes) -> str:
    """Readable but lossless-ish rendering of attacker bytes: CRLF becomes a newline, printable ASCII stays,
    everything else (including a lone CR, NUL, control and high bytes) is shown as an explicit \\xNN escape."""
    out = []
    i, n = 0, len(b)
    while i < n:
        c = b[i]
        if c == 13 and i + 1 < n and b[i + 1] == 10:
            out.append("\n"); i += 2; continue
        if c == 10:
            out.append("\n")
        elif c == 9 or 32 <= c < 127:
            out.append(chr(c))
        else:
            out.append("\\x%02x" % c)
        i += 1
    return "".join(out)


def hexdump(b: bytes) -> str:
    lines = []
    for off in range(0, len(b), 16):
        chunk = b[off:off + 16]
        hx = " ".join("%02x" % c for c in chunk)
        asc = "".join(chr(c) if 32 <= c < 127 else "." for c in chunk)
        lines.append("%08x  %-47s  |%s|" % (off, hx, asc))
    return "\n".join(lines)


def raw_path(sha: str):
    if not SHA_RE.match(sha or ""):
        return None                                   # only a 64-char hex hash is ever turned into a filename
    p = CAPTURE_DIR / (sha + ".bin")
    return p if p.is_file() else None


def raw_view(sha: str, limit: int = VIEW_BYTES):
    p = raw_path(sha)
    if p is None:
        return None
    limit = max(256, min(int(limit), VIEW_BYTES))      # inline previews ask for a few KB, the inspector for the full view
    size = p.stat().st_size
    with open(p, "rb") as f:
        data = f.read(limit)
    head, sep, body = data.partition(b"\r\n\r\n")
    if not sep:
        head, sep, body = data.partition(b"\n\n")
    return {"sha256": sha, "size": size, "truncated": size > len(data),
            "head": show(head), "has_body_separator": bool(sep), "body_size": max(size - len(head) - len(sep), 0),
            "body": show(body), "hex": hexdump(data[:HEX_BYTES]), "hex_truncated": size > HEX_BYTES}


def state(window, hide=True):
    gte, interval = WINDOWS.get(window, WINDOWS["24h"])
    rng = {"range": {"@timestamp": {"gte": gte}}}
    exploit = {"term": {"exploit_like": True}}
    mn = [{"terms": {"src_ip": IGNORE}}] if (hide and IGNORE) else []   # events from ignored IPs (RCE/crash events have no src_ip and are never hidden)
    main = es(f"/{INDEX}/_search?ignore_unavailable=true", {
        "size": 300, "sort": [{"@timestamp": "desc"}], "track_total_hits": True,
        "_source": ["@timestamp", "kind", "src_ip", "geo", "asn.organization_name", "path", "method", "exploit_like",
                    "tags", "rce_type", "detail", "signal", "shape_hash", "ua", "sha256", "request_line", "body_len"],
        "query": {"bool": {"filter": [rng], "must_not": mn}},
        "aggs": {
            "kinds": terms("kind", 10, last={"max": {"field": "@timestamp"}}),
            "ips": {"cardinality": {"field": "src_ip"}},
            "exploit": {"filter": exploit, "aggs": {"ips": {"cardinality": {"field": "src_ip"}}}},
            "timeline": {"date_histogram": {"field": "@timestamp", "fixed_interval": interval},
                         "aggs": {"x": {"filter": exploit}, "r": {"filter": {"term": {"kind": "rce_confirmed"}}}}},
            "heat": {"date_histogram": {"field": "@timestamp", "fixed_interval": "1h"}},
            "tags": terms("tags", 15),
            "countries": terms("geo.country_name", 12, x={"filter": exploit}),
            "asns": terms("asn.organization_name", 12, x={"filter": exploit}),
            "ua_names": terms("ua_parsed.name", 10),
            "ua_os": terms("ua_parsed.os.name", 8),
            "methods": terms("method", 8),
            "status": terms("upstream_status", 8),
            "paths": terms("path", 12, x={"filter": exploit}),
            "iocs": terms("iocs", 15),
            "cred_users": terms("cred_user", 10),
            "cred_pass": terms("cred_pass", 10),
            "hdr": terms("header_hash", 8, ips={"cardinality": {"field": "src_ip"}}),
            "tls": terms("tls_version", 5),
            "sni": terms("sni", 5),
            "top_ips": terms("src_ip", 12, x={"filter": exploit}, c={"terms": {"field": "geo.country_iso_code", "size": 1}},
                             first={"min": {"field": "@timestamp"}}, last={"max": {"field": "@timestamp"}}),
            "shapes": terms("shape_hash", 10, ips={"cardinality": {"field": "src_ip"}},
                            asns={"cardinality": {"field": "asn.organization_name"}},
                            first={"min": {"field": "@timestamp"}}, last={"max": {"field": "@timestamp"}},
                            avg_size={"avg": {"field": "body_len"}},
                            sample={"top_hits": {"size": 1, "_source": ["request_line", "tags", "multipart", "sha256"]}}),
            "body_bytes": {"sum": {"field": "body_len"}},
            "latency": {"percentiles": {"field": "upstream_ms", "percents": [50, 95, 99]}},
            "empty_resp": {"filter": {"term": {"upstream_empty": True}}},
            "bait": {"filter": {"term": {"tags": "bait-hit"}}},
            "creds": {"filter": {"term": {"tags": "credential-attempt"}}},
            "ht_reuse": {"filter": {"term": {"tags": "honeytoken-reuse"}}},
        }})
    # all-time first-seen per payload shape, to count genuinely new shapes in the window
    firsts = es(f"/{INDEX}/_search?ignore_unavailable=true", {
        "size": 0, "query": {"bool": {"filter": [exploit], "must_not": mn}},
        "aggs": {"s": {"terms": {"field": "shape_hash", "size": 1000}, "aggs": {"first": {"min": {"field": "@timestamp"}}}}}})
    rce = es(f"/{INDEX}/_search?ignore_unavailable=true", {
        "size": 20, "sort": [{"@timestamp": "desc"}],
        "query": {"bool": {"filter": [{"term": {"kind": "rce_confirmed"}}]}}})
    rce_hits = [h["_source"] for h in rce.get("hits", {}).get("hits", [])]
    interesting = es(f"/{INDEX}/_search?ignore_unavailable=true", {         # newest exploit-like requests, for the inspector list
        "size": 30, "sort": [{"@timestamp": "desc"}],
        "_source": ["@timestamp", "src_ip", "geo.country_iso_code", "request_line", "method", "path", "tags", "body_len", "sha256", "shape_hash"],
        "query": {"bool": {"filter": [rng, {"term": {"kind": "request"}}, exploit], "must_not": mn}}})
    # suspected sources: requests in the 15 s before each confirmation (shared container, so it is a time correlation)
    suspects = []
    if rce_hits:
        nd = ""
        for h in rce_hits:
            nd += json.dumps({"index": INDEX, "ignore_unavailable": True}) + "\n"
            nd += json.dumps({"size": 4, "sort": [{"exploit_like": "desc"}, {"@timestamp": "desc"}],
                              "_source": ["@timestamp", "src_ip", "geo", "request_line", "shape_hash", "tags", "sha256"],
                              "query": {"bool": {"filter": [{"term": {"kind": "request"}}, {"range": {"@timestamp": {
                                  "gte": h["@timestamp"] + "||-15s", "lte": h["@timestamp"]}}}], "must_not": mn}}}) + "\n"
        resp = es("/_msearch", nd, ndjson=True)
        suspects = [[x["_source"] for x in r.get("hits", {}).get("hits", [])] for r in resp.get("responses", [])]
    hidden = 0
    if IGNORE:                       # how many requests in this window come from the ignored IPs (shown next to the toggle)
        hidden = es(f"/{INDEX}/_search?ignore_unavailable=true", {
            "size": 0, "track_total_hits": True,
            "query": {"bool": {"filter": [rng, {"term": {"kind": "request"}}, {"terms": {"src_ip": IGNORE}}]}}})["hits"]["total"]["value"]
    return {"window": window, "now": None, "total": main["hits"]["total"]["value"],
            "ignore": {"ips": IGNORE, "active": bool(hide and IGNORE), "hidden_requests": hidden},
            "recent": [h["_source"] for h in main["hits"]["hits"]], "aggs": main["aggregations"],
            "shape_first": firsts.get("aggregations", {}).get("s", {}).get("buckets", []),
            "rce": rce_hits, "suspects": suspects,
            "interesting": [h["_source"] for h in interesting.get("hits", {}).get("hits", [])]}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def authorised(self):
        """True if the request carries valid credentials; otherwise sends 401/429 and returns False."""
        now = time.time()
        with _fails_lock:
            _fails[:] = [t for t in _fails if now - t < FAIL_WINDOW]
            locked = len(_fails) >= MAX_FAILS
        if locked:
            self.send_response(429)
            self.send_header("Retry-After", str(FAIL_WINDOW))
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"too many failed logins, try again later")
            return False
        header = self.headers.get("Authorization", "")
        ok = False
        if header.startswith("Basic "):
            try:
                user, _, pw = base64.b64decode(header[6:]).decode("utf-8").partition(":")
                # compare both fields in constant time and always evaluate both
                ok = hmac.compare_digest(user.encode(), USER.encode()) & hmac.compare_digest(pw.encode(), PASSWORD.encode())
            except Exception:
                ok = False
        if not ok:
            if header:                                   # a wrong attempt, not just the browser's first anonymous request
                with _fails_lock:
                    _fails.append(now)
                time.sleep(1)                            # slow guessing down
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="php-Honeypot", charset="UTF-8"')
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"authentication required")
        return ok

    def do_GET(self):
        if not self.authorised():
            return
        u = urlparse(self.path)
        if u.path == "/api/state":
            try:
                qs = parse_qs(u.query)
                w = qs.get("w", ["24h"])[0]
                hide = qs.get("hide", ["1"])[0] != "0"       # default: hide the configured IPs
                self.send(200, json.dumps(state(w, hide)).encode(), "application/json")
            except Exception as e:
                self.send(502, json.dumps({"error": str(e)}).encode(), "application/json")
        elif u.path == "/api/raw":
            q = parse_qs(u.query)
            sha = q.get("sha", [""])[0]
            p = raw_path(sha)
            if p is None:
                self.send(404, json.dumps({"error": "no stored request with that hash"}).encode(), "application/json")
            elif q.get("download", ["0"])[0] == "1":
                # attacker-controlled bytes: always an attachment, never rendered or executed by the browser
                self.send_response(200)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Disposition", f'attachment; filename="request-{sha[:12]}.bin"')
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("Content-Length", str(p.stat().st_size))
                self.end_headers()
                with open(p, "rb") as f:
                    self.wfile.write(f.read())
            else:
                try:
                    limit = int(q.get("limit", [VIEW_BYTES])[0])
                except ValueError:
                    limit = VIEW_BYTES
                self.send(200, json.dumps(raw_view(sha, limit)).encode(), "application/json")
        elif u.path in ("/", "/index.html"):
            self.send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        else:
            self.send(404, b"not found", "text/plain")


if __name__ == "__main__":
    if not USER or len(PASSWORD) < 8:
        sys.exit("refusing to start: set LIVE_USER and a LIVE_PASSWORD of at least 8 characters (there is no unauthenticated mode)")
    bind = os.environ.get("LIVE_BIND", "127.0.0.1")
    print(f"live dashboard on {bind}:{PORT} (ES {ES}), basic auth enabled for user '{USER}'", flush=True)
    ThreadingHTTPServer((bind, PORT), Handler).serve_forever()
