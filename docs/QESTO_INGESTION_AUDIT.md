# QESTO — аудит получения финансовых данных и Synoball

Baseline: 2026-09-05; финальная проверка: 2026-09-06. Режим: repository audit, без изменения приложения и пользовательских данных.

## A. Executive assessment

**Synoball — реальное общее ядро, но пока не единая система гарантий финансовой целостности.** Все найденные подключённые способы создания операций доходят до `SynoballCore`. Это хорошая основа; переписывать приложение, менять стек или вводить серверный ledger не требуется. Однако одинаковый конечный класс не означает одинаковые правила идентичности, обновления и учёта.

Фактически Synoball — синхронный in-memory Dart engine: адаптер → ingestion/candidate → deduplicator → canonical operation/evidence → enrichment/read models. Сохраняет весь граф не ядро, а `BudgetController` через локальный repository. Между ними остаются преобразования через прежнюю модель `BudgetTransaction`, специальные исправления Сбера и отдельная логика Cash Flow.

Главные выводы:

1. Разные покупки могут ошибочно объединиться: несовпадение известных счетов не запрещает fuzzy match; сильный provider ID не ограничен подключением/банком/счётом; равные кандидаты не отправляются на разбор. **F01**.
2. Некоторые источники путают идентичность доставки, строки и операции: координаты Excel, Android notification key и меняющийся fingerprint Сбера имеют разные ограничения. Скриншот может потерять две одинаковые строки ещё до Synoball. **F02**.
3. Ядро хранит копейки, UI-модель — целые денежные единицы. Повторный импорт или редактирование через эту модель может уже необратимо округлить canonical amount. Web extraction округляет раньше. **F03**.
4. Ручная категория в конкретном Sber refresh защищена и проверяется тестом, но универсальной защиты пользовательских полей нет. Повторная выписка проходит через полную запись и помечает автоматические значения как user-confirmed. **F04**.
5. Частичная история распознаётся коннектором, но новый sync wrapper превращает её в success. Пользовательский баланс и полнота денежного потока — разные факты; текущий остаток не доказывает, что все операции извлечены. **F08**.
6. Шифрование и последовательная запись уже есть, однако не установлены crash-safe commit, атомарность с checkpoint и остановка поздних writes после timeout/delete. Ошибка декодирования финансовой модели местами маскируется пустым профилем. **F07, F09**.
7. В Android voice UI подтверждение не доходит до `confirmCandidate`: сохраняется pending candidate, а интерфейс сообщает «Операция добавлена». Desktop voice использует отдельную корректную цепочку подтверждения. **F13**, статически подтверждено; на устройстве не воспроизводилось.

**Ответ на центральный вопрос:** одна установленная покупка из уведомления, SMS, чека, сайта и выписки *может* стать одной операцией, но такая гарантия для всех порядков, счетов и повторов **не подтверждена и по нескольким веткам нарушается**. Две похожие самостоятельные покупки тоже сохраняются не во всех ветках. Нельзя считать задачу решённой только потому, что все источники вызывают `ingest`.

Проверки: **324 passed, 7 skipped**, `flutter analyze --no-pub` — **No issues found**. Это unit/widget проверки и отдельные fixture flows, не live-bank или Android end-to-end certification. Новые тесты в рамках аудита не добавлялись.

Первый рекомендуемый пакет: зафиксировать безопасные границы matching (**F01**) и убрать разрушительную запись округлённой проекции/автоматических данных поверх пользовательских полей (**F03–F04**). До расширения автоматики также необходимы **F07–F09**. Сохранить существующие парсеры, CEF и ядро; исправлять конкретные контракты.

## B. Baseline, документы и границы покрытия

### B1. Snapshot

| Параметр | Значение |
|---|---|
| Repository | `C:\Users\ARM\Documents\Qesto` |
| Branch | `codex/sber-browser-sync` |
| HEAD | `5b4ac1829e215d15c57031b0a117e2ed3e673921` |
| HEAD subject | `feat: build capital investments goals and debt planning` |
| Исследованный код | HEAD **плюс существующий dirty working tree**, включая новую фоновую синхронизацию |
| App | `apps/qesto_app`, Flutter `3.44.6`, Dart `3.12.2`; `pubspec.yaml`: `1.0.36+37` |
| Persisted codec | `UserFinancialDataCodec.schemaVersion = 6`; историческое имя ключа `qesto.user-financial-data.v1` не является номером текущей схемы |
| Проверяющий host | Windows / PowerShell; физический Android и live CEF в аудит не запускались |

До аудита уже были изменены 12 tracked файлов: shell приложения/desktop, bank connections UI, registry, browser profiles/models/controller, Sber auth/models, vendored CEF Dart wrapper, pubspec, profile tests. Также уже существовали untracked `domain/bank_sync_models.dart`, `sync/`, два sync test файла и корневой `tmp/`. Эти изменения сохранены. Ссылки на строки ниже относятся именно к этому working-tree snapshot, не только к HEAD.

Проверка `git status --short` после тестов сохранила исходный список изменений. Аудит добавляет только два документа в `docs/`. Flutter мог обновить ignored `.dart_tool`, `build` и собственный SDK cache; их побайтовый baseline не снимался. Исходники, тесты, зависимости и конфигурация не редактировались, `pub get`, upgrade, сборка/установка EXE и Git push не выполнялись.

### B2. Инструкции и источники

- Полностью исследовано приложенное ТЗ аудита `d696384a-…/pasted-text.txt`.
- `AGENTS.md` не найден в корне, проверенных родительских каталогах и поиске repo-owned файлов, исключая временные/сборочные/vendor деревья.
- **MASTER CHECKLIST и QESTO AI Development Protocol не найдены** по именам и содержимому доступных проектных документов. Их правила/идентификаторы не выдумывались. Mapping этапов ниже относится только к приоритетам, перечисленным в ТЗ аудита.
- Найдены README, SECURITY, CHANGELOG и `docs/{DESKTOP_AUDIT,DESKTOP_IMPLEMENTATION,QESTO_ANALYTICS_MIGRATION,SECURITY_IMPLEMENTATION_RU,SYNOBALL_ARCHITECTURE,SYNOBALL_CORE_WALKTHROUGH_RU,SYNOBALL_LEGACY_AUDIT}.md`. Старые Synoball architecture/legacy описания использованы как указатели intent; текущая реализация подтверждалась кодом. Например, утверждения старых документов о legacy storage/будущем voice нельзя переносить на нынешний snapshot.
- Предыдущая переписка — контекст проблем, не доказательство исправления или поломки. Реальные выписки, Excel пользователя, PIN, банковский профиль, store.json, HTML авторизованного банка и DEV endpoint в этом аудите не открывались.

### B3. Метод и уровень доказательств

Выполнены два независимых поиска: (A) UI/native/background входы → запись; (B) constructors и изменения canonical/DTO, `ingest/update/delete/restore`, storage writes → callers. Области: `apps/qesto_app/lib`, Android Kotlin/manifest, Windows host/bridges, vendored CEF boundary, `test`, `web` собственные файлы, `services`, `.github/workflows`, `docs`. Полный аудит Chromium/PDF.js/Tesseract/Whisper и платформенных SDK не проводился.

Обозначения: **S** — подтверждено статическим анализом; **E** — исполнен конкретный существующий тест; **R** — обоснованный риск, требующий воспроизведения; **U** — не проверено; **NF** — не найдено в указанном охвате; **N/A** — неприменимо. Приоритет finding не является степенью доказанности.

Первый запуск Flutter в sandbox не выдал тестового результата и был остановлен; read-only диагностика процессов через CIM получила access denied. Повторный запуск с разрешённым расширением доступа к локальному SDK выполнил тесты. Это ограничение окружения, не assertion failure. Сетевые банковские действия не запускались. Flutter показал собственное уведомление о новой версии; SDK не обновлялся.

## C. CURRENT STATE: входы, writers и consumers

### C1. Фактическая схема

```text
Android NotificationListener → encrypted NotificationInbox → Dart importer ┐
Android on-device speech / Windows Whisper → draft + confirmation          │
Receipt QR / local OCR → receipt preview + optional explicit link          │
Bank screenshot local OCR → Sber/generic parser → editable batch           ├→ BudgetController
PDF/TXT Sber / XLSX,XLSM → parser → selected rows                           │   → source adapter
CEF Sber → auth → dashboard → accounts → history → snapshot                │   → SynoballCore.ingest
Manual form → user command                                                ┘     → candidate/match/canonical/evidence
                                                                                 ↓
                                   QestoReadModelService → Sber compatibility → BudgetTransaction
                                                                                 ↓
                 UI / budget / overview / statistics / cashflow / capital ← controller
                                                                                 ↓
                mergeInto → UserFinancialDataCodec → encrypted repository → local snapshot

Отдельно: native inbox; CEF profile/cookies; profile.json + sync metadata; secret vault.
```

Переходы не являются одной транзакцией хранения. Constructor `BudgetTransaction` в preview не равен сохранению операции. `SynoballApiV1` — локальный read facade, не HTTP-сервис и не дополнительный writer (`lib/synoball/api/v1/synoball_api_v1.dart:7`).

Во всех путях ниже префикс `A/` означает **`apps/qesto_app/`**, `L/` — **`apps/qesto_app/lib/`**, `T/` — **`apps/qesto_app/test/`**. Это сокращения существующих repository-relative путей, не предполагаемые будущие модули.

### C2. Реестр писателей — сверка обоих проходов

