# QESTO — вход для следующего implementation specification

Baseline: 2026-09-05; финальная проверка: 2026-09-06. **Это результат аудита, не разрешение реализовывать изменения.** Полные доказательства, матрицы и каталог T01–T18: `docs/QESTO_INGESTION_AUDIT.md`.

## 1. Контекст для нового исполнителя

Qesto — существующее Flutter PFM-приложение Android/Windows с общей Dart моделью Synoball. Требуется укрепление текущего получения и согласования финансовых данных, без переписывания продукта, расширения банков и реализации roadmap. Предыдущие сообщения о работе парсеров не считать доказательством текущей полноты.

Repository: `C:\Users\ARM\Documents\Qesto`; app: `apps/qesto_app`; branch: `codex/sber-browser-sync`; HEAD: `5b4ac1829e215d15c57031b0a117e2ed3e673921`. Аудит исследует **HEAD + dirty working tree** с фоновой CEF-синхронизацией. До аудита были незакоммичены shell/UI/browser/profile/auth/pubspec/CEF изменения, `domain/bank_sync_models.dart`, `sync/` и sync tests; они принадлежат пользователю. Не отменять и не предполагать, что они уже находятся в Git HEAD. При начале будущей задачи сверить snapshot и line numbers заново.

Окружение аудита: Windows, Flutter 3.44.6, Dart 3.12.2, app 1.0.36+37, financial codec schemaVersion=6 (storage key по историческим причинам заканчивается `.v1`). `flutter test --no-pub --reporter expanded`: **324 passed, 7 skipped**; analyze: **No issues found**. Native Windows OCR/PDF/Whisper, private Excel corpus, Android device, live bank, crash-injection не проверялись. Production-ready/alpha-ready не установлено.

MASTER CHECKLIST / QESTO AI Development Protocol / применимый AGENTS.md в исследованном доступном репозитории не найдены. Не выдумывать их требования. Приоритеты из ТЗ: надёжность текущих источников, выписки без копирования business logic, качество Сбера, dedup/категории/edits, наблюдаемость, безопасность миграций.

### Реальный pipeline

UI/native/background trigger → source parser/preview → `BudgetController` → `ManualInputAdapter`, `VoiceInputAdapter`, `AndroidNotificationAdapter`, `SmsNotificationAdapter`, `ReceiptAdapter`, `BankScreenshotAdapter`, `StatementAdapter` или `BankWebAdapter` → **синхронный** `SynoballCore.ingest` → candidates/matching/canonical/evidence → `QestoReadModelService` → Sber compatibility → UI `BudgetTransaction` → `mergeInto` → `LocalQestoRepository` → encrypted JSON snapshot.

Storage отделён от in-memory merge. Отдельно существуют Android NotificationInbox, CEF profiles/cookies, profile.json с scheduling metadata. SynoballApiV1 — read facade, не backend. Open Banking — disabled/fake scaffold, email ingestion не найден. SMS читаются через notifications поддержанных messaging apps, не напрямую из Telephony SMS.

### Непереговорные инварианты

1. Две известные разные покупки не уничтожаются по сходству суммы/merchant/time.
2. Один установленный факт из нескольких источников не повторяет денежный эффект; связь не выдумывается при недостатке identity.
3. Money сохраняется в minor units; category/merchant edit не изменяет сумму/валюту/дату побочно.
4. Автоматический source update не становится user-confirmed edit и не уничтожает пользовательские поля.
5. Unknown account/дата/тип не заменяются достоверным first/default без явного основания.
6. Lifecycle/transfer/refund имеют единый downstream treatment; posted не downgrade устаревшим наблюдением.
7. Ack/success/checkpoint не подтверждают несохранённое или неполное; retry после crash безопасен.
8. Timeout/delete/cancel лишают старую работу права писать; любой recoverable snapshot остаётся доступен.
9. Provenance достаточен для объяснения результата и ограничений replay при минимуме PII.
10. Исторические данные/edits/IDs не мигрируются разрушительно или по догадке.

## 2. Findings и решения

