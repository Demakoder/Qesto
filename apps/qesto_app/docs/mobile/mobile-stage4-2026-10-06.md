# Qesto Mobile — Stage 4

Дата: 6 октября 2026. Цель: mobile-first presentation «Обзор» и «Бюджет» поверх существующего financial read model. Проверки без телефона; физическая QA Stage 3/4 не заявляется выполненной. Новый PR не создавался. Stage 5 не начат.

## Что изменено

«Обзор» больше не строится через DesktopDashboardPage. Компактный период остаётся в прежнем shell. Первая сводка: текущий капитал, расходы периода, чистый поток. Капитал без счетов/инвестиций/долгов обозначен как отсутствующие данные, не как известный нулевой баланс. Нулевой virtual fallback из существующего legacy bridge не считается подтверждённым балансом; сам fallback и финансовые расчёты не менялись. Реальный счёт с нулевым балансом по-прежнему показывает 0. Суммы масштабируются без переноса, поддержан privacy режим.

Далее: существующее сравнение расходов, непустая очередь внимания, preview динамики и ведущих категорий, income/expense/net summary, крупные расходы и preview ближайших событий. Отсутствующее сравнение не выдаётся за изменение 0%. Прогноз не выдаётся за совершившуюся операцию. Полная desktop «Река» не размещается на первом экране.

«Бюджет» имеет собственный landing: план/факт, остаток или превышение, progress, список лимитов категорий, назначение общего и отдельного лимита. При отсутствии лимита остаток бюджета не показывается как вычисленная сумма. Категории без расходов/лимитов доступны через «Назначить лимит категории». Редактор вызывает прежние setTotalBudget / setCategoryBudget, 0 снимает лимит, диапазон суммы прежний. Отмена не пишет данные; повторное сохранение использует прежний стабильный ID.

Аналитика и события — отдельные rows/routes: расходы, денежный поток, ритм, предстоящие/регулярные. Нет nested horizontal tabs или постоянно раскрытого budget toolbar. «Капитал» намеренно не переделан.

### Расходы

Период → сумма и сравнение → touch-график → категории/продавцы → точные операции. Вторичные настройки находятся в меню: сравнение, валюта отображения, качество, локальное обновление. Использован прежний FilterSheet и filter engine. Применённые фильтры видны отдельно, можно снять один или всё. Sheet сохраняет исходные tag filters, пока пользователь явно не сбросит их; compact-режим ограничивает ширину длинных chip labels, desktop layout по умолчанию сохранён.

Дополнительные показатели раскрываются отдельным маршрутом: медианный чек, средние дневные расходы, частота и чеки продавцов, диапазоны сумм, крупнейшие операции и существующие негенеративные insights. Все значения из существующего StatisticsSnapshot. Валютная конверсия использует прежний встроенный snapshot ЦБ с явной датой 22.08.2026, не новый онлайн currency engine.

### Денежный поток

Показываются income / expense / net и читаемая list representation всех источников и направлений, с раскрытием длинного списка. По месяцам показан чистый поток, доходы и расходы и доступны фактические операции. Сложная desktop river не дублируется на телефоне. Внутренние переводы доступны как исключённая выборка, не расход/доход. Неподходящие валюты не складываются в общий поток, это явно обозначено.

Summary использует существующий CashFlowCalculationService и exact minor units. Display-группы используют прежнее desktop округление/major-unit presentation без изменения его алгоритма. Canonical membership сохраняется при группировке и передаётся в journal как список ID, не подбирается fuzzy search по подписи.

### Ритм и события

Сохранены календарь, дни недели (с количеством и средним чеком), недели периода, первые пять дней после поступления дохода и существующее сообщение о недостатке точного времени суток. Календарь имеет touch и альтернативу «Даты и суммы списком». Выбор дня/недели/цикла ведёт к конкретным операциям текущей query.

UpcomingEventsService общий с desktop: manual one-time, manual recurring, inferred, debt, overdue и tentative остаются разными источниками. Прогнозы не пишут observed transaction. Ручной план редактируется прежним UpcomingExpenseEditor; открытие/отмена не создают период. Для inferred доступны canonical IDs фактической серии. Debt entity/forms остаются следующим slice, вместо имитации редактирования показано явное направление «Капитал → Долги».

## Файлы и архитектура

```text
lib/mobile/
  analytics/
    mobile_overview_page.dart
    mobile_budget_page.dart           # landing, category route, limit editor
    mobile_analysis_page.dart         # expenses / cash flow / rhythm routes
    mobile_upcoming_page.dart
    mobile_financial_widgets.dart
    mobile_statistics_controls.dart
  adapters/mobile_page_adapters.dart
  mobile_app_shell.dart               # только подключение новых routes

lib/features/statistics/presentation/state/
  analytics_presentation_selectors.dart

test/
  fixtures/mobile_stage4_data.dart
  mobile_stage4_analytics_test.dart
tool/mobile_stage4_preview_test.dart
docs/mobile/stage4-20261006/           # 31 PNG + галерея
```