| Path | Trigger / достижимость | Execution path и запись | Особые гарантии/отклонения; evidence |
|---|---|---|---|
| W01 | Android/desktop ручная форма, connected | `add_expense_screen` / desktop add → `BudgetController.addExpense` → ManualInputAdapter → ingest → canonical insert → общий snapshot | UI validation; новый microsecond ID на команду; fuzzy отключён для incoming manual. `L/features/budget/state/budget_controller.dart:1193` |
| W02 | Android voice, connected, но posting после UI-confirm сломан | `budget_screen` → AndroidVoiceSpeechRecognizer → VoiceTransactionParser → confirmation sheet → `addImportedTransactions(confirmedVoiceInput: true)` → VoiceInputAdapter → **pending candidate** → snapshot | `confirmCandidate` здесь не вызывается; `confirmedInPreview` остаётся raw metadata. UI закрывает sheet с успехом. `L/features/voice_transaction/presentation/voice_transaction_confirmation_sheet.dart:135–166`, controller:590–641; **F13** |
| W03 | Windows voice / текстовая фраза desktop, connected | `_openVoiceInput` → VoiceCaptureService/VoiceTransactionDraftParser → `addVoiceCandidate` → persisted pending → `confirmVoiceCandidate` → canonical | Pending хранится отдельно от операции. `L/desktop/desktop_app_shell.dart:390`, controller:1481–1520 |
| W04 | Receipt QR/photo/manual QR, Android/Windows варианты | ReceiptImportScreen → scanner/parser → user preview/link → `ingestReceiptTransaction` / `_ingestReceipt` → ReceiptAdapter → snapshot | Явно выбранная операция передаёт canonicalId; полная сумма берётся из receipt.totalMinor. Matcher UI — лишь предложения, но первое предварительно выбрано. `L/features/receipt_import/presentation/receipt_import_screen.dart:239`, controller:2586 |
| W05 | Android notification, пассивно при живом Dart app; иначе отложенная очередь | native listener/inbox → method/event channels → AutomaticNotificationImporter.drain → parser/account resolver → `addNotificationTransaction` → AndroidNotificationAdapter → save → native ack | Auto-confirm; один active drain; неизвестный счёт оставляет inbox item. `L/features/notification_import/services/automatic_notification_importer.dart:50,92,125,147`, controller:1279 |
| W06 | Банковское SMS в notification app, тот же transport | W05, но SmsNotificationAdapter | **Не** READ_SMS, broadcast SMS_RECEIVED или inbox telephony API. `A/android/app/src/main/kotlin/ru/qesto/qesto/BankNotificationListener.kt:16,86`, controller:1324 |
| W07 | Импорт нескольких bank screenshots, Android/Windows | scanner → BankScreenshotImportService → Sber/generic parser → edited selected candidates → `importBankScreenshotCandidates` → BankScreenshotAdapter → snapshot | Удаление дублей до ядра по candidate.id; сохраняются hashes, не изображение. `L/features/bank_screenshot_import/services/bank_screenshot_import_service.dart:15`, controller:1364 |
| W08 | PDF/TXT Sber / Excel UI, connected | StatementImportScreen → file extraction → SberbankStatementParser / UniversalExcelStatementAdapter → preview → `importStatement` → StatementAdapter → ingest → **matched refresh через updateTransaction** → snapshot | Создаются счета/периоды; точные суммы передаются отдельно, но refresh снова использует DTO. `L/features/statement_import/presentation/statement_import_screen.dart:69,157,268`, controller:656–779 |
| W09 | Sber manual sync desktop, connected | bank connections UI → SberConnector.sync → extractors → `importSberSnapshot` → `importStatement(bankWebSource:true)` → BankWebAdapter → snapshot; затем profile metadata | Account reconciliation, compatibility migration и категория — вне deduplicator. `L/desktop/pages/desktop_bank_connections_page.dart:1058`, controller:786–1077 |
| W10 | Sber background, existing dirty implementation | shell → BankSyncScheduler → BankSyncManager → SberBackgroundSyncRunner → тот же W09 import → profile checkpoint | Release desktop или `--qesto-bank-background-sync`; opt-in profile, same app process. Background auth **allowStoredPin:false**. `L/app/qesto_app_shell.dart:71–113`, `L/features/bank_browser/sync/sber_background_sync_runner.dart:43–102` |
| W11 | Редактирование / bulk category / confirm в UI и statistics | `updateTransaction(s)` → legacy bridge → core.updateTransaction → snapshot | Не raw SQL bypass; обходит source merge policy и выполняет full-object write. `L/features/budget/state/budget_controller.dart:1569–1615`; UI callers в `features/statistics/presentation/screens/statistics_auxiliary_screens.dart:515–527` |
| W12 | Удалить / undo | controller.deleteTransaction → soft delete; undoAction → delete created IDs / restore prior DTO / restore accounts → snapshot | Evidence сохраняется; restore делает posted; reimport не имеет единой tombstone policy. controller:1523,1730; `L/synoball/core/synoball_core.dart:352–388` |
| W13 | Startup legacy migration, connected при отсутствии synoballState | codec → controller constructor → QestoLegacyBridge.buildInput → LegacyQestoAdapter → core; ближайшее save сохраняет новый graph | При наличии Synoball legacy transactions не импортируются повторно. controller:100–108; `L/synoball/adapters/qesto_legacy_bridge.dart:12` |
| W14 | Delete all, connected UI | `clearAllFinancialData` сбрасывает controller → onChanged; loader `_deleteAllData` удаляет financial key и notification inbox → reload | Browser profiles/credentials/scheduler — отдельные ресурсы, не единая wipe transaction. controller:1739; `L/app/qesto_app.dart:127`; F09 |
| W15 | Счета / capital links / balance snapshots / goals/debt/investment | controller.upsertAccount, mergeAccountInto, plan/product lists → mergeInto → repository | Это writers связанных сущностей, не hidden transaction ingestion. `controller:1691`, `core:258,274`; goal/investment/debt collections не становятся canonical Transaction автоматически |
| W16 | Fixture/mock Open Banking | CbrOpenFinanceFixtureParser → CbrOpenFinanceAdapter; test-only calls | В app wiring ingest caller не найден. DenyAllExternalIoGuard, disabled runtime; не live bank API. `L/synoball/open_banking/core/runtime.dart:3`, `providers/disabled_provider.dart:7`, `T/synoball_core_test.dart:612` |

Общее хранилище W01–W15: `L/features/budget/state/budget_controller.dart:401–445` → `L/app/qesto_app_shell.dart:126` → `L/data/repositories/local_qesto_repository.dart:55` → encrypted key-value snapshot. `CanonicalTransaction` создаётся в core:405, восстанавливается через model/codec; прямой production SQL writer финансовых транзакций не найден.

Дополнительные найденные конструкции: `SynoballApiV1` только читает; seed/demo fixtures в тестах не являются production source. Бюджетные категории из `mocks/fixtures/budget_categories.dart` реально используются как справочник, не как подставная история операций. Python `services/deals_ingestion` пишет SQLite offers/raw messages — это публичные предложения, не финансовые операции. Найденный `email.message` относится к HTTP tests, не к импорту писем.

### C3. Source × bank × format × platform

Здесь **connected** означает достижимый путь, не production-ready. Общий контракт для всех connected источников **частично обеспечен**: ограничения конкретизированы F01–F13.

| Источник / вариант | Implementation | Integration | Verification в этом аудите |
|---|---|---|---|
| Manual Android/Windows | connected | W01, общие create/save; command retry gap | E: widget flows + core; native release storage U |
| Voice Android | connected при поддержке on-device speech; posting defective | W02; UI подтверждает, core остаётся pending, F13 | E: parser/widget success message; canonical effect после Android save не проверен тестом, дефект S; native U |
| Voice Windows | connected, требует bundled Whisper runtime/model | W03; pending/confirm | E: draft/core; native Whisper test skipped |
| Receipt Android QR, photo, manual QR | connected | W04; item metadata и явная link; F01/F03/F10 | E: QR/OCR text/parser/widget; камера/native OCR U |
| Receipt Windows photo/manual QR | connected; camera QR unsupported явно | W04 | E: manual QR; native OCR skipped |
| Bank screenshot Sber Android/Windows | connected | W07; баланс иногда используется для inferred amount | E: synthetic OCR lines + controller/widget; native OCR skipped |
| Bank screenshot прочие банки | partial/generic, не отдельные банковские contracts | W07; F02/F11 | E: generic text fixture; bank-specific runtime U |
| Notifications Sber | connected на Android | W05 | E: parser/controller/mocked channel, не Kotlin listener E2E |
| Notifications T-Bank/Alfa/VTB | partial generic rules; packages allowlisted | W05, нет отдельных покрытых банковских grammar profiles | S; наличие package не подтверждает полноту форматов |
| SMS Sber/другие финансовые тексты через supported messaging packages | connected/partial recognition | W06; SMS origin не эквивалентен bank API identity | E: SMS fixture + core kind; direct SMS transport NF |
| Sber PDF/TXT | connected Android/Windows; text PDF | W08; два parser layout варианта; OCR image-only PDF не найден | E: synthetic text/UI; native PDF skipped |
| XLSX/XLSM, ledger и агрегированные бюджеты | connected Android/Windows; макросы не исполняются | W08; координаты/aggregate semantics F02/F11 | E: generated workbooks/security limits; 3 private-corpus tests skipped |
| Старый XLS / CSV как отдельный statement importer | NF в picker/parser paths | N/A | Не заявлять поддержку на основании слова «универсальный» |
| Web browser build PDF | connected JS bridge PDF.js → W08 | partial, отдельный storage runtime | S; `A/web/pdf_statement_reader.js:137`, native Excel intentionally unsupported |
| Sber CEF manual Windows | connected | W09; extraction + partial report + canonical import | E: row normalization, fake-browser pagination, controller; live bank U |
| Sber CEF background Windows | connected, experimental dirty implementation | W10; F08/F09/F12 | E: fake scheduler/runner + UI; hidden live runtime U |
| CEF другие банки | absent в registry | N/A | S: registry содержит только sber |
| macOS/Linux/iOS | отдельные app directories/desktop guards не доказывают ingestion support | неизвестно/partial; Windows/Android native bridges не переносимы автоматически | native builds/runtime not run |
| Email | absent в исследованных app/native/services ingestion entry points | N/A, будущий источник | NF; не дефект текущего roadmap |
| Open Banking ЦБ / direct bank API | disabled scaffold + in-memory fake | W16; не live | E: contract/security mock tests; внешние вызовы запрещены кодом |

## D. Модель, поля и инварианты

### D1. Источник истины и cardinality

Persisted `UserFinancialData` содержит и `synoballState`, и Qesto projections/планы/actions. При наличии Synoball controller строит список из него; это не две независимые активные базы транзакций. Но обратная запись projection → canonical делает её потенциально разрушительным writer, F03/F04.

Реальные связи: `RawPayload ← IngestionRecord ← TransactionCandidate`; `SourceEvidence → IngestionRecord` и `SourceEvidence → CanonicalTransaction`; `CanonicalTransaction.receiptId → SynoballReceipt → ReceiptItem[]`. Ingestion хранит adapterId/version и optional connection/institution/batch. Candidate после обработки получает status, **но не resolved canonical ID**; SourceEvidence не содержит candidate ID (`models.dart:466,794`). У повторного observation с тем же provider ID старый evidence не ссылается на новый ingestion. Audit/event entries не являются полной историей полей.

