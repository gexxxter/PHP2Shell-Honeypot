#!/bin/bash
# One-time shop seeding: fictional brand "Trailhaven", a believable catalogue, reviews, legal and info pages, menus,
# footer, sidebar and theme colours. Everything is invented; no real company, person or address is meant.
# The admin password is random and never shown, so no attacker can actually log in as admin
# (a successful login would open a second, unrelated route to code execution and muddy the data).
set -e
cd /var/www/html
WP="wp --allow-root"
U="--user=shopmanager"
ADMIN_PASS="$(head -c 24 /dev/urandom | base64)"

$WP core install --url="${SHOP_URL:-http://localhost}" --title="Trailhaven Outdoor Supply" \
    --admin_user=shopmanager --admin_password="$ADMIN_PASS" --admin_email=shop@trailhaven.example --skip-email
$WP plugin activate woocommerce
$WP theme activate storefront
$WP option update blogdescription "Gear for the long way round"
$WP option update timezone_string "Europe/Berlin"
$WP option update date_format "j F Y"
$WP option update woocommerce_currency EUR
$WP option update woocommerce_default_country DE
$WP option update woocommerce_store_address "Kaispeicher 9"
$WP option update woocommerce_store_city "Hamburg"
$WP option update woocommerce_store_postcode "20457"
$WP option update woocommerce_demo_store yes
$WP option update woocommerce_demo_store_notice "Free shipping on orders over 75 EUR  |  30-day returns  |  Delivery in 2-4 working days"
$WP option update woocommerce_enable_reviews yes
$WP option update woocommerce_review_rating_verification_label yes
$WP option update woocommerce_calc_taxes yes
$WP option update woocommerce_prices_include_tax yes
$WP option update comments_notify 0
$WP rewrite structure '/%postname%/'     # .htaccess itself is written by bait.sh on every start

# WooCommerce's own Shop / Cart / Checkout / My account pages (normally created by its setup wizard)
$WP wc tool run install_pages $U >/dev/null 2>&1 || true

# --- theme colours: a muted forest-green brand instead of Storefront's default purple
$WP theme mod set storefront_accent_color '#2f6f4f'
$WP theme mod set storefront_heading_color '#1f2a24'
$WP theme mod set storefront_text_color '#3d4640'
$WP theme mod set storefront_header_background_color '#ffffff'
$WP theme mod set storefront_header_link_color '#1f2a24'
$WP theme mod set storefront_header_text_color '#52605a'
$WP theme mod set storefront_button_background_color '#2f6f4f'
$WP theme mod set storefront_button_text_color '#ffffff'
$WP theme mod set storefront_button_alt_background_color '#2f6f4f'
$WP theme mod set storefront_button_alt_text_color '#ffffff'
$WP theme mod set storefront_footer_background_color '#1f2a24'
$WP theme mod set storefront_footer_heading_color '#ffffff'
$WP theme mod set storefront_footer_text_color '#c9d6cf'
$WP theme mod set storefront_footer_link_color '#ffffff'

# --- categories
declare -A CAT
for c in Tents Packs Cooking Sleeping Footwear Accessories; do
    CAT[$c]=$($WP wc product_cat create --name="$c" --porcelain $U)
done

# --- products (see products.tsv): name|price|sale|category|type|colour|sku|weight|short|long
while IFS='|' read -r name price sale cat type color sku weight short long; do
    [ -n "$sku" ] || continue
    args=(--name="$name" --type=simple --regular_price="$price" --sku="$sku" --weight="$weight"
          --short_description="$short" --description="$long" --status=publish
          --manage_stock=true --stock_quantity=$((RANDOM % 40 + 5)) --categories="[{\"id\":${CAT[$cat]}}]")
    [ -n "$sale" ] && args+=(--sale_price="$sale")
    $WP wc product create "${args[@]}" --porcelain $U >/dev/null
done < /opt/seed/products.tsv

/opt/seed/images.sh

# --- customer reviews
names=("Anna K." "Markus B." "Sofia L." "Jonas W." "Lena H." "Tim R." "Marie S." "Felix P." "Nora D." "Paul G.")
good=("Great quality for the price, exactly as described." "Used it on a week-long trip and it held up perfectly."
      "Arrived quickly and well packed. Very happy." "Better than I expected. Would buy again."
      "Solid build and sensible details. Recommended." "Lightweight and comfortable, no complaints.")