Дополнительно затронуты presentation-файлы: desktop_cash_flow_page, secondary_statistics_sections (bounded shared extraction), statistics_screen (публичный общий FilterSheet), statistics_charts и overview_expense_trend_chart (opt-in scrub). Desktop defaults и layout этих chart widgets сохранены. pubspec version — 1.0.66+67.

### Navigation graph

```text
Обзор [retained root]
  → аналитика расходов / денежного потока [свой query + период]
    → точные scoped operations [canonical IDs]
      → MobileTransactionDetail → Stage 3 editor
  → внимание / предстоящие

Бюджет [retained root + выбранный period ID + scroll]
  → категория → точные operations → detail/editor
  → limit editor [существующие commands]
  → Расходы / Денежный поток / Ритм / Предстоящие [mobile routes]

Операции и Капитал: прежние отдельные retained roots
Ещё / глобальный + / source attention / capability wiring: foundation сохранён
Back: detail → исходная ID-выборка → аналитика/категория → исходный root
```

Открытие аналитики из бюджета получает выбранный период бюджета; дальнейший period/filter query локален этому маршруту. Изменение query не перезаписывает Operations root. Touch-selection сохраняется после локального изменения/refresh данных, пока её дата остаётся внутри выбранного диапазона. State и scroll сохраняются прежними root Navigator/PageStorage механизмами; новая persistence UI state/schema не добавлялась.

### Удалённые и оставшиеся adapters

Удалены из mobile roots: DesktopDashboardPage и DesktopBudgetPage. Основные expenses/rhythm/recurring routes заменены MobileAnalysisPage/MobileUpcomingPage; cash-flow route больше не вызывает desktop page через hidden selection.

Оставлены намеренно: DesktopTransactionsPage как lazy journal, DesktopAccountsPage и остальные Capital modules/forms, подробная CategoryDetailsScreen, category/rule manager, history/trash, существующие intake/review и ручной UpcomingExpenseEditor. «Ещё» продолжает подключать прежние выгоду/ИИ/settings. Это не незаметное удаление capabilities и не заявка, что все mobile screens уже redesigned.

## Финансовая логика и safety boundary

- Общие модели, Synoball, BudgetController, repository, API, storage codec/schema и financial algorithms в Stage 4 не изменены.
- Overview напрямую использует DesktopOverviewData и OverviewDrilldownData; budget — summaryFor/categoryPlansFor; Expenses — StatisticsController/Snapshot; CashFlow — существующий service; события — UpcomingEventsService.
- Shared extraction переносит только прежние display grouping cash flow и недельные/пятидневные presentation selectors из desktop UI. Их результаты сопоставлены с прежними implementation formulas на одном fixture. Desktop использует те же selectors.
- Charts не переписаны: добавлен opt-in horizontal scrub, текст выбранного значения и list fallback. Desktop behavior по умолчанию прежний.
- Opening/navigation/render/cancel проверяются на неизменность encoded financial profile. Native banks/permissions/import pipeline в Stage 4 не изменены.
- В working tree уже были изменения Stage 2/3 и более ранние задачи. Они сохранены; их diff в models/controller/Synoball не является новым Stage 4 изменением.

## Проверки

Stage 4 targeted run: **41 тест + 2 empty-profile проверки + 1 render harness = 44, все прошли**. Предыдущий targeted run с baseline mobile layout/navigation дал 68 успешных тестов до добавления трёх state checks; окончательный общий baseline подтверждён полным suite.

Новые проверки: 32 combinations Overview/Budget (320/360/390/430 × empty/typical/many/huge/exceeded/no-budget/long/no-comparison), полное пролистывание и честное empty capital; parity Overview/Budget/Expenses/CashFlow и shared grouping/rhythm; filter individual/reset/tags; cancel/read-only и stable-ID save; exact-ID drill-down/Back; privacy; scrub selection после refresh; error → предыдущие данные → retry; 320 px text scale 1.6. Старые тесты startup/Back обновлены с desktop-приветствия на mobile root с сохранением проверки пользовательских данных и выбранного корня.

Окончательные результаты:

- Полный `flutter test --no-pub --concurrency=1`: **880 passed / 12 skipped / 0 failed**, 4 min 42 s. Stage 3 baseline (839 passed) сохранён, добавлен 41 Stage 4 тест. Лог: `build/stage4-full-tests-verified.log`.
- Desktop regression прошёл внутри полного suite: shell, overview/drill-down, cash flow, capital/debts, recurring, theme/DPI и операции. Windows-target widget tests выполнены; отдельный Windows release build/установка в этой mobile-задаче не выполнялись.
- Mobile foundation/navigation, Stage 3 safety/editor/scopes/source attention/lifecycle, analytics/budget parity и period restoration проходят в общем suite.
- `flutter analyze --no-pub`: **No issues found**, 80.3 s. Лог: `build/stage4-analyze-verified.log`.
- Render harness: 31 актуальный PNG, 8 обязательных экранов/состояний представлены в галерее. Файлы вручную визуально просмотрены; размеры Overview/Budget проверены на 320/360/390/430 logical px. Лог targeted run: `build/stage4-targeted-final.log`.
- APK release build: успешно; версия и подпись отдельно проверены (ниже).

