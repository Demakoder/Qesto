# Qesto Desktop — аудит перед реализацией

Дата: 13 августа 2026.

В исходном ТЗ используется рабочее написание Kesta. В репозитории и текущем
продукте каноническое имя — **Qesto**, поэтому desktop сохраняет Qesto как
consumer-бренд, а Synoball — как внутренний финансовый слой.

## Текущий стек

| Область | Состояние | Решение |
| --- | --- | --- |
| UI | Flutter 3 / Dart 3.12, Material 3 | REUSE |
| Платформы | Android, iOS, Web, Windows, macOS, Linux уже созданы | REUSE |
| Desktop framework | Flutter Desktop | REUSE |
| Persistence | `SharedPreferences`, JSON schema v2 | REUSE на MVP |
| Финансовое ядро | Synoball Core v1 | REUSE как source of truth |
| Product read-model | `BudgetController` + `QestoReadModelService` | ADAPT для desktop |
| State | `ChangeNotifier` / `ListenableBuilder` | REUSE |
| Навигация | mobile `Navigator` + bottom navigation | ADAPT: отдельный desktop shell |

Electron, Tauri, отдельная desktop-БД и отдельная `DesktopTransaction` не
нужны: они только удвоят технологический контур.

## Существующие экраны

| Экран | Состояние | Решение |
| --- | --- | --- |
| Бюджет | Рабочий mobile dashboard, периоды и drill-down | ADAPT |
| Статистика | Богатые вычисления, фильтры и drill-down | REUSE services, ADAPT views |
| Капитал / счета | Балансы и группировка | ADAPT |
| Добавление расхода | Рабочая форма | REUSE |
| Выписка Сбербанка | Рабочий import flow | REUSE через Synoball |
| Чек QR/OCR | Рабочий import flow | REUSE через Synoball |
| Android-уведомления | Рабочий capture/import flow | REUSE через Synoball |
| Выгода | Купоны, акции, tracked products | REUSE; desktop P1/P2 |
| Накопления | Цели и gamification | ADAPT; desktop P1 |
| История действий | Рабочий журнал и undo | REUSE |
| Голос | Есть Synoball candidate/confirmation API, нет capture UI | ADAPT |

Mobile-экраны не удаляются и не переписываются: desktop выбирается только на
широком viewport.

## Компоненты и design system

| Компонент | Состояние | Решение |
| --- | --- | --- |
| `QestoColors` / `buildQestoTheme` | Светлая спокойная палитра | ADAPT в semantic tokens |
| `QestoCard` | Карточка 22 px с тенью | REUSE mobile, ADAPT desktop density |
| `QestoButton` | Mobile primary/secondary | REUSE в import flows |
| Empty/Error/Skeleton | Есть базовые состояния | ADAPT для desktop |
| Category icon/colors | 30 категорий и единый mapping | REUSE |
| Sticky header / bottom navigation | Mobile-specific | KEEP только mobile |
| Charts | CustomPainter line, bars, donut, heatmap, scatter | REUSE математику, ADAPT размеры и chrome |

Сохраняются синий accent, дружелюбные радиусы, спокойные нейтральные фоны и
цвета категорий. Desktop уменьшает радиусы/тени и повышает плотность данных.

## Финансовые модели и сервисы

| Слой | Состояние | Решение |
| --- | --- | --- |
| `SynoballState` | Canonical accounts, transactions, evidence, recurring, audit | REUSE |
| Adapter pipeline | manual, voice, notification, receipt, statement, CBR fixture | REUSE |
| Dedup / trust / enrichment | Работают до product UI | REUSE |
| `FinancialStateService` | Ликвидность, доходы, расходы, cash-flow, капитал, quality | REUSE |
| `SynoballAnalyticsReadService` | Daily, category, merchant, cash-flow | REUSE |
| `StatisticsCalculationService` | Comparison, periods, heatmap inputs, insights | REUSE |
| Budget services | Summary, category plan, forecast | REUSE |

Desktop читает только canonical/read-model данные. Source используется для
provenance и фильтра, но не определяет продуктовую бизнес-логику.

## Parsers и импорт

| Источник | Текущий путь | Решение |
| --- | --- | --- |
| Manual | Form → `BudgetController` → Synoball adapter | REUSE |
| Voice | Candidate → confirm → canonical transaction | ADAPT UI |
| Receipt | QR/OCR parser → Receipt adapter | REUSE |
| Statement | File service/Sber parser → Statement adapter | REUSE |
| Notification | Android parser → Notification adapter | REUSE |
| CBR/Open Finance | Provider-shaped fixture → regulated adapter | REUSE fixture |
| CSV/XLSX | Нет готового parser | P1, не подменять фиктивным импортом |

## Хранилище, AI и приватность

- Local-first уже выполняется: canonical/raw/evidence сохраняются в schema v2.
- AI получает task-specific `AiFinancialContext`, а не полную сырую историю.
- Для production bank sync всё ещё нужен серверный token/consent vault.
- Demo mode должен использовать отдельный repository и никогда не записываться
  в production key.

## Проблемы исходной desktop-композиции

- `MaterialApp.builder` всегда ограничивает ширину 520 px.
- Нет desktop shell, sidebar, topbar и contextual drawer.
- Основные экраны состоят из mobile card stack.
- Нет единого global search и keyboard shortcuts.
- Transactions нет как самостоятельной большой таблицы.
- Demo dataset пустой и не подходит для visual/product QA.

Эти элементы следует REWRITE как presentation-only desktop слой. Финансовый
движок, persistence и source adapters переписывать нельзя.

## Целевая структура первой итерации

```text
lib/desktop/
├── desktop_app_shell.dart
├── desktop_destination.dart
├── pages/
├── widgets/
└── README.md
```

Общими остаются:

```text
Synoball Core
→ Qesto read-model / BudgetController
→ shared analytics services
→ mobile views | desktop views
```

Приоритет реализации: shell → demo dataset → Dashboard → Transactions →
Budget → Cash Flow → Accounts → Recurring/settings foundation.
