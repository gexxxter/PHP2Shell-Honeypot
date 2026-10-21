#!/bin/bash
# Manage the IPs the dashboards hide by default (your own machines, test boxes).
#   scripts/ignore-ip.sh 203.0.113.7 [more ...]     add one or more IPs / CIDR ranges
#   scripts/ignore-ip.sh --remove 203.0.113.7       remove one
#   scripts/ignore-ip.sh --list                     show the current list
# Updates .env, restarts the live dashboard (the honeypot itself is not touched) and rebuilds the Kibana dashboard so
# both hide the same IPs. The live dashboard keeps a toggle to show them again; Kibana excludes them in every panel.
set -e
cd "$(dirname "$0")/.."
touch .env
current() { grep '^LIVE_IGNORE_IPS=' .env | tail -1 | cut -d= -f2- | tr -d "'\""; }
valid() { [[ "$1" =~ ^[0-9a-fA-F:.]+(/[0-9]{1,3})?$ ]]; }

list="$(current)"
case "${1:-}" in
    --list|"") echo "ignored IPs: ${list:-(none)}"; exit 0;;
    --remove)  shift; for ip in "$@"; do list="$(echo ",$list," | sed "s/,$ip,/,/; s/^,//; s/,$//")"; done;;
    *)         for ip in "$@"; do valid "$ip" || { echo "not an IP or CIDR: $ip"; exit 1; }
                   case ",$list," in *",$ip,"*) ;; *) list="${list:+$list,}$ip";; esac; done;;
esac

sed -i '/^LIVE_IGNORE_IPS=/d' .env
echo "LIVE_IGNORE_IPS=$list" >> .env
echo "ignored IPs now: ${list:-(none)}"
if docker info >/dev/null 2>&1; then D=docker; else D="sudo docker"; fi
$D compose up -d live
if command -v jq >/dev/null 2>&1; then LIVE_IGNORE_IPS="$list" ./scripts/kibana-import.sh || echo "(Kibana dashboard not updated; run scripts/kibana-import.sh later)"; fi
