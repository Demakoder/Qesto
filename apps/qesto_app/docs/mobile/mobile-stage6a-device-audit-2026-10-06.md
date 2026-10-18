# QESTO Mobile — Stage 6A: аудит физического Android

Период: 06.10.2026 22:20 — 07.10.2026 00:07, Europe/Moscow. Дата имени файла — начало аудита.
Режим **AUDIT ONLY**. Исправления Stage 6B не выполнялись.

## Environment

| Параметр | Фактическое значение |
| --- | --- |
| Устройство | Samsung Galaxy S24, SM-S921B; serial RFCX50B03JD |
| Android / API | Android 16 / 36 |
| Экран / density | 1080×2340, 480 dpi; приблизительно 360×780 dp |
| Locale / navigation | ru-RU; gesture navigation_mode=2; portrait |
| Package / build | ru.qesto.qesto, versionName 1.0.67, versionCode 68 |
| minSdk / targetSdk | 24 / 36 |
| First install / last update | 11.09.2026 23:53:49 / 06.10.2026 22:12:28 |
| Доступная память в baseline | MemTotal 7,397,300 KB; MemAvailable 2,134,224 KB |
| Storage baseline | /data/user/0: 105 GB всего; 5.4 GB свободно, 95% занято |
| APK | build/app/outputs/flutter-apk/Qesto-1.0.67-mobile-stage5.apk |
| APK SHA-256 | dd0c1faac66d028d1cea30d130e4a0cc6e706f61a311eae8b4f132881e61121a |
| Signing SHA-256 | 5ad742281bf9eb813f3e71ed722e77d09ad08d1120954deec8a219fc7871a916; debug certificate |

Установленный APK сопоставлен по хешу с Stage 5, не только по имени/versionName. В рамках Stage 6A APK не собирался и не устанавливался. Debug signing — свойство тестовой сборки, не изменение этого аудита.

## Device connection

ADB: C:/Users/ARM/AppData/Local/Android/Sdk/platform-tools/adb.exe, serial со статусом device.
Использованы shell input, UIAutomator XML, screencap, dumpsys package/activity/meminfo/gfxinfo, logcat.
Диагностический helper: [device-audit.ps1](stage6a-20261006/device-audit.ps1).
Private release storage через run-as недоступен. Обхода защиты не было; canonical-проверка выполнена штатным JSON export.

## Executive summary

Матрица содержит **54 группы требований**, соответствующие §3–56 ТЗ: **5 PASS / 6 FAIL / 35 PARTIAL / 8 NOT TESTED / 0 BLOCKED**.
Это не количество отдельных taps или unit tests. PARTIAL означает, что перечисленная часть прошла, но весь набор подпунктов нельзя считать пройденным. Два FAIL относятся к одному дефекту selection.

Подтверждённые дефекты: **P0: 0 / P1: 2 / P2: 4 / P3: 1**. Отдельно 8 INFO/LIMITATION записей.
Самые серьёзные: валидный XLSX не импортируется; нативный QR scanner выбрасывает exception и остаётся busy.
Потеря/искажение сохранённых canonical QA операций не обнаружена. Полная безопасность банковских notification Save/ack ещё не доказана физическим E2E.
Это завершённый ограниченный аудит, **не допуск релиза по всем acceptance criteria**: непроверенные критические ветки перечислены.

Production audit: 328 baseline SHA-256 совпадают, изменений нет. Старые dirty/untracked Stage 2–5 файлы сохранены, не являются изменениями Stage 6A. Единственный файл в source roots вне hash baseline — gitignored GeneratedPluginRegistrant.java, создан 17.07, изменён 29.08, до аудита. Не удалялся и не редактировался.
См. [integrity result](stage6a-20261006/production-integrity-result.json).

## Test matrix

Номер — раздел исходного ТЗ. Evidence указывает префиксы PNG/XML в локальной папке stage6a-20261006.
Для каждого PARTIAL непроверенные подпункты не наследуют PASS от automated tests.