Cardinality: batch 1:N candidates; canonical 1:N evidence; canonical 0:1 прямой receiptId, receipt 1:N items. Несколько оплат одного чека, parent/children split и парные стороны transfer отдельными связями в canonical model не найдены. Поэтому строки товаров не считаются операциями — верно; доказать несколько оплат/распределение чека имеющейся связью нельзя.

`SynoballAccount.balance` — сохранённое наблюдение/ручное значение, не автоматически поддерживаемый ledger balance после каждого add/delete transaction. Account balance не пересчитывается core.ingest. Производные Capital тренды пытаются реконструировать историю из snapshot и flows; это не независимая сверка банка.

### D2. Полевая матрица

Общие свойства `L/synoball/core/models.dart:88–114,618–731`: integer minorUnits, direction отдельно; сериализация decimal string с **двумя** знаками; currency string; один occurredAt; createdAt/updatedAt; одно fieldTrust; userCategoryOverride; tags. Нет отдельного postingAt, timezone ID, field revision/CAS, original currency/exchange rate, связи transfer/refund parent. Money.fromJson обрезает лишние fractional digits, не проверяет ISO/exponent.

| Источник | Amount/currency | Время | Merchant/category/type | Account/identity | Raw/provenance |
|---|---|---|---|---|---|
| Manual | UI integer major → ×100; currency периода | Выбор даты/local DateTime | Пользователь; expense; category seed не всегда помечен manual override | Выбранный account; microsecond command ID | JSON введённых полей |
| Voice | Windows minor в seed; Android путь через BudgetTransaction | Extracted/inferred date; нет явного precision contract | Regex draft + user confirmation, modelInference до confirm | Выбранный/default UI account; candidate/new command IDs | Transcript/corrections, не audio |
| Notification/SMS | Parser decimal → minor, explicit RUB/USD/EUR variants | `postedAt` уведомления, не обязательно время банковской операции | Financial verbs/amount guard; category rules, source flag | Resolver по suffix/bank/числу счетов; Android key | Полный notification text сохраняется в encrypted core |
| Receipt | QR fiscal amountMinor; точный total в core | Fiscal timestamp; local calendar | QR kind refund/expense; merchant OCR/manual; items | Fiscal tuple, optional explicit canonical link | QR + OCR text + items; 1 прямой receipt link |
| Screenshot | OCR minor; Sber может вывести amount из соседних balances | Header date либо capture date; `dateOnly`; возможна неизвестная дата, превращённая в today | Sber/generic rules; preview editable | Content hash ID, optional accountHint; selected account | Raw text не сохраняется; imageHashes/parserIds и candidates остаются |
| Sber PDF | Signed minor и balanceMinor; currency default RUB | operationDate + processingDate в DTO, **processingDate теряется** при seed mapping | Two-layout parser + classifier | Date/auth-code ID, last-four account | Extracted PDF text, не оригинальные PDF bytes |
| Excel | Double cell → round minor; currency normalization; `balanceMinor:0` | Excel/date/month/year inference; _draft обнуляет время; override года в preview | Ledger или aggregate row; savings/investment отдельные kinds | Filename/sheet/row/column ID; account per filename | Metadata filename для binary Excel, не workbook; F10 |
| Bank web | `num.round()`/money parser → **целый major** до Synoball | DOM dateIso/local text; one time | DOM merchant/type/status; Спасибо отдельно; compatibility classifier | Content fingerprint, account suffix/name; profile identity не передана ingest | Persisted raw — source/time/list IDs, не extracted rows; F10 |
| Open Banking fake | Money mapping + DTO API fields | Поля API в scaffold | Mock contracts | Institution/connection/consent предусмотрены | Fixture; неприменимо как подтверждение live ingestion |

Основные поля/потери подтверждают `controller:1279–1437,2532–2610`, `qesto_legacy_bridge.dart:141–190`, `qesto_read_model.dart:56–101`, `statement_import_screen.dart:169–277`, `universal_excel_statement_adapter.dart:1054–1122`, `sber_extractors.dart:342–436`.

Nullable поля в canonical.copyWith используют `value ?? old` (models:678–730): нельзя выразить намеренное очищение категории override, merchant, transferDirection или receiptId обычным null. Специальный clear есть только для recurringStreamId. Пустая строка, null, неизвестность и удаление поля не имеют общего patch-контракта.

### D3. Scope идентичности

| Идентификатор | Реальный scope / ограничение |
|---|---|
| entityId | Fuzzy/exact canonical/provider matching сначала ограничен active entity; UI сейчас локальный пользователь. Это не проверка ownership перед любой записью |
| canonicalId | Сильный match внутри entity; validation account/amount/type для этой ветки отсутствует |
| providerTransactionId | Сильный match по sourceType + ID + active entity; institution/connection/account не участвуют |
| hasTransactionOrProviderId | Глобальный Set provider strings внутри core, без entity/source scope; содержит evidence удалённых операций |
| delivery / ingestion / candidate IDs | Новые time/counter IDs при каждом вызове; это не стабильные delivery idempotency keys |
| Android notificationKey | `sbn.key`, может обновляться и повторно использоваться. Inbox заменяет прежнюю версию с тем же ключом |
| PDF row ID | `sber-$dateKey-${authorizationCode}`; проверить уникальность auth code между счетами/днями, connection не входит |
| Excel row ID | hash filename/sheet/row/column; тот же filename+cell в другом содержимом = тот же ID; rename = новый ID |
| Sber web ID | hash sourceId/date/amount/text/observationKey; sourceId не используется как самостоятельный стабильный provider identity |
| Screenshot ID | Sber hash date/kind/amount/merchant/balance/suffix; generic hash date/kind/amount/merchant, **без currency/account/occurrence** |
| Fiscal receipt | tuple fn/document/sign; отделён от доставки QR; не моделирует несколько платежей |

### D4. Инварианты и реальное обеспечение

| Инвариант | Где обеспечивается | Ограничение/результат |
|---|---|---|
| Две самостоятельные покупки сохраняются | same-source fuzzy запрет; tests N+N и N+2D | F01/F02: cross-source ambiguity и pre-core collapse |
| Один факт из разных источников даёт один эффект | TransactionDeduplicator + evidence | Проверен частный N→D→R; не все пары/порядки, F01/F02 |
| Валюта/знак/точность корректны | seed absolute minor; direction; adapter validate | F03; сильный ID обходит monetary compatibility; F11 |
| User edits не уничтожаются | userCategoryOverride + Sber manual tag | Частичная защита, F04 |
| Posted не downgrade поздним pending | Нет monotonic guard; source trust отдельно от status | F05 |
| Возврат/fee не дубль покупки | direction gate в fuzzy, refund tags | Нет refund-parent/fee relation; сильный ID может обойти direction, F01/F05 |
| Own transfer не доход/расход | cash-flow internal tag / savingsTransfer exclusion | Нет linked legs; bank parsing ownership эвристический; F06/F11 |
| Invalid/unknown не становятся фактами | UI/parser checks, adapter.validate | Проверяет не всё, unknown account может стать first account; F06/F11 |
| Save перед ack | AutomaticNotificationImporter await controller, затем native remove | Верно по wiring, но crash/failed outcome gaps F07; test не исполняет диск |
| Данные отражаются в UI | _syncFromSynoball + notifyListeners | Уведомление UI до сохранения; округлённые и compatibility projections, F03/F05/F07 |
| Delete не случайно возрождает историю | soft tombstone / global provider guard | Правило неодинаково по source, F02/F09; продуктовая политика D02 |
| Баланс сверяется с потоком | Отдельные snapshots и summaries | Полная сверка opening→closing с coverage не реализована; баланс ≠ net flow |

## E. Matching, порядок и надёжность

### E1. Реальный алгоритм

`L/synoball/reconciliation/deduplication.dart:23–184`:

1. Активные canonical одной entity, кроме deleted.
2. canonicalId → затем provider ID + sourceType. Совпадение считается достаточным без amount/currency/account/status проверки.
3. Для incoming manual, voice и modelInference fuzzy отключён.
4. Fuzzy исключает canonical, уже имеющую evidence того же sourceType. Это one-per-source heuristic, не one-to-one reconciliation по наблюдениям.
5. Равные minor amount, currency, direction; merchant similarity ≥0.5; ≤48 часов при statement/screenshot на любой стороне, иначе ≤24 часов.
6. Score: 0.60 деньги + 0.20/0.16/0.12 merchant + 0.20/0.14/0.10 время + 0.02 + 0.04 за одинаковый account. Threshold 0.84. **Разный account — только отсутствие бонуса**, не отрицательное свидетельство.
7. Выбирается один максимальный score; равные scores сохраняют первого встреченного. Нет margin/ambiguous outcome.

Нормализация merchant — детерминированные aliases/regex/token similarity, не обучающаяся система. Отдельные словари есть в `synoball/enrichment/enrichment.dart`, deduplicator, `features/transaction_import/services/transaction_category_resolver.dart`, notification MerchantCategoryClassifier и Sber compatibility. Пользовательская категория не добавляет автоматическое глобальное правило для будущих merchant.

### E2. Полная направленная матрица восьми source families

Строка — **A уже существует**, столбец — **приходит B**. `I`: только сильная identity, fuzzy запрещён; `F`: fuzzy возможен при условиях E1, не гарантирован; `*`: receipt UI дополнительно может явно связать canonicalId. Никакая клетка сама по себе не означает корректность outcome или сохранение edits. Strong-ID правила применимы и перед F.

| A \ B | Manual M | Voice V | Receipt R | Screenshot O | Notification N | SMS S | Statement D | Web W |
|---|---|---|---|---|---|---|---|---|
| M | I | I | F* | F | F | F | F | F |
| V | I | I | F* | F | F | F | F | F |
| R | I | I | I* | F | F | F | F | F |
| O | I | I | F* | I | F | F | F | F |
| N | I | I | F* | F | I | F | F | F |
| S | I | I | F* | F | F | I | F | F |
| D | I | I | F* | F | F | F | I | F |
| W | I | I | F* | F | F | F | F | I |

Пример асимметрии: manual→notification может merge, notification→новая manual создаст ещё одну canonical. Это не автоматически ошибка для двух намеренных покупок; для одной установленной покупки нужно explicit link/identity, не более агрессивный fuzzy. Statement D включает PDF и Excel: между ними same-source fuzzy запрещён, хотя это могут быть два документа одного факта.

Для 3+ источников решение зависит от накопленного evidence: после N→D canonical уже нельзя fuzzy-связать с другим D, даже если этот D — новый формат той же выписки. N→D→R покрыт existing test, но N→W→D, все перестановки M/V/O/S и повтор каждой доставки с перезапуском repository — gap. При двух кандидатах одинаковой суммы неверный первый match может определить все последующие связи.

