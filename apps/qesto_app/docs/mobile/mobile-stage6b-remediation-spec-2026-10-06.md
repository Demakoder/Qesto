# QESTO Mobile — Stage 6B Remediation Specification

Источник: physical audit Stage6A, 06–07.10.2026, Samsung SM-S921B / Android16 / API36, Qesto1.0.67(68).
[Audit report](mobile-stage6a-device-audit-2026-10-06.md) и private evidence stage6a-20261006 — исходные факты.
**Это ТЗ, а не выполненные исправления. Начинать только после отдельного согласования slice.**

## Цель / boundaries

Исправить 2 P1, 4 P2, 1 P3, подтверждённые живым Android. Доказать результат canonical data и device E2E, не только widget tests.
Не создавать новый финансовый engine, parallel import connector, storage schema, migration, transaction type или currency engine.
Не обходить банковскую/Android безопасность. Не выбирать fallback account автоматически ради исчезновения ошибки.
Не расширять fractional capital model, debt-payment CRUD, arbitrary receipt OCR или AI placeholder.
Существующие whole-unit editors остаются whole-unit; transaction cents и decimal interest сохраняются.
Desktop presentation/импорт регрессии проверять после shared-file changes.
Нельзя очищать профиль, переустанавливать с data loss, удалять native inbox, публиковать персональные raw payload или менять signing без согласования.
Сохранить исходный installed build до device сравнения. Обновление APK допустимо только в будущем согласованном implementation stage, с обычным безопасным upgrade и backup.

## Последовательность slices

| Slice | Scope | Issues / результат |
| --- | --- | --- |
| A | Safety gate, без speculative P0 fix | P0 не обнаружен; зафиксировать canonical baseline и запрет разрушительных изменений |
| B | XLSX compatibility | A6-01/P1: package URI resolution, отдельно от UI redesign |
| C1 | Android QR lifecycle | A6-02/P1: exception safety/retry + расследование SDK NPE |
| C2 | Actionable source attention | A6-05/P2: понятные ephemeral причины и безопасные действия |
| D | Mobile navigation/actions | A6-03/P2 selection и A6-04/P2 global create; можно один presentation PR после независимых reproductions |
| E | Capital UX | A6-06/P2 archived breakdown и A6-07/P3 validation wording |
| F | Accessibility/lifecycle/performance retest | Закрыть device gaps; исправлять только новые доказанные issues и с дополнительным scope approval |
| G | RC regression | Полный automated + physical safety matrix, release readiness решение |

Не объединять B/C1 в большой rewrite. Можно выпускать независимые минимальные patches; после каждого — targeted device acceptance, затем G.
Все новые найденные financial P0 сначала документируются и отдельно согласовываются, не входят автоматически в UX slice.

## Slice A — baseline / data-safety gate

Before:
- Сохранить штатный diagnostic export с privacy flags до изменений, version/APK hash, уникальные transaction/account IDs, pending count, permission state.
- Использовать QA entities и synthetic fixtures; реальные notification names не включать в public tests.
- В Stage6A конец: 4 canonical operations (100.55 expense /84.99 expense /500.25 income /40.15 refund), один QA bank account50000.00, brokerage150, debt1000.
- Goal contribution200 + allocation300 даёт projection300, не500; forecast/allocation/contribution не bank transactions.
- Исходный manual ID можно сверять с redacted export348; сохранение ID относительно самого первого edit не считать доказанным.

Acceptance:
- Любой отменённый editor/picker не пишет transaction.
- Pending ack только после успешного persistence; fail/cancel сохраняет входящее.
- Нет fixture operations, авто-вставленных в production профиль вне explicit UI confirm.
- Старые пользовательские данные не исчезают; QA cleanup только по отдельному желанию пользователя, через штатный recoverable flow.
- Ни одной migration. Разница данных после теста объясняется только заранее перечисленными UI действиями.

## Slice B — A6-01, P1: XLSX relationship compatibility

### Before reproduction
Запустить сохранённый diagnostic test excel-fixture-diagnostic_test.dart на QA-ST6-import.xlsx и через native DocumentsUI.
Не изменять fixture, чтобы скрыть incompatibility. Raw decoder должен сначала воспроизводить Damaged Excel file: styles.
Expected rows: expense80.35 на06.10.2026, income2000.25 на05.10.2026.