| Finding | Суть / приоритет |
|---|---|
| F01 | Scope matching, hard account conflicts, ambiguous candidates — P0 |
| F02 | Delivery/document/row/provider identity смешаны — P0 |
| F03 | Major-unit roundtrip портит canonical amount — P0 |
| F04 | Automatic refresh пишет полную user-confirmed projection — P0 |
| F05 | Status/tags/financial consumers расходятся — P1 |
| F06 | First-account fallback и разная account identity разных sources — P1 |
| F07 | Decode fallback/commit/crash/ack contract — P0 |
| F08 | Partial history становится success, coverage не durable — P1 |
| F09 | Timeout/delete late writes и profile metadata races — P0, обоснованный риск |
| F10 | Evidence lineage/replay/retention недостаточны — P1 |
| F11 | Validation/inferred/aggregate семантика — P1 |
| F12 | Native E2E и обещания фонового режима не подтверждены — P1, verification gap |
| F13 | Android voice UI подтверждает, но core candidate остаётся pending — P1, подтверждено статически |

Decision IDs (не разрешать молча):

- **D01:** что доказывает account ownership, card→account связь и различие CEF connections; как обозначать unresolved account.
- **D02 — решён 2026-09-06:** пользователь подтвердил корзину без автоочистки, suppression повторного импорта известной удалённой операции и явное восстановление. В будущем delete/restore распространяются через собственный сервер между устройствами Qesto. Локальная реализация и ограничения: `QESTO_TRANSACTION_TRASH.md`; серверная доставка пока отсутствует.
- **D03:** Excel aggregates — cash events или отдельная статистическая база? Как сочетать detail с monthly totals? Нужна ли нескольким оплатам receipt отдельная модель?
- **D04:** что делать с legacy userConfirmed, который мог установить автоматический refresh; консервативно сохранять спорное.
- **D05:** включает ли delete all CEF cookies/PIN/profiles; raw/normalized/tombstone retention.
- **D06:** правила pending/refund/reversal/own external wallet/cash movement и fees; какие суммы входят в Cash Flow.
- **D07:** обещание «фон» — живой/minimized process или закрытое приложение; сейчас только живой app, background saved-PIN login отключён.
- **D08:** разрешение/обезличенные материалы для live Sber completeness: DOM/page cases и независимый row manifest за тот же период/счета.

## 3. Готовность и порядок

Ready-to-spec не означает готовность к безопасному production rollout. Новые регрессионные тесты разрешены только в следующей implementation задаче.

| Stage | Статус | Зависимости |
|---|---|---|
| S01 Matching safety | Ready: hard conflicts/ambiguity; полный account scope условно | D01 для mapping; держать fallback явно unknown |
| S03 Exact money | Ready для существующих two-decimal валют | Сверка money consumers, совместно S04 |
| S04 Field authority | Ready для ограничения auto writer и field patches | S03; D04 для backfill |
| S07 Commit/recovery | Ready | Никаких live data fault tests |
| S09 Cancellation/deletion fencing | Ready для safety; wipe policy условно | S07; D05/D07 |
| S02 Stable source identity | Частично ready, миграция заблокирована решениями | S01/S07; D02/D03, provider evidence |
| S06 Account mapping | Не выпускать без account fixtures/decision | S01/S02, D01 |
| S05 Lifecycle/consumer parity | Ready для stale guard; остальные outcomes условно | S03/S04, D06 |
| S08 Coverage propagation | Ready для partial; полнота gated | S02/S07, D08 |
| S10 Provenance/retention | Частично ready; policy/backfill условно | S02/S04/S07; D02/D04/D05 |
| S11 Validation/aggregates | Ready для hard validation, aggregates gated | S03/S06; D03/D06 |
| S12 Native verification | Готов test plan, нет live разрешения | Предшествующие safety stages, D07/D08 |
| S13 Android voice confirmation | Ready, узкое исправление подключённого потока | Existing core confirmation; S07 для durable failure/retry |

Сначала S01/S03/S04 и S07/S09; не расширять источники поверх unsafe writers. Небольшое partial-status propagation S08 можно выполнить раньше, отдельно от полноценного incremental sync. Этапы должны быть небольшими reviewable изменениями, не одним rewrite PR.

В следующем разделе пути относительно `apps/qesto_app/`. Существующие символы указаны явно. Любые новые types/services — **предложения**, не уже существующая реализация.

## 4. Входы этапов

### S01 — safe matching, без уничтожения самостоятельных покупок