12 skipped — существующие opt-in проверки с приватными/local corpus fixtures и Windows native bridge интеграцией. Они не объявляются выполненными. Физическая Android QA по-прежнему отложена.

### APK для общей проверки на телефоне

[Qesto 1.0.66 — Stage 4](../../build/app/outputs/flutter-apk/Qesto-1.0.66-mobile-stage4.apk), versionCode 67, package `ru.qesto.qesto`. Размер 98 960 168 байт (~94.4 MiB), minSdk 24 / targetSdk 36, ABI arm64-v8a / armeabi-v7a / x86_64.

Release build завершён успешно (87.6 s, финальная инкрементальная сборка). `aapt dump badging` подтвердил версию; `apksigner verify` подтвердил v2-подпись. Это **тестовая release-сборка с Android Debug signing**, не production/store-signing. Сертификат совпадает с предыдущим Stage 3 APK.

- APK SHA-256: `08cddf3bee0feb00a88aeaed204c9ce5b67b1ef2c4f6f5bf84388ff6de0cb508`.
- Certificate SHA-256: `5ad742281bf9eb813f3e71ed722e77d09ad08d1120954deec8a219fc7871a916`.
- Build log: `build/stage4-apk-build-verified.log`.

APK не устанавливался на телефон или эмулятор. Установленное Windows-приложение, пользовательское хранилище и банковский профиль не обновлялись и не открывались. Предыдущий именованный Stage 3 APK сохранён. При будущем несовпадении подписи не удалять старое приложение/данные ради установки — сначала сохранить данные и согласовать перенос.

Состояния loading/capability lifecycle сохранены из host Stage 3; новые local refresh/error states добавлены без bank network request. Error не заменяет предыдущую сводку ложным нулём. Data quality warnings обозначают известную неполноту, не доказывают полноту банковской истории. Новой банковской freshness метрики не изобретено.

## Рендеры

[Галерея всех основных экранов и состояний](stage4-20261006/index.html).

1. [Обзор](stage4-20261006/01-overview.png)
2. [Бюджет](stage4-20261006/02-budget.png)
3. [Расходы](stage4-20261006/03-expenses.png)
4. [Денежный поток](stage4-20261006/04-cash-flow.png)
5. [Ритм жизни](stage4-20261006/05-rhythm.png)
6. [Предстоящие и регулярные](stage4-20261006/06-upcoming.png)
7. [FilterSheet](stage4-20261006/07a-filter-sheet.png) / [активные фильтры](stage4-20261006/07b-active-filters.png)
8. [Touch-selection графика](stage4-20261006/08-chart-touch.png)

Это реальный Flutter widget render на синтетических данных, не изображение-макет и не снимок физического Android. Harness не читает установленный профиль, банк или inbox. Native settings/keyboard/device gestures этим не проверены.

## Отложенная физическая QA Stage 3 + Stage 4

Устанавливать поверх совместимой предыдущей сборки, без удаления данных. Пока ни одна проверка ниже не отмечена выполненной:

- Notification permission denied → native settings → grant → resume → source badge/banner; revoke и сохранённый inbox.
- Manual/notification/screenshot операции: доход/расход/возврат/перевод, направление, копейки, сохранение canonical ID, pending ack только после Save.
- Transaction detail → edit → keyboard/Save → Back; discard; поворот/малый экран; нижние safe areas.
- Import picker/scanner/OCR: cancel, error, retry, late async result, review до подтверждения; нет write при cancel.
- Delete/bulk/restore/trash и отсутствие восстановления удалённого при sync.
- Корни/More/global +: hardware/gesture Back, независимые query/scroll/period stacks, reselect без reset.
- Overview → analytics → selected day/category → operations → edit → Back с сохранением selection/filter/period.
- Budget period → category limit edit → operations → detail → Back; no-budget/exceeded/длинные названия/большие суммы.
- Chart tap и horizontal scrub, вертикальная прокрутка, screen reader и list fallback, accessibility text scale, privacy.
- Upcoming: manual/inferred/debt/tentative, forecast не создаёт факт списания.

## Stop point и известные ограничения

Капитал и его формы, дополнительные category/rule/detail layouts и intake screens пока используют прежнюю presentation. Новой схемы сохранения UI-state между перезапусками нет (foundation retention внутри session). Голосовой parser не получает новую поддержку копеек. Financial service rounding и существующий persistence error/in-memory contract не переписывались.

Приёмка Stage 4 coding part не означает пройденную физическую Android QA. Следующий slice согласовывается отдельно; Stage 5 автоматически не начинается.