| ТЗ § | Проверка | Результат | Evidence / границы |
| --- | --- | --- | --- |
| 3 | Устройство / APK | PASS | environment-before; installed APK hash = Stage 5 |
| 4 | Сохранность обновлённого профиля | PARTIAL | Профиль изначально пуст по подтверждению пользователя; QA persistence проверена, прежние финансовые данные отсутствовали |
| 5 | Baseline startup / logcat | PASS | Startup logs; процесс запускается без зависшего splash |
| 6 | Force-stop / resume / recreation | PASS | 34; 288; 350–355; данные сохранены |
| 7 | Четыре корня / UI-state | PARTIAL | 01–05; 116–120; 280–305; не все filters/reselect/background сочетания |
| 8 | Независимые navigation stacks | FAIL | 117–120: detail/category сохранены, но selection Overview сброшен; A6-03 |
| 9 | Android Back | PARTIAL | IME → discard; detail → scoped list → root; пользовательский жест «вроде да»; predictive animation не подтверждена |
| 10 | Keyboard / формы / границы | PARTIAL | Реальная IME transaction/account/investment/debt/goal; нижние поля достижимы; paste/negative/huge не проверены |
| 11 | Notification permission lifecycle | PASS | 70–82: revoke/grant, статус меняется после resume без restart; granted восстановлен |
| 12 | Source attention | PARTIAL | Banner/badge ведут в источники; pending/error видны, но причина failedCount не объяснена; A6-05 |
| 13 | Incoming notification safety | PARTIAL | Реальный исходящий transfer 23 RUB просмотрен и отменён, pending сохранён; Save/ack всех типов NOT TESTED |
| 14 | Journal / search / long history | PARTIAL | 353: 4 из 4; long list/search/all filters не пройдены |
| 15 | Transaction Detail | PARTIAL | Exact expense/refund; часть source/optional/long-text сценариев не проверена |
| 16 | Transaction Edit | PARTIAL | 123.45 → 100.55; сохранение и restore; ID совпадает в 131/348; ID до первого edit и double-save не зафиксированы |
| 17 | Delete / Trash / Restore | PARTIAL | 93–98, 353: одна QA операция удалена/восстановлена и пережила restart; bulk/undo NOT TESTED |
| 18 | Scoped analytics Back contract | FAIL | 105–119: scoped route сохраняется, выбранная точка пропадает после изменения totalPlan; A6-03 |
| 19 | Manual add / cancel / persistence | PASS | 36–56; 348/353: cancel без записи, save с копейками, одна canonical operation |
| 20 | Voice | PARTIAL | 310: «кофе 100 руб», expense 100, Café, review; cancel без записи. Denial/unsupported recognizer/fractional не проверены |
| 21 | QR / чек | FAIL | 315–317: synchronous native NPE, затем stuck busy; A6-02. Recognize/preview/confirm недоступны |
| 22 | Screenshot import | PARTIAL | 321–324: DocumentsUI открылся, отмена возвращает экран; OCR/preview/confirm NOT TESTED |
| 23 | PDF / TXT statement | PARTIAL | TXT: 3 вида с копейками, повторный импорт 0 новых (337–339). PDF extraction NOT TESTED |
| 24 | Excel XLSX / XLSM | FAIL | 255, local parser diagnostic: корректный XLSX отклонён; A6-01. XLSM/large file NOT TESTED |
| 25 | Overview UX / privacy / границы | PARTIAL | Empty/50k/49,150 states; metrics/period/attention; huge/negative/privacy полный сценарий NOT TESTED |
| 26 | Expenses Analytics | PARTIAL | Category/day scoped list; total/period; полный FilterSheet/currency/merchant цикл не пройден |
| 27 | Cash Flow | PARTIAL | UI income/expenses/net; canonical expense/income/refund export. Own transfers/multi-currency не проверены на этом профиле |
| 28 | Rhythm | NOT TESTED | Нет живого device сценария календаря/зарплатного цикла |
| 29 | Upcoming / recurring | PARTIAL | Debt forecast показан отдельно; не весь manual/inferred/overdue сценарий |
| 30 | Budget landing | PARTIAL | Empty → total 50; expense exceeded; Café limit 200; long categories/large limit NOT TESTED |
| 31 | Budget editing | PARTIAL | Total/category Save; restart видит назначенный план. 0-removal/cancel/double-save не подтверждены |
| 32 | Capital landing / breakdown | FAIL | 355: total 49,150 = 50,000 + archived 150 − debt 1,000, но Investments 0 без объяснения; A6-06 |
| 33 | Liquidity / graph / scrub | NOT TESTED | Только сумма root 50,000; отдельная страница и graph touch не пройдены |
| 34 | Accounts / preferences | PARTIAL | Create/detail/unknown virtual balance; exact imported bank fraction/multicurrency/flags NOT TESTED |
| 35 | Reserve / Подушка | NOT TESTED | Не открывался редактор reserve и не менялись его настройки |
| 36 | Investments | PARTIAL | Create123 → valuation150 → contribution50 без valuation-change → archive/history; metadata edit/double-save не подтверждены |
| 37 | Whole-unit investment boundary | PARTIAL | Whole amount сохранён; nonzero-cent rejection проверен на account, не полный 123/123.00/123.45 именно investment цикл |
| 38 | Debts | PARTIAL | Create1000, rate12.5%, scenario/upcoming; payments/history/edit/archive полный цикл NOT TESTED |
| 39 | Debt-event deep link | NOT TESTED | Upcoming → конкретный Debt Detail → Back не подтверждён |
| 40 | Goals | PARTIAL | User create1000; contribution200; allocation300 → goal300, не500. Withdrawal/remove/complete/archive/restart-detail NOT TESTED |
| 41 | Whole-unit Goal / Debt boundary | NOT TESTED | Нецелые суммы именно в этих двух моделях не прогнаны; decimal interest 12.5% проверен |
| 42 | Global + | FAIL | Account/manual/imports/voice доступны; «Счёт / актив / долг» открывает только account, нет investment/debt/goal shortcut; A6-04 |
| 43 | Ещё | PARTIAL | Sources/Trash/AI/Settings visited; Benefits/History/rules лишь entry, полный flow NOT TESTED |
| 44 | AI Export | PARTIAL | Diagnostic сохранён через SAF и прочитан; Compact выбран по умолчанию, но отдельный save/share Compact не завершён |
| 45 | Settings | PARTIAL | Appearance/System/FX status; profile/avatar/currency/rules editing не пройден |
| 46 | Theme | PARTIAL | System-dark roots + Light Operations/Budget/Capital; Light Overview и explicit Dark не зафиксированы |
| 47 | System font / display size | PARTIAL | 1.3: четыре root, без явного overflow; 1.0 восстановлен. Long editor/detail/display-size не пройдены |
| 48 | TalkBack | NOT TESTED | Пользователь отказался включать; визуальная читаемость не равна TalkBack PASS |
| 49 | Rotation | NOT TESTED | user_rotation=1 не повернул окно; actual landscape не достигнут; настройки возвращены |
| 50 | Native lifecycle callbacks | PARTIAL | Settings/SAF/speech возврат и cancel; QR FAILED; late callbacks/process death внутри picker не исчерпаны |
| 51 | Performance | PARTIAL | Force-start 500/928ms, resume171ms; малый профиль. Не измерены large list/large Capital |
| 52 | Memory / health | PARTIAL | PSS253391→278083KB, RSS315951→309845KB; два несопоставимых snapshot не доказывают leak/его отсутствие |
| 53 | Network / offline | NOT TESTED | Сеть пользователя не отключалась |
| 54 | Error handling | PARTIAL | Fraction rejected; permission attention; cancelled picker; Excel generic error; QR raw NPE/busy |
| 55 | Visual audit | PARTIAL | Physical 360×780dp; dark/light/font samples; обнаружены A6-04/06/07; не все screens/themes |
| 56 | Touch audit | PARTIAL | ADB taps/chart and user Back/voice; физические edge targets/scrub systematic test не выполнены |