- **Цель/Finding/Priority:** F01 и часть F06, P0. Отделить hard conflicts от similarity; создать неразрушительный исход неоднозначности.
- **Current evidence:** `lib/synoball/reconciliation/deduplication.dart`, `TransactionDeduplicator.findMatch:27`, строки 33–184: provider ID без bank/connection/account scope; fuzzy mismatch account не запрещён; equal score — первый. Core `_reconcile`, `lib/synoball/core/synoball_core.dart:390` применяет результат.
- **Required before/after:** две разные покупки на A/B сейчас могут стать одной; после change остаются две. Два equally plausible N для D не выбираются произвольно. Смена placeholder на подтверждённый account допустима только как доказанное enrichment, не как общий bypass.
- **Reuse/preserve:** core, evidence, existing merchant aliases, source-specific parsing, exact identity fast path с проверкой scope. Не подменять это AI matching.
- **Минимальный scope:** deduplicator constraints/result semantics + controller handling unresolved; provider scope из доступного ingestion metadata. Новый ambiguity result — предложение, не обязательное имя класса.
- **Invariants/edges/tests:** T01–T03/T06/T09; разные users/currencies/accounts; одинаковые provider strings; permutations; ties; unknown accounts; two purchases with same merchant minute.
- **Compatibility/recovery:** не менять canonical IDs и не auto-merge историю; старый key остаётся alias при доказанном scope. Rollout сначала new observations + diagnostics на synthetic corpus.
- **Acceptance:** 0 false merges в T02/T03; все доказанные T01 mappings дают 1 effect; ambiguous никогда не выбирается порядком списка; permutation не меняет количество экономических фактов; returned conflict содержит безопасную причину без raw PII.
- **Non-goals/decisions:** не новый matching framework и не multiuser feature. D01 блокирует полный known-account mapping; количество совпадений не увеличивать ценой неопределённости.

### S02 — identities по источникам и совместимый replay

- **Цель/Finding/Priority:** F02, P0; после S01/S07. Развести transport delivery, source observation version и economic identity.
- **Current:** `UniversalExcelStatementAdapter._draft/_toStatementTransaction`, `lib/features/statement_import/services/universal_excel_statement_adapter.dart:1054–1122`; `SberExtractors._transactionFromRow`, `lib/features/bank_browser/sber/sber_extractors.dart:394–399`; `BankNotificationListener.onNotificationPosted` и `NotificationInbox.save/remove`; Sber/GenericBankScreenshotParser fingerprints/putIfAbsent.
- **Required before/after:** rename Excel больше не равен новому cash effect; новая книга с тем же filename+cell не перезаписывает другой период. Bank sourceId не зависит от меняющегося merchant text. Exact delivery retry не дублирует operation; distinct equal rows сохраняются.
- **Reuse/preserve:** existing parsers, `_reconcile` evidence, fiscal fingerprint, Sber one-to-one compatibility mapping `BudgetController.importSberSnapshot:826–852`. Не удалять legacy aliases до подтверждения безопасного reimport.
- **Scope:** source identity builders, version-aware inbox acknowledgement, observation identity metadata и migration proposal. Для неизвестных source IDs сохранить ambiguity, не создавать глобальный content hash «истину».
- **Tests/edges:** T02/T04/T07/T11–T13/T15/T18: book rename, insert row, file replaced in-place, same SMS notification key update, pending→posted changed display, overlap OCR с двумя равными реальными строками.
- **Compatibility/rollout:** dry-run manifest old→new IDs с причинами/конфликтами; суммы/ownership/count сохранены. Канонические ID сохранить. Cutover versioned, restartable; rollback не должен удалить новые observations.
- **Acceptance:** exact retry: created=0 и duplicate evidence delivery links=0; отдельный known fact никогда не overwrite; все workbook mutations заранее размечены expected identity. Неопределённое отмечено review, не silent collapse.
- **Non-goals/blocked:** не гарантировать dedup любых похожих таблиц. D02/D03 и доказательство scope provider IDs нужны до исторического backfill; без них можно исправлять только новые explicit identities и multiplicity.

### S03 — денежная точность сквозь presentation и edit

