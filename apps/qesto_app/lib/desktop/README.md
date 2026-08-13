# Qesto Desktop

Desktop presentation layer for viewports from 900 px. Financial business logic
and persistence remain in Synoball, `BudgetController` and shared services.

```powershell
flutter run -d windows
```

The application starts with the persisted local user state. A new installation
contains no seeded accounts, operations, budgets, goals, offers or forecasts.

Windows data entry:

- statement: native file dialog, bundled pure-Dart PDF text extraction or
  direct TXT import, then preview and confirmation;
- receipt: manual fiscal QR entry plus local Windows OCR for a receipt image;
- voice: microphone through bundled offline whisper.cpp Russian recognition,
  structured draft, Synoball candidate and explicit confirmation;
- manual expense: the shared canonical manual-input adapter.

The Statistics destination reuses the same calculation controller and chart
sections as Android: overview, expenses, rhythm, merchants, categories, cash
flow, budget quality and recurring payments. Desktop adds period/comparison
menus, filters and a wide constrained canvas without duplicating finance logic.
