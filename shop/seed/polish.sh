#!/bin/bash
# Idempotent content polish, runs on every start (after images.sh): product specifications, an FAQ, a size guide and a few
# journal posts, so the shop reads like a real, slightly boring business. Everything is invented. A page or post that
# already exists (by slug) is left alone, so edits made in the admin survive and nothing is duplicated.
cd /var/www/html
WP="wp --allow-root"
U="--user=shopmanager"

$WP eval-file /opt/seed/polish.php 2>&1 | sed 's/^/[shop] /'

exists() { [ -n "$($WP post list --post_type="$1" --name="$2" --post_status=publish,draft --field=ID 2>/dev/null | head -1)" ]; }
add_page() { # slug title content -> prints the new id, or nothing when it exists
    exists page "$1" && return 0
    $WP post create $U --post_type=page --post_status=publish --post_name="$1" --post_title="$2" --post_content="$3" --porcelain
}
add_post() { # slug title days-ago content
    exists post "$1" && return 0
    $WP post create $U --post_type=post --post_status=publish --post_name="$1" --post_title="$2" \
        --post_date="$(date -d "-$3 days" '+%Y-%m-%d') 09:$((RANDOM % 50 + 10)):00" --post_content="$4" --porcelain
}

FAQ_ID=$(add_page faq "FAQ" '<h2>Orders and delivery</h2>
<p><strong>How long does delivery take?</strong><br>Orders placed before 14:00 on working days ship the same day. Delivery within Germany takes 2-4 working days, EU delivery 3-7 working days.</p>
<p><strong>Can I track my parcel?</strong><br>Yes. You receive a tracking link by email as soon as your order leaves the warehouse.</p>
<p><strong>Which payment methods do you accept?</strong><br>Card, PayPal, SEPA direct debit and invoice for returning customers.</p>
<h2>Returns and warranty</h2>
<p><strong>What is your return policy?</strong><br>You have 30 days to return unused items for a full refund. We send a prepaid label.</p>
<p><strong>Is there a warranty?</strong><br>All Trailhaven products carry a 2-year warranty against defects in materials and workmanship. Boots and tents can be repaired by our workshop in Hamburg.</p>
<h2>Gear advice</h2>
<p><strong>Which tent size should I pick?</strong><br>Take the number of people and add one if you want space for packs. Our <a href="/journal/">journal</a> has a guide.</p>
<p><strong>I am between two boot sizes. What now?</strong><br>Take the larger size and wear thicker socks. See the <a href="/size-guide/">size guide</a>.</p>
<p>Still stuck? Write to service@trailhaven.example or call +49 40 5550 1234 (Mon-Fri, 9:00-17:00).</p>')
SIZE_ID=$(add_page size-guide "Size guide" '<h2>Boots</h2>
<table><thead><tr><th>EU</th><th>UK</th><th>US (men)</th><th>Foot length</th></tr></thead><tbody>
<tr><td>40</td><td>6.5</td><td>7.5</td><td>25.0 cm</td></tr><tr><td>41</td><td>7</td><td>8</td><td>25.5 cm</td></tr>
<tr><td>42</td><td>8</td><td>9</td><td>26.5 cm</td></tr><tr><td>43</td><td>9</td><td>10</td><td>27.5 cm</td></tr>
<tr><td>44</td><td>9.5</td><td>10.5</td><td>28.0 cm</td></tr><tr><td>45</td><td>10.5</td><td>11.5</td><td>29.0 cm</td></tr></tbody></table>
<h2>Socks</h2><p>Sizes 36-39, 40-43 and 44-47. If you are between sizes, take the larger one: merino shrinks a little in the first wash.</p>
<h2>Packs</h2><p>Measure from the bump at the base of your neck to the top of your hip bones. 42-46 cm fits most people with the Summit 45L; the back length is adjustable.</p>')

add_post choose-a-three-season-tent "How to choose a three-season tent" 21 '<p>A three-season tent covers spring to autumn: rain, wind and the odd cold night, but not heavy snow. Start with the number of sleepers and add one if you want your pack inside. Two doors and two vestibules sound like a luxury until you need to get out at night without climbing over your partner.</p>
<p>Look at weight and packed size next. A two-person tent around 2.4 kg is a good compromise; going lighter usually costs durability. Check the waterproof rating of the fly (1500 mm is enough for the floor, 3000 mm for the fly) and make sure the seams are taped.</p>
<p>Finally, pitch it at home before the trip. Ten minutes in the garden saves an hour in the dark.</p>'
add_post weekend-packing-list "A packing list for two nights out" 14 '<p>Our standard list for two nights in the hills, from the people who test the gear: tent, sleeping bag and mat, stove with a small canister, pot and spoon, a headlamp with spare batteries or a full charge, a warm layer, a rain jacket, and one more pair of socks than you think you need.</p>
<p>Food: 600 g of dry food per person per day is plenty. Water: carry one litre and treat the rest. Leave the cotton at home, it never dries.</p>'
add_post caring-for-your-sleeping-bag "Caring for your sleeping bag" 9 '<p>Never store a sleeping bag compressed. Keep it loose in the big cotton sack it came with, in a dry place. Wash it two or three times a year at 30 degrees with a mild detergent, dry it slowly with a few tennis balls, and it will outlast most tents.</p>
<p>A liner keeps the bag cleaner and adds a few degrees of warmth. We wash ours after every long trip.</p>'
add_post why-we-resole-boots "Why we resole boots instead of replacing them" 4 '<p>A good pair of boots has years in it; the sole usually wears out first. Our workshop in Hamburg resoles Ledge boots for a fixed price, usually within two weeks. Send them in, we replace the sole and clean the leather.</p>
<p>It costs less than new boots, keeps the fit you broke in, and keeps a pair out of the bin.</p>'

# menus: Journal, FAQ and size guide are added once, when the pages are created
JOURNAL_ID=$($WP post list --post_type=page --name=journal --field=ID | head -1)
if [ -z "$JOURNAL_ID" ]; then
    JOURNAL_ID=$($WP post create $U --post_type=page --post_status=publish --post_name=journal --post_title="Journal" --porcelain)
    $WP option update page_for_posts "$JOURNAL_ID" >/dev/null
    $WP menu item add-post Primary "$JOURNAL_ID" >/dev/null
fi
[ -n "$FAQ_ID" ]  && $WP menu item add-post "Customer service" "$FAQ_ID"  >/dev/null
[ -n "$SIZE_ID" ] && $WP menu item add-post "Customer service" "$SIZE_ID" >/dev/null
echo "[shop] content polish done"