- **Цель/Finding/Priority:** F03, P0; ready-to-spec для RUB/USD/EUR/CNY в текущей two-decimal модели.
- **Current:** `lib/synoball/analytics/qesto_read_model.dart`, `_roundedMajor:128`, `_transaction:56`; `QestoLegacyBridge.canonicalFromQesto/_transaction` (`lib/synoball/adapters/qesto_legacy_bridge.dart:93,141`); `BudgetController.importStatement:734–746`, `updateTransaction(s):1569`; `SberExtractors._transactionFromRow:346–352`, `SberTransactionFact`.
- **Required example:** 10025 minor → display 100.25 или округлённая подпись → category-only edit → **10025**, не 10000. Web must retain exact parsed cents. -100 minor balance не отображается как ноль из-за неверной signed rounding.
- **Reuse/preserve:** Money, exactMinorById, receipt.totalMinor, current currencies/formatters; amount formatting — presentation only.
- **Scope:** narrow DTO/projection money plumbing, field update boundaries, Sber extractor/fact precision. Нельзя просто «добавить копейки к UI», сохранив обратную full write.
- **Tests:** T01/T07/T10/T13/T17; fractional/integer/signed boundary values, old snapshots, user category/account edits, same-ID reimport, exact consumer totals в currency.
- **Compatibility/migration:** новый codec field/version только при необходимости, legacy integer major → minor известным ×100. Уже потерянные cents не восстанавливать расчётом; только source evidence/явный reimport.
- **Acceptance:** canonical amount до/после любого не-money edit/replay равен побитово по minor/currency; no float drift; negative balance conversion correct; повторный statement сохраняет exactMinor. Tests use canonical, не только UI round.
- **Rollout/non-goals:** shadow comparison before cutover, recovery snapshot. Не строить FX ledger/поддержку всех ISO exponents без отдельного scope; не обещать этим исправить всю историю Cash Flow.

### S04 — user patches и source field authority

- **Цель/Finding/Priority:** F04, P0; совместно S03.
- **Current:** controller `importStatement` вызывает core.updateTransaction через legacy bridge для matched IDs; bridge ставит userCategoryOverride и userConfirmed. Core merchant/time rank отдельно от fieldTrust (`synoball_core.dart:454–525,675–746`). Nullable `CanonicalTransaction.copyWith` не выражает clear для большинства полей (`models.dart:678–730`).
- **Required example:** user category «Поездки», исправленная дата и название → source refresh меняет providerDescription → canonical user fields сохранены, observation обновлён; automatic fields не получают userConfirmed. Намеренный clear override отличается от «поле не передано».
- **Reuse/preserve:** userCategoryOverride, qestoManualCategoryTag, source trust policy, audit purpose, Sber manual-category regression. Сохранить возможность enriching missing data.
- **Scope:** убрать auto-import full-object user edit; patch только выбранных пользователем полей; field precedence/clear semantics; importer correction не masquerades как user action.
- **Tests:** T05/T07/T10/T18, оба порядка edit/sync; receipt explicit link; bulk category edit; update same manual category; empty/null/clear.
- **Compatibility:** legacy bridge нужен startup/undo migration, не удалять без replacement. Старые userConfirmed неоднозначны; сохранять до D04, не массово сбрасывать confidence.
- **Acceptance:** T10 все user fields сохранены после reload, новых raw/evidence не потеряно; auto import audit не userConfirmed; у category-only edit нет изменений Money/account/time; clear можно проверить отдельно.
- **Rollout/non-goals/blocked:** narrow writer cutover before reclassification. Не создавать систему глобального обучения категорий; historical authorship repair заблокирован D04.

### S05 — lifecycle и один смысл операции у consumers

- **Цель/Finding/Priority:** F05, P1; после S01/S03/S04.
- **Current files/symbols:** `SynoballCore._statusFromCandidate/_reconcile`; `QestoReadModelService._transactionType`; `CashFlowCalculationService.treatment`; `SynoballAnalyticsReadService.cashflow`; `BudgetController._applySberAdapterCompatibility`. Старые pending/type tags могут противоречить current status, разные consumers их читают по-разному.
- **Required example:** known posted Q + stale P остаётся posted; обновление статуса не оставляет активный pending exclusion. Separate refund/fee не duplicate исходного expense. Own transfer с подтверждённой принадлежностью не external income/outflow.
- **Reuse/preserve:** текущие statuses, tags как provenance там, где не active semantics, shared CashFlowCalculationService. Не удалять Sber compatibility до доказанной замены.
- **Scope:** monotonic/freshness rules, exclusive current flags, единый treatment для projection/analytics; compare current consumer calculations на synthetic fixtures.
- **Tests/acceptance:** T04–T06/T16/T18; все existing consumers дают одинаковый net в minor для одного range/currency; stale source не меняет confirmed lifecycle; pending/reversed не учитываются по старым tags.
- **Compatibility/recovery:** legacy tags переводить в current semantics только при однозначности, ambiguous cases оставить review. Финансовые summaries до/после входят в migration diff, а не молча меняют итоги.
- **Non-goals/decisions:** не банковский settlement engine. D06 определяет refund/reversal/cash/wallet нюансы, но stale downgrade guard можно специфицировать сразу.