## Bugs

Все карточки относятся к build 1.0.67 (68), Samsung SM-S921B / Android 16. Время — Moscow.
Результаты ADB tap проверялись по settled screenshot/XML; ошибочные координаты не объявлялись багами.

### A6-01 — P1: XLSX с package-root relationship не читается

- Время: 06.10 23:39:43; экран «Excel-таблица».
- Repro: выбрать QA-ST6-import.xlsx, созданный как безопасный двухстрочный fixture; дождаться разбора.
- Expected: preview расхода 80.35 RUB и дохода 2000.25 RUB с правильными датами.
- Actual: «Не удалось прочитать Excel…». Preview/confirm недоступны; operation не создана.
- Повторяемость: device failure + тот же неизменённый production adapter в diagnostic test; независимый read-only openpyxl читает файл.
- **Confirmed first root cause**: excel_community 2.2.1 переносит Target="/xl/styles.xml" из xl/_rels/workbook.xml.rels без package URI resolution. styles_parser ищет xl//xl/styles.xml вместо xl/styles.xml. Raw exception: Damaged Excel file: styles.
- Files: lib/features/statement_import/services/universal_excel_statement_adapter.dart:49; dependency lib/src/parser/parse.dart и styles_parser.dart. Generic catch скрывает подробность от UI.
- Evidence: [255](stage6a-20261006/255-excel-preview.png), excel-fixture-local-parser.txt, xlsx-independent-read.txt, outputs/stage6a-import/QA-ST6-import.xlsx.
- Confidence: высокая для первого decode failure; совместимость всех остальных XLSX элементов после исправления НЕ доказана.
- Data risk: импорт блокируется, прежняя база не очищается; нет доказанного повреждения данных.