### Confirmed cause / affected files
UniversalExcelStatementAdapter.parse (lib/features/statement_import/services/universal_excel_statement_adapter.dart) → Excel.decodeBytes.
excel_community2.2.1 parse.dart + styles_parser.dart принимают "/xl/styles.xml" как relative и ищут "xl//xl/styles.xml".
Первое ошибочное lookup доказано; остальные особенности этого workbook после исправления надо проверить заново.

### Implementation boundary
- Сперва определить минимальный корректный package URI resolution, применимый к styles/sharedStrings/worksheets.
- Предпочтение: локальная compatibility boundary перед decode ПОСЛЕ существующего archive guard либо проверенное upstream решение; dependency update только если отдельно обоснован и согласован.
- Не править Pub cache как deliverable. Не удалять styles/суммы/даты и не конвертировать деньги в int major units.
- Package-root URI "/xl/..." должен разрешаться относительно ZIP package, не файловой системы Windows.
- Разрешать только внутренние ZIP entries. Не скачивать external relationships, не выполнять macros, не разрешать UNC/drive paths/path traversal.
- Сохранить существующие 20MB, ZIP/uncompressed size, sheet/row/column ограничения; не ослаблять защиту ради fixture.
- Не менять Synoball ingestion/identity/source trust или statement models.

### Automated After
- Absolute "/xl/styles.xml" и standard relative "styles.xml" fixtures.
- Absolute sharedStrings/worksheet relations.
- Malformed missing relation, traversal и external relationships остаются отказом без writes.
- Извлечение двух строк: type/direction/date/8035 и200025minor; валюты и IDs стабильны.
- Existing Excel corpus/regression + archive-limit tests.
- XLSM читается без исполнения макросов; если нет safe fixture, пометить gap.

### Device acceptance
DocumentsUI → тот же файл → корректный preview → существующий QA account → explicit confirm →2 новых IDs.
Повторный импорт →0 новых, account identity тот же; текущий известный balance не заменяется балансом statement без существующего разрешённого правила.
Ошибка другого XLSX → понятный error, предыдущие данные доступны.
Риск регрессии: normalization может изменить source hash/identity; сравнить existing fixtures и repeated imports, не придумывать новый identity алгоритм.

## Slice C1 — A6-02, P1: QR start failure / pending result lifecycle

### Before
«+» → «Чек» → scanner на текущем release build. Зафиксировать первый NPE и второй busy.
Одно воспроизведение достаточно для ловушки retry, но для SDK cause нужно independent recreation повторение.

### Confirmed cause / hypothesis
MainActivity.scanReceiptQr: pendingReceiptResult устанавливается до getClient/startScan; synchronous throw не попадает в listeners, pending остаётся.
Native stack обфусцирован. Причина самого SDK NPE неизвестна; Android16/Play Services/R8 пока гипотезы.

### Investigation first
Сопоставить stack с mapping текущего release build, проверить scanner availability/module initialization, версии Play Services и manifest metadata.
Не отключать security, R8 или добавлять broad keep rules без доказанного причинного механизма.
Не подменять scanner случайным camera implementation или новым plugin только ради первого исключения.

### Minimal fix boundary
Affected: android/app/src/main/kotlin/ru/qesto/qesto/MainActivity.kt scanReceiptQr; receipt_scanner_service_native.dart; receipt_import_screen.dart.
- Exception-safe acquire/start и освобождение pending на synchronous failure.
- Один terminal result на request; success/failure/cancel/destroy не отвечают дважды.
- Late callback старого request не завершает новый request.
- Busy только когда scanner действительно активен.
- Typed безопасная ошибка пользователю, локальный diagnostic code без raw Java stack в UI.
- Retry и Back работают без force-stop. При unavailable scanner ручной QR input сохраняет existing fallback.
- Ошибка не превращается в success(null), если это не cancellation.

