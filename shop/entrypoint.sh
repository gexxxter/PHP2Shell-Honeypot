#!/bin/bash
set -e
# Falco needs ~30-60 s to finish initialising; processes started before that are not attributed to this container.
sleep "${START_DELAY:-0}"
cd /var/www/html

echo "[shop] waiting for database..."
until php -r 'exit(@mysqli_connect(getenv("DB_HOST"), getenv("DB_USER"), getenv("DB_PASS")) ? 0 : 1);'; do
    sleep 2
done

if [ ! -f wp-config.php ]; then
    wp config create --allow-root --skip-check \
        --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST" --extra-php <<'PHP'
define('DISABLE_WP_CRON', true);
define('WP_AUTO_UPDATE_CORE', false);
define('AUTOMATIC_UPDATER_DISABLED', true);
define('WP_HTTP_BLOCK_EXTERNAL', true);
PHP
fi

if ! wp core is-installed --allow-root 2>/dev/null; then
    /opt/seed/seed.sh
fi

# bait is recreated on every (re)start, so tampering does not persist
/opt/seed/bait.sh
chown -R www-data:www-data /var/www/html

exec docker-php-entrypoint "$@"
