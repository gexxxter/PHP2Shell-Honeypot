# php-Honeypot

A honeypot for the PHP core RCE flaws **CVE-2026-109618 / CVE-2026-109619** ("PHP2Shell", fixed in PHP 8.5.12 / 8.4.27 / 8.3.36 / 8.2.35),
built as an add-on to [T-Pot](https://github.com/telekom-security/tpotce). It runs a **real, deliberately vulnerable PHP 8.3.35** behind a fake
WooCommerce webshop, records every request byte-for-byte, and tells you when an attack actually achieved code execution.

> Status: written without being able to run it (no Docker engine on the authoring machine). Expect to fix small things on first deploy.
> Exploit details were not public when this was written, so detection is heuristic until you have real samples in `captures/`.

## Deploy (one command)

On a fresh throwaway Debian 13 / Ubuntu VPS (8 GB RAM minimum, 16 GB recommended, 128 GB disk), as a non-root user with passwordless sudo:

```bash
git clone <this repo> php-Honeypot && cd php-Honeypot
./deploy.sh --web-user admin --web-pass 'a-strong-password' --domain shop.example.com --email you@example.com
```

`--domain` and `--email` are optional but make the shop far more discoverable (a real certificate shows up in certificate-transparency logs that
scanners watch). The DNS A record must already point at the VPS.

The script installs T-Pot, reboots (SSH then lives on port **64295**), resumes by itself, and finishes with the URLs. Follow along with
`ssh -p 64295 user@vps 'tail -f ~/php-honeypot-deploy.log'`.

Provider firewall: open 80/443 (plus any other T-Pot honeypot ports you want) to the world; restrict 64295 and 64297 to your IP.

## What you get

| Thing | Where |
|---|---|
| Fake shop "Trailhaven" (WooCommerce, bait files, fake customers) | `http://<vps>/` |
| **Live dashboard**: map, feed, funnel, ~40 metrics, confirmed-RCE table with suspected source | `ssh -p 64295 -L 8000:127.0.0.1:64300 user@vps` then http://localhost:8000, login = the `--web-user`/`--web-pass` you gave `deploy.sh` |
| **Kibana dashboard** "php-Honeypot" inside T-Pot | T-Pot web UI `https://<vps>:64297` -> Kibana -> Dashboards |
| T-Pot's own map, Suricata, CyberChef, other honeypots | same T-Pot web UI |
| Raw request bytes of everything | docker volume `hpdata`: `captures/<sha256>.bin`, `logs/events.jsonl` |

## How it works

```
attacker -> capture (:80/:443)  ->  realphp (PHP 8.3.35 + WooCommerce)  ->  db
            raw bytes, tags,         ^ watched by Falco: process spawn / script written / outbound connect
            fingerprints, IOCs       ^ Apache "child exit signal" lines = exploit attempts that crashed a worker
decoy (db-backup.internal:3306) <- bait credentials in .env / backup.sql; any connection = attacker already inside
all of it -> Vector -> T-Pot's Elasticsearch (GeoIP + ASN + user-agent enrichment, 30-day retention) -> dashboards + alerts
```

`realphp` and `db` sit on a Docker network with no route to the internet, so a payload cannot call home. The attempt is still logged.

### What counts as "RCE confirmed"
Falco rules in `falco/php2shell_rules.yaml`, all scoped to the `realphp` container:
1. Apache/PHP spawns a child process (the shop never does).
2. Apache/PHP writes a `.php/.phtml/.phar/.sh/.py/.pl/.so` file.
3. Apache/PHP opens an outbound connection (reverse shell / payload fetch).

Because one container serves everyone, the **source** of a confirmed RCE is a time correlation (requests in the 15 s before it), shown as "suspected source".

### Metrics collected
Per request: method, path, HTTP version, header order and a header-order fingerprint, user agent (parsed), TLS version/cipher/SNI, body and response size,
read and upstream timings, upstream status, multipart structure (parts, boundary length, terminator, filenames, part headers), a **shape hash** that
groups variants of one exploit, extracted URLs/IPs from payloads, credentials tried on login forms, tags, GeoIP, ASN. Plus RCE events, PHP worker crashes,
bait-file hits, honeytoken reuse, decoy DB connections, and sensor health.

## Operations

```bash
scripts/reset-shop.sh          # recreate the shop container: removes any dropped webshell
scripts/reset-shop.sh --db     # also wipe and reseed the database
scripts/kibana-import.sh       # re-import the Kibana dashboard
cp vector/alerts/slack.yaml.example vector/alerts/slack.yaml   # Slack alerts on RCE and new payload shapes (set SLACK_WEBHOOK_URL in .env)
```

Reset the shop after any confirmed RCE (and on a schedule, e.g. daily from cron) so one attacker's leftovers do not skew the next one's data.

## Safety and data protection
- Run this only on a disposable VPS with no other workloads. A real vulnerable PHP is reachable from the internet by design.
- Source IPs are personal data under GDPR. Raw events are deleted after 30 days (`scripts/setup.sh`, ILM policy); captured request files in `hpdata` are not rotated automatically.
- The shop is fictional. Do not give it the name or branding of a real company.
- The shop admin password is random and never shown, so attackers cannot log in as admin (a second, unrelated route to code execution would muddy the data).
- The bait credentials all contain the marker `HT7f3a`; any request containing it is tagged `honeytoken-reuse`.

## Documentation
[docs/BUILD-LOG.md](docs/BUILD-LOG.md) records every decision, step, defect found and what was and was not verified (material for a write-up).

## Layout
`deploy.sh` one-command deploy · `docker-compose.yml` add-on stack · `capture/` raw-capture proxy + decoy DB · `shop/` vulnerable PHP + WooCommerce seed/bait ·
`falco/` RCE rules · `vector/` log shipping and alerts · `live/` live dashboard · `scripts/` ES setup, T-Pot port prep, certificates, reset, Kibana import

## Verified locally (Docker Desktop, Windows) and what that does and does not prove
Run with T-Pot's own Elasticsearch/Kibana 9.3.5 (its Windows compose file) and `docker-compose.local.yml`:
- All images build; the shop seeds itself (WordPress + WooCommerce: 12 products with images, categories, shop front page) and every shop page (shop, product, category, cart, checkout, account, search, REST, AJAX) answers correctly as PHP/8.3.35 through the capture proxy.
- Capture -> Vector -> T-Pot Elasticsearch works, including GeoIP, ASN and user-agent enrichment.
- The Kibana dashboard imports (17 objects) and renders with live data; the live dashboard renders and shows confirmed RCE with suspected sources.
- Falco rules fire on a simulated attack (a test script planted in the shop that spawns a shell, writes a `.php` file and opens a connection)
  and stay silent during normal shop use (browsing, search, cart, login attempt, account registration).

Not proven: the real exploit. Its trigger was not public, so nothing here shows the *vulnerability* being exploited; only that code execution,
once achieved, is detected. T-Pot's installer and its Linux honeypots were not run (Windows edition only), nor was a VPS deployment.

### Things learned while testing (all handled in the code, listed so you know why)
- **Start order matters.** Falco does not attribute processes of a container that started before Falco finished initialising. The shop therefore
  waits `START_DELAY` (45 s) and depends on `falco`. **If you restart Falco, also run `docker restart realphp`.**
- **WordPress must stay quiet.** PHP `mail()` execs `sendmail` and WordPress/WooCommerce make loopback HTTP requests; both look exactly like RCE.
  `shop/seed/bait.sh` installs a must-use plugin that swallows mail and blocks WordPress's own HTTP requests.
- **Failed connections carry no destination** in Falco's normal fields (egress is blocked on purpose); the attempted address is parsed from the
  event args by Vector.
- Falco's modern eBPF probe prints tracepoint warnings on Docker Desktop's VM but works; on a normal Linux VPS expect fewer.

### Re-running the local test
```bash
# T-Pot's Windows edition (once): clone tpotce, set TPOT_OSTYPE=win and a WEB_USER in .env, then: docker compose up -d elasticsearch kibana nginx
ES_URL=http://127.0.0.1:64298 scripts/setup.sh
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
# shop: http://localhost:8081   live dashboard: http://localhost:64300
```

## Access control (every dashboard is behind a login)
| Dashboard | Protection |
|---|---|
| Kibana, CyberChef, T-Pot UI | T-Pot's nginx on `:64297` (HTTPS, basic auth with `--web-user` / `--web-pass`); Kibana itself listens on loopback only |
| Live dashboard | HTTP basic auth, same credentials; bound to loopback (use the SSH tunnel). It **refuses to start without a password** (min. 8 characters); 8 failed logins within 5 minutes lock it for 5 minutes |
| Elasticsearch | loopback only (`127.0.0.1:64298`), T-Pot's own binding |

Basic auth is not encrypted by itself, which is why the live dashboard stays on loopback behind the SSH tunnel; add TLS in front before exposing it.
The lockout is global (behind a tunnel every request comes from 127.0.0.1), so an attacker who could reach it could also lock you out for five minutes.
Only the honeypot itself (`:80`/`:443`) and T-Pot's login-protected nginx are meant to be reachable from the internet.
