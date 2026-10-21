#!/bin/bash
# One-time shop seeding: fictional brand "Trailhaven", fake products, fake customers.
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
$WP rewrite structure '/%postname%/' --hard

U="--user=shopmanager"
for c in Tents Packs Footwear Cooking Sleeping; do $WP wc product_cat create --name="$c" $U >/dev/null; done

add() { # name price description
    $WP wc product create --name="$1" --type=simple --regular_price="$2" --description="$3" \
        --status=publish --manage_stock=true --stock_quantity=$((RANDOM % 40 + 5)) $U >/dev/null
}
add "Ridge 2P tent"        189.00 "Freestanding two-person three-season tent."
add "Ridge 3P tent"        239.00 "Roomy three-person version of our bestseller."
add "Summit 45L pack"      129.00 "Lightweight trekking pack with rain cover."
add "Daybreak 24L pack"     79.00 "Everyday hiking daypack."
add "Ember camp stove"      54.90 "Compact canister stove, boils 1L in 3 minutes."
add "Cinder cook set"       44.00 "Nesting pot and pan set, hard-anodised."
add "Frost -5 sleeping bag" 99.00 "Synthetic mummy bag rated to -5 C."
add "Dune sleeping mat"     64.00 "Self-inflating mat, 5 cm thick."
add "Ledge trail boots"    149.00 "Waterproof mid-cut hiking boots."
add "Pebble trail socks"    16.50 "Merino blend, pack of two."
add "Beacon headlamp"       39.90 "300 lumen rechargeable headlamp."
add "Ranger trekking poles" 59.00 "Aluminium, folding, pair."

# fictional customers (example.invalid never resolves)
first=(Anna Ben Clara David Eva Felix Greta Hans Ida Jonas Klara Lars Mia Nico Olga Paul)
last=(Becker Fischer Hoffmann Keller Lehmann Meyer Neumann Richter Schmitt Wagner Weber Wolf)
for i in $(seq 1 30); do
    f=${first[$((RANDOM % ${#first[@]}))]}; l=${last[$((RANDOM % ${#last[@]}))]}
    $WP wc customer create --email="$(echo "$f.$l$i" | tr 'A-Z' 'a-z')@example.invalid" \
        --first_name="$f" --last_name="$l" --password="$(head -c 12 /dev/urandom | base64)" $U >/dev/null || true
done
echo "[shop] seeding done"