ok=("Good overall, but the instructions could be clearer." "Does the job. Took a few days to get used to.")
for pid in $($WP post list --post_type=product --field=ID); do
    for k in $(seq 1 $((RANDOM % 4 + 2))); do
        n=${names[$((RANDOM % ${#names[@]}))]}
        if [ $((RANDOM % 6)) -eq 0 ]; then rating=$((RANDOM % 2 + 3)); text=${ok[$((RANDOM % ${#ok[@]}))]}
        else rating=$((RANDOM % 2 + 4)); text=${good[$((RANDOM % ${#good[@]}))]}; fi
        cid=$($WP comment create --comment_post_ID="$pid" --comment_author="$n" --comment_author_email="reviewer$RANDOM@example.invalid" \
              --comment_content="$text" --comment_type=review --comment_approved=1 --porcelain)
        $WP comment meta add "$cid" rating "$rating" >/dev/null
        $WP comment meta add "$cid" verified 1 >/dev/null
    done
    $WP eval "WC_Comments::clear_transients($pid);" >/dev/null 2>&1 || true
done

# --- pages
mkpage() { $WP post create --post_type=page --post_status=publish --post_title="$1" --post_name="$2" --porcelain --post_content="$3"; }
HOME_ID=$(mkpage "Home" "home" '<img src="/assets/hero.png" alt="Autumn trail sale" style="width:100%;height:auto;border-radius:4px" />
<h2>Shop by category</h2>
[product_categories number="6" columns="3" parent="0"]
<h2>On sale</h2>
[products on_sale="true" limit="4" columns="4"]
<h2>New arrivals</h2>
[products limit="4" columns="4" orderby="date" order="DESC"]')
ABOUT_ID=$(mkpage "About us" "about-us" '<p>Trailhaven started in 2014 in a Hamburg flat with a single question: why is good outdoor gear either cheap and flimsy or expensive and over-engineered?</p>
<p>Today we are a small team of hikers, climbers and cyclists. We test every product on real trips before it goes into the shop, and we only sell what we would pack ourselves.</p>
<h3>What we care about</h3>
<ul><li>Gear that lasts: we repair and resole before we replace.</li><li>Honest descriptions, including weights measured on our own scale.</li><li>Fair prices and no fake discounts.</li></ul>')
CONTACT_ID=$(mkpage "Contact" "contact" '<p>Questions about sizing, an order or a repair? We usually reply within one working day.</p>
<p><strong>Email:</strong> service@trailhaven.example<br /><strong>Phone:</strong> +49 40 5550 1234 (Mon-Fri, 9:00-17:00)</p>
<p><strong>Trailhaven Outdoor Supply GmbH</strong><br />Kaispeicher 9<br />20457 Hamburg, Germany</p>')
SHIP_ID=$(mkpage "Shipping and returns" "shipping-and-returns" '<h3>Shipping</h3>
<p>Orders placed before 14:00 on working days ship the same day. Delivery within Germany takes 2-4 working days; EU delivery 3-7 working days. Shipping is free on orders over 75 EUR, otherwise 4.90 EUR (Germany) or 9.90 EUR (EU).</p>
<h3>Returns</h3>
<p>You have 30 days to return unused items for a full refund. Write to service@trailhaven.example with your order number and we will send a prepaid label.</p>')
IMPR_ID=$(mkpage "Imprint" "imprint" '<p><strong>Trailhaven Outdoor Supply GmbH</strong><br />Kaispeicher 9<br />20457 Hamburg</p>
<p>Managing director: Jonas Lindqvist<br />Email: service@trailhaven.example<br />Phone: +49 40 5550 1234</p>
<p>Commercial register: Amtsgericht Hamburg<br />Responsible for content: Jonas Lindqvist</p>')
PRIV_ID=$(mkpage "Privacy policy" "privacy-policy" '<p>We process personal data only as far as needed to run this shop: order and delivery details, your account, and technical logs. We do not sell data. Payment is handled by our payment provider; we never see full card numbers.</p>
<p>You can ask for access to, correction or deletion of your data at any time at service@trailhaven.example.</p>')
TERMS_ID=$(mkpage "Terms and conditions" "terms-and-conditions" '<p>These terms apply to all orders placed with Trailhaven Outdoor Supply GmbH. A contract is formed when we confirm your order by email. Prices include VAT. Statutory warranty rights remain unaffected.</p>')

$WP option update show_on_front page
$WP option update page_on_front "$HOME_ID"
$WP post delete 1 2 --force >/dev/null 2>&1 || true      # default "Hello world!" post and "Sample Page"

# --- menus
$WP menu create "Primary" >/dev/null
$WP menu item add-post Primary "$HOME_ID" --title="Home" >/dev/null
SHOPPAGE=$($WP option get woocommerce_shop_page_id)
$WP menu item add-post Primary "$SHOPPAGE" --title="Shop" >/dev/null
for c in Tents Packs Cooking Sleeping Footwear; do $WP menu item add-term Primary product_cat "${CAT[$c]}" >/dev/null; done
$WP menu item add-post Primary "$ABOUT_ID" >/dev/null
$WP menu item add-post Primary "$CONTACT_ID" >/dev/null
$WP menu location assign Primary primary >/dev/null
$WP menu location assign Primary handheld >/dev/null

$WP menu create "Customer service" >/dev/null
$WP menu item add-post "Customer service" "$SHIP_ID" >/dev/null
$WP menu item add-post "Customer service" "$CONTACT_ID" >/dev/null
$WP menu item add-post "Customer service" "$($WP option get woocommerce_myaccount_page_id)" >/dev/null
$WP menu item add-post "Customer service" "$TERMS_ID" >/dev/null
$WP menu create "Company" >/dev/null
$WP menu item add-post Company "$ABOUT_ID" >/dev/null
$WP menu item add-post Company "$IMPR_ID" >/dev/null
$WP menu item add-post Company "$PRIV_ID" >/dev/null

# --- widgets: a shop-like sidebar and a four-column footer
$WP widget reset sidebar-1 >/dev/null 2>&1 || true
$WP widget add woocommerce_product_categories sidebar-1 1 --title="Categories" --hide_empty=1 >/dev/null 2>&1 || true
$WP widget add woocommerce_price_filter sidebar-1 2 --title="Filter by price" >/dev/null 2>&1 || true
$WP widget add woocommerce_top_rated_products sidebar-1 3 --title="Top rated" --number=3 >/dev/null 2>&1 || true
CS_ID=$($WP menu list --fields=term_id,name --format=csv | awk -F, '$2=="Customer service"{print $1}')
CO_ID=$($WP menu list --fields=term_id,name --format=csv | awk -F, '$2=="Company"{print $1}')
$WP widget add nav_menu footer-1 1 --title="Customer service" --nav_menu="$CS_ID" >/dev/null 2>&1 || true
$WP widget add nav_menu footer-2 1 --title="Company" --nav_menu="$CO_ID" >/dev/null 2>&1 || true
$WP widget add text footer-3 1 --title="Visit us" --text='<p>Kaispeicher 9<br>20457 Hamburg</p><p>Mon-Fri 10:00-18:00<br>Sat 10:00-16:00</p>' >/dev/null 2>&1 || true
$WP widget add text footer-4 1 --title="Questions?" --text='<p>service@trailhaven.example<br>+49 40 5550 1234</p><p>We reply within one working day.</p>' >/dev/null 2>&1 || true

# --- fictional customers (example.invalid never resolves)
first=(Anna Ben Clara David Eva Felix Greta Hans Ida Jonas Klara Lars Mia Nico Olga Paul)
last=(Becker Fischer Hoffmann Keller Lehmann Meyer Neumann Richter Schmitt Wagner Weber Wolf)
for i in $(seq 1 30); do
    f=${first[$((RANDOM % ${#first[@]}))]}; l=${last[$((RANDOM % ${#last[@]}))]}
    $WP wc customer create --email="$(echo "$f.$l$i" | tr 'A-Z' 'a-z')@example.invalid" \
        --first_name="$f" --last_name="$l" --password="$(head -c 12 /dev/urandom | base64)" $U >/dev/null || true
done
echo "[shop] seeding done"