### S06 — account/card/connection mapping

- **Цель/Finding/Priority:** F06, P1, необходим для безопасного расширения F01.
- **Current:** `TransactionAccountResolver.resolve` в `lib/features/transaction_import/services/transaction_account_resolver.dart:21`; `BudgetController.importSberSnapshot/_reconcileSberAccounts:786,1080`; `StatementImportScreen._importSelected:157`. Web unresolved → first account, PDF и web IDs разных namespaces; при импорте web profile scope не передаётся.
- **Required example:** PDF и web одного установленного физического счёта обновляют один balance/account alias; другая карта того же account не добавляет второй капитал. Unknown/card conflict → unresolved/review, не привязка к единственной неподходящей карте другого банка.
- **Reuse/preserve:** linkedCardLastFours, suffix-aware account merge, resolver. Safe explicit mapping может быть минимальным решением; название/баланс не identity.
- **Scope:** передать connection/institution identity, сохранить source account alias relationship, remove arbitrary fallback; unknown UI path без потери parsed operation.
- **Tests:** T03/T07/T14/T16/T17; same suffix across banks/profiles, two savings same name, account with two cards, no products found, PDF+web.
- **Acceptance:** known balance не удваивается; операции принадлежат правильному owner/account; contradictory hints никогда не autoassign first; current account merge test сохраняет 2 transactions.
- **Compatibility/cutover/recovery:** read-only account mapping preview, preserve canonical account IDs где возможно, repoint всех ссылок согласованно; old alias stored, rollback plan. Не объединять только по строке lastFour без остальных доказательств.
- **Blocked/non-goals:** D01 и обезличенные account relationships требуются для полной спецификации. Не семейные финансы и не подключение новых банков.

### S07 — durable ingestion outcomes и recovery

- **Цель/Finding/Priority:** F07, P0, ready-to-spec.
- **Current files/symbols:** `LocalQestoRepository.getUserFinancialData/saveUserFinancialData/deleteUserFinancialData` (`lib/data/repositories/local_qesto_repository.dart:34,55,74`); `_readAll/_writeAll` (`lib/data/persistence/local_key_value_store_io.dart:38,60`); `UserFinancialDataCodec.decode`; `SynoballCore.ingest`; `BudgetController._changed`; `AutomaticNotificationImporter._drainOnce`.
- **Required example:** bad/unsupported schema → recoverable error/read-only, оригинал не перезаписан пустотой. Save failure → no success/ack; after snapshot committed before ack → retry не теряет/не повторяет effect. Candidate failure не выглядит successful empty result.
- **Reuse/preserve:** encrypted store + secure key storage, snapshot codec, write chain/backup, importer await-before-ack. Backend replacement не prerequisite.
- **Scope:** explicit committed/rejected/failed outcomes, fail-closed load, deterministic snapshot replace/recovery; isolate mutable state vs committed view настолько, насколько требуется для truthful UI/ack.
- **Tests:** T08/T09/T14/T17/T18; реальная временная директория, injected errors/interruptions на каждом write/rename boundary, backup-only recovery, second crash during recovery, failed candidate, unsupported future schema.
- **Acceptance:** ни один ack не относится к uncommitted/failed record; не менее одного validated snapshot восстановим на каждом crash boundary; codec error не вызывает empty autosave; failed batch records можно повторить; UI отражает failed save.
- **Compatibility/rollout:** в isolated copy доказать старые encrypted blobs читаются; new schema version только при необходимости; no irreversible upgrade before backup validation. Recovery не читает/публикует PII в logs.
- **Non-goals/decisions:** не обещать exactly-once distributed processing; local durable correctness достаточно. Выбор SQL обсуждать только по результатам prototype/fault tests; не внедрять автоматически.

### S08 — честная completeness и checkpoint

