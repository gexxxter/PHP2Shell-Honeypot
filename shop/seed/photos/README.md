# Product photos

Free-to-use stock photos from Unsplash (https://unsplash.com/license: free for commercial use, no attribution required),
cropped square on the product, with a few small maker's marks painted out. One file per product, named after its SKU.

| File | Unsplash photo id |
|---|---|
| TH-TNT-2P | 1785037605565-11329f737b71 |
| TH-TNT-3P | 1778017342222-e9c6047eb565 |
| TH-PCK-45 | 1757726197992-7faac6840095 |
| TH-PCK-24 | 1680983746885-70695c2c1b05 |
| TH-CKN-STV | 1546890948-82b45c9712c2 |
| TH-CKN-SET | 1522041350204-22285237eeca |
| TH-SLP-F5 | 1558477280-1bfed08ea5db |
| TH-SLP-MAT | 1706467998521-c100ef713a20 |
| TH-FTW-BT | 1575987116913-e96e7d490b8a |
| TH-FTW-SK | 1496389164152-053867affa71 |
| TH-ACC-HL | 1517457773273-412ec74a18cd |
| TH-ACC-TP | 1632411316785-33d395035a3c |

Page: https://unsplash.com/photos/<last 11 characters of the id>. `images.sh` imports `photos/<SKU>.jpg` as the product image
(marked with the attachment meta `_th_photo`); a product without a file keeps the drawn illustration.
