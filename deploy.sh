#!/bin/bash
# One-command deployment of php-Honeypot on a fresh, throwaway Debian 13 / Ubuntu VPS.
#
#   ./deploy.sh --web-user admin --web-pass 'S3cret!' [--domain shop.example.com] [--email you@example.com]
#
# What it does, in order:
#   1. installs T-Pot (hive edition) unattended, if it is not installed yet
#   2. registers itself to continue automatically after T-Pot's reboot (SSH then moves to port 64295)
#   3. frees ports 80/443 from T-Pot, prepares Elasticsearch (enrichment, retention, template)
#   4. (optional) gets a Let's Encrypt certificate for --domain
#   5. builds and starts the add-on: capture proxy, vulnerable shop, decoy DB, Falco, Vector, live dashboard
#   6. imports the Kibana dashboard into T-Pot
#
# Requirements: non-root user with passwordless sudo, Internet access, >= 8 GB RAM (16 GB recommended), >= 128 GB disk.
# Safe to re-run: every step checks whether it is already done.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
PROJ="$PWD"
STATE="$HOME/.php-honeypot-deploy.env"
SERVICE=php-honeypot-resume

WEB_USER="" WEB_PASS="" DOMAIN="" EMAIL="" RESUME=0
while [ $# -gt 0 ]; do
    case "$1" in
        --web-user) WEB_USER="$2"; shift 2;;
        --web-pass) WEB_PASS="$2"; shift 2;;
        --domain)   DOMAIN="$2"; shift 2;;
        --email)    EMAIL="$2"; shift 2;;
        --resume)   RESUME=1; shift;;
        -h|--help)  sed -n 2,17p "$0"; exit 0;;
        *) echo "unknown option: $1"; exit 1;;
    esac
done

