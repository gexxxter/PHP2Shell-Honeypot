<?php
// Product illustration: php make-image.php TYPE "#RRGGBB" out.png
// Drawn at 2x and downsampled for anti-aliasing. Light studio background, soft shadow, one object per product type.
[$self, $type, $hex, $out] = $argv;
$S = 1200;
$im = imagecreatetruecolor($S, $S);
imagealphablending($im, true);
[$r, $g, $b] = sscanf($hex, '#%02x%02x%02x');
$c = fn($rr, $gg, $bb) => imagecolorallocate($im, max(0, min(255, $rr)), max(0, min(255, $gg)), max(0, min(255, $bb)));
$main = $c($r, $g, $b);
$dark = $c((int)($r * .66), (int)($g * .66), (int)($b * .66));
$light = $c($r + 50, $g + 50, $b + 50);
$strap = $c(40, 40, 42);
$white = $c(245, 245, 243);
$metal = $c(170, 174, 178);
$metal2 = $c(120, 124, 130);
// background: soft vertical gradient
for ($y = 0; $y < $S; $y++) {
    $v = (int)(246 - 16 * ($y / $S));
    imageline($im, 0, $y, $S, $y, $c($v, $v, $v - 2));
}
// ground shadow
$sh = imagecolorallocatealpha($im, 0, 0, 0, 100);
imagefilledellipse($im, 600, 1010, 760, 90, $sh);
imagefilledellipse($im, 600, 1010, 560, 60, imagecolorallocatealpha($im, 0, 0, 0, 90));
$poly = fn(array $p, $col) => imagefilledpolygon($im, $p, $col);
$rr = function ($x1, $y1, $x2, $y2, $rad, $col) use ($im) {          // rounded rectangle
    imagefilledrectangle($im, $x1 + $rad, $y1, $x2 - $rad, $y2, $col);
    imagefilledrectangle($im, $x1, $y1 + $rad, $x2, $y2 - $rad, $col);
    foreach ([[$x1 + $rad, $y1 + $rad], [$x2 - $rad, $y1 + $rad], [$x1 + $rad, $y2 - $rad], [$x2 - $rad, $y2 - $rad]] as [$cx, $cy])
        imagefilledellipse($im, $cx, $cy, 2 * $rad, 2 * $rad, $col);
};
imagesetthickness($im, 6);

