<?php
// Generates a simple product tile: php make-image.php "Product name" "#RRGGBB" /path/out.png
[$self, $name, $hex, $out] = $argv;
$w = 600; $h = 600;
$im = imagecreatetruecolor($w, $h);
[$r, $g, $b] = sscanf($hex, '#%02x%02x%02x');
$bg = imagecolorallocate($im, $r, $g, $b);
$light = imagecolorallocate($im, min(255, $r + 40), min(255, $g + 40), min(255, $b + 40));
$dark = imagecolorallocate($im, (int)($r * 0.7), (int)($g * 0.7), (int)($b * 0.7));
$white = imagecolorallocate($im, 255, 255, 255);
imagefilledrectangle($im, 0, 0, $w, $h, $bg);
imagefilledellipse($im, 300, 250, 330, 330, $light);                              // sun
imagefilledpolygon($im, [0, 600, 200, 330, 400, 600], $dark);                      // mountains
imagefilledpolygon($im, [220, 600, 420, 280, 600, 600], $dark);
$font = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';
$lines = explode("\n", wordwrap($name, 16, "\n", true));
$y = 470 - 18 * (count($lines) - 1);
foreach ($lines as $line) {
    $box = imagettfbbox(34, 0, $font, $line);
    imagettftext($im, 34, 0, (int)(($w - ($box[2] - $box[0])) / 2), $y, $white, $font, $line);
    $y += 46;
}
imagepng($im, $out);
