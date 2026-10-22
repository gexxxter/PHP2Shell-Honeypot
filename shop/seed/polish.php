<?php
// Product specifications shown in the "Additional information" tab: php polish.php via `wp eval-file`.
// Idempotent: the attribute list of each product is simply set again on every start.
$specs = [
    'TH-TNT-2P'  => ['Capacity' => '2 persons', 'Season' => '3-season', 'Fabric' => '20D ripstop nylon, 3000 mm PU coating', 'Poles' => '7001 aluminium, 2 poles', 'Packed size' => '46 x 16 cm', 'Doors' => '2 doors, 2 vestibules'],
    'TH-TNT-3P'  => ['Capacity' => '3 persons', 'Season' => '3-season', 'Fabric' => '20D ripstop nylon, 3000 mm PU coating', 'Poles' => '7001 aluminium, 3 poles', 'Packed size' => '52 x 17 cm', 'Doors' => '2 doors, 2 vestibules'],
    'TH-PCK-45'  => ['Volume' => '45 L', 'Back length' => 'Adjustable, 42-52 cm', 'Material' => '210D recycled nylon', 'Frame' => 'Aluminium stay, ventilated back panel', 'Rain cover' => 'Included'],
    'TH-PCK-24'  => ['Volume' => '24 L', 'Hydration' => 'Fits a 2 L bladder', 'Material' => '150D polyester, water-repellent', 'Pockets' => '2 side, 1 front, 1 lid', 'Rain cover' => 'Included'],
    'TH-CKN-STV' => ['Fuel' => 'Screw-thread gas canister (EN 417)', 'Output' => '2.8 kW', 'Boil time' => '1 L in about 3 minutes', 'Ignition' => 'Manual, piezo not included', 'Folded size' => '9 x 5 x 5 cm'],
    'TH-CKN-SET' => ['Material' => 'Hard-anodised aluminium', 'Pot' => '1.2 L with lid', 'Pan' => '0.8 L', 'Included' => 'Folding grip, mesh bag', 'Dishwasher safe' => 'Yes'],
    'TH-SLP-F5'  => ['Comfort / limit / extreme' => '0 / -5 / -18 C (EN 13537)', 'Fill' => 'Synthetic, 200 g/m2', 'Shape' => 'Mummy', 'Length' => 'Up to 185 cm body height', 'Packed size' => '40 x 22 cm'],
    'TH-SLP-MAT' => ['R-value' => '3.5', 'Thickness' => '5 cm', 'Length x width' => '183 x 51 cm', 'Packed size' => '28 x 14 cm', 'Inflation' => 'Self-inflating, valve included'],
    'TH-FTW-BT'  => ['Membrane' => 'Waterproof, breathable', 'Upper' => 'Leather and textile', 'Sole' => 'Lugged rubber, 4 mm', 'Cut' => 'Mid', 'Sizes' => 'EU 38-47'],
    'TH-FTW-SK'  => ['Material' => '52% merino wool, 45% polyamide, 3% elastane', 'Sizes' => '36-39, 40-43, 44-47', 'Pack' => '2 pairs', 'Wash' => '30 C, no tumble dryer'],
    'TH-ACC-HL'  => ['Output' => '300 lumens', 'Battery' => 'Rechargeable, 1200 mAh, USB-C', 'Burn time' => '40 h low / 4 h high', 'Modes' => 'White high, low, red, strobe', 'Water resistance' => 'IPX4'],
    'TH-ACC-TP'  => ['Material' => '7075 aluminium', 'Sections' => '3, folding', 'Length' => '105-135 cm', 'Grip' => 'Cork', 'Weight per pair' => '500 g'],
];
foreach ($specs as $sku => $rows) {
    $id = wc_get_product_id_by_sku($sku);
    if (!$id) continue;
    $p = wc_get_product($id);
    $attrs = [];
    $pos = 0;
    foreach ($rows as $name => $value) {
        $a = new WC_Product_Attribute();
        $a->set_id(0);
        $a->set_name($name);
        $a->set_options([$value]);
        $a->set_position($pos++);
        $a->set_visible(true);
        $a->set_variation(false);
        $attrs[] = $a;
    }
    $p->set_attributes($attrs);
    $p->save();
}
echo "specs set for " . count($specs) . " products\n";
