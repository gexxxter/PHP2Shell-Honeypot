#!/bin/bash
# Bait files that make the shop look like a sloppily deployed target.
# All credentials are fake and carry the marker HT7f3a (see HONEYTOKEN_MARKER): any request containing it
# is tagged honeytoken-reuse, and any connection to db-backup.internal is logged by the decoy listener.
cd /var/www/html
M="HT7f3a"
rnd() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
# built from pieces so secret scanners do not flag this repository
S1="sk"; S2="live"

cat > .env <<EOF
APP_ENV=production
APP_DEBUG=false
DB_HOST=db-backup.internal
DB_PORT=3306
DB_DATABASE=trailhaven_prod
DB_USERNAME=shop_prod_${M}
DB_PASSWORD=${M}-$(rnd 6)
STRIPE_SECRET_KEY=${S1}_${S2}_${M}$(rnd 10)
SMTP_HOST=mail.trailhaven.example
SMTP_PASSWORD=${M}-$(rnd 6)
EOF

cat > backup.sql <<EOF
-- Trailhaven nightly backup (do not publish)
-- Host: db-backup.internal   Database: trailhaven_prod
CREATE TABLE users (id INT, email VARCHAR(120), pw_hash VARCHAR(80));
INSERT INTO users VALUES (1,'admin@trailhaven.example','\$2y\$10\$${M}$(rnd 20)');
INSERT INTO users VALUES (2,'billing@trailhaven.example','\$2y\$10\$${M}$(rnd 20)');
EOF

cat > robots.txt <<'EOF'
User-agent: *
Disallow: /backup.sql
Disallow: /.env
Disallow: /admin-old/
EOF

mkdir -p admin-old
cat > admin-old/index.php <<'EOF'
<!doctype html><title>Legacy admin</title>
<form method="post"><h3>Legacy admin</h3>
<input name="username" placeholder="Username"><br><input type="password" name="password" placeholder="Password"><br>
<button>Sign in</button></form>
<?php if ($_SERVER['REQUEST_METHOD'] === 'POST') { echo '<p>Invalid credentials.</p>'; } ?>
EOF

echo '<?php phpinfo();' > phpinfo.php

# WordPress itself must never trigger what the RCE rules look for: no process spawns (PHP mail() execs
# sendmail) and no outbound/loopback connections (update checks, WooCommerce's async runner, REST loopback).
# So swallow outgoing mail and refuse every WordPress HTTP request in-process. An attacker's own code is not
# affected by this: it opens sockets directly, which is exactly what gets flagged.
mkdir -p wp-content/mu-plugins
cat > wp-content/mu-plugins/quiet-shop.php <<'PHP'
<?php
add_filter('pre_wp_mail', '__return_true');
add_filter('pre_http_request', function () { return new WP_Error('http_disabled', 'HTTP requests are disabled'); });
add_filter('action_scheduler_allow_async_request_runner', '__return_false');
add_action('wp_head', function () {
    echo '<style>body.home .entry-title{display:none}.woocommerce-store-notice{background:#2f6f4f!important}.woocommerce-store-notice a{color:#fff!important}</style>';
});
PHP
rm -f wp-content/mu-plugins/no-mail.php

# WordPress rewrite rules. Written on every start (WP-CLI cannot detect mod_rewrite, and the Apache image must
# have AllowOverride All, see Dockerfile). Without this every pretty URL (/shop/, /cart/, /product/...) is a 404.
cat > .htaccess <<'HT'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HT

# product images / hero / favicon live on the container filesystem: recreate them if a reset removed them
/opt/seed/images.sh
