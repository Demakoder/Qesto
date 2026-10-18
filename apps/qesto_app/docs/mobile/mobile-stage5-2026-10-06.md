# Qesto Mobile — Stage 5 / Капитал

Дата: 6 октября 2026. Scope: mobile navigation, presentation и редакторы существующих сущностей. Физическая Android QA Stage 3–5 отложена по согласованию с пользователем. Новый PR не создавался; Stage 6 автоматически не начинается.

## Реализовано

### Capital landing

Собственный `MobileCapitalLanding` вместо desktop Accounts dashboard. Сначала общий капитал из существующего `FinancialState` (активы минус долги), затем компактные переходы: ликвидность, счета, подушка, инвестиции, долги, цели. Цели не прибавляются к активам повторно. Отсутствие данных не выдаётся за известный нулевой капитал. Hero поддерживает exact minor units, отрицательное значение, огромные суммы без переноса и privacy. Не добавлена фиктивная историческая дельта net worth: её нет в существующем read model.

Важное существующее ограничение: `FinancialState` считает капитал в базовой валюте учёта, а `AccountCapitalService` использует свой существующий валютный пересчёт ликвидности. При валютных счетах итог hero может не равняться механической сумме пересчитанных разделов. На landing показано пояснение. Это не исправлялось новым mobile financial algorithm.

### Liquidity, Accounts, Reserve

- Отдельный Liquidity route: period, текущий итог, изменение, история, распределение денег, существующий прогноз до следующего дохода, обязательные платежи по долгам, freshness/quality и предупреждения о недостатке данных.
- График: tap и horizontal scrub выбирают дату и сумму; текстовая точка и отдельный доступный lazy список дат/значений. Несколько valuations одной даты не смешиваются. Расчётная история явно отличается от подтверждённых точек. Privacy убирает график и значения.
- Lazy список счетов → detail по стабильному account ID → редактор preferences. Показаны тип/роль, reserve/hidden/closed, известность баланса, валюта и состояние данных. Баланс банковского счёта сохраняет исходные копейки. Unresolved/fallback не маскируется под реальный известный счёт.
- Настройки используют существующие include-in-total/net-worth/analytics, emergency fund, visible, closed и role. Создание — существующий `addAccount`. Удаление счёта не добавлено.
- Account history имеет period, touch и list fallback; переход к операциям использует имеющиеся ID, не угадывает привязку по названию.
- Подушка: текущая сумма, цель, progress, покрытие расходов и выбранные счета. Editor меняет существующие account preferences и существующую цель «Финансовая подушка». Сумма/месяцы используют прежнюю формулу desktop и не создают новый asset. Месяцы доступны, только когда известны средние essential expenses; нового persisted поля нет.

### Investments

Список → detail → metadata editor / valuation / contribution / history / archive. Сохранены существующие types, currencies, status, inclusion flag, plan, preferred day, reminder, comment и opening date. Текущая оценка меняется отдельным valuation action, не случайно при редактировании metadata. Взнос и изменение оценки не смешиваются с observed bank transactions; используется прежний `adjustBalance` и существующие commands. History/period/freshness и различие изменений стоимости/вложений сохранены. Архив не удаляет snapshots или contributions.

### Debts

Список → detail → условия/editor, read-only записанные payments, история остатков, предстоящие события и отдельный сценарий. Monthly-extra и one-time-extra используют существующий `DebtAnalyticsService`; результаты обозначены как прогноз, а не совершённый платёж. Editor поддерживает имеющиеся типы/валюту/остаток/ставку/платёж/день/даты/credit-card условия и status. Ставка допускает десятичное значение. Архив/закрытие использует прежний command. **Нового debt-payment CRUD нет**, `addDebtPayment` из mobile Capital не вызывается.

### Goals

Список → detail → contribution/withdrawal, allocations, темп/сценарий, история, editor и archive. На первом экране: накоплено, target, осталось, progress, статус/срок. Распределение средств использует реальные существующие accounts/investments/manual-asset capabilities и прежний `GoalPlanningService`. Edit/remove allocation сохраняют identity; contribution не пишет банковскую операцию и не удваивает derived allocation amount. История существующих contributions/events сохранена, прогноз темпа отделён от факта. Completed/archived/overfunded состояния учитываются.

