#!/bin/bash
# T-Pot's Snare and h0neytr4p occupy ports 80 and 443, which capture needs. This comments out those two
# port mappings in T-Pot's compose file. Run as the T-Pot user, then restart T-Pot.
set -e
F="${1:-$HOME/tpotce/docker-compose.yml}"
[ -f "$F" ] || { echo "not found: $F (pass the path to T-Pot's docker-compose.yml)"; exit 1; }
cp -n "$F" "$F.bak-php-honeypot"
sed -i -E 's|^(\s*)- "80:80"|\1# - "80:80"   # disabled for php-Honeypot|; s|^(\s*)- "443:443"|\1# - "443:443"  # disabled for php-Honeypot|' "$F"
grep -nE '"(80|443):(80|443)"' "$F" || true
echo "Backup: $F.bak-php-honeypot. Now: sudo systemctl restart tpot"
