#!/bin/bash
# One-time shop seeding: fictional brand "Trailhaven", fake products with generated images, fake customers.
# The admin password is random and never shown, so no attacker can actually log in as admin
# (a successful login would open a second, unrelated route to code execution and muddy the data).
set -e
cd /var/www/html
WP="wp --allow-root"
ADMIN_PASS="$(head -c 24 /dev/urandom | base64)"

$WP core install --url="${SHOP_URL:-http://localhost}" --title="Trailhaven Outdoor Supply" \
    --admin_user=shopmanager --admin_password="$ADMIN_PASS" --admin_email=shop@trailhaven.example --skip-email
$WP plugin activate woocommerce
$WP theme activate storefront
$WP option update blogdescription "Gear for the long way round"
$WP option update woocommerce_currency EUR
$WP option update woocommerce_default_country DE
$WP option update woocommerce_store_address "Hafenstrasse 12"
$WP option update woocommerce_store_city "Hamburg"
$WP option update woocommerce_store_postcode "20457"
# .htaccess is written by bait.sh on every start; WP-CLI cannot detect mod_rewrite itself
$WP rewrite structure '/%postname%/'

# make sure WooCommerce's Shop/Cart/Checkout/My account pages exist (normally created by its setup wizard)
$WP wc tool run install_pages --user=shopmanager >/dev/null 2>&1 || true

U="--user=shopmanager"
declare -A CAT
for c in Tents Packs Footwear Cooking Sleeping Accessories; do
    CAT[$c]=$($WP wc product_cat create --name="$c" --porcelain $U)
done

add() { # name price category colour description
    local id
    id=$($WP wc product create --name="$1" --type=simple --regular_price="$2" --description="$5" \
        --short_description="$5" --status=publish --manage_stock=true --stock_quantity=$((RANDOM % 40 + 5)) \
        --categories="[{\"id\":${CAT[$3]}}]" --porcelain $U)
    php /opt/seed/make-image.php "$1" "$4" "/tmp/img-$id.png"
    $WP media import "/tmp/img-$id.png" --post_id="$id" --featured_image --porcelain >/dev/null
    rm -f "/tmp/img-$id.png"
}
add "Ridge 2P tent"         189.00 Tents       "#2f6f4f" "Freestanding two-person three-season tent."
add "Ridge 3P tent"         239.00 Tents       "#3b7d5b" "Roomy three-person version of our bestseller."
add "Summit 45L pack"       129.00 Packs       "#b5532a" "Lightweight trekking pack with rain cover."
add "Daybreak 24L pack"      79.00 Packs       "#c26a3a" "Everyday hiking daypack."
add "Ember camp stove"       54.90 Cooking     "#a63d2f" "Compact canister stove, boils 1L in 3 minutes."
add "Cinder cook set"        44.00 Cooking     "#7a4a3a" "Nesting pot and pan set, hard-anodised."
add "Frost -5 sleeping bag"  99.00 Sleeping    "#2f5d8a" "Synthetic mummy bag rated to -5 C."
add "Dune sleeping mat"      64.00 Sleeping    "#4a7fa8" "Self-inflating mat, 5 cm thick."
add "Ledge trail boots"     149.00 Footwear    "#5a4a3a" "Waterproof mid-cut hiking boots."
add "Pebble trail socks"     16.50 Footwear    "#6b6b5a" "Merino blend, pack of two."
add "Beacon headlamp"        39.90 Accessories "#8a6d1f" "300 lumen rechargeable headlamp."
add "Ranger trekking poles"  59.00 Accessories "#4a5a6a" "Aluminium, folding, pair."

# storefront front page: the Shop page, not the default blog
SHOP_ID=$($WP option get woocommerce_shop_page_id)
$WP option update show_on_front page
$WP option update page_on_front "$SHOP_ID"
$WP post delete 1 2 --force >/dev/null 2>&1 || true      # default "Hello world!" post and "Sample Page"

# fictional customers (example.invalid never resolves)
first=(Anna Ben Clara David Eva Felix Greta Hans Ida Jonas Klara Lars Mia Nico Olga Paul)
last=(Becker Fischer Hoffmann Keller Lehmann Meyer Neumann Richter Schmitt Wagner Weber Wolf)
for i in $(seq 1 30); do
    f=${first[$((RANDOM % ${#first[@]}))]}; l=${last[$((RANDOM % ${#last[@]}))]}
    $WP wc customer create --email="$(echo "$f.$l$i" | tr 'A-Z' 'a-z')@example.invalid" \
        --first_name="$f" --last_name="$l" --password="$(head -c 12 /dev/urandom | base64)" $U >/dev/null || true
done
echo "[shop] seeding done"