### E3. Idempotency ≠ matching ≠ reconciliation

- **Idempotency:** stable provider/canonical ID может предотвратить повтор canonical; новый ingestion/raw/candidate создаётся всё равно. При non-null повторном provider ID evidence не растёт, но и не связывает новую версию raw. Manual commands и voice без стабильного command key не имеют общего retry contract.
- **Matching:** эвристика E1 решает похожесть. Это не гарантия соответствия экономическому факту.
- **Reconciliation:** core объединяет поля, но не проверяет банковские opening/closing balances, completeness, количество авторитетных строк или связность transfer legs. Называть имеющийся deduplicator полноценной банковской сверкой нельзя.

### E4. Atomic boundaries и последовательности сбоев

| Граница | Что есть | Чего не доказывает |
|---|---|---|
| Core.ingest | Синхронный вызов без await в одном isolate; candidate matching + mutation последовательно | Один process не имеет classic simultaneous absent-candidate race между двумя вызовами core. Это **не** multiprocess constraint и не durable transaction |
| Core batch | Raw/records/candidates добавляются до reconcile; per-candidate errors catch; records summary | Нет rollback всего batch или явного per-record failed outcome; pending/failure metadata разной полноты |
| Controller → save | Snapshot encoding до постановки в per-repository save chain | In-memory state и UI уже изменены при error; нет CAS или revision |
| Local file | Очередь writes в isolate, temp/backup/rename с rollback при exception | Power loss в нескольких rename, два app процесса, восстановление после второго crash не покрыты |
| Android ack | Save await перед remove notification | Inbox apply() асинхронный, key может уже обозначать новую версию notification; нет versioned ack |
| Sber import → profile checkpoint | Save финансов отдельно, затем profile.json | Crash между ними приводит к replay; безопасность зависит от F01–F04. lastImportedTransactionAt — newest seen, не coverage cursor |
| Sync timeout | Manager lock, background best-effort cancel | Dart timeout не отменяет Future; manual ветка не имеет cancel; finally освобождает lock независимо от завершения старой работы |

Конкретные последовательности для проверки:

- **C1:** mutate canonical → repository write throws → UI уже показывает импорт; retry в том же controller видит запись, после restart её нет. Failed ingest outcome + ack нужно тестировать отдельно, F07.
- **C2:** финансовый snapshot сохранён → crash до profile checkpoint → тот же диапазон читается снова. При изменившихся fingerprint или filename появляется дубль/перезапись, F02/F08.
- **C3:** два BrowserProfileManager updates прочли одну metadata → writes в общий `.tmp` → потерян field update или file-operation error. Последовательный test stale profile это не покрывает, F09.
- **C4:** `runManual` timeout → `_release` → новая задача/delete all → старый callback завершает `importSberSnapshot` и снова пишет данные. Это R, нужен delayed fake с проверкой actual save, F09.
- **C5:** file primary отсутствует, backup читается после crash → следующий `_writeAll` удаляет backup → crash до temp rename → reader не рассматривает `.temporary`. Окно потери discoverable snapshot, F07.
- **C6:** NotificationInbox прочитан key K/v1 → пришёл K/v2 → ack v1 удаляет запись K целиком. Kotlin synchronized отдельные методы не дают versioned read/ack, F02/F07.

### E5. Полнота Sber и границы платформ

Работающая часть: `SberExtractors.transactions` собирает rows на **каждом** шаге, шагает с перекрытием, ждёт 1500 ms, нажимает load-more у конца списка и ждёт изменения fingerprint (`sber_extractors.dart:60–191`). Это существенно лучше single screenshot scrape. Ограничения: maxScrolls=160, stationary/max retries, range stop при обнаружении более старой строки; ни expected bank count, ни доказательства отсутствия gaps нет. Timeout JS-проверки hasMore превращается в null, далее false.

Connector формирует `syncPartial` и warnings для fallback dashboard, rejected rows, незакрытой pagination (`sber_connector.dart:140–205`). **Оба новые wrapper пути** принимают непустой partial snapshot и возвращают `BankSyncResult.success` (`sber_background_sync_runner.dart:82–102`; desktop bank page:1075–1110). Ручной dialog ещё умеет писать «частично» (desktop:1190), а metadata scheduler уже successful. Это противоречие статически подтверждено.

Background всегда запрашивает last30Days, а не начинает с durable covered cursor. Старые delayed records могут не попасть в окно. Scheduler — Dart Timer при живом приложении, не Windows service/Task Scheduler/Android Worker. Android native listener сохраняет notifications независимо от экрана, но canonical импорт выполняет Dart shell при событии/start/resume. Очередь ограничена 100 записями и 7 днями; после force-stop/lifecycle pause своевременное применение не доказано.

Background **не вводит сохранённый PIN** (`allowStoredPin:false`), а требует пользовательскую авторизацию при pin/full-login state. Это текущее поведение, не вывод о том, как следует менять банковскую безопасность. Повторно входить в банк для аудита не требовалось.

### E6. Безопасность и privacy в границах ingestion

- Financial snapshot шифруется AES-GCM с AAD logical key, ключ через FlutterSecureStorage (`L/data/persistence/encrypted_local_key_value_store.dart:15–35,38–125`). Это не доказывает одинаковую OS protection на всех платформах; fresh-key race нескольких store instances не проверялся. `SberPinVault` тоже использует secure storage, но **один общий key для Сбера**, не key per CEF profile (`L/features/bank_browser/sber/sber_auth_manager.dart:10–26`): несколько профилей могут использовать один сохранённый PIN. Не передавать PIN в observation/raw/logging.
- CEF profile/cookies и profile metadata находятся **вне** encrypted financial blob. `BankBrowserSecurityPolicy` блокирует небезопасные схемы и ограничивает main-frame origins, очищает userInfo/query/fragment для persisted URL; non-main-frame HTTPS допускается (`L/features/bank_browser/security/bank_browser_security_policy.dart:16–51`). Это navigation policy, не полная network sandbox или security certification.
- Connector scripts bounded/marked, запрещают явные cookie/storage/fetch/XHR обращения (`browser_controller.dart:173–199`). DEV mode запускается явно из bank UI, loopback port + random bearer token, no-store, descriptor удаляется при stop (`dev/dev_browser_bridge.dart:31–114`; desktop bank page:998–1004). Regex guards не считать изоляцией исполнения произвольного кода. DEV snapshot потенциально содержит финансовый DOM; descriptor token и exports требуют user-private доступа. File ACL, unexpected crash cleanup и adversarial bypass не проверялись; live DEV bridge не вызывался.
- Android listener отбрасывает OTP markers до encrypted inbox; inbox ограничена 100/7 дней и удаляет нерасшифровываемое вместо выдачи частичных секретных данных. Это сознательный privacy-vs-recovery компромисс; потери inbox не диагностируются как восстановимые банковские события. После переноса в core raw уже не имеет этой TTL (F10).
- Найденные OCR и voice paths локальные: Android on-device SpeechRecognizer с проверкой availability, Tesseract; Windows local OCR bridge/Whisper; web PDF.js bundled. Отправка финансового raw во внешний AI/OCR ingestion endpoint в исследованных paths **не найдена**. Отдельные public deals/CBR FX сетевые вызовы не являются upload financial raw. Runtime network traffic не измерялся.
- Native Android OCR и Windows voice используют временные файлы с cleanup в обычных finally; process crash может оставить temporary remnants. Аудит не просматривал личные temp-каталоги и не проверял очистку после аварии. F09/F10 предусматривают scoped cleanup/retention без удаления источников пользователя.
- Import input недоверенный: PDF size/page/text limits, Excel ZIP expansion/encryption/symlink limits и запрет macro execution уже есть; domain validation поверх extraction всё ещё неполна (F11). Увеличивать allowlist или ослаблять TLS ради прохождения теста не требуется.

Это scoped review, не аудит compliance/ГОСТ/всех внешних зависимостей. Новых сертификатов, ключей, разрешений Android или банковских сессий аудит не создавал.

## F. Findings register

Приоритеты соответствуют ТЗ: P0 — конкретная угроза сохранности/ложного учёта/edits на затронутом пути; P1 — необходимое укрепление заявленных сценариев. **S не означает воспроизведение на банковских данных пользователя.** Ниже нет утверждения, что конкретное прежнее расхождение Cash Flow вызвано одной из этих причин без построчной сверки.

### F01 — недостаточный scope и отсутствие ambiguous outcome в matching

- **Тип / приоритет / уверенность:** подтверждённый дефект правил, P0, S; проявление на реальных данных U.
- **Trigger/current:** N на известном счёте A; W/R/D с теми же amount/currency/direction/merchant/time на известном другом счёте B. Fuzzy score достигает threshold без account bonus. Два равных кандидата разрешаются порядком обхода. Strong provider match учитывает только sourceType/ID/entity, не connection/institution/account.
- **Evidence:** `L/synoball/reconciliation/deduplication.dart:33–74,94–110,122–184`; `core/synoball_core.dart:128–130`. W04–W10; все платформы общего ядра.
- **Нарушение/эффект:** две самостоятельные покупки могут стать одной; деньги и ownership могут перейти к более доверенному source; при коллизии provider даже currency/direction gate не выполняется.
- **Воспроизведение:** синтетические accounts A/B, две известные разные покупки 100.25 RUB у одного merchant в одну минуту; импорт N(A), затем W(B). Отдельно два N(A) + одно неоднозначное D(A), перестановка N. Existing `synoball_core_test:57` намеренно допускает смену account, но не различает неизвестную/placeholder принадлежность и два подтверждённых счёта.
- **Минимальное направление:** запрещать auto-merge противоречащих известных ownership/currency/type; отделить подтверждённую account identity от fallback; provider key scope по реальному источнику; ambiguous → неразрушительный pending/review. Не лечить увеличением time window или снижением threshold.
- **Reuse/compatibility:** сохранить deduplicator, aliases, evidence и core; потребуется версия/alias для старых scoped IDs, без массового автоматического объединения прошлых операций.
- **Проверки/зависимости:** T01–T03, T06, T09; зависит от согласования account identity D01; часть hard conflict checks ready-to-spec, stage S01.

### F02 — идентичность delivery/строки/экономического факта смешана