- **Цель/Finding/Priority:** F08, P1. Partial propagation ready; доказательство live полноты gated.
- **Current:** `SberExtractors.transactions` (`lib/features/bank_browser/sber/sber_extractors.dart:60`), `SberConnector.sync:46` создают boundary/counters/partial. `SberBackgroundSyncRunner.run:82–102` и manual closure desktop page:1075–1110 возвращают success на непустом partial. `BankSyncManager._complete:270` сохраняет success time.
- **Required example:** 10 accepted + hasMore=true/boundary=false → данные допустимо сохранить как partial, но статус/coverage остаются partial; lastSuccessful full coverage не сдвигается. Valid empty range и broken parser различаются.
- **Reuse/preserve:** already collected rows/reward/service/rejected/load-more counters, user period picker, gradual scroll. Не заменять CEF или парсер количеством scrolls «с запасом».
- **Scope:** report→result→metadata→UI propagation, reason-of-stop, requested/observed/covered range; incremental overlap contract после stable identity. Counters reflect post-commit outcomes, а не только preimport projection diff.
- **Tests:** T08/T14/T15; gap/slow-load/hasMore timeout/old late record/equal timestamps, dashboard fallback, partial saved + restart.
- **Acceptance:** каждый non-full scenario виден как partial/error до UI/checkpoint; нет invented full coverage; seen/accepted/rejected/excluded/new/updated/unchanged explainable без двойного подсчёта Спасибо как money. Для known fixture каждая денежная строка сопоставляется row manifest, не просто «не меньше N».
- **Compatibility/recovery:** legacy newest-seen marker не называть covered cursor. Не auto-reimport всю историю пользователя; диапазон recovery explicit. Current balance сохраняется отдельно от cash-flow net.
- **Non-goals/blocked:** не подгонять net под баланс. D08/отдельное read-only разрешение нужны до заявления «актуальный Сбер полностью проверен».

### S09 — stop/cancel/delete fencing и profile writes

- **Цель/Finding/Priority:** F09, P0 (R); ready-to-spec safety mechanisms, no live fault injection.
- **Current:** `BankSyncManager.runBackground:72/runManual:176` в `lib/features/bank_browser/sync/bank_sync_manager.dart`, timeout/finally:124–217; `CancellableBankBackgroundSyncRunner`; `SberBackgroundSyncRunner.cancel`; `BrowserProfileManager._writeProfile/openProfile/updateLastKnownUrl`; `QestoApp` loader `_deleteAllData`; shell dispose.
- **Required example:** timed-out run возвращает delayed result после нового run/wipe → никаких финансовых writes, ack, notifications или checkpoint от старого поколения. Metadata changes не теряют соседний field. Если native close ещё владеет writable profile — новый runner не открывает его.
- **Reuse/preserve:** manager locks, cancellable runner interface, profile metadata and schedule retry policy. Не отключать security/allowlist ради надёжности.
- **Scope:** proposed operation generation/fence перед mutable effects; cancellation propagation; сериализованный profile read-modify-write и recoverable file replace; deletion barrier; single-instance policy или process lock для нескольких процессов.
- **Tests:** T08–T11/T17, delayed fake после timeout; cancel throws/times out; two metadata writers; delete while save in flight; app resume loader replacement; close/open shared profile.
- **Acceptance:** после terminal cancel/delete ни одного accepted write от старой операции; после two updates все непересекающиеся metadata fields сохранены; profile.json recovery доступно после interrupt; repeated cleanup idempotent; existing mutual-exclusion/schedule tests pass.
- **Compatibility/cutover:** новая generation metadata с безопасным default, stale work never trusted. Rollback без unsafe scheduler replay. Данные bank sessions не стирать при простой смене версии.
- **Non-goals/decisions:** D05 задаёт состав wipe; D07 — закрытое приложение. Не добавлять OS daemon/saved-PIN automation как побочный эффект fixes.

### S10 — observation provenance и политика replay

