#!/bin/bash
# T-Pot's Snare and h0neytr4p occupy ports 80 and 443, which the capture proxy needs. This moves those two
# honeypots to loopback-only ports (they stay in the stack, just unreachable from outside). Do NOT delete or
# comment out the port lines instead: a service whose `ports:` list ends up empty makes docker compose reject the
# whole file and T-Pot crash-loops. Run as the T-Pot user, then restart T-Pot. Safe to run twice.
set -e
F="${1:-$HOME/tpotce/docker-compose.yml}"
[ -f "$F" ] || { echo "not found: $F (pass the path to T-Pot's docker-compose.yml)"; exit 1; }
[ -f "$F.bak-php-honeypot" ] || cp "$F" "$F.bak-php-honeypot"
sed -i -E 's|^(\s*)- "80:80"\s*$|\1- "127.0.0.1:18080:80"   # moved off :80 for php-Honeypot|; s|^(\s*)- "443:443"\s*$|\1- "127.0.0.1:18443:443"  # moved off :443 for php-Honeypot|' "$F"
grep -nE '"(127\.0\.0\.1:18080:80|127\.0\.0\.1:18443:443|80:80|443:443)"' "$F" || true
if command -v docker >/dev/null 2>&1; then
    (cd "$(dirname "$F")" && sudo docker compose -f "$(basename "$F")" config -q) && echo "compose file still valid" \
        || { echo "ERROR: compose file is invalid after the edit; restoring backup"; cp "$F.bak-php-honeypot" "$F"; exit 1; }
fi
echo "Backup: $F.bak-php-honeypot. Now: sudo systemctl restart tpot"