- **Тип / приоритет / уверенность:** подтверждённые ограничения identity и pre-core потери, P0, S; частота Android key reuse/Sber changes — R.
- **Trigger/current:** Excel использует координаты с filename: переименование создаёт новые IDs, а новая книга с тем же именем/ячейками перезаписывает прежние факты. Sber web включает mutable date/amount/text даже при наличии sourceId. Native inbox заменяет запись по `sbn.key`. Generic screenshot `putIfAbsent` объединяет одинаковые строки до ядра.
- **Evidence:** `universal_excel_statement_adapter.dart:1081,1104`; `sber_extractors.dart:394–399`; `BankNotificationListener.kt:95–99`, `NotificationInbox.kt:46–63,106–117`; `generic_bank_screenshot_parser.dart:55–74`, `bank_screenshot_import_service.dart:31–33`; `deduplication.dart:94–99` (same-source fuzzy не спасает rename).
- **Нарушение/эффект:** false merge, overwrite или повторный финансовый эффект. Generic screenshot identity не содержит currency/account/row occurrence: две реальные одинаковые date-only покупки могут исчезнуть из preview. Один SMS thread notification может содержать несколько сообщений, а Dart parse выдаёт один результат.
- **Воспроизведение:** rename workbook → import; две разные месячные книги с тем же filename и координатами → import; две одинаковые OCR строки без различимого balance → parseAll; bank sourceId неизменен, текст/сумма changed → extraction; K/v1 read, K/v2 save, ack(K).
- **Минимальное направление:** отдельные стабильные identities для доставки/версии/наблюдения и scoped provider fact; не считать content equality доказательством одинаковой покупки. Для OCR сохранять multiplicity, объединять overlap только при достаточной привязке; для Excel различать документ/версию и row identity.
- **Reuse/compatibility:** сохранить source parsers и UI preview; legacy Sber one-to-one compatibility на controller:826–852 использовать только с явно зафиксированными условиями. Нужны alias mapping/versioned import identity, dry-run review исторических конфликтов.
- **Проверки/зависимости:** T02,T04,T07,T11–T13,T15,T18; S02 после S01; D02/D03 определяют reimport и Excel document semantics.

### F03 — потеря minor units на границе UI и повторной записи

- **Тип / приоритет / уверенность:** подтверждённый дефект, P0, S. Тесты проверяют часть входа с копейками, но не сохранение после edit/reimport.
- **Trigger/current:** canonical 10025 minor → read model amount=100 → category edit → legacy bridge amount=10000. `importStatement` сначала передаёт exactMinor, затем для same-ID matched row вызывает full DTO update с roundedRubles. Web вообще округляет `amountValue` до создания fact. Для отрицательного баланса `_roundedMajor = (minor+50) ~/100` даёт некорректный результат, например -100 minor → 0 major.
- **Evidence:** `L/synoball/analytics/qesto_read_model.dart:40,64,128`; `L/synoball/adapters/qesto_legacy_bridge.dart:98–115,157–160`; controller:725,734–746,1569–1615; `sber_extractors.dart:346–352`; `SberTransactionFact.amount` — int major, `sber_connector_models.dart:99–125`.
- **Нарушение/эффект:** арифметическая точность canonical меняется от UI-операции, которая не должна менять сумму; cross-source exact-amount matching начинает расходиться. Это не может само по себе объяснить десятки тысяч прежнего Cash Flow: для этого нужна сверка missing/type rows.
- **Минимальное направление:** UI formatting отделить от canonical amount; category-only patch не пишет сумму/дату; exact minor провести через Sber fact и account mapping; повторный import не делает round-trip через integer major.
- **Reuse/compatibility:** Money minorUnits и exactMinorById уже существуют; не требуется новый ledger. Проекции/DTO могут потребовать совместимого расширения. Потерянные раньше копейки нельзя выдумывать; восстановление только из авторитетного source/reimport с отчётом.
- **Проверки/зависимости:** T01,T07,T10,T13,T17; суммы ±0.01/0.49/0.50/1.00/100.25, RUB/USD/EUR/CNY; S03 ready-to-spec, согласовать текущую two-decimal область.

### F04 — автоматический refresh нарушает authority пользовательских полей

- **Тип / приоритет / уверенность:** подтверждённый дефект контракта, P0, S; конкретный Sber manual-category happy path E.
- **Trigger/current:** user меняет category/title/date/account → повторный same-ID import. `canonicalFromQesto` заменяет полный объект, ставит `userCategoryOverride=value.categoryId` и `fieldTrust=userConfirmed`, в том числе когда вызван автоматическим refresh. Core отдельно выбирает merchant/time по source rank, не по field-specific user ownership.
- **Evidence:** controller:734–746,1569–1615; `qesto_legacy_bridge.dart:93–116`; core:454–525,675–746; models:678–730. Sber частная защита category — controller:861–910, test `T/sber_import_flow_test.dart:153–166`.
- **Нарушение/эффект:** потеря ручных исправлений, автоматическое поле ошибочно становится пользовательским, future enrichment блокируется/обходит защиту. Nullable `copyWith` не позволяет снять override/transfer metadata намеренным null.
- **Воспроизведение:** D(id=X) → user category/date correction → D(id=X) → W; отдельно W → user merchant correction → W. Проверять canonical и projection после restart, не только label категории в одном refresh.
- **Минимальное направление:** source observation update не вызывает user edit command; явный patch только изменённых пользователем полей; правила per-field preserve/clear и источника authority. Не присваивать userConfirmed автоматическому импорту.
- **Reuse/compatibility:** сохранить userCategoryOverride, manual tag, SourceTrustPolicy и audit purpose; ограничить legacy bridge восстановлением/миграцией. Ранее неверно присвоенный userConfirmed не снимать массово без provenance: D04.
- **Проверки/зависимости:** T05,T07,T10,T18; S04 совместно с S03; существующий Sber category test обязателен как regression, но недостаточен.

### F05 — lifecycle и финансовый тип расходятся между status, tags и consumers

- **Тип / приоритет / уверенность:** дефект общей lifecycle policy, P1, S; реальная последовательность mutable bank events U.
- **Trigger/current:** на стабильную identity приходит старый pending/cancelled; `_statusFromCandidate` устанавливает статус из incoming tags независимо от trust/времени доставки. При merge tags union сохраняет старые lifecycle/legacy-type tags. QestoReadModel выбирает первый `legacy-type-*` по enum; cashflow отдельно исключает `sber-status-pending`, даже если canonical уже posted.
- **Evidence:** core:461,521,574–594; `qesto_read_model.dart:90–101`; `L/features/budget/services/cash_flow_calculation_service.dart:86–108`; `synoball/analytics/read_models.dart:141–179`; controller:238–311 добавляет Sber-only reinterpretation.
- **Нарушение/эффект:** один canonical может иметь противоречащие labels; core analytics и desktop/budget aggregates могут считать его по-разному. Refund/reversal представлены tags/status, не связью с исходной покупкой; комиссии не отдельный canonical event kind.
- **Минимальное направление:** явные допустимые lifecycle transitions с freshness/authority; mutually-exclusive derived flags; общий treatment от canonical semantics, не накопленных history tags; отдельный observed refund не склеивать с покупкой.
- **Reuse/compatibility:** сохранить enum statuses и CashFlowCalculationService; согласовать их с SynoballAnalyticsReadService. Legacy flags мигрировать только детерминированно, со snapshot recovery; не переобозначать все transfers как expense.
- **Проверки/зависимости:** T04–T06,T16,T18, S05 после S01–S04. Требуется D06 для pending/refund presentation, но запрет необоснованного downgrade ready-to-spec.

### F06 — неизвестная принадлежность заменяется счётом, а identity счетов неодинакова

- **Тип / приоритет / уверенность:** подтверждённое поведение, P1; риск неверного ownership/двойного капитала S/R.
- **Trigger/current:** web fact account не найден → importedAccounts.first / accounts.first; passive resolver при несовпадении bank/suffix может выбрать единственную bankCard или единственный eligible account. PDF создаёт `sber-<suffix>-account`, web — `sber-account-…`; web reconciliation рассматривает только web-prefix eligible accounts. Два CEF профиля не передают собственный connection scope в импорт.
- **Evidence:** controller:815–817,893–900,1024–1037,1087–1095; `L/features/transaction_import/services/transaction_account_resolver.dart:31–75`; `statement_import_screen.dart:169–188`. `SynoballAccount` имеет entity/institution fields, но core adapter validate не проверяет foreign ownership.
- **Нарушение/эффект:** корректная сумма может оказаться на произвольной карте; suffix collision/name fallback может объединить accounts; PDF+web могут показать один физический счёт дважды. Без observed-account mapping нельзя безопасно ужесточить F01 одним сравнением текстовых IDs.
- **Минимальное направление:** unresolved отдельно от known; hard conflict hint не заменять first; canonical mapping bank connection/provider account/card alias. Подтверждённая карта — alias счёта, не второй актив с тем же балансом.
- **Reuse/compatibility:** TransactionAccountResolver, `_reconcileSberAccounts`, linkedCardLastFours уже есть. Для исторических связей — preview counts/known suffix links, не автоматическое fuzzy merge по имени/балансу.
- **Проверки/зависимости:** T03,T07,T14,T16,T17; S01/S06; D01 — критерии идентичности и unknown account UX.

### F07 — durable commit и ошибка загрузки не имеют безопасного общего контракта

- **Тип / приоритет / уверенность:** silent decode fallback — подтверждённый дефект S; crash/ack windows — R. P0.
- **Trigger/current:** корректно расшифрованный financial JSON неверной структуры/неподдержанной codec version → FormatException/TypeError → emptyUserFinancialData. Следующая запись заменит прежний graph. Core меняет память и notifyListeners до durable save; batch failures ловятся, но IngestionOutcome не несёт failed IDs. Importer делает ack после возвращённого outcome, не проверяя per-record failure.
- **Evidence:** `L/data/repositories/local_qesto_repository.dart:34–66`; codec:58–61; controller:442–445; core:138–188,212–219; automatic importer:125–149; `local_key_value_store_io.dart:38–76`. AES envelope tampering, в отличие от codec fallback, даёт исключение — это существующая полезная защита.
- **Нарушение/эффект:** «пустой новый профиль» маскирует повреждение/несовместимость; UI может подтвердить несохранённое; один ошибочный candidate потенциально теряет native delivery. C5 показывает второе crash окно recovery.
- **Минимальное направление:** fail-closed load/recovery state без autosave поверх unreadable data; сохраняемый ingestion outcome и ack только успешно committed/явно rejected record; устойчивый snapshot replace/recovery protocol. Синхронный core можно сохранить; SQL не обязателен.
- **Reuse/compatibility:** EncryptedLocalKeyValueStore, codec, save chain/temp backup, import outcomes. Разделить schema incompatibility, ciphertext error, parser reject, I/O failure. Backup должен оставаться восстановимым; cleanup raw не смешивать с recovery.
- **Проверки/зависимости:** T08,T09,T14,T17,T18; настоящая isolated file persistence и fault injection обязательны в следующей задаче. S07 ready-to-spec. Нужны safe abort и recovery без удаления originals.