- **Цель/Finding/Priority:** F10, P1; после S02/S04/S07.
- **Current:** `SourceEvidence`, `TransactionCandidate`, `IngestionRecord`, `RawPayload` (`lib/synoball/core/models.dart`); core `_reconcile:537–562`; `StatementImportScreen:108–114` сохраняет Excel metadata, controller web import:1030–1034 — IDs. Exact provider replay не связывает новый ingestion с прежним evidence.
- **Required example:** повтор **доставки** не множит evidence, новая version observation сохраняется и объясняет изменение canonical; known parser replay воспроизводим либо явно unsupported из-за удалённого raw. observed time не подменяется временем покупки.
- **Reuse/preserve:** существующий graph, adapter version, redacted screenshot policy, audit events. Новые поля минимальны, названия/формат должны быть утверждены отдельным spec.
- **Scope:** resolved candidate/observation→canonical link, source row reference/parser version, delivery dedup vs version update; retention/replay protocol.
- **Tests:** T01/T07/T11/T13/T17/T18; same provider revised fields, partial raw cleanup, user edits, receipt items vs multiple payment relation.
- **Acceptance:** для каждого automatic change определим source observation; every terminal candidate имеет объяснимый результат; exact delivery replay не множит links; raw-unavailable replay явно отказан; logs/exports no secrets.
- **Compatibility/rollout:** legacy graph помечается incomplete, не выдумывается; optional fields back-compatible; retention cleanup только после recovery/tombstone policy. Сначала mapping dry-run, затем release.
- **Non-goals/blocked:** не полное event sourcing и не бесконечное хранение DOM/выписок. D02/D04/D05; невозможно восстановить не сохранённые ранее web rows/Excel bytes без отдельного импорта.

### S11 — hard validation и aggregate-aware consumers

- **Цель/Finding/Priority:** F11, P1; часть ready, aggregate expected results требуют решения.
- **Current:** `_TransactionAdapter.validate`, `lib/synoball/adapters/adapters.dart:28–45`; Money.fromJson; `SberBankScreenshotParser.parse:68–105`; Excel `_draft/_toStatementTransaction`, `StatementImportScreen._importSelected` aggregate/capital tags.
- **Required example:** invalid account/currency/date → record reject/review, не ложная canonical. Missing screenshot date/amount → clearly inferred and confirmed, не silently factual today/balance delta. Monthly groceries total плюс receipt details не удваивает cashflow без выбранной coverage policy.
- **Reuse/preserve:** Excel ZIP/resource limits, parser confidence, preview selection/edit, tags/date precision, receipts items.
- **Scope:** common canonical validation и source-quality flags, aggregate statistical coverage treatment. Уточнение raw parser fields допустимо, но money/account policy общая.
- **Tests:** T06/T13/T14/T16–T18; zero/negative/invalid ISO, invalid day rollover, unknown date, balance delta across different accounts/gapped rows, summary+detail same month, capital allocations.
- **Acceptance:** unsupported/invalid inputs не silent success; known detail records сохранены; aggregate не искажает daily rhythm/merchant count; exact period totals совпадают с размеченным ground truth по policy. Нет automatic reserve balance из суммы всех transfer inflows без указания, что это оценка.
- **Compatibility/rollout:** старые aggregate tags позволяют identify affected records, но не auto-delete их. Migration reports classification and totals changes, recovery snapshot retained.
- **Non-goals/blocked:** не новый investment/debt roadmap; D03/D06 решают экономический смысл. Не навязывать expected net для неоднозначной пользовательской таблицы.

### S12 — native verification и честные продуктовые гарантии

- **Цель/Finding/Priority:** F12, P1; существующие mock tests сохранить, добавить реальные acceptance gates в будущей задаче.
- **Current:** 324 tests pass; importer test не имеет repository callback; Android file store использует общую HOME/currentDirectory ветку; native 7 opt-in tests skipped. Runtime/background flags в `lib/app/qesto_app_shell.dart:107–113`; notification pipeline в Kotlin + `automatic_notification_importer.dart`; native OCR/speech bridges и `test/windows_native_bridges_test.dart`.
- **Required example:** synthetic financial notification → настоящий native inbox → controller → actual durable app-private store → kill/restart → одна canonical. Off-device/closed-app ограничения объяснены. Background CEF не считается проверенным только по fake runner.
- **Reuse/preserve:** тестовый corpus, scripted browser tests, native scanner/voice tests, real package bridges; не заменять unit tests live tests.
- **Scope:** device/test-harness execution и fixtures, safe file-path verification, restart/access revocation; отдельная live-read сессия только после permission.
- **Tests:** T08/T12–T15; Android allow/revoke access, cold start, process death, queue full/TTL, microphone unsupported/on-device model absent; Windows native PDF/OCR/Whisper temporary synthetic files; CEF hidden→auth-required→user reauth→sync.
- **Acceptance:** published matrix passed/failed/skipped с host/version и exact assertions; no unverified 'all sources integrated'; native data survives restart and isolation; no real credentials in logs. Live Sber success — только с independent per-row manifest и equal range/accounts.
- **Compatibility/recovery:** если требуется перенос Android store path, сначала locate/validate old data и recoverable migration, не fresh empty store. Не запускать destructive crash тесты на профиле пользователя.
- **Non-goals/blocked:** OS-level always-on sync и изменение bank auth flow — отдельные решения D07. D08/явное разрешение нужны для банка; до этого только synthetic fixtures.

