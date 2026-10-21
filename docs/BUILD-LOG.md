# Build log: a honeypot for the PHP2Shell vulnerabilities

Everything below happened on 21 October 2026, the day PHP released fixes for CVE-2026-109618 and CVE-2026-109619.
This is the raw material for a blog post: what was decided, why, what failed, and what was proven. Nothing here is polished on purpose.

## 1. The starting point

**Goal:** build a honeypot to detect and collect attacks on "the recent PHP vulnerability".

**What was known.** A web search the same day turned up "PHP2Shell": two critical PHP core RCE flaws (CVSS 9.2), fixed in PHP 8.5.12 / 8.4.27 /
8.3.36 / 8.2.35, with details leaked a day before the coordinated release. Sources disagreed on whether exploitation had started: watchTowr listed
both as exploited in the wild, NCSC-NL and the PHP release text said they had no indication. **Crucially, no technical detail was public:** no root
cause, no request shape, no proof of concept, no indicators. Two vendor pages said so explicitly.

**Consequence for the design:** a honeypot that matches known exploit signatures was impossible. The design had to (a) capture everything raw, so the
exploit could be studied later, and (b) detect *success* by behaviour rather than by signature.

## 2. Decisions, in order

| # | Question | Decision | Why |
|---|---|---|---|
| 1 | Custom code or a framework? | Started custom (small Python proxy) | Needed full raw bytes of malformed multipart bodies; frameworks tend to parse and normalise |
| 2 | Can an emulated PHP honeypot tell you an attack *worked*? | No, so added a real vulnerable PHP | An emulator never executes anything, so it only shows attempts |
| 3 | Which framework to build on? | First "the Honeynet framework" (Snare/Tanner), then corrected to **T-Pot** | Snare/Tanner last committed June 2024 (Alpine 3.15 base, Python 3.6 era); T-Pot is current (commit 17 Oct 2026) and ships Elastic, Kibana, an attack map and 30+ honeypots |
| 4 | How to make a convincing target? | A fake WooCommerce shop with bait | Scanners fingerprint the platform first; WooCommerce is the most-scanned shop software |
| 5 | How to detect real code execution? | Falco watching the shop container | Public indicator guidance (Huntress) was behavioural: PHP workers spawning shells, new webshell files, outbound connections |
| 6 | Risk of running a real vulnerable PHP? | Accepted: throwaway VPS; shop on a network with no internet route | User confirmed the VPS is disposable |
| 7 | How to deploy? | One script that installs T-Pot, reboots, resumes itself and starts everything | User asked for deployment "in one go, including the T-Pot dashboards" |

The framework survey that fed decision 3 covered T-Pot, Beelzebub, HTTP Honeypot (Go), HoneyHTTPD, Galah, Snare/Tanner and others. None offers
"confirm the exploit worked", which is why a real vulnerable PHP plus runtime monitoring was added on top.

## 3. Final architecture

```
attacker -> capture proxy (:80/:443)  ->  vulnerable shop (PHP 8.3.35 + WooCommerce)  ->  MariaDB
            raw bytes, tags, fingerprints,        ^ Falco: process spawn / script written / outbound connect
            IOCs, TLS, timings                    ^ Apache log: "child exit signal" = exploit attempt that crashed a worker
decoy DB (db-backup.internal:3306) <- bait credentials in .env / backup.sql: any connection = attacker already inside
all events -> Vector -> T-Pot's Elasticsearch (GeoIP, ASN, user-agent enrichment, 30-day retention)
           -> live dashboard (map, feed, funnel, ~40 metrics) + Kibana dashboard inside T-Pot + optional Slack alerts
```

The shop and database sit on a Docker network with no route out, so a payload cannot call home; the attempt is still logged.

## 4. How it was built, step by step

1. **Capture proxy** (`capture/capture.py`, Python stdlib). Reads each request off the socket, stores the raw bytes under their SHA-256 *before* any parsing,
   then forwards a copy to the shop and relays the real response. Adds: tags (command execution, shell strings, webshell drops, malformed multipart,
   honeytoken reuse, bait hits, login attempts), a "shape hash" that groups variants of one exploit, header-order fingerprint, extracted URLs/IPs,
   TLS version/cipher/SNI, timings. Handles `Expect: 100-continue`; forces `Connection: close` upstream and passes the real client IP via `X-Forwarded-For`.
2. **Decoy database** (`capture/decoy.py`). Speaks just enough of the MySQL handshake to capture the username an attacker tries against the bait database.
3. **Vulnerable shop** (`shop/`). `php:8.3.35-apache` (one patch below the fix), WordPress, WooCommerce and the Storefront theme. A seed script creates a fictional
   brand ("Trailhaven"), 12 products and 30 fake customers. A random, never-displayed admin password means attackers cannot log in as admin (that would be a
   second, unrelated route to code execution). Bait: `.env`, `backup.sql`, `robots.txt` pointing at both, a legacy admin login, `phpinfo.php`.
   All fake credentials carry a marker so any reuse is tagged.
4. **Falco rules** (`falco/php2shell_rules.yaml`). Three rules scoped to the shop container: Apache spawning a process; Apache writing a script/binary; Apache opening an
   outbound connection.
5. **Log shipping** (`vector/`). Vector tails the capture log, decoy log, Falco output and the shop's Apache log (for worker crashes) into Elasticsearch through an
   enrichment pipeline (GeoIP, ASN, user agent).
