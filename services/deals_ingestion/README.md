# Qesto Deals Ingestion

Source-neutral service for Qesto promotions. It currently reads public Telegram
Web Preview pages, applies the existing safety filters and rule-based extractor,
deduplicates offers in SQLite, and exposes the JSON API used by Flutter.

MAX support remains in the code but is disabled in `config/sources.json`. The
Flutter application does not contain a bundled list of promo codes.

The configured provider loads public previews from every enabled channel and
isolates channel failures. Telegram must be reachable from the computer running
the service, so enable VPN before starting Qesto. The scheduler runs on startup
and every 45 minutes.

## Run the whole application

From the repository root, run `Qesto.cmd`. It starts this service in the
background and then launches Flutter. The same command is available from the
VS Code task `Qesto: Run app + deals service`.

## Run only the service

```powershell
cd C:\Users\ARM\Documents\Qesto\services\deals_ingestion
python -m qesto_deals sync
python -m qesto_deals serve --host 127.0.0.1 --port 8787 --interval 2700
```

Endpoints:

- `GET /health`
- `GET /offers?limit=200`
- `GET /offers?kind=promo_code&limit=200`
- `POST /sync` (disabled unless `QESTO_DEALS_SYNC_TOKEN` is configured)

Telegram/MAX responses are capped by `max_response_bytes` (5 MiB by default,
10 MiB hard configuration maximum). Individual message text, links and formatted
codes are bounded before storage so a compact upstream response cannot grow into
an oversized database/API response. MAX API endpoints must use HTTPS, and
cross-origin redirects are rejected before an API token can be forwarded.

For a physical Android phone, prefer USB and `adb reverse`; the repository
runner configures it automatically:

```powershell
python scripts/run_qesto.py --device <android-device-id>
```

If USB forwarding is unavailable, explicitly expose the public-offers service
to the local network with `--allow-lan`. Do not use this mode on a public Wi-Fi
network:

```powershell
python scripts/run_qesto.py --allow-lan --device <android-device-id>
```

To enable the manual sync endpoint, set a long random token and send it as an
HTTP Bearer token. Browser origins beyond localhost must also be listed in the
comma-separated `QESTO_DEALS_ALLOWED_ORIGINS` environment variable.

The token is accepted only while the service is bound to a loopback address.
Starting a non-loopback HTTP listener with `QESTO_DEALS_SYNC_TOKEN` fails
closed. LAN mode therefore exposes only the public read endpoints, with bounded
concurrency and per-client rate limiting.

## Tests

```powershell
python -m unittest discover -s tests -v
```