log() { echo -e "\n\033[1;34m### $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

# remember the arguments across the reboot (the file holds the T-Pot web password: it is deleted at the end)
if [ "$RESUME" = 1 ]; then
    [ -f "$STATE" ] && source "$STATE"
else
    [ -n "$WEB_USER" ] && [ -n "$WEB_PASS" ] || die "--web-user and --web-pass are required (they protect T-Pot's web UI)"
    umask 077
    printf 'WEB_USER=%q\nWEB_PASS=%q\nDOMAIN=%q\nEMAIL=%q\n' "$WEB_USER" "$WEB_PASS" "$DOMAIN" "$EMAIL" > "$STATE"
fi

es_up()  { curl -fsS -o /dev/null "http://127.0.0.1:64298/_cluster/health" 2>/dev/null; }
wait_es() { log "waiting for T-Pot's Elasticsearch (can take a few minutes)"
    for _ in $(seq 1 180); do es_up && return 0; sleep 5; done; die "Elasticsearch did not come up on 127.0.0.1:64298"; }

[ "$(id -u)" -ne 0 ] || die "run as a normal user with passwordless sudo, not as root"
sudo -n true 2>/dev/null || die "passwordless sudo is required (T-Pot's unattended installer needs it)"

log "installing base packages"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git curl jq ca-certificates >/dev/null

# ---------------------------------------------------------------- phase 1: T-Pot
if ! es_up && [ ! -d "$HOME/tpotce" ]; then
    log "phase 1: installing T-Pot (hive). This takes 10-30 minutes and ends with a reboot."
    git clone --depth 1 https://github.com/telekom-security/tpotce.git "$HOME/tpotce"

    # continue automatically after the reboot
    sudo tee "/etc/systemd/system/$SERVICE.service" >/dev/null <<EOF
[Unit]
Description=php-Honeypot deployment (resume after T-Pot install)
After=network-online.target docker.service tpot.service
Wants=network-online.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$PROJ
ExecStart=$PROJ/deploy.sh --resume
StandardOutput=append:$HOME/php-honeypot-deploy.log
StandardError=append:$HOME/php-honeypot-deploy.log
TimeoutStartSec=3h

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE.service" >/dev/null

    (cd "$HOME/tpotce" && ./install.sh -s -t h -u "$WEB_USER" -p "$WEB_PASS")
    log "T-Pot installed. Rebooting in 10 s. Afterwards: SSH is on port 64295; deployment continues on its own."
    echo "Follow progress with:  ssh -p 64295 $USER@<vps-ip> 'tail -f ~/php-honeypot-deploy.log'"
    sleep 10; sudo reboot
    exit 0
fi

# ---------------------------------------------------------------- phase 2: add-on
wait_es
TPOT_COMPOSE="$HOME/tpotce/docker-compose.yml"

if grep -qE '^\s*- "(80:80|443:443)"' "$TPOT_COMPOSE" 2>/dev/null; then
    log "freeing ports 80/443 from T-Pot (Snare, h0neytr4p) and restarting it"
    "$PROJ/scripts/prepare-tpot.sh" "$TPOT_COMPOSE"
    sudo systemctl restart tpot
    sleep 20; wait_es
fi

log "preparing Elasticsearch (enrichment pipeline, 30-day retention, mappings)"
"$PROJ/scripts/setup.sh"

if [ -n "$DOMAIN" ] && [ ! -f "$PROJ/certs/fullchain.pem" ]; then
    log "requesting a TLS certificate for $DOMAIN (DNS A record must already point to this VPS)"
    "$PROJ/scripts/get-cert.sh" "$DOMAIN" "$EMAIL" || echo "WARNING: certificate failed; continuing with HTTP only"
fi

log "writing .env"
if [ ! -f "$PROJ/.env" ]; then
    SHOP_URL="http://localhost"; [ -n "$DOMAIN" ] && [ -f "$PROJ/certs/fullchain.pem" ] && SHOP_URL="https://$DOMAIN"
    [ -n "$DOMAIN" ] && [ ! -f "$PROJ/certs/fullchain.pem" ] && SHOP_URL="http://$DOMAIN"
    cat > "$PROJ/.env" <<EOF
SHOP_URL=$SHOP_URL
DB_PASS=$(head -c 18 /dev/urandom | base64 | tr -dc 'A-Za-z0-9')
CERT_DIR=./certs
SLACK_WEBHOOK_URL=
EOF
fi
mkdir -p "$PROJ/certs"

log "building and starting the add-on (first build downloads WordPress and WooCommerce; allow ~10 minutes)"
cd "$PROJ"
if docker info >/dev/null 2>&1; then DOCKER="docker"; else DOCKER="sudo docker"; fi
$DOCKER compose up -d --build

log "waiting for the shop to finish seeding"
for _ in $(seq 1 120); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: localhost' http://127.0.0.1:80/ || true)
    [ "$code" = "200" ] && break; sleep 5
done
echo "shop answered HTTP ${code:-none}"

log "importing the Kibana dashboard"
for _ in $(seq 1 60); do curl -fsS -o /dev/null http://127.0.0.1:64296/api/status 2>/dev/null && break; sleep 5; done
"$PROJ/scripts/kibana-import.sh" || echo "WARNING: Kibana import failed; re-run scripts/kibana-import.sh later"

# cleanup of the resume machinery and the stored password
if [ -f "/etc/systemd/system/$SERVICE.service" ]; then
    sudo systemctl disable "$SERVICE.service" >/dev/null 2>&1 || true
    sudo rm -f "/etc/systemd/system/$SERVICE.service"; sudo systemctl daemon-reload
fi
rm -f "$STATE"

IP=$(curl -fsS https://api.ipify.org 2>/dev/null || echo "<vps-ip>")
cat <<EOF

================  php-Honeypot is running  ================
Shop (the bait)     http://$IP/        ${DOMAIN:+https://$DOMAIN/}
SSH                 ssh -p 64295 $USER@$IP
T-Pot web UI        https://$IP:64297   (user: ${WEB_USER:-your web user})
                    -> Kibana -> Dashboards -> "php-Honeypot"
Live dashboard      ssh -p 64295 -L 8000:127.0.0.1:64300 $USER@$IP   then open http://localhost:8000
Raw captures        docker volume 'hpdata' (captures/<sha256>.bin, logs/events.jsonl)
Reset the shop      scripts/reset-shop.sh [--db]

Firewall: in your VPS provider's firewall, allow 80/443 (+ the other T-Pot honeypot ports you want exposed)
from anywhere, and restrict 64295 and 64297 to your own IP.
EOF
