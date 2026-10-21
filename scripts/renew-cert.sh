#!/bin/bash
# Renews the Let's Encrypt certificate (valid 90 days; certbot only renews when under 30 days remain) and restarts
# the capture proxy so it loads the new files. Port 80 is held by the proxy, so it is stopped for the renewal.
# deploy.sh installs a weekly cron job for this. Usage: renew-cert.sh your-domain.example
set -e
DOMAIN="${1:?usage: renew-cert.sh your-domain.example}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
certbot renew --quiet --standalone \
    --pre-hook "docker stop capture" \
    --deploy-hook "cp -L /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem $PROJ/certs/ && chmod 644 $PROJ/certs/*.pem" \
    --post-hook "docker start capture"