### S13 — довести Android voice confirmation до canonical posting

- **Цель/Finding/Priority:** F13, P1, ready-to-spec. Устранить конкретное расхождение UI-success и отсутствующего денежного факта, не заменять speech engine.
- **Current/evidence:** `lib/features/voice_transaction/presentation/voice_transaction_confirmation_sheet.dart:135–166` → `BudgetController.addImportedTransactions:590–641`. `confirmedVoiceInput` выбирает VoiceInputAdapter; `confirmedInPreview` записывается только в raw metadata. Адаптер `lib/synoball/adapters/adapters.dart:148–174` сохраняет requiresConfirmation=true; core pending branch `lib/synoball/core/synoball_core.dart:157–163` не создаёт canonical. Controller не подтверждает candidate, UI всё равно получает success.
- **Required:** подтверждение пользователем в Android preview вызывает ровно одно существующее core confirmation с проверкой результата и сохранения. Только после успешного сохранения UI сообщает о добавлении. При failure — явная ошибка и безопасный retry, без второго неочевидного подтверждения.
- **Reuse/preserve:** VoiceInputAdapter, core `confirmCandidate`, controller `confirmVoiceCandidate`, source type manualVoice и audit/evidence. Desktop `addVoiceCandidate` → confirm остаётся pending до явного действия пользователя. Не снимать requiresConfirmation со всех voice inputs.
- **Scope/tests:** T12; расширить `test/widget_test.dart` и controller voice tests: Android save проверяет canonical/evidence/amount/category и отсутствие pending, reload сохраняет эффект; повтор доставки command не создаёт дубль; failure не выдаёт success. `test/voice_input_flow_test.dart` сохраняет desktop semantics. Сейчас Android widget проверяет только строку «Операция добавлена».
- **Acceptance:** одна подтверждённая фраза — одна сохранённая операция и один денежный эффект. Отмена preview — ноль; неподтверждённый desktop candidate не публикуется. Success text не заменяет проверку финансового состояния.
- **Compatibility/recovery:** schema redesign не нужен. Уже накопленные pending candidates не подтверждать массово и не удалять; отдельно предложить пользователю review. Retry/commit общий контракт согласовать с S07.
- **Non-goals:** новый voice AI, фоновые записи микрофона, автоподтверждение неотредактированных распознаваний, изменения native permissions.

## 5. Общие acceptance / cutover правила для будущего spec

- Каждый stage начинает с воспроизводимого synthetic regression и evidence текущей ветки; тесты не должны закреплять false merge как желательное поведение.
- Для сравнения использовать canonical count/IDs + minor sums по currency/status/direction + evidence links + user edits + account ownership. UI integer totals недостаточны.
- Сначала dry-run на изолированной копии. Исторические данные не трогать без mapping/rollback и разрешения, особенно corrupted JSON, tombstones, missing raw и ambiguous userConfirmed.
- Сохранять оригинальные документы/last-known-good encrypted snapshot; никакого «очистить всё, чтобы тест прошёл».
- Любые proposed new schema fields versioned/back-compatible; unsupported newer schema не перезаписывать. Старый EXE не запускать поверх несовместимой схемы как rollback.
- Новая автоматика не включается до safe matching/write/cancel constraints. Не делать Git push/PR/build/install из одного этого документа: запросить/получить отдельную задачу реализации с выбранными этапами.
- Результат каждой реализации: что изменено, что подтверждено execution, что осталось static-only/blocked, affected IDs/amount invariants, migration/cutover plan. Честное partial лучше недоказанного complete.

## 6. Центральная проверка результата

Следующий исполнитель должен суметь показать **оба** результата на одной версии:

1. Один ground-truth расход из notification/SMS/web/statement/receipt/screenshot при повторной доставке не даёт второй экономический эффект, сохраняет source evidence и пользовательские edits.
2. Две ground-truth самостоятельные покупки с одинаковыми суммой/merchant/временем не исчезают ни в source parser, ни в matcher, ни при reimport.

Если для конкретного варианта identity недостаточна, правильный результат — объяснимая неоднозначность и безопасный review, а не обещание автоматически угадать.