### A6-02 — P1: QR scanner падает до открытия и блокирует retry

- Время: 07.10 00:00:13 native error; screenshots 00:00:17 и 00:01:08.
- Repro: «+» → «Чек» → «Сканировать QR»; повторить на том же экране.
- Expected: нативный scanner либо понятная unavailable ошибка, затем возможность retry.
- Actual: raw Java NullPointerException в UI; scanner не открылся. Второй tap: «Сканер чеков уже открыт».
- Evidence: [315](stage6a-20261006/315-qr-open.png), [316](stage6a-20261006/316-qr-ready.png), [317](stage6a-20261006/317-qr-retry.png), [process log](stage6a-20261006/317-qr-process-log.txt).
- **Confirmed lifecycle cause**: MainActivity.scanReceiptQr устанавливает pendingReceiptResult до GmsBarcodeScanning.getClient/startScan; synchronous exception выходит через MethodChannel до регистрации success/cancel/failure listeners. pending не очищается, следующий вызов получает busy.
- Причина самого SDK NPE **не установлена**: стек release обфусцирован; не объявлять без расследования, что виноват Android 16, Play Services или R8.
- Files: android/app/src/main/kotlin/ru/qesto/qesto/MainActivity.kt:432; lib/features/receipt_import/presentation/receipt_import_screen.dart; receipt_scanner_service_native.dart.
- Повторяемость: первая ошибка и один retry в том же process. Независимые запуски scanner после recreation не проверены.
- Confidence: высокая для stuck-busy cause; средняя для нижележащего SDK failure.
- Data risk: чек не импортирован; app process продолжает работать, это channel exception, не доказанный process crash.

### A6-03 — P2: Overview теряет chart selection после изменения плана того же периода

- Время: 06.10 22:59:57 → 23:01:52.
- Repro: выбрать точку Overview → scoped operations → transaction; переключиться в Budget, изменить totalPlan на 50, вернуться в прежний Overview detail и Back до chart.
- Expected: period, selection, exact scope и scroll сохранены, когда диапазон периода не менялся.
- Actual: scoped route и period/scroll сохранились, chart point / selected CTA исчезли.
- Evidence: [105](stage6a-20261006/105-chart-point.png), 106/108/114/117–119, [119](stage6a-20261006/119-chart-return.png).
- **Hypothesis, high confidence**: MobileOverviewPage.didUpdateWidget сравнивает oldWidget.period != widget.period. BudgetPeriod не имеет value equality; update totalPlan заменяет его через copyWith. Смена объекта того же диапазона сбрасывает _selected.
- Files: lib/mobile/analytics/mobile_overview_page.dart:72; lib/data/models/budget_models.dart:52; lib/features/budget/state/budget_controller.dart:2174.
- Один составной device repro; не доказано, что обычный Back без изменения Budget всегда теряет selection.
- Data risk: presentation-state, не изменение ledger. Before test с двумя контрольными ветками обязателен до fix.