### After tests / device
- Synchronous throw → pending очищен → следующий request может стартовать.
- Success, async failure, cancel, overlapping tap, Activity destroy/late callback; no double result.
- Device scanner действительно открывается. Пользователь показывает контролируемый QR; preview/review перед confirm; cancel оставляет ledger неизменным.
- Missing scanner module/permission/unavailable flow: понятный error+retry, не crash/busy forever.
- Canonical duplicate check после повторного подтверждения одного чека.
Риск: общий pendingReceiptResult используется и для document scanner; его flow не должен сломаться.
Не объявлять slice завершённым, если лишь NPE превращён в красивый error, а scanner по-прежнему не открывается.

## Slice C2 — A6-05, P2: причины source attention

### Before
Существующий pending1/failed1 → Sources. UI показывает только generic count.
Исследовать именно текущую pending запись через штатный review; account-confidence причина пока не установлена.

### Minimal boundary
Files: automatic_notification_importer.dart; mobile_source_attention_controller.dart; mobile_source_status_page.dart.
Разделить ephemeral outcome reasons: needs_account / permission / unsupported / read_failure / persistence_failure / ack_failure.
Не вводить новую persistent financial schema. Если reason нельзя получить без schema или публичного API изменения — остановить и согласовать scope.
Не хранить новый raw банковский текст ради banner. Нужны code/count и existing review/retry actions.
Unresolved account должен вести к безопасному explicit выбору/созданию счёта; ack_failure retry — идемпотентный.
Permission revoke/resume продолжает обновляться без restart, pending не исчезает.
Несколько причины не должны создавать одинаковые дублирующие banners; badge счётчик и summary объясняют свою семантику.

### After tests / acceptance
Each outcome reason, permission grant/revoke, channel unavailable on desktop, save failure/pending сохранён, ack retry без duplicate.
Device incoming transfer preview/cancel и безопасный контролируемый Save. Причина видна; её устранение очищает attention только после реального успеха.
Не превращать все incoming в expense; preserve original kind/direction/amount/cents/ID.
Текущую ошибку не «исправлять» выбором произвольного QA account или стиранием inbox.

## Slice D — navigation / global creation

### A6-03, P2: selected chart point

Before reproduction test: выбрать point и scoped IDs, detail → Budget edit totalPlan того же id/start/end → Overview Back.
Контрольная ветка без Budget change. Отдельно смена реального диапазона должна сбрасывать stale selection.
Hypothesis: reference inequality BudgetPeriod в didUpdateWidget; controller update создаёт copyWith. Сначала подтвердить widget regression и device control case.

Boundary: mobile_overview_page.dart; tests. Не менять глобальную BudgetPeriod equality или financial model только ради UI.
Сравнить presentation period key (ID/range/currency по требуемой семантике). Budget plan change сам по себе не новый диапазон.
После transaction edit пересчитать selected bucket/scope по текущим canonical IDs, не оставлять stale deleted ID; сохранять point, где он ещё валиден.

After: root independent stacks, point/day/week/month, period, exact scope, filters/scroll, controller replacement, deleted selected operation, changed budget plan.
Device return должен восстановить тот же point и scope. Desktop chart contract не изменён.

### A6-04, P2: global + actions

Confirmed: _AddDataAction.account → mobile.createAccount().
Affected: lib/desktop/desktop_app_shell.dart (shared dispatch) и lib/mobile/mobile_app_shell.dart; existing capital editor functions.
Minimal mobile-only submenu «Счёт / Инвестиция / Долг / Цель» или отдельные короткие пункты.
Reuse openMobileAccountCreate/openMobileInvestmentEditor/openMobileDebtEditor/openMobileGoalEditor и текущие native mobile routes.
Не строить новый editor/storage. Cancel возвращает к исходному root/stack без writes; Save → detail созданной сущности по одному ID.
Desktop branch сохраняет прежние действия; capability policy не ломать.

After: global+ с каждого из4roots → все4editors, Back/dirty discard, IME, double-tap защиту, stable route, no duplicated entity.
Device каждое действие реально открывает конкретную форму, не просто Capital root.
Есть reachable scroll и читабельные labels при font1.3; не требуется массовый redesign всего приложения.

## Slice E — capital presentation / validation

