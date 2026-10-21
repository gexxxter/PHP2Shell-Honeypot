#!/bin/bash
# Idempotent: (re)creates everything that lives on the container's own filesystem and is therefore lost when the container
# is recreated while the database survives: product images (media attachments), the homepage hero and the favicon.
# Runs after seeding and on every start (see bait.sh), so a reset never leaves broken images behind.
cd /var/www/html
WP="wp --allow-root"
U="--user=shopmanager"

mkdir -p assets
[ -f assets/hero.png ] || php /opt/seed/make-banner.php hero assets/hero.png
[ -f favicon.ico ]     || php /opt/seed/make-banner.php favicon favicon.ico

while IFS='|' read -r name price sale cat type color sku weight short long; do
    [ -n "$sku" ] || continue
    id=$($WP post list --post_type=product --meta_key=_sku --meta_value="$sku" --field=ID | head -1)
    [ -n "$id" ] || continue
    tid=$($WP post meta get "$id" _thumbnail_id 2>/dev/null || true)
    file=""
    [ -n "$tid" ] && file=$($WP eval "echo (string) get_attached_file((int) '$tid');" 2>/dev/null || true)
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        [ -n "$tid" ] && $WP post delete "$tid" --force >/dev/null 2>&1 || true
        php /opt/seed/make-image.php "$type" "$color" "/tmp/img-$sku.png"
        $WP media import "/tmp/img-$sku.png" --post_id="$id" --featured_image --title="$name" --alt="$name" --porcelain >/dev/null
        rm -f "/tmp/img-$sku.png"
        echo "[shop] image (re)created for $name"
    fi
done < /opt/seed/products.tsv

# category tiles: use the first product's image instead of WooCommerce's grey placeholder
for row in $($WP term list product_cat --fields=term_id,slug --format=csv | tail -n +2); do
    tid_cat=${row%%,*}; slug=${row##*,}
    [ "$slug" = "uncategorized" ] && continue
    pid=$($WP post list --post_type=product --product_cat="$slug" --field=ID --posts_per_page=1 | head -1)
    [ -n "$pid" ] || continue
    thumb=$($WP post meta get "$pid" _thumbnail_id 2>/dev/null || true)
    [ -n "$thumb" ] && $WP term meta update "$tid_cat" thumbnail_id "$thumb" >/dev/null
done