switch ($type) {
    case 'tent':
        $poly([180, 960, 600, 360, 1020, 960], $main);
        $poly([600, 360, 1020, 960, 780, 960], $dark);                 // shaded side
        $poly([470, 960, 600, 640, 730, 960], $c(30, 34, 32));         // door
        $poly([520, 960, 600, 700, 680, 960], $c(55, 60, 58));
        imageline($im, 600, 360, 600, 640, $dark);
        imageline($im, 180, 960, 90, 985, $strap); imageline($im, 1020, 960, 1110, 985, $strap);
        imagefilledellipse($im, 600, 355, 26, 26, $metal2);
        break;
    case 'pack':
        $rr(330, 330, 870, 960, 90, $main);
        $rr(330, 330, 870, 520, 90, $light);                            // lid
        imageline($im, 340, 520, 860, 520, $dark);
        $rr(400, 640, 800, 900, 40, $dark);                             // front pocket
        imageline($im, 400, 700, 800, 700, $main);
        $rr(285, 560, 345, 820, 28, $dark); $rr(855, 560, 915, 820, 28, $dark);   // side pockets
        imagesetthickness($im, 18);
        imageline($im, 460, 520, 460, 640, $strap); imageline($im, 740, 520, 740, 640, $strap);
        imagefilledrectangle($im, 440, 600, 480, 640, $metal); imagefilledrectangle($im, 720, 600, 760, 640, $metal);
        imagearc($im, 600, 330, 240, 200, 180, 360, $strap);
        break;
    case 'stove':
        imagefilledrectangle($im, 520, 640, 680, 930, $metal);          // canister
        imagefilledrectangle($im, 520, 640, 570, 930, $c(195, 198, 202));
        $rr(500, 600, 700, 660, 20, $metal2);
        imagefilledrectangle($im, 585, 540, 615, 610, $metal2);          // stem
        $poly([400, 540, 800, 540, 700, 480, 500, 480], $dark);          // burner head
        imagefilledellipse($im, 600, 480, 300, 60, $main);
        imagefilledellipse($im, 600, 480, 160, 28, $dark);
        imagesetthickness($im, 14);
        foreach ([[420, 530, 330, 600], [780, 530, 870, 600], [600, 540, 600, 610]] as [$x1, $y1, $x2, $y2]) imageline($im, $x1, $y1, $x2, $y2, $metal2);
        break;
    case 'pot':
        $rr(330, 560, 870, 900, 50, $main);
        $rr(310, 470, 890, 580, 40, $dark);                              // lid
        imagefilledellipse($im, 600, 450, 90, 40, $metal2);
        imagesetthickness($im, 22);
        imageline($im, 330, 650, 200, 620, $strap); imageline($im, 870, 650, 1000, 620, $strap);
        imagefilledrectangle($im, 340, 700, 380, 860, $light);
        break;
    case 'bag':
        // mummy bag seen from above: round hood, body tapering to the foot box
        $poly([440, 430, 760, 430, 840, 620, 770, 940, 430, 940, 360, 620], $main);
        imagefilledellipse($im, 600, 400, 330, 300, $main);
        imagefilledellipse($im, 600, 400, 210, 190, $dark);              // hood opening
        imagefilledellipse($im, 600, 405, 150, 130, $c(232, 232, 228));  // face opening
        imagesetthickness($im, 12);
        for ($i = 0; $i < 6; $i++) {                                      // quilting
            $yy = 520 + $i * 68;
            imageline($im, 385 + ($i * 6), $yy, 815 - ($i * 6), $yy, $dark);
        }
        imageline($im, 600, 520, 600, 930, $metal2);                      // zip
        imagefilledellipse($im, 600, 524, 26, 40, $metal);
        break;
    case 'mat':
        $rr(230, 430, 970, 930, 60, $main);                              // rolled mat, side-on
        imagefilledellipse($im, 230, 680, 110, 500, $dark);
        imagefilledellipse($im, 230, 680, 60, 280, $light);
        imagefilledellipse($im, 230, 680, 24, 100, $main);
        imagesetthickness($im, 24);
        imageline($im, 500, 440, 500, 920, $strap); imageline($im, 760, 440, 760, 920, $strap);
        break;
    case 'boot':
        $poly([380, 340, 640, 340, 660, 640, 960, 740, 990, 900, 300, 900, 300, 620], $main);
        $poly([300, 880, 990, 880, 990, 960, 300, 960], $strap);         // sole
        $poly([380, 340, 640, 340, 640, 420, 380, 420], $dark);          // collar
        imagesetthickness($im, 10);
        for ($i = 0; $i < 4; $i++) { imageline($im, 500, 470 + $i * 50, 640, 450 + $i * 50, $white); imagefilledellipse($im, 500, 470 + $i * 50, 18, 18, $metal); }
        break;
    case 'socks':
        foreach ([[430, 0], [700, 40]] as [$ox, $oy]) {
            $poly([$ox - 90, 330 + $oy, $ox + 90, 330 + $oy, $ox + 90, 700 + $oy, $ox + 240, 800 + $oy, $ox + 220, 920 + $oy, $ox - 90, 900 + $oy], $main);
            imagefilledrectangle($im, $ox - 90, 330 + $oy, $ox + 90, 400 + $oy, $dark);
            imagefilledrectangle($im, $ox - 90, 410 + $oy, $ox + 90, 425 + $oy, $white);
            $poly([$ox + 90, 800 + $oy, $ox + 240, 800 + $oy, $ox + 220, 920 + $oy, $ox + 90, 910 + $oy], $light);
        }
        break;
    case 'lamp':
        imagefilledellipse($im, 600, 640, 880, 640, $strap);            // headband as a ring
        imagefilledellipse($im, 600, 640, 800, 560, $c(238, 238, 236));
        imagesetthickness($im, 6);
        $rr(450, 430, 750, 650, 60, $main);
        imagefilledellipse($im, 600, 540, 150, 150, $white);
        imagefilledellipse($im, 600, 540, 90, 90, $c(255, 244, 190));
        $rr(500, 645, 700, 700, 22, $dark);
        break;
    case 'poles':
        imagesetthickness($im, 30);
        foreach ([[0, 0], [150, 20]] as [$dx, $dy]) {
            imageline($im, 330 + $dx, 940 + $dy, 760 + $dx, 300 + $dy, $metal2);
            imagesetthickness($im, 44);
            imageline($im, 735 + $dx, 340 + $dy, 790 + $dx, 260 + $dy, $main);
            imagesetthickness($im, 30);
            imagefilledellipse($im, 330 + $dx, 940 + $dy, 70, 34, $dark);
        }
        break;
}
$small = imagecreatetruecolor(600, 600);
imagecopyresampled($small, $im, 0, 0, 0, 0, 600, 600, $S, $S);
imagepng($small, $out);