6. **Dashboards.** `live/` is a small Python backend plus a single HTML page (Leaflet map, Chart.js timeline, bars, heatmap, RCE table with "suspected source").
   `scripts/kibana-import.sh` builds and imports a 15-panel Kibana dashboard with `jq`.
7. **One-command deploy** (`deploy.sh`). Installs T-Pot unattended, registers a systemd unit to resume after T-Pot's reboot, frees ports 80/443 from T-Pot's own
   honeypots, prepares Elasticsearch, gets a Let's Encrypt certificate, builds and starts the add-on, imports the dashboard, removes its own resume unit.

## 5. Verification, and every defect it found

Static checks first (no Docker engine was running at that point): all shell scripts passed `bash -n`; the capture proxy, decoy and live backend were run in WSL
against a stand-in upstream; the Kibana and Elasticsearch JSON was generated and parsed with `jq`.

Then a full local run on Docker Desktop, using T-Pot's own Windows compose file for Elasticsearch 9.x/Kibana 9.3.5. Defects found, in order:

| Found by | Defect | Fix |
|---|---|---|
| WSL smoke test | `live.py`: a sub-aggregation named `size` collided with the helper's `size` argument; every query failed | renamed to `avg_size` |
| WSL smoke test | my own test used `curl -F "x=<..."`, which curl reads as "load from file" | test bug, used `--form-string` |
| First image build | wp-cli ran out of PHP memory (128 MB) unpacking WordPress | apply `memory_limit` before the download |
| Second build | `wp plugin install` needs a database config that does not exist at build time | download plugin and theme zips directly |
| First stack start | Vector: syntax error in a VRL object literal | rewrote the Falco transform with plain assignments |
| First stack start | Vector: `pipeline` is a top-level sink option, not under `query` | moved |
| First stack start | live container ignored the bind address | made it configurable (`LIVE_BIND`) |
| Falco first events | **false positive**: WordPress's own loopback HTTP request looked like an outbound connection | ignore loopback; block all WordPress HTTP in a must-use plugin |
| Server logs | **false positive risk**: PHP `mail()` would exec `sendmail` from Apache, i.e. look like RCE | swallow mail inside WordPress |
| Falco warnings | modern Falco dropped enter events, so a rule on connect-enter can never match | back to exit events |
| Falco output | failed connections (egress is blocked on purpose) have no destination in Falco's normal fields | parse the attempted address from the event args in Vector |
| Falco after restart | a container that started before Falco finished initialising is not attributed; attacks went unseen | shop waits 45 s and depends on Falco; documented "restart the shop after Falco" |
| Browser check | Kibana blank on its direct port: T-Pot serves it behind nginx under `/kibana/` | expected; used a prefix-stripping proxy for the check |
| Browser check | map tiles showed "API key required" (basemap provider now needs a key) | switched to OpenStreetMap tiles with a dark CSS filter |

**Results of the local run:** all four images build; the shop seeds and serves as PHP/8.3.35 through the proxy; events flow end to end with GeoIP/ASN/user-agent
enrichment (confirmed with a synthetic public-IP event); the Kibana import is accepted (17 objects) and renders with data; the live dashboard renders;
**normal browsing, search, cart, a login attempt and an account registration produced zero RCE events**; a simulated attack (a test script planted in my own
container that runs `id; whoami`, writes `drop.php` and opens a connection to 203.0.113.9) produced the expected five events, including the attempted destination
and the suspected source request.

## 6. What this does not prove (be honest in the post)

- The real exploit was never run. Its trigger was not public, so nothing shows the *vulnerability* being exploited; only that code execution, once achieved, is detected.
- T-Pot's Linux installer and the VPS deployment were not run. Only T-Pot's Windows edition (Elasticsearch, Kibana, nginx) was.
- Detection of the vulnerability itself is heuristic until real samples exist in the raw captures.
- With one shared container, the source of a confirmed RCE is a time correlation, not proof.
- Local traffic comes from a private Docker address, so the map showed no markers and "Top networks" was empty. GeoIP itself was proven separately.

## 7. Operating notes

- Run only on a disposable VPS. Reset the shop after any confirmed RCE (`scripts/reset-shop.sh`).
- Restart the shop after restarting Falco.
- Source IPs are personal data under GDPR; events expire after 30 days but captured request files are not rotated.
- Keep the shop's brand fictional.

## 8. Suggested angles for the blog post

- **"Detect success, not attempts":** why an emulated honeypot cannot answer the question people actually ask, and how runtime monitoring can.
- **"Building a honeypot for a bug nobody has described yet":** capture raw first, classify later.
- **The false positives:** the most instructive part. A WordPress shop doing normal things (sending mail, calling itself) looks exactly like a compromise to a syscall monitor.
- **Honest verification:** what was tested, how, and the list of what was not.
- Screenshots worth taking: the live dashboard (KPIs and RCE table), the Kibana dashboard, the shop front page, the Falco event JSON.
- Link sources: the [watchTowr FAQ](https://watchtowr.com/intelligence/php-cve-2026-109618-faq/), [Huntress write-up](https://www.huntress.com/blog/php2shell-leaked-critical-php-vulnerabilities),
  and [T-Pot](https://github.com/telekom-security/tpotce).