Debt-related upcoming event теперь ведёт к **конкретному Debt Detail по sourceId**, не в общий desktop раздел. Manual/inferred события остаются в прежних appropriate flows.

## Навигация и редакторы

```text
4 независимых retained roots: Обзор / Операции / Бюджет / Капитал
Ещё: вторичный вход; +: отдельное глобальное действие

Капитал
  → Ликвидность → история дат/сумм / Подушка → editor
  → Счета → Account Detail → preferences
          → операции этого account scope → Stage 3 detail/editor
  → Инвестиции → Investment Detail
                 → metadata / valuation / contribution / history / archive
  → Долги → Debt Detail → editor / history / recorded payments / scenario
  → Цели → Goal Detail → editor / contribution / allocations / pace / history

Любой исходный root → глобальный + → новый счёт → его Account Detail
Предстоящие → debt event → конкретный Debt Detail → исходные Предстоящие

Back: Editor → Detail → List → исходный root
Cross-link возвращается в исходный стек, не переключает молча корень.
Sheet закрывает только sheet; dirty editor спрашивает о несохранённых изменениях.
```

Маршруты — `MaterialPageRoute` в уже существующем root Navigator. Сохранены independent root stacks/PageStorage, period/scroll внутри живого route, capability wiring, источники внимания и общая action lane. Новая persistence UI-state/schema не добавлялась.

Редакторы одноколоночные, scroll/keyboard-aware, Save доступен внизу формы. Валидация проверяет и offscreen поля, не только уже построенные widgets. Dirty Back защищён, ошибка оставляет editor открытым, double-save блокируется.

**Money boundary:** investment/debt/goal CRUD модели сейчас хранят суммы целыми major units. `123,45` не округляется и не обрезается: поле показывает ошибку и Save не выполняется. `123,00` допустимо. Rate `13,25` поддерживается. Exact account balances, пришедшие из банка, отображаются без потери копеек. Добавление fractional CRUD требует отдельного изменения моделей и не сделано скрыто в этой задаче.

**Retry boundary:** существующие controller commands изменяют память до await persistence. UI queue при такой ошибке повторяет прежний persistence callback, а не повторно создаёт сущность/взнос. Compound reserve action продолжает с незавершённого шага. Draft после частичного применения фиксируется; закрытие не объявляется rollback и предупреждает об уже применённых изменениях. Data-generation/write guard не позволяет старому editor вернуть сущность после сброса данных. Новый repository API или транзакционный storage слой не создавались.

## Файлы

```text
lib/mobile/capital/
  mobile_capital_common.dart     # service wiring, rows, money, history interaction
  mobile_capital_editor.dart     # UI draft, validation, unsaved Back, retry boundary
  mobile_capital_pages.dart      # landing, liquidity, accounts/detail/preferences, reserve
  mobile_investment_pages.dart   # list/detail/history/edit/valuation/contribution
  mobile_debt_pages.dart         # list/detail/history/edit/read-only scenarios
  mobile_goal_pages.dart         # list/detail/edit/contribution/allocation/pace/history

lib/mobile/adapters/mobile_page_adapters.dart
lib/mobile/mobile_app_shell.dart
lib/mobile/analytics/mobile_upcoming_page.dart
lib/desktop/desktop_app_shell.dart  # global + account: mobile route, desktop old branch
pubspec.yaml                      # 1.0.67+68

test/fixtures/mobile_stage5_data.dart
test/mobile_stage5_capital_test.dart
test/mobile_capital_forms_test.dart
test/mobile_navigation_foundation_test.dart
test/mobile_desktop_parity_test.dart
tool/mobile_stage5_preview_test.dart
docs/mobile/stage5-20261006/        # 64 PNG + gallery
```

### Adapters и overlays

Из основного mobile Capital убраны `DesktopAccountsPage`, desktop modules/расширения и `MobileModuleAdapter`. Liquidity/Accounts/Investments/Debts/Goals больше не вызывают desktop pages. Их details/actions открываются routes, а не desktop selection/overlay. `MobilePageAdapters` остаётся wiring-классом: он не владеет финансовыми данными и не означает desktop UX нового Capital.