### F08 — неполная история становится successful sync

- **Тип / приоритет / уверенность:** подтверждённый дефект propagation, P1, S; полнота банка U.
- **Trigger/current:** connector.syncPartial + непустой snapshot → background/manual wrapper success → lastSuccessfulSyncAt/next schedule. Число imported + unchanged не сообщает разницу между seen, rejected, filtered out-of-range, new evidence и merged. latest seen date называется lastImportedTransactionAt, не удостоверяет covered interval.
- **Evidence:** `sber_connector.dart:140–205`; `sber_extractors.dart:60–173`; `sber_background_sync_runner.dart:82–102`; `desktop_bank_connections_page.dart:1075–1110`; `bank_sync_manager.dart:279–306`; `controller.importSberSnapshot:991–1077` summary сравнивает projections до core outcome.
- **Нарушение/эффект:** положительный Cash Flow может оказаться результатом пропущенных расходов при внешне успешном импорте. Историческое замечание пользователя «видел больше строк, чем добавилось» нельзя считать закрытым fake-browser test.
- **Минимальное направление:** сохранять partial и причину окончания, requested/observed/covered range, known rejected counts; не продвигать confirmed coverage по partial; retry overlap с stable IDs. Развести valid empty history и parser mismatch. Не подгонять количество под прежние 125 операций без сопоставимого периода/типов.
- **Reuse/compatibility:** уже есть boundary/hasMore/reward/service counters и partial report; донести до manager/UI/persistence. Current balance остаётся отдельным snapshot, не вычисляемым остатком доходов.
- **Проверки/зависимости:** T08,T14,T15; S08 после S02/S07; контрольный обезличенный DOM и независимый statement row manifest нужны для полного Sber acceptance.

### F09 — timeout, параллельная metadata и delete не ограждают от поздней записи

- **Тип / приоритет / уверенность:** конкретно обоснованный риск, P0, R; отсутствие cancellation fence/атомарной metadata видно S.
- **Trigger/current:** manager применяет Future.timeout; manual callback не получает cancellation. Background cancel best-effort, errors swallowed, lock освобождается finally. BrowserProfileManager выполняет несериализованный read-modify-write в общий `.tmp`, delete target → rename. Delete all не останавливает runners и отдельно очищает finance/inbox, не CEF/profile resources.
- **Evidence:** `bank_sync_manager.dart:124–172,176–217`; `sber_background_sync_runner.dart:109–130`; `browser_profile_manager.dart:73–90,112–125,161–170`; `qesto_app.dart:127–134`; shell:131–136. Locks — только Sets внутри одного manager instance.
- **Нарушение/эффект:** поздний старый run способен записать после timeout, нового run или wipe; lost metadata update; crash между target.delete/rename теряет видимый profile.json. Shutdown active importer/loader replacement на resume также требует проверки, не объявлен доказанной порчей.
- **Минимальное направление:** cancellable operation + generation/fencing до любых write/ack/checkpoint; lock освобождать после прекращения владения; сериализация profile changes и recoverable replace; deletion barrier. Поддержку нескольких app процессов либо запретить single-instance, либо обеспечить process lock.
- **Reuse/compatibility:** BankSyncManager, CancellableBankBackgroundSyncRunner, metadata copyWith, existing schedule tests. Reset поколения совместимее массовой миграции финансовых данных; CEF sessions не удалять без выбранной wipe policy D05.
- **Проверки/зависимости:** T08–T11,T17; delayed run после timeout, cancel throws/hangs, metadata update race, wipe while import awaits save; S09 после S07. Existing timeout test использует fake cancellable runner и не проверяет late controller write.

### F10 — provenance есть, но replay и field lineage неполны

- **Тип / приоритет / уверенность:** подтверждённое ограничение/decision required, P1, S.
- **Trigger/current:** повтор source ID создаёт новые raw/ingestion/candidate, но evidence остаётся связанным с первым ingestion; evidence.observedAt заполняется occurredAt операции. Candidate не хранит resolved canonical ID. Web raw содержит только transaction IDs; binary Excel raw — metadata; screenshot raw redacted, при этом candidates сохраняют извлечённые значения. Adapter version есть, upstream parser version не везде зафиксирована.
- **Evidence:** core:537–562; `models.dart:466–601,794–834`; controller:1030–1034; `statement_import_screen.dart:108–114`; adapters:276–322; `_TransactionAdapter.normalize:55–118`.
- **Нарушение/эффект:** нельзя гарантированно повторить parsing web/Excel или объяснить, какое конкретное новое наблюдение изменило поле; source trust/reconciliation audit не равен field history. Receipt cardinality ограничена одним прямым link; повторный parser не имеет controlled replay command.
- **Минимальное направление:** разделить повтор доставки и новую версию наблюдения; хранить достаточный нормализованный evidence с source row reference/parser version и явным resolved link. Сроки raw и redaction — продуктовая политика, а не рекомендация хранить всё вечно.
- **Reuse/compatibility:** RawPayload/IngestionRecord/SourceEvidence/AuditEntry уже полезны; расширять минимально и versioned. Не восстанавливать отсутствующие raw bytes из догадок; маркировать legacy provenance incomplete.
- **Privacy/recovery:** core raw/candidates/events растут без найденной TTL; raw notification/transcript/PDF/receipt encrypted, но содержащие PII. Native inbox имеет TTL и fail-closed drop. Нужны retention policy, export redaction и запрет reimport deletion tombstone leakage. F02/F07/F09 связаны.
- **Проверки/зависимости:** T01,T07,T11,T13,T17,T18; S10; D02/D04/D05. Полный raw replay заблокирован отсутствующими исходниками — не обещать обратимость.

### F11 — validation и aggregate semantics не отделяют предположение от факта

- **Тип / приоритет / уверенность:** подтверждённое ограничение, P1; некоторые expected outcomes требуют решения.
- **Trigger/current:** adapter.validate проверяет entity/raw nonempty, amount не отрицательный, длину currency=3, непустой account ID; не проверяет account existence/ownership, supported currency, календарную валидность/точность, zero, совместимость типа. Source DTO часто делает abs/default. Sber screenshot при отсутствии суммы выводит её из соседних балансов без доказательства непрерывности/одного счёта и помечает selected. Excel aggregate хранится как обычная операция с tag.
- **Evidence:** adapters:28–45; `sber_bank_screenshot_parser.dart:36–40,68–105`; `universal_excel_statement_adapter.dart:75–80,1085,1111–1119`; `statement_import_screen.dart:254–258`; models:88–114. Excel archive/row limits уже хорошо реализованы (adapter:36–60,1127+).
- **Нарушение/эффект:** category total + детальные покупки за тот же период могут учитываться одновременно; date-only aggregate 01 числа превращается в «ритм покупок»; unknown date/currency может выглядеть уверенным фактом. Низкий confidence сам по себе не делает candidate unconfirmed: StatementAdapter auto-import.
- **Минимальное направление:** граница validation перед durable canonical, unknown/inferred flags и safe review; aggregate coverage не смешивать с детализацией без выбранного правила; inferred amount только с явной маркировкой и подтверждением. Не создавать новую бухгалтерскую систему.
- **Reuse/compatibility:** существующие confidence, tags `excel-period-aggregate`, `date-precision:day`, preview selection и archive limits. Данные прошлого импорта не переклассифицировать молча.
- **Проверки/зависимости:** T06,T13,T14,T16–T18; S11 после S03/S06; D03/D06 блокируют часть семантики aggregate/own transfer.

### F12 — platform end-to-end и автономность импорта не подтверждены

- **Тип / приоритет / уверенность:** verification gap, P1; подтверждённые статические границы, без объявления native runtime сломанным.
- **Current:** Android SMS — notifications only, listener сохраняет максимум 100/7 дней, canonical drain требует app shell. Существующий test «persisted without confirmation» создаёт BudgetController **без onChanged repository callback**. Native Windows OCR/PDF/Whisper opt-in skipped. Android durable file path выбирается общей IO веткой `HOME/.local/share`, не явным app filesDir. Background CEF в последних изменениях native реально не проверен.
- **Evidence:** `T/automatic_notification_importer_test.dart:11–16,26–55`; NotificationInbox:23–24; shell:93–122; `local_key_value_store_io.dart:79–94`; `T/windows_native_bridges_test.dart`, `T/bank_screenshot_windows_ocr_test.dart`; config/runtime table C3.
- **Риск:** сильные заявления «пассивно всегда», «переживает restart», «проверено на Android» не следуют из имеющихся tests. Окружение Android HOME/current directory может не дать ожидаемый durable app-private path — это R, нужна device проверка.
- **Минимальное направление:** acceptance gates на реальном native storage и закрытом/свёрнутом app lifecycle, без расширения на новые источники. Определить обещание «фон»: живой процесс, minimized или closed application. Для существующего режима отобразить честные ограничения.
- **Reuse/compatibility:** сохранить native listener/queue, OCR bridge, scheduler, fake tests; добавить device/integration verification в отдельной implementation задаче. Не переносить store path без recovery migration.
- **Проверки/зависимости:** T08,T12–T15 + Android kill/restart/access revocation; S12 после важных P0; D07, отдельное разрешение на live bank verification.

### F13 — Android voice: подтверждение UI не публикует операцию

