<?php
// Homepage hero banner and favicon: php make-banner.php hero out.png | favicon out.png
[$self, $what, $out] = $argv;
$font = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
$fontR = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
if ($what === 'favicon') {
    $im = imagecreatetruecolor(64, 64);
    imagefill($im, 0, 0, imagecolorallocate($im, 47, 111, 79));
    imagefilledpolygon($im, [8, 52, 32, 14, 56, 52], imagecolorallocate($im, 245, 245, 243));
    imagefilledpolygon($im, [24, 52, 32, 34, 40, 52], imagecolorallocate($im, 47, 111, 79));
    imagepng($im, $out);
    exit;
}
$W = 2400; $H = 640;                                   // drawn at 2x, downsampled to 1200x320
$im = imagecreatetruecolor($W, $H);
for ($y = 0; $y < $H; $y++) {                          // sky gradient, dusk
    $t = $y / $H;
    imageline($im, 0, $y, $W, $y, imagecolorallocate($im, (int)(38 + 70 * $t), (int)(70 + 70 * $t), (int)(95 + 40 * $t)));
}
imagefilledellipse($im, 1850, 260, 150, 150, imagecolorallocate($im, 250, 226, 170));
$layers = [[0.62, [30, 52, 58], 11], [0.74, [22, 40, 44], 7], [0.86, [14, 28, 30], 5]];
foreach ($layers as [$base, $col, $seed]) {            // mountain ridges
    $pts = [0, $H];
    for ($x = 0; $x <= $W; $x += 40) {
        $y = $H * $base - 90 * sin($x / 330 + $seed) - 60 * sin($x / 140 + $seed * 2) - 25 * sin($x / 55 + $seed);
        array_push($pts, $x, (int)$y);
    }
    array_push($pts, $W, $H);
    imagefilledpolygon($im, $pts, imagecolorallocate($im, ...$col));
}
// tent silhouette
imagefilledpolygon($im, [420, 600, 560, 440, 700, 600], imagecolorallocate($im, 8, 16, 16));
imagefilledellipse($im, 560, 520, 18, 18, imagecolorallocate($im, 250, 210, 120));
$white = imagecolorallocate($im, 255, 255, 255);
$soft = imagecolorallocate($im, 214, 226, 220);
imagettftext($im, 74, 0, 160, 250, $white, $font, 'Autumn trail sale');
imagettftext($im, 36, 0, 164, 320, $soft, $fontR, 'Up to 30% off tents, packs and sleeping gear');
imagefilledrectangle($im, 164, 380, 520, 464, imagecolorallocate($im, 63, 125, 92));
imagettftext($im, 32, 0, 206, 436, $white, $font, 'Shop the sale');
$small = imagecreatetruecolor(1200, 320);
imagecopyresampled($small, $im, 0, 0, 0, 0, 1200, 320, $W, $H);
imagepng($small, $out);
