#!/usr/bin/env python3
"""
Decoy database listener (honeytoken tripwire).

The bait files in the shop (.env, backup.sql) name a "backup database" at db-backup.internal with
fake credentials. Nothing legitimate ever connects there, so any connection means an attacker has
code execution and is using stolen bait credentials. Speaks just enough of the MySQL handshake to
capture the username, then answers "access denied".
"""
import asyncio, json, os, struct, time
from pathlib import Path

LOG = Path(os.environ.get("HP_DATA", "/data")) / "logs" / "decoy.jsonl"
LOG.parent.mkdir(parents=True, exist_ok=True)
SALT = b"abcdefgh" + b"ijklmnopqrst"


def greeting() -> bytes:
    p = b"\x0a" + b"8.0.36\x00" + struct.pack("<I", 4242) + SALT[:8] + b"\x00"
    p += struct.pack("<H", 0xF7FF) + b"\x21" + struct.pack("<H", 2) + struct.pack("<H", 0x81FF)
    p += b"\x15" + b"\x00" * 10 + SALT[8:] + b"\x00" + b"mysql_native_password\x00"
    return struct.pack("<I", len(p))[:3] + b"\x00" + p


def deny(user: str) -> bytes:
    msg = f"Access denied for user '{user}'@'localhost' (using password: YES)".encode()
    p = b"\xff" + struct.pack("<H", 1045) + b"#28000" + msg
    return struct.pack("<I", len(p))[:3] + b"\x02" + p


async def handle(reader, writer):
    peer = writer.get_extra_info("peername") or ("?", 0)
    user, first = "", b""
    try:
        writer.write(greeting())
        await writer.drain()
        first = await asyncio.wait_for(reader.read(4096), 10)
        if len(first) > 36:
            user = first[36:].split(b"\x00", 1)[0].decode("latin-1", "replace")[:100]
        writer.write(deny(user))
        await writer.drain()
    except Exception:
        pass
    event = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".000Z", "kind": "decoy_connect",
             "src_ip": peer[0], "src_port": peer[1], "cred_user": user, "bytes": len(first),
             "tags": ["honeytoken-use"], "exploit_like": True}
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")
    print(event, flush=True)
    writer.close()


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", 3306)
    async with server:
        await server.serve_forever()

asyncio.run(main())