Не относящиеся к Capital secondary adapters сохранены: выгода/ИИ-export/settings в «Ещё», category/rules, action history/trash, intake/review и существующий manual UpcomingExpenseEditor. Merchants/Categories могут использовать `DesktopBudgetAnalysisPage`. Journal Stage 3 остаётся общей adaptive реализацией с именем `DesktopTransactionsPage`, **но на Android использует mobile list/toolbar и отдельные MobileTransactionDetail/editor routes**, а не desktop Capital layout. Переименование/дублирование этой рабочей реализации не включалось в Stage 5.

## Protected layers / parity

В Stage 5 **не менялись** models, repository, Synoball, codec/persistence/schema, financial calculations, Android native bridge, banks/import pipeline. Контрольные суммы до/после совпали для четырёх model-файлов, `BudgetController` и четырёх domain services Капитала. Их уже существующие изменения в общем dirty working tree относятся к предыдущим задачам, а не к Stage 5.

На одном синтетическом profile проверены:

- hero net worth из прежнего `FinancialState`, в том числе отрицательный;
- общий liquidity итог и вся история против `AccountCapitalService`;
- investment valuation против `InvestmentAnalyticsService`;
- debt balance и projection против `DebtAnalyticsService`;
- goals totals/progress против `GoalPlanningService`;
- отсутствие финансовой записи при просмотре, navigation, scenario и render;
- stable IDs при edit/retry; archive не уничтожает историю; reserve не меняет account balances.

Не создано новых financial business models. Chart points — UI tuples для уже вычисленных значений; chart painter считает только геометрию. Lists строятся лениво, не удерживается тяжёлая desktop tree. Stress fixture содержит 180 сущностей каждого вида и 1500 valuation snapshots; viewport не строит весь список заранее.

## Проверки

- Final targeted run: **72 passed / 0 failed**, 50 s — новый Capital плюс прежние forms/navigation/mobile-desktop parity. Лог `build/stage5-targeted-verified.log`.
- `flutter analyze --no-pub`: **No issues found**, 6.0 s. Лог `build/stage5-analyze-verified.log`.
- Render harness: **1 passed**, 11 s; **64 PNG**. Лог `build/stage5-renders-verified.log`.
- Окончательный полный `flutter test --no-pub --concurrency=1`: **906 passed / 12 skipped / 0 failed**, **4 min 18 s**. Лог `build/stage5-full-tests-verified.log`. Baseline Stage 4 (880 passed) сохранён, добавлено 26 проверок; same-date chart regression включён в этот прогон.

12 skipped — прежние opt-in проверки приватных/local corpus fixtures и Windows native bridge интеграций. Они не объявляются выполненными. Desktop widget regression проходит в общем suite; отдельный Windows release build/установка не выполнялись.

Покрыты create/edit/archive investment/debt/goal, valuation/contribution, allocation edit/remove, reserve, account exact balance/preferences, dirty Back (включая shell Android pop contract), двойной Save, ошибка persistence/retry, сброс данных при открытом editor, currency/whole-money validation, touch/scrub/list/privacy, exact debt-event link и retained root navigation. Desktop regression выполняется в полном suite: shell, charts, overview/drill-down, debt/capital, операции, тема/DPI и recurring.

Render matrix: десять основных screens × 320/360/390/430; details и четыре формы при text scale 1.3/320; landscape Capital/Liquidity; empty/negative/overfunded/many; huge amounts/long names; Reserve. Keyboard inset 280 px подтверждает достижимость Save в widget harness, **не подтверждает настоящую Android клавиатуру**. PNG вручную визуально просмотрены выборочно, весь matrix проверен harness на Flutter layout exceptions. Старые Stage 3/4 renders/APK сохранены.

## APK

Версия **1.0.67+68**, package `ru.qesto.qesto`. Release build прошёл за **135.3 s**. `aapt dump badging` подтвердил versionName/versionCode, minSdk **24**, targetSdk **36**, ABI **arm64-v8a / armeabi-v7a / x86_64**. `apksigner verify --verbose --print-certs` подтвердил APK Signature Scheme v2.