### A6-04 — P2: глобальный «+» обещает актив/долг, но открывает только account

- Время: 06.10 23:35–23:36, повторно menu 07.10 00:01.
- Repro: «+» → «Счёт / актив / долг».
- Expected: конкретный editor выбранного объекта или короткий submenu; investment/debt/goal доступны согласно §42.
- Actual: «Добавить счёт», без выбора investment/debt/goal. В Capital локальные create действия работают.
- Evidence: 244/248, [245](stage6a-20261006/245-excel-source.png), 312/319. Имя 245 ошибочно содержит excel: фактически это account editor.
- Confirmed root cause: DesktopAppShell _AddDataAction.account mobile branch вызывает только mobile.createAccount().
- Files: lib/desktop/desktop_app_shell.dart:570 и :779; mobile shell action adapters; существующие capital create functions.
- Data risk: отсутствует; отдельные редакторы не удалены. Не считать, что Capital CRUD сломан целиком.

### A6-05 — P2: source error не объясняет, как закончить импорт

- Время: 06.10 22:38–22:52 и после final restart 07.10 00:05.
- Repro: открыть banner «Входящих: 1 / Ошибок импорта: 1» → Sources → Incoming.
- Expected: причина actionable: требуется счёт, отказ разрешения, неподдерживаемая запись или реальная ошибка записи; понятное действие.
- Actual: generic failedCount и «Проверьте входящие уведомления», без конкретной причины/связи с pending. Permission state сам по себе обновляется корректно.
- Evidence: 60–68/75–82, 351; raw pending персонален и не публикуется.
- Confirmed design cause: AutomaticNotificationImporter.failed объединяет unresolved account confidence, channel/read/write/ack failures; MobileSourceStatusPage показывает только количество.
- Причина именно текущей записи НЕ подтверждена raw storage; предположение account confidence <0.9 не выдавать за установленный факт.
- Files: lib/features/notification_import/services/automatic_notification_importer.dart; lib/mobile/sources/mobile_source_attention_controller.dart и mobile_source_status_page.dart.
- Data risk: безопасный отказ сохраняет pending, но без понятного пути пользователь может не завершить импорт. Автоматически выбирать произвольный счёт или превращать draft в expense нельзя.

### A6-06 — P2: archived investment включён в total, но исчезает из видимого breakdown

- Время: 06.10 23:15:31; повторно 07.10 00:06:14.
- Repro: investment balance150 с includeInTotal → archive (UI подтверждает archive≠sale) → Capital root.
- Expected: из breakdown можно объяснить общий капитал, включая архивный актив, либо явно обозначена разница active portfolio / total assets.
- Actual: capital49,150, liquidity50,000, debts1,000, Investments0; необъяснённые 150 RUB.
- Evidence: 179/182/183/[188](stage6a-20261006/188-capital-low.png); [355](stage6a-20261006/355-final-capital-ready.png); 348 export brokerage150.
- Confirmed cause: root total использует canonical financialState, а investment row — InvestmentAnalyticsService с filter isActive && includeInTotal. Archive не обнуляет canonical balance.
- Files: lib/mobile/capital/mobile_capital_pages.dart; mobile_capital_common.dart; InvestmentAnalyticsService.calculate; BudgetController._upsertCanonicalInvestmentAccount.
- Data risk: сохранённый balance корректен; defect — объяснение total. Нельзя «чинить» продажей/обнулением или исключением актива из ядра.

### A6-07 — P3: validation error выглядит как ошибка сохранения

- Время: 06.10 22:31–22:33; account editor, сумма 50000.45.
- Expected: ясное объяснение whole-unit boundary, исправить сумму и обычный Save.
- Actual: длинный field error обрезан; ниже повторён полный текст; кнопка «Повторить сохранение» даже при local validation, до repository write.
- Evidence: [29](stage6a-20261006/29-account-cents-validation.png), 30–33.
- Confirmed cause: MobileCapitalEditor._error используется для validation и persistence error; label выбирается лишь по _error != null; штатная single-line field error.
- Files: lib/mobile/capital/mobile_capital_editor.dart:177, :385–404.
- Data risk: fractional input явно отклонён, не округлён и не сохранён. Whole-unit boundary остаётся LIMITATION, не финансовый баг.

