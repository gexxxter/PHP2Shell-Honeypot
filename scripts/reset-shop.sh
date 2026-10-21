#!/bin/bash
# Throws away the shop container (and any webshell dropped into its filesystem) and recreates it from the image.
# Pass --db to also wipe the database and reseed from scratch. Raw captures and logs are kept.
set -e
cd "$(dirname "$0")/.."
if [ "$1" = "--db" ]; then
    docker compose rm -sf realphp db
    docker volume rm -f "$(docker volume ls -q | grep '_dbdata$' | head -1)" >/dev/null
    docker compose up -d db
fi
docker compose up -d --force-recreate --no-deps realphp