Это **тестовая release-сборка с прежней Android Debug подписью**, не store/production signing. Сертификат совпадает с APK предыдущих Stage 3/4.

- Размер: **99 582 760 байт** (~95.0 MiB).
- APK SHA-256: `dd0c1faac66d028d1cea30d130e4a0cc6e706f61a311eae8b4f132881e61121a`.
- Certificate SHA-256: `5ad742281bf9eb813f3e71ed722e77d09ad08d1120954deec8a219fc7871a916`.
- Build log: `build/stage5-apk-build-verified.log`.
- Именованный Stage 4 APK сохранён; его SHA-256 по-прежнему `08cddf3bee0feb00a88aeaed204c9ce5b67b1ef2c4f6f5bf84388ff6de0cb508`.

[Qesto 1.0.67 — Stage 5 APK](../../build/app/outputs/flutter-apk/Qesto-1.0.67-mobile-stage5.apk)

APK не устанавливался на телефон/эмулятор. Windows app не собирался/не устанавливался в этой mobile-задаче; установленный пользовательский финансовый профиль и банковская сессия не читались и не менялись. Миграции данных нет. Не удалять старое приложение при несовпадении подписи: сначала резервная копия и отдельное согласование.

## Fresh renders

[Галерея всех 64 рендеров](stage5-20261006/index.html) — фильтры по ширине/scale/landscape/edge/forms.

1. [Capital landing](stage5-20261006/01-capital-390.png)
2. [Liquidity](stage5-20261006/02-liquidity-390.png)
3. [Accounts](stage5-20261006/03-accounts-390.png)
4. [Account Detail](stage5-20261006/04-account-detail-390.png)
5. [Investments](stage5-20261006/05-investments-390.png)
6. [Investment Detail](stage5-20261006/06-investment-detail-390.png)
7. [Debts](stage5-20261006/07-debts-390.png)
8. [Debt Detail](stage5-20261006/08-debt-detail-390.png)
9. [Goals](stage5-20261006/09-goals-390.png)
10. [Goal Detail](stage5-20261006/10-goal-detail-390.png)

Это actual Flutter render на synthetic fixtures, не HTML-концепт и не снимок физического устройства. Mock native channels не читают пользовательский inbox.

## Deferred Android Device QA — Stage 3–5

После установки на телефон без удаления прежних данных:

1. Проверить update/signature, запуск, 4 roots, «Ещё», глобальный +, independent navigation state.
2. Системный Back/gesture, dirty confirmation, восстановление scroll/period, уход приложения в фон и resume.
3. Настоящая клавиатура на account/investment/debt/goal editors, comma/decimal/numeric input, clipboard, Save/IME insets, rotation.
4. Создать/изменить/архивировать тестовые сущности; повторное сохранение и restart: ID/балансы/история не дублируются.
5. Touch/scrub Capital/analytics charts, доступный list fallback; TalkBack, крупный системный шрифт и display size, privacy.
6. Stage 3 notification/SMS permissions, denied→status, incoming review, сохранение направления/исходного типа/копеек, источник ошибки/необработанные записи заметны из shell.
7. Stage 3 operations editor/drill-down/scopes/manual/import flows и Stage 4 Overview/Budget/limits/filters/upcoming на реальных локальных данных.
8. Error/retry на реальном persistence/lifecycle, безопасность reset при открытом editor и отсутствие duplicate save.
9. Проверить performance на большом profile и продолжительность длинной history. Widget lazy tests не заменяют device profiling.

## Ограничения и stop point

Native QA не выполнена. Fractional CRUD для major-unit моделей, единый валютный net-worth consolidation и новый debt-payment editor требуют отдельного scope. Эти ограничения не скрываются UI округлением или фиктивными действиями. Secondary screens вне Capital остаются перечисленными adapters.

Stage 5 **завершён по коду**: сборка, статический анализ и финальный полный suite прошли. Физическая Android QA остаётся deferred. Здесь остановка; следующий этап не начинается без согласования.