## UX observations

Четыре корневые вкладки доступны на реальном экране; полный mobile editor заменяет desktop overlay. Реальная IME не перекрыла sticky transaction Save. Для длинных capital forms требовался scroll по краю; нельзя считать промах координат дефектом touch targets.
Глобальный add sheet длинный, последний пункт виден частично; scroll доступен. Главная actionable проблема этого пункта — A6-04, не сам факт scroll.
Dark/System и выбранные Light screens читаемы на зафиксированных renders; этот вывод не распространяется на все темы/шкалы.
Числовые hero/rows могут показывать whole RUB, тогда как detail/export сохраняют копейки. Это не доказательство потери денег.

## Performance

- Force-stop recreation: наблюдалось завершение старого PID и новый process. am start -W назвал запуск WARM: TotalTime500ms / Wait503ms; финально928/946ms. Не приписывать ему framework COLD timing.
- Resume: WARM171/175ms.
- dumpsys gfxinfo: 2086 frames, 132 janky (6.33%); p50 5ms, p90 9ms, p95 13ms, p99 42ms. Android view statistics не полный Flutter frame trace; учитывают весь сеанс, не конкретный flow.
- PSS253391→278083KB; RSS315951→309845KB. Это не сопоставимый нагрузочный цикл, leak не установлен.
- Observed process crash/ANR в проверенном сеансе не найден. QR MethodChannel NPE зафиксирован отдельно.
- LOW_MEMORY exits от 05.10 предшествуют аудиту; текущие force stops выполнены тестом.
- Малый ledger 4 записи не является large-list performance verification.

## Accessibility

Font scale1.3 протестирован на четырёх roots; полного long-editor/detail теста нет.
Пользователь подтвердил визуальную читаемость и отказался включать TalkBack. **TalkBack NOT TESTED**, accessibility acceptance не закрыт.
ADB Back работает в пройденных сценариях; пользовательский gesture «вроде да» — PARTIAL. Predictive Back animation не подтверждена.
Rotation setting не повернул окно; landscape не получен, это NOT TESTED, а не PASS или доказанный orientation bug.

## Native flows

Notification listener был granted → revoked → granted через native Settings; root attention обновился на resume. Существующий pending не удалялся.
Speech permission UI появился, пользователь разрешил микрофон; recognizer вернул controlled «кофе 100 руб», review открыт, затем cancel. Отдельный permission-denied flow не выполнен. RECORD_AUDIO возвращён к baseline denied перед final restart.
DocumentsUI: XLSX failure; TXT import+repeat; screenshot picker cancel; JSON save. Это не подтверждает PDF/OCR/QR successful extraction.
Final state: font_scale1.0, accelerometer_rotation0, user_rotation0, screen_off_timeout30000; appearance System; notification listener granted; microphone denied. Ничьи системные разрешения вне Qesto не менялись.

## Data safety

Штатные UI-only QA данные оставлены для воспроизведения; прямых DB writes, сброса, очистки, uninstall/migration не было.

| QA сущность | Итог |
| --- | --- |
| Account | QA-ST6-Account, RUB50000.00; canonical latestStoredBalance=50000.00 |
| Manual expense | QA-ST6-Expense100.55 RUB, expense/outflow/externalOutflow |
| TXT expense |84.99 RUB, expense/outflow/externalOutflow |
| TXT income |500.25 RUB, income/inflow/externalInflow |
| TXT refund |40.15 RUB, refund/inflow/refund |
| Investment | QA-ST6-Investment150 RUB, archived; contribution50 без дополнительного valuation |
| Debt | QA-ST6-Debt1000 RUB; annual rate12.5%; payment100/day10 |
| Goal | QA-ST6-Goal1000 RUB target; contribution200; allocation300; projection300, не500 |
| Budget | Total50 RUB; Café category200 RUB |

