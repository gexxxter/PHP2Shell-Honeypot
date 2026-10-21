#!/bin/bash
# Obtains a Let's Encrypt certificate with certbot's standalone mode and copies it to ./certs for the capture proxy.
# Standalone mode needs port 80 free: `deploy.sh` runs this before the stack starts. If the stack is already running,
# this script stops the capture proxy for the few seconds certbot needs, then starts it again.
# A real certificate is published in certificate-transparency logs, which scanners watch: it makes the shop discoverable.
set -e
DOMAIN="${1:?usage: get-cert.sh your-domain.example [email]}"
EMAIL="${2:-}"
cd "$(dirname "$0")/.."
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get install -y -qq certbot >/dev/null 2>&1

args=(certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos)
if [ -n "$EMAIL" ]; then args+=(-m "$EMAIL"); else args+=(--register-unsafely-without-email); fi

running=0
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -qx capture; then running=1; sudo docker stop capture >/dev/null; fi
set +e
sudo certbot "${args[@]}"; rc=$?
set -e
if [ "$rc" = 0 ]; then
    mkdir -p certs
    sudo cp -L "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/etc/letsencrypt/live/$DOMAIN/privkey.pem" certs/
    sudo chmod 644 certs/*.pem
fi
# start the proxy again only now, so it loads the new certificate files (it reads them once at startup)
[ "$running" = 1 ] && sudo docker start capture >/dev/null
[ "$rc" = 0 ] || { echo "certbot failed (exit $rc). Is the DNS A record for $DOMAIN pointing at this server, and is port 80 reachable?"; exit "$rc"; }
echo "Certificates copied to ./certs. Set SHOP_URL=https://$DOMAIN in .env."
