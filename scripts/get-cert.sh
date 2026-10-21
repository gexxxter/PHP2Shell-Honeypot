#!/bin/bash
# Obtains a Let's Encrypt certificate with certbot's standalone mode (needs port 80 free: run BEFORE `docker compose up`).
# A real certificate is published in certificate-transparency logs, which scanners watch: it makes the shop discoverable.
set -e
DOMAIN="${1:?usage: get-cert.sh your-domain.example [email]}"
EMAIL="${2:-}"
sudo apt-get install -y certbot >/dev/null
sudo certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos ${EMAIL:+-m "$EMAIL"} ${EMAIL:--register-unsafely-without-email}
mkdir -p certs
sudo cp -L "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "/etc/letsencrypt/live/$DOMAIN/privkey.pem" certs/
sudo chmod 644 certs/*.pem
echo "Certificates copied to ./certs. Set SHOP_URL=https://$DOMAIN in .env."
