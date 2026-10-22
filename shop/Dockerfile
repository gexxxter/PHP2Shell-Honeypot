# PHP 8.3.35 is vulnerable to CVE-2026-109618 / CVE-2026-109619 (fixed in 8.3.36). Do NOT bump this tag.
# WordPress, WooCommerce and the theme are installed at build time at their current versions, so the only
# known-exploitable component should be PHP itself.
FROM php:8.3.35-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libzip-dev libpng-dev libjpeg-dev libfreetype6-dev libicu-dev \
        mariadb-client curl unzip less ca-certificates fonts-dejavu-core \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j2 mysqli gd zip intl exif opcache bcmath \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

# The base image ships with AllowOverride None, which silently disables WordPress's .htaccess rewrites:
# every pretty URL (/shop/, /cart/, /product/...) would then be a 404.
RUN printf '<Directory /var/www/html>\n    AllowOverride All\n</Directory>\n' > /etc/apache2/conf-available/wp-override.conf \
    && a2enconf wp-override

RUN curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

COPY php.ini /usr/local/etc/php/conf.d/zz-honeypot.ini
WORKDIR /var/www/html
RUN wp core download --allow-root --locale=en_US \
    && curl -fsSL -o /tmp/wc.zip https://downloads.wordpress.org/plugin/woocommerce.latest-stable.zip \
    && curl -fsSL -o /tmp/sf.zip https://downloads.wordpress.org/theme/storefront.latest-stable.zip \
    && unzip -q /tmp/wc.zip -d wp-content/plugins && unzip -q /tmp/sf.zip -d wp-content/themes && rm /tmp/*.zip \
    && chown -R www-data:www-data /var/www/html

COPY seed/ /opt/seed/
COPY entrypoint.sh /entrypoint.sh
# strip Windows line endings in case the repo was checked out with CRLF
RUN tr -d '\r' < /entrypoint.sh > /entrypoint.tmp && mv /entrypoint.tmp /entrypoint.sh \
    && for f in /opt/seed/*.sh /opt/seed/*.php /opt/seed/*.tsv; do tr -d '\r' < "$f" > "$f.tmp" && mv "$f.tmp" "$f"; done \
    && chmod +x /entrypoint.sh /opt/seed/*.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