- **Тип / приоритет / уверенность:** подтверждённый дефект потока управления, P1, S. Не результат live Android проверки и не дефект всех voice paths.
- **Current:** confirmation sheet передаёт `confirmedVoiceInput: true` в `BudgetController.addImportedTransactions`. Контроллер вызывает `VoiceInputAdapter`, записывая `confirmedInPreview` только в `userCorrections`. Адаптер всегда выставляет `requiresConfirmation = true`; `_withRawBody` не меняет candidates. Core оставляет их pending, возвращает пустые `createdTransactionIds`. Контроллер сохраняет состояние и возвращает; sheet возвращает `true`, UI показывает успешное добавление. В этом пути нет `confirmCandidate`/`confirmVoiceCandidate`.
- **Evidence:** `L/features/voice_transaction/presentation/voice_transaction_confirmation_sheet.dart:135–166`; `L/features/budget/state/budget_controller.dart:590–641`; `L/synoball/adapters/adapters.dart:96–97,148–174,507`; `L/synoball/core/synoball_core.dart:157–163,222–255`. Поиск `confirmedInPreview` находит только запись metadata, не обработчик подтверждения.
- **Влияние:** пользователь подтверждает голосовой расход, но canonical transaction и денежный эффект не создаются этим действием; сохранён лишь кандидат. Это конкретный пример того, почему «путь идёт через Synoball» недостаточно.
- **Минимальное направление:** связать уже выполненное UI-подтверждение с существующим core confirmation command и проверенным durable outcome. Не отключать confirmation глобально в VoiceInputAdapter. Desktop `addVoiceCandidate` → `confirmVoiceCandidate` сохранить.
- **Tests/compatibility:** `T/voice_input_flow_test.dart` проверяет отдельный desktop/controller путь pending→confirm. `T/widget_test.dart:104–136` нажимает Android save, но проверяет только текст «Операция добавлена», а не transactions/evidence/суммы. Оба проходят и не опровергают дефект. Дополнить T12 в следующей задаче; старые pending не подтверждать массово без решения пользователя.
- **Зависимости:** отдельный небольшой S13; существующую модель Synoball менять не требуется. Failure/commit сценарии согласовать с S07, без скрытого второго UI-confirm.

## G. Verification и каталог test specifications

### G1. Исполненные команды

Рабочая директория: `apps/qesto_app`.

```powershell
& 'C:\Users\ARM\development\flutter\bin\flutter.bat' test --no-pub --reporter expanded
# exit 0, 324 passed, 7 skipped, All tests passed (около 28 s тестового времени)

& 'C:\Users\ARM\development\flutter\bin\flutter.bat' analyze --no-pub
# exit 0, No issues found! (63.4 s)
```

Пропуски: 1 Windows screenshot OCR с explicit local screenshot fixture; 3 Excel private fixture tests (общий corpus и два workbook-specific); 3 native Windows PDF/OCR/Whisper. `QESTO_EXCEL_FIXTURE_DIR`, `QESTO_BANK_SCREENSHOT_PATHS`, native opt-in flags не задавались. Corpus test перечисляет **23 файла (0–22)**, хотя в переписке встречается «22»; его minimum-count/years/kinds assertions не равны построчному финансовому ground truth.

Build Android/Windows/web, physical device, live bank, crash injection, external API и full private corpus: **not run**. Исходное sandbox зависание: **blocked/environment**, не failed assertion. Тесты не проверяют SQL constraints — finance SQL storage в текущем приложении не найден. Репозиторий/шифрование преимущественно проверяются MemoryKeyValueStore/fake secure storage, а не Windows filesystem power-loss или Android Keystore lifecycle.

### G2. Coverage matrix

`E` означает соответствующий частный тест исполнен; `U` — нужная гарантия не подтверждена. Во всех рядах native end-to-end отдельный U.

| Source/variant | Parsing | Validation/normalization | Matching | Persistence | User overrides | Retry/concurrency | Consumers |
|---|---|---|---|---|---|---|---|
| Manual | E widget form | E base validation | E intentional same-source; U command key | E codec/memory; U disk failure | E UI category; U per-field patches | U command retry/concurrent edit | E budget widget |
| Voice | E draft/phrase | E desktop confirmation; Android defect S/F13 | E desktop pending→confirm; U all source orders | E state serialization; U native restart | U subsequent source updates | U same command retry | Android widget E проверяет только success text, не денежный эффект |
| Receipt QR/OCR text | E QR/OCR parser | E total/items/service lines | E matcher proposals + N/D/R | E controller/codec | U edited link → authoritative refresh | U split/multi-payment and persistence retry | E receipt details |
| Screenshot | E Sber/generic OCR lines | E filtering | E identical screenshot replay | E controller state; redacted raw assertion | E editable preview | U equal real rows/currency collision | E preview save |
| Notification | E Sber/general fixtures | E OTP/balance rejection | E N→D→R; N+N | **U disk:** importer test no repository callback | U all field ownership | E ack failure in fake; U K/v2 race | E widget auto add |
| SMS notification | E fixture | E financial text guard | U SMS × every source | U device/disk | U | U thread updates/multi-message | E type/source assertion, not full bank reconciliation |
| Sber PDF/TXT | E 2 text layouts | E signs/category | E retry known IDs | E controller/codec | E selected compatibility; U full edit preservation | U changed doc/overlap same auth IDs | E cashflow fixtures |
| Excel | E generated tables | E year/aggregate/capital + ZIP security | U rename/shift/overlap with detail | E controller path; private corpus skipped | U replacement book same filename | U replay after layout changes | E import UI; U aggregate ownership |
| Sber web | E normalized rows/fake browser | E merchant/Спасибо/service/type | E compatibility provider transition | E controller; U real persistence+checkpoint | E Sber manual category only | E fake pagination/schedule; U actual CEF/cancel late write | E cashflow/controller/UI |

Ключевые assertions и ограничения:

- `T/synoball_core_test.dart:57–128`: N → **StatementAdapter**, не BankWebAdapter → Receipt; asserts one canonical, three evidence, merchant/category/receipt. Не исполняет native extraction, repository или permutations. `:131–152` сохраняет два N с разными keys; `:191–237` ограничивает N↔две D; `:240–288` сохраняет receipt time.
- `T/automatic_notification_importer_test.dart:58–82`: fake remove fails once, second drain created=0, merged=1, evidence=1. Это доказательство in-memory retry, не durable-commit-before-ack.
- `T/sber_import_flow_test.dart:153–166`: manual category survives конкретный Sber refresh. `:239–321`: suffix-linked account merge, два transactions сохранены. Не PDF+web same-account и не два CEF профиля.
- `T/bank_screenshot_synoball_flow_test.dart:9`: один candidate дважды, second created empty, redacted raw и один UI amount. Не два разных equal purchases.
- `T/encrypted_local_key_value_store_test.dart:7–71`: encryption envelope, plaintext migration, AAD и tamper rejection; MemoryKeyValueStore/fake key backend. Не master-key creation race или file rename crash.
- `T/user_financial_data_codec_test.dart:274–333`: repository restart/delete через test store, не реальный app process. `T/synoball_core_test.dart:632` — raw/canonical/evidence JSON round trip.
- `T/bank_sync_schedule_test.dart:148,168,203`: fake runner mutual exclusion, cancellable timeout, visible browser lock. Нет delayed import write после timeout/cancel failure.
- `T/sber_extractors_test.dart` «history waits for and follows every load-more page» / «reports an incomplete range when pagination is still present»: fake BrowserController возвращает scripted rows/commands; доказывает алгоритмическую ветку, не актуальный DOM банка и не wrapper partial propagation.

### G3. T01–T18 — воспроизводимые specifications, не добавленный код

Все суммы ниже синтетические. Каждый тест должен проверять canonical IDs/count, evidence/observation links, поля, snapshot reload и consumer financial effect; только count недостаточен. Ожидания относятся к **установленному ground truth**, не к внешнему сходству.

| ID | Initial state → входы/порядок → expected outcome | Existing coverage / gap |
|---|---|---|
| T01 | Empty graph, known account A. Один документально установленный расход 100.25 RUB: N «Пятёрочка», W «PYATEROCHKA 123 MOSCOW», D та же банковская identity/date. Все 6 порядков; затем replay каждого, reload. Expected: 1 canonical, 3 distinct source observations, 1 outflow 10025 minor, no duplicate evidence при exact delivery replay; новые observation versions различимы | N→D→R частично E, полный N/W/D + SMS/OCR/receipt permutations U; F01–F04/F10 |
| T02 | Две **разные** покупки 100.25 у одного merchant в 12:00/12:01 с distinct provider IDs; N для обеих, затем D/W в обратном порядке. Отдельно OCR date-only две строки без account/balance. Expected: 2 operations; ambiguous cross-source mapping не уничтожает одну; unresolved evidence разрешено | N+N и N+2D E, pre-core OCR collapse и adversarial multi-source U; F01/F02 |
| T03 | A/B разных известных счетов, затем разные entities и RUB/USD с одинаковыми numerical amounts; равные provider strings в разных connection scopes. Expected: 2 independent facts/owners/effects в каждом случае, strong-ID conflict не объединяет | Entity recurring isolation E не равно transaction scope tests; U основные combinations |
| T04 | Pending observation P с immutable bank identity; posted Q подтверждён как тот же факт, изменены time/amount/display/source alias. P→Q и replay. Expected: 1 canonical posted, current authoritative amount, обе versions. Если bank identity отсутствует и связь не доказана — pending relation/review, не заранее expected merge | Status mapping snippets E, полноценный transition/changed identity U; D06 |
| T05 | Уже posted Q; приходит позднее N, затем stale pending P с тем же bank identity. Expected: no downgrade/amount rollback; evidence добавлено; consumers still count posted. Все порядки и old tags included | U; F04/F05 |
| T06 | Expense 100.25, separate partial refund 40.00, fee 1.00, затем подтверждённая отмена исходной operation. Разные source IDs. Expected: refund/fee не duplicate purchase; reversal status по выбранной policy, net не считает одновременно cancellation и полный refund дважды | Expense/income/refund type fixtures E; related lifecycle and partial refunds U; D06 |
| T07 | D1 содержит facts X/Y; exact replay; D2 overlapping Y/Z; другой PDF layout; Excel rename/insert row/new month same filename. Ground truth IDs и суммы заданы заранее. Expected: X/Y/Z по одному, versions/new data retained; изменения формата не меняют число фактов | Stable same IDs E; independent source/document identity U |
| T08 | Durable empty state + batch X/Y. Inject failure после X reconcile, до snapshot replace, после replace до inbox ack/profile checkpoint; restart/retry. Expected: committed statuses объясняют retry, итог X/Y ровно по одному, source не потерян, старый валидный snapshot восстанавливаем | Fake ack retry E; real fs fault injection и candidate fail outcome U |
| T09 | N/W одного known fact вызываются почти одновременно в одном controller; затем два repository/controller instances; sync delayed after timeout. Expected: один effect, no lost acknowledged state. Для unsupported multiprocess — второй instance отвергается явно | Одноизолятный core синхронен S; scheduler lock E; concurrent durable/late write U |
| T10 | D/W → user меняет category, merchant, date, account; source refresh → overlapping D. Повторить с UI edit во время delayed sync. Expected: только пользовательские patches победили в своих fields; автоматический observation всё равно сохранён; minor amount не меняется от category edit | Sber category E; прочие поля и simultaneous orders U |
| T11 | Persisted X → user delete → тот же source, затем другой source того же X. Expected: **D02 required**: suppression или explicit restore, но не скрытая двойная identity. Existing undo restores one fact с сохранными links. Transaction split/user merge UI NF — N/A; account merge проверить отдельно | Soft delete/undo paths S; reimport invariants U |
| T12 | Android voice preview → Save → ровно одна canonical операция с суммой/категорией/evidence, нет оставшегося pending для неё; persistence reload сохраняет эффект; save failure не показывает успех. Отдельно desktop pending→confirm. Один logical manual/voice command C доставлен дважды, затем C2 намеренно повторяет содержание. Expected: C даёт 1 effect, C2 ещё 1; pending state survives restart | Desktop confirm E; Android success text E, canonical posting defective S/F13; logical command identity U; нельзя dedup по одному тексту |
| T13 | Screenshot содержит 3 факта, 2 равные покупки; overlap второй screenshot; receipt содержит 4 items и, отдельно, две оплаты. OCR replay и ошибочно inferred balance delta. Expected: 3 денежных факта, items не дополнительные расходы; payment cardinality policy D03 required; inferred amount не превращается в уверенный silently | Synthetic 1 screenshot/replay and item parser E; multiplicity/multipayments U |
| T14 | Invalid amount/zero/overflow, ISO code '???', неверная календарная дата, unknown account, OTP/ads, пустой JSON, broken DOM/hasMore timeout. Expected: явный reject/review/error по каждому record, не пустой «успех»; неподтверждённый account не first | OTP, malformed QR, PDF/Excel limits E; canonical validation/coverage outcomes U |
| T15 | History pages overlap, одинаковые timestamps на границе, slow virtualized render, mid-page gap, delayed posted row старше lookback. Expected: stable row identities, no lost equal rows; partial не advance covered range; old late record требует documented recovery path | Fake load-more/boundary E; actual completeness, late reconciliation U |
| T16 | Два подтверждённых собственных accounts A/B. Transfer debit 100 + credit 100, затем обе стороны N/W/D. Expected: account flows -100/+100, aggregate external flow 0, подтверждённая связь сторон; отдельная fee=1 остаётся outflow. Unknown external wallet ownership не объявлять internal автоматически | Internal tag consumer tests E; paired legs entity model NF, D01/D06 |
| T17 | Legacy financial v1/v6 без metadata, existing duplicates, current user edits; future migration interrupted halfway. Expected: versioned dry-run, counts/amounts preserved, idempotent restart, reversible cutover, unknown не выдуман. Unsupported future schema сохраняется для recovery, не empty autosave | Codec/legacy bridge E; migration design и injected restart U, реализации пока нет |
| T18 | Source observation v1 → parser/aliases v2 → replay, пользовательские edits уже есть; raw часть удалена по policy. Expected: identity/edits preserved; effect не размножен; explicit 'not replayable' там, где bytes/rows не сохранились, не silent fabricated replay | Persistence roundtrip E, controlled replay U; F02/F04/F10 |

