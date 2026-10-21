#!/usr/bin/env python3
"""
Backfill `request_text` (and `raw_size`) on request events captured before the capture proxy started storing them.

Reads each event's raw request file (captures/<sha256>.bin, written by the proxy for every request) and writes the same
readable rendering the proxy produces today into the Elasticsearch document, so old requests show up in the Kibana
tables too. Safe to re-run: it only touches events that are still missing the field.

Run it next to the data (it needs the hpdata volume and Elasticsearch):
  sudo docker run --rm --network host -v php-honeypot_hpdata:/data:ro -v "$PWD/scripts/backfill-request-text.py:/b.py:ro" \
      python:3.12-slim python -I /b.py
Environment: ES_URL (default http://127.0.0.1:64298), CAPTURE_DIR (default /data/captures).
"""
import json, os, re, urllib.request
from pathlib import Path

ES = os.environ.get("ES_URL", "http://127.0.0.1:64298")
CAP = Path(os.environ.get("CAPTURE_DIR", "/data/captures"))
SHA = re.compile(r"^[0-9a-f]{64}$")


def show(b: bytes) -> str:
    """Same rendering as capture.py: CRLF -> newline, printable ASCII kept, everything else as \\xNN."""
    out, i, n = [], 0, len(b)
    while i < n:
        c = b[i]
        if c == 13 and i + 1 < n and b[i + 1] == 10:
            out.append("\n"); i += 2; continue
        out.append("\n" if c == 10 else chr(c) if (c == 9 or 32 <= c < 127) else "\\x%02x" % c)
        i += 1
    return "".join(out)


def call(path, body, ndjson=False):
    data = body if ndjson else json.dumps(body)
    req = urllib.request.Request(ES + path, data=data.encode(), method="POST",
                                 headers={"Content-Type": "application/x-ndjson" if ndjson else "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def main():
    # marker: raw_size. (Not request_text: long values are not indexed, so an "exists" test on it is false for exactly the long
    # requests we care about and the loop would pick them up forever.)
    query = {"bool": {"filter": [{"term": {"kind": "request"}}, {"exists": {"field": "sha256"}}],
                      "must_not": [{"exists": {"field": "raw_size"}}]}}   # raw_size is a number, always indexed (request_text is too long to be)
    done = missing = 0
    cache = {}
    for _batch in range(2000):                      # hard cap (1,000,000 events): this loop must never run away
        # no search_after needed: updated documents drop out of the query, so we simply ask for the next batch
        res = call("/php2shell-*/_search", {"size": 500, "_source": ["sha256"], "query": query, "sort": ["_doc"]})
        hits = res["hits"]["hits"]
        if not hits:
            break
        lines, progressed = [], 0
        for h in hits:
            sha = h["_source"].get("sha256", "")
            if sha not in cache:
                p = CAP / (sha + ".bin") if SHA.match(sha) else None
                cache[sha] = None
                if p is not None and p.is_file():
                    raw = p.read_bytes()
                    cache[sha] = (show(raw[:8192]), len(raw))
            if cache[sha] is None:
                missing += 1
                # mark so the loop does not pick it up again: an empty text means "raw file no longer available"
                doc = {"request_text": "", "raw_size": 0}
            else:
                doc = {"request_text": cache[sha][0], "raw_size": cache[sha][1]}
            lines.append(json.dumps({"update": {"_index": h["_index"], "_id": h["_id"]}}))
            lines.append(json.dumps({"doc": doc}))
            progressed += 1
        resp = call("/_bulk?refresh=true", "\n".join(lines) + "\n", ndjson=True)
        if resp.get("errors"):
            bad = [i for i in resp["items"] if "error" in i.get("update", {})][:1]
            raise SystemExit("bulk update reported errors, first: " + json.dumps(bad))
        done += progressed
        print(f"updated {done} events so far...", flush=True)
    print(f"done: {done} events updated, {missing} had no raw file on disk (marked empty)")


if __name__ == "__main__":
    main()
