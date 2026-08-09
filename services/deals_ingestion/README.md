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
python -m qesto_deals serve --host 0.0.0.0 --port 8787 --interval 2700
```

Endpoints:

- `GET /health`
- `GET /offers?limit=200`
- `GET /offers?kind=promo_code&limit=200`
- `POST /sync`

For a physical phone, run Flutter with the computer's LAN address:

```powershell
flutter run --dart-define=QESTO_DEALS_API_URL=http://192.168.1.10:8787
```

## Tests

```powershell
python -m unittest discover -s tests -v
```