## H. Минимальная TARGET STATE и эволюция

### H1. Что сохранить

Flutter приложение; Windows CEF и isolated profiles; native Android notification listener/ограниченную encrypted inbox; local OCR/on-device speech/Whisper; PDF/Excel parsers и preview; Synoball Money, entities/accounts/candidates/evidence; core как единую точку merge; encrypted local repository; существующие тесты. Отсутствие email/live Open Banking не причина расширять scope.

Вариант **без структурного redesign** реалистичен: точечные policy/DTO/patch changes, стабильные source identities, record-level outcome, сохранённая metadata и защищённый snapshot writer. Переход на SQL, event sourcing или microservices не является prerequisite. Решение о storage backend принимать только если fail-injection покажет, что минимальный file protocol неудобно поддерживать.

| Current | Required | Минимальное изменение / findings |
|---|---|---|
| Similarity без hard ownership constraints | Никогда не уничтожать известные разные facts | scoped keys, conflicts, ambiguity; F01/F06 |
| Filename/content fingerprints как provider identity | Стабильная identity и отдельные observation versions | source-specific corrections + aliases, F02 |
| Integer-major DTO пишет canonical | Minor-unit данные не теряются при presentation/edit | сохранить Money, patch commands; F03 |
| Auto refresh делает user edit | Source enrichment и user ownership различаются | убрать full-object bridge writer с importer; F04 |
| Status/tags/read models расходятся | Один financial treatment для одного canonical state | lifecycle policy + projections; F05 |
| Save/ack/checkpoint независимы без результата commit | Нельзя подтвердить потерянное/неполное | snapshot recovery + explicit outcomes/fence; F07/F09 |
| Partial превращается success | Частичность сохраняется до UI/checkpoint | протянуть существующие counters/status; F08 |
| Raw без воспроизводимого row lineage | Объяснимые source changes при минимуме PII | resolved observation links/retention; F10 |
| Aggregate row выглядит как обычная покупка | Статистические totals не удваивают detail coverage | narrow aggregate semantics/validation; F11 |
| Android voice UI success при pending candidate | Подтверждение создаёт один сохранённый денежный факт | existing confirmation command + outcome check; F13 |

### H2. Порядок этапов

Полные stage inputs находятся во втором документе; здесь зависимости. Это рекомендации, **не разрешение начать правки**.

1. **S01** matching safety + ownership conflicts (F01/F06), совместно с read-only identity inventory для D01.
2. **S03/S04** точность денег и user-patch authority (F03/F04); небольшие regression-first изменения до дополнительной автоматики.
   **S13** — отдельное узкое исправление Android voice confirmation с проверкой canonical эффекта; не требует redesign.
3. **S07/S09** durable save, recovery, late-write fence/delete barrier (F07/F09). Не откладывать до расширения источников.
4. **S02/S06** versioned source/account identities с migration dry-run после решений D01/D02/D03.
5. **S05/S08** lifecycle/consumer parity и completeness propagation; partial propagation можно вынести в ранний небольшой фикс, но полное incremental sync зависит от identity/storage.
6. **S10/S11** provenance/retention и aggregate validation после продуктовых решений.
7. **S12** native acceptance с synthetic data, затем отдельно разрешённая live сверка; не маркировать ready до проверки.

Связь с приоритетами checklist из ТЗ: надёжность способов ввода — S01–S09/S12/S13; расширяемость выписок без копирования business logic — S02–S06/S11; качество Сбера — S02/S06/S08/S09; Synoball/dedup — S01–S05/S10; категории/edits — S04/S05; наблюдаемость — S07/S08/S10; безопасность миграций перед alpha — S07/S09/S10/S12. Никакие пункты отсутствующего MASTER CHECKLIST не объявляются выполненными.

### H3. Migration/cutover/recovery constraints

- Сначала read-only manifest: version, IDs/scopes, canonical count, суммы **в minor по currency/direction/status**, evidence links, deleted IDs, overrides, accounts и unknowns. Не использовать округлённый total UI как контрольную сумму.
- На изолированной копии зафиксировать before/after каждого proposed mapping; не угадывать авторство `userConfirmed` прошлых automatic refresh и потерянные копейки.
- Не делать automatic mass merge по amount/merchant. Ambiguous historical groups — review, сохраняя обе записи до решения.
- Canonical IDs сохранять, где доказано соответствие; legacy provider aliases не удалять до безопасного reimport. Tombstone retention согласовать с privacy.
- Storage upgrade atomic/versioned; неизвестная более новая schema — readonly recovery, не empty profile. Держать last-known-good snapshot отдельно до cutover.
- Backfill должен быть checkpointed/idempotent и не запускаться из обычного screen build. Прерывание на любой стадии — old state recoverable. Rollback после новых observations требует явной совместимости, не просто запуска старого EXE поверх нового schema.
- Delete all останавливает/ограждает writers до очистки; отдельно объясняет, остаются ли bank connection/cookies/PIN. Аудит не удалял эти данные и не менял сертификаты.

## I. Открытые решения и блокирующие данные

| Decision | Почему важно / варианты из текущей системы | Что блокирует / какие данные нужны |
|---|---|---|
| D01 Account ownership | Virtual/default vs подтверждённый bank account; suffix недостаточен для нескольких банков/профилей. Нужен mapping account/card alias/connection | Полный S01/S06 и безопасная migration. Нужны обезличенные примеры stable account/provider IDs, связи card→account; не логины/PIN |
| D02 Delete/reimport | Delete означает «скрыть факт навсегда», «убрать этот импорт» или «разрешить восстановить»? Сейчас mixed behavior | Tombstone semantics S02/S09/S10. Выбрать UX restore/suppression и retention minimal identity |
| D03 Excel aggregates и receipt payments | Aggregate статистика или фактический cash event? Как сочетать месячный total с detalization? Multiple payments receipt пока вне модели | S11 и T13/T16. Нужны примеры с установленным ground truth и выбранный rule: exclude covered detail, explicit replacement или separate statistical observation |
| D04 Авторство старых полей | userConfirmed мог поставить importer; автоматически отличить ручное исправление не всегда возможно | Migration S04/S10. Нужен conservative rule: сохранить спорное, переобучение/reclassification только opt-in |
| D05 Privacy/wipe | «Удалить все данные» включает bank cookies/PIN/profiles? Как долго хранить notification/PDF/transcript/observation/tombstone? | Полная S09/S10. Решение пользователя/продукта, не повод сейчас стереть CEF |
| D06 Lifecycle/transfer/refund policy | Pending UI vs cashflow; reversed vs separate refund; наличные/свои внешние wallets и fee | Полный S05/S11. Ground-truth fixtures и продуктовый treatment; нельзя просто все переводы сделать расходом |
| D07 Обещание фона | Пока app живо, в tray, или полностью закрыто? Текущий режим — живой Dart process, background PIN disabled | S12 acceptance и будущий scheduler scope. ОС-служба/полностью автономный вход не добавляются автоматически |
| D08 Sber live completeness | Fake DOM не доказывает 100% текущей истории | Финальный S08/S12. Отдельное разрешение на read-only sync или обезличенные page fixtures + independent row manifest за **одинаковый** период/набор счетов |

Итог: единая точка ingestion уже создана; главная следующая задача — сделать общими и проверяемыми **identity, money, field ownership, lifecycle и commit**, а не добавлять ещё один универсальный парсер поверх текущих обходов.