### A6-06, P2: архивный investment в breakdown
Confirmed: canonical financial total включает brokerage150; active InvestmentAnalyticsService excluding archived даёт0.
Files: mobile_capital_pages.dart/mobile_capital_common.dart; services — только как read-only источники.
Minimal presentation решение: active portfolio явно подписан и архивная включённая в капитал стоимость раскрывается отдельно; либо breakdown показывает все включённые активы с archive badges.
Сначала подтвердить product semantics includeInTotal при archive. Не превращать archive в sale, не обнулять balance, не менять core aggregate ради красивого совпадения.
Before: account50000 + archived150 − debt1000 =49150; строки обязаны объяснять150.
After: archived истории/contribution retained, total прежний, value объясним, активный список может исключать архив. Unarchive/flags/currencies regression.

### A6-07, P3: validation vs save failure
Files: mobile_capital_editor.dart; form tests.
Before: nonzero fractional capital → clipping/duplicate error + «Повторить сохранение».
Minimal: различать local validation и actual write failure в presentation state; multiline полезный helper, focus/scroll invalid field; normal Save при исправлении.
Whole-unit rejection НЕ отменять. Local invalid input не запускает repository; persistence error сохраняет draft и настоящий retry.
After: 123/123.00 accepted,123.45 rejected в respective whole editors; transaction123.45 и interest12.5 всё ещё accepted. Font1.0/1.3 + IME top/middle/bottom + dirty discard.
Partial compound writer retry не должен повторять уже успешно записанный шаг.

## Slice F — outstanding physical gates (не новые функции)

Обязательная повторная проверка:
- Реальные/контролируемые bank notifications expense/income/refund/transfer+cents: capture →review/edit безопасного поля →Save →canonical →ack →repeat/restart.
- Большой безопасный журнал и длинные Capital histories; mixed currencies; exact fractional BANK balance (не whole manual editor).
- PDF extraction, screenshot OCR review/confirm/cancel/retry; fixed XLSX/XLSM; fixed scanner success/cancel.
- Liquidity selected point/scrub/scroll/list fallback; Reserve editor/flags не меняют bank balance.
- Goals withdraw/edit/remove allocation/complete/archive/restart; debts readonly recorded payments/scenario/archive; debt Upcoming exact route.
- Budget0 removal/cancel/repeat save/restart; Filters search/review/clear/exact canonical scope.
- Light Overview, explicit Dark, System; font1.3 details и длинный editor; display size.
- TalkBack только если пользователь согласен: bottom-nav labels, charts fallback, fields, destructive confirmation.
- Реальная landscape rotation, predictive/edge Back и native lifecycle cancellation; если orientation не поддержана, документировать policy и ограничение.
- Offline local ledger, network error explanation; вернуть сеть и настройки после теста.

Не считать missing test причиной переписать компонент. Новые bugs: evidence/severity/root cause сначала, новый scope после согласования.
Один memory snapshot или gfxinfo Flutter смешанный report не доказывает leak/jank root cause.

## Slice G — RC acceptance / выпуск

1. По каждому A6 issue: failing Before repro → минимальный patch → targeted automated → тот же device path → canonical/permission/lifecycle proof.
2. flutter analyze без ошибок. Полный test run: публиковать исходные PASS/SKIP/FAIL; retry отдельно. Не маскировать flakes зелёным итогом.
3. Targeted desktop regressions: shared shell/actions, chart/scopes, imports, Synoball dedup, notification persistence. Windows smoke/release build только в отдельно согласованном release workflow.
4. Новые Android release APK version/hash/signing, upgrade поверх текущего без uninstall; backup до установки, сравнить old/new data.
5. Scanner SDK release (R8) тест именно на release, не только debug.
6. Всё QA/личное evidence остаётся локальным; public fixtures синтетические. Git/PR только по запросу пользователя.
7. Финальные settings/permissions зафиксированы. Не оставлять неожиданно включённый mic/network/font/rotation.
8. Ни одного открытого P0/P1; P2/P3 либо закрыты, либо явно приняты пользователем; critical NOT TESTED не выдаются за acceptance PASS.
9. Отчёт: changed files, tests, before/after data, device renders, известные ограничения. Ни одного финансового fix без canonical доказательства.

## Stop condition

Сейчас выполнено только проектирование Stage6B. Начало любого slice, смена dependencies/signing/schema, сборка нового APK или cleanup профиля требует соответствующей отдельной команды.
