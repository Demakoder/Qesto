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

Overview and AI are standalone destinations. Budget owns operational pages;
expense analytics combine category structure, merchants, shopping frequency
and average checks in one page, while rhythm remains a dedicated view.
The former Statistics hub is intentionally absent: cash flow, budget planning
and recurring payments use their stronger dedicated desktop pages instead of
showing duplicate analytics tabs. All analytical pages still share the same
statistics controller, period/comparison menus and filters.