[348 diagnostic export](stage6a-20261006/348-final-export.json): четыре уникальных canonical IDs и указанные amount.value/type/direction/treatment; один resolved QA account. Manual ID совпадает с 131 после restore/repeat. Export v2 использует money.value string, не поле exactAmountMinor на верхнем уровне.
После TXT repeat — 0 новых; account остаётся50000.00; forecast/contribution/allocation не создали bank operations.
После final restart journal4/4 и capital49,150, назначенный budget видны. Goal detail после этого restart отдельно не открыт, его restart coverage PARTIAL.
Точный денежный поток этих четырёх записей: 500.25 −100.55 −84.99 +40.15 =354.86 RUB. UI whole-unit355; legacy per-row rounding не равно canonical corruption.
Устройство было пустым до QA по подтверждению пользователя; сохранность pre-existing финансового ledger при upgrade нельзя доказать пустым исходным профилем.
Реальный pending notification только preview/cancel. Возможные риски income/refund/transfer Save→ack требуют следующего физического safety E2E; TXT не подменяет этот тест.
Evidence/export содержат стабильные pseudonymous IDs, некоторые screenshots — personal notifications/файлы picker. **Не публиковать эту папку автоматически в Git/PR.**

## Automated checks

- flutter analyze --no-pub: No issues found,112.0s.
- Full unchanged Flutter suite: **904 passed /12 skipped /2 failed**,2:14.
- Failures: cef_browser_lifecycle_test fast completion — teardown temporary-directory errno32 lock; bank_sync_ui_test status/toggle — pumpAndSettle timeout.
- Sequential retry этих двух файлов: **7 passed /0 failed**.
- Это flaky/harness observation, а не зелёный исходный full run и не два доказанных device bugs. Прежний Stage5 отчёт906/12/0 не заменяет текущий результат.
- Diagnostic Excel reproduction test намеренно падает на обнаруженном A6-01; не включён в production suite.
- Запускались текущие tests без изменения исходников/versions/dependencies. Windows desktop smoke руками в этой Android-only задаче не делался; существующие desktop regression tests вошли в suite.
- Logs: analyze-direct-after.txt, flutter-test-direct-after.txt, two-failures-retry.txt, excel-fixture-local-parser.txt.

## Known limitations / INFO (8)

1. Whole-major-unit investment/debt/goal/manual-capital CRUD; cents rejection сохраняется; fractional interest разрешён.
2. Debt recorded-payment CRUD не входит в текущий UI; forecast не факт транзакции.
3. Currency consolidation boundary существующего ядра; multi-currency acceptance не проверен.
4. AI assistant placeholder; JSON export работает отдельно.
5. Receipt OCR — QR-first enrichment, не arbitrary photo importer. Это НЕ объясняет A6-02.
6. Rounded whole-RUB summary rows/legacy analytical projection при точных detail/export; нового round-loss canonical defect не найдено.
7. Два flaky Windows test failures с успешным retry; root cause test flakiness требует отдельного расследования, не auto-fix.
8. Debug signing тестового APK; production distribution signing вне scope, ключи не менялись.

## Evidence index

[Private evidence folder](stage6a-20261006/): numbered PNG/XML + logs; snapshot names не являются истиной сами по себе.
Опорные наборы: 01–05 roots;12–16 IME/discard;27–33 boundary;34 restart;36–56 manual;65–82 pending/permissions;85–98 edit/trash;105–124 scopes/budget;126–131 first export;149–188 investment;189–209 debt;225–243 goal;249–255 Excel;259–277 TXT;280–305 font/themes;310 voice;315–317 QR;322–324 screenshot cancel;337–339 repeat;348 export;350–355 restart.
131/348 exports redacted через штатные privacy options, но не public fixtures.
production-hashes-before/after.json + production-integrity-result.json — baseline integrity.
before/after memory, frames, exit-info;349-final-process-log и356-post-restart-process-log.
Ошибочно названные/невалидные captures исключены: 00/71/226/293 lock;137–139 external app;170/180 contribution editor;202 balance history, не payments;245/246 account editor, не Excel;276/277 refund, не income;289 portrait, не landscape;302 неуспешный label lookup.
Репорт не заявляет PASS на основании имени capture или одного semantics tree.

## Next step / STOP

Подготовлено отдельное [Stage6B remediation specification](mobile-stage6b-remediation-spec-2026-10-06.md).
Stage6B, новый APK, installation, Git/PR не выполнялись. Нужна отдельная команда на согласованный slice.
