# A. Repository Audit

08.10.2026 · Qesto 1.0.68+69 · исследование без изменения приложения.

## 1. Границы и метод

Изучены production-код Flutter, модели, repository/persistence, контроллер финансов, Synoball ingestion/reconciliation/read models, Android notification inbox, банковский runtime и существующий backend. Наличие классов не принималось за доказательство готового сетевого сервиса. Название каталога `mocks` также не принималось за доказательство использования mock-хранилища: например, там лежат рабочие defaults пустого профиля и справочник системных категорий.

Рабочая ветка уже содержит изменения прежних задач. Они сохранены. Не запускались банковская синхронизация, миграция реального профиля, загрузка финансов на сервер, сборка или установка новой версии. Содержимое пользовательских банковских секретов не читалось.

Ссылки ниже ведут на текущие файлы workspace; номера строк соответствуют состоянию на дату аудита.

## 2. Фактическая архитектура

```text
Desktop presentation / Mobile presentation
                  │
          общий BudgetController
                  │
       Synoball + capital/planning models
                  │
        UserFinancialData + codec v7
                  │
       LocalQestoRepository.save snapshot
                  │
 AES-GCM envelope → RecoverableJsonFile → store.json
```

Flutter/Dart — общая кодовая база Windows и Android. [pubspec.yaml](../../../apps/qesto_app/pubspec.yaml) содержит `http`, `cryptography`, `flutter_secure_storage`, парсеры и vendored `webview_cef`. Зависимости клиентской SQLite/Drift или готового financial sync отсутствуют. Версия Dart constraint — `^3.12.2`.

[QestoApp](../../../apps/qesto_app/lib/app/qesto_app.dart) по умолчанию использует `LocalQestoRepository`; загрузка приложения объединяет финансовый профиль, конфигурацию и публичные deals. [QestoAppShell](../../../apps/qesto_app/lib/app/qesto_app_shell.dart:55) создаёт общий `BudgetController`; callback [_saveFinancialData](../../../apps/qesto_app/lib/app/qesto_app_shell.dart:131) сохраняет `controller.mergeInto(...)` в repository. Разные mobile/desktop pages не означают разные финансовые БД.

На resume выполняются локальная обработка notification inbox, desktop bank scheduler и обновление публичных deals. Межустройственного финансового pull здесь нет.

## 3. Хранение: что гарантировано и чего нет

| Уровень | Реальная реализация | Гарантия / ограничение |
|---|---|---|
| Repository | [LocalQestoRepository](../../../apps/qesto_app/lib/data/repositories/local_qesto_repository.dart:11), ключ `qesto.user-financial-data.v1` | Чтение/запись целого профиля; последовательная `_pendingSave` в процессе; при невалидной загрузке save запрещён |
| Codec | [UserFinancialDataCodec](../../../apps/qesto_app/lib/data/persistence/user_financial_data_codec.dart:9), версия 7 | Decode старых поддержанных версий; будущая версия отвергается, не превращается в пустой профиль |
| Шифрование | [EncryptedLocalKeyValueStore](../../../apps/qesto_app/lib/data/persistence/encrypted_local_key_value_store.dart:36) | AES-GCM-256, random nonce, storage key как AAD; master key через `FlutterSecureStorage`; не E2EE |
| Файл | [RecoverableJsonFile](../../../apps/qesto_app/lib/data/persistence/recoverable_json_file.dart:6) | Flush staged file, backup, rename, recovery, process queue и file lock; это не entity OCC и не SQL unit of work |
| Native path | [local_key_value_store_io.dart](../../../apps/qesto_app/lib/data/persistence/local_key_value_store_io.dart), [android_store_location.dart](../../../apps/qesto_app/lib/data/persistence/android_store_location.dart) | Windows `%APPDATA%/Qesto/store.json`; Android app-private `filesDir/Qesto/store.json`, безопасное разрешение пути |
| Web | [local_key_value_store_web.dart](../../../apps/qesto_app/lib/data/persistence/local_key_value_store_web.dart) | `localStorage`; нельзя переносить на него native transaction guarantees |
| Theme | [app_appearance_controller.dart](../../../apps/qesto_app/lib/core/theme/app_appearance_controller.dart) | Отдельная локальная UI-настройка |
| Public cache | Repository + DealsApi | Отдельный несекретный кэш предложений; не финансовый sync |

File lock защищает замену файла, но не доказывает отсутствие lost update, если два писателя построили снимки из устаревшего состояния. Backup проверяет целостность внешнего JSON; криптографическая/логическая проверка финансового содержимого происходит следующим уровнем.

`QestoRepository.saveUserFinancialData` имеет default no-op в [базовом интерфейсе](../../../apps/qesto_app/lib/data/repositories/qesto_repository.dart:10). Production override есть, но при введении нового repository необходимо сделать гарантии сохранения обязательными и проверять реализацию, а не считать интерфейс уже транзакционным.

## 4. Точки записи и готовность модулей

Главная точка бизнес-изменений — [BudgetController](../../../apps/qesto_app/lib/features/budget/state/budget_controller.dart). [_changed](../../../apps/qesto_app/lib/features/budget/state/budget_controller.dart:522) ждёт callback сохранения и затем уведомляет UI. Однако многие команды меняют in-memory state **до** ожидания save. Универсальной staged mutation/rollback/атомарной outbox-записи нет.

| Flow | Метод / участок | Что фактически меняет |
|---|---|---|
| Выписки | `importStatement`, около 754 | Staged Synoball import с проверками, затем публикация и сохранение профиля |
| Сбер | `importSberSnapshot`, около 950 | Account facts, точные суммы и bank evidence через существующий pipeline |
| Ручной ввод | `addExpense`, около 1605 | ManualInputAdapter → canonical transaction; draft ID помогает retry |
| Уведомление/SMS | `addNotificationTransaction`, около 1709 | Direction/type/exact minor units, source evidence; native ACK после успешного save |
| Чек / голос | Участки 1930 / 1956 | Adapter ingestion / candidate confirmation, не отдельный финансовый store |
| Правки операции | Участки 2074 / 2104 и classification part | Synoball update, ручные locks/override, category scope/rule |
| Бюджет | `setCategoryBudget`, `setTotalBudget`, около 2143 / 2168 | Period/category plans |
| Счёт | `addAccount`, около 2222 | Сохранённый баланс и canonical account; не пересчёт баланса от каждого transaction event |
| Корзина | Участок 2261 | Explicit delete/restore команды Synoball |
| Цели | Участки 2389 / 2641 | Goal, allocation, contribution/history и агрегаты цели |
| Инвестиции | Участки 2676 / 2768 / 2790 | Metadata, canonical account, balance snapshot, contribution |
| Долги | Участки 2891 / 3030 / 3064 | Metadata, snapshots, archive, payment; payment сам по себе не новый банковский расход |
| Planned expenses | Участок 3073 | Create/update/delete upcoming items, отдельно от наблюдённых операций |
| Очистка | `clearAllFinancialData`, около 2295 | Локальная очистка агрегата; нельзя автоматически превратить в global cloud delete |

Модули реально существуют и связаны с общим сохранением. Их совместное редактирование на нескольких устройствах, серверная валидация и HTTP-auth **не реализованы**. `_actions` ограничен 50 элементами и содержит local undo, не полный журнал команд.

## 5. Матрица сущностей и первичности

Хранение всех финансовых строк таблицы ниже сейчас — единый codec-снимок, если не указано иное. `sync` означает будущую необходимость, не текущую возможность.

| Сущность / модель | ID и lifecycle сейчас | Источник изменений / риск | Рекомендация |
|---|---|---|---|
| [QestoUser](../../../apps/qesto_app/lib/data/models/qesto_models.dart:82) | `id`; defaults `local-user`; нет login/revision | Profile preferences; collision между установками | Sync профиль; отделить auth subject, workspace и legacy user ID |
| [SynoballAccount](../../../apps/qesto_app/lib/synoball/core/models.dart:304) + [QestoAccount](../../../apps/qesto_app/lib/data/models/qesto_models.dart:113) | ID/external ID, balance; нет универсального observedAt/revision | Bank/manual balances; stale update | Sync primary account facts; QestoAccount — projection, не второе изменение |
| [CanonicalTransaction](../../../apps/qesto_app/lib/synoball/core/models.dart:631) | ID, createdAt/updatedAt, pending/posted/reversed/deleted | Manual/source edits; опасные amount/currency/type conflicts | Sync canonical + override/locks + lifecycle + evidence; server revision sidecar |
| [SourceEvidence](../../../apps/qesto_app/lib/synoball/core/models.dart:824), ingestion/candidates/importBatch | Локальные IDs/provider identity/status | Два источника одной покупки; ambiguous candidates | Sync минимально достаточный provenance и review state; core решает reconciliation |
| RawPayload / receipt originals | Raw body и local refs | Содержат PII; unredacted допустим в модели | Полные оригиналы локально по умолчанию; минимальные parsed proof/receipt facts отдельно |
| Системные категории | Стабильный code справочника | Версии справочника | Versioned config, не копировать как пользовательские новые категории |
| Custom categories/rules/tags/redirects | ID и поля policy, нет общего revision | Merge/delete + массовые overrides | Sync; related policy changes как logical atomic unit |
| [BudgetPeriod](../../../apps/qesto_app/lib/data/models/budget_models.dart:52), CategoryBudget | Локальные/deterministic IDs; category-budget связан с period/category | Совпавший ID ещё не доказывает одинаковый план | Sync plans; reconcile logical keys явно; derived summaries не sync |
| Account preferences | AccountRef, reserve roles и отображение | Один и тот же account на разных devices | Sync финансовые preference; local layout не sync |
| [SavingsGoal](../../../apps/qesto_app/lib/data/models/qesto_models.dart:318), allocations/contributions/history | IDs, даты, references; contribution + savedAmount | Concurrent additive intent / duplicate command | Sync goal aggregate и события с idempotency; не складывать contribution второй раз |
| [DebtAccount](../../../apps/qesto_app/lib/data/models/debt_models.dart:45), snapshots/payments | IDs, created/updatedAt, linkedAccount | Metadata и canonical balance должны согласоваться | Sync вместе; прогноз долга derive |
| [InvestmentAccount](../../../apps/qesto_app/lib/data/models/investment_models.dart:37), snapshots/contributions | IDs, linkedAccount, balance time/source | Две версии account/meta и contribution | Sync atomic related facts; return/forecast derive |
| UpcomingExpense / planned points | IDs/period refs; план, не банковский факт | Concurrent edits / удаление | Sync планы отдельно; не превращать в observed transaction |
| Recurring streams, Cash Flow, liquidity charts | Derived from primary financial state | Different core/config version | Пересчитывать; version parity, не синхронизировать готовые итоги |
| FinancialAction / Synoball events/audit | Local history IDs/time | Не complete replay log / нет ACK | Local undo/diagnostics; отдельный server audit и outbox |
| TrackedProducts | Пользовательские tracked records | Независимое preference | Можно sync после финансового MVP; public offers/cache не sync |
| CEF profile, PIN, cookies, native inbox | Device-private storage | Secrets/permission/native delivery state | Только local; финансовый результат inbox может sync после local commit |
| Theme, route/scroll selection | Local settings/state | Нет финансового конфликта | Local; expenseDisplayCurrency — отдельно sync user preference |

`UserFinancialData` хранит и canonical state, и legacy/UI projections ([модель](../../../apps/qesto_app/lib/data/models/qesto_models.dart:487)). Bootstrap не должен импортировать обе копии как два набора операций. Если canonical присутствует — он источник транзакций/счетов, projections проверяются и перестраиваются. Остальные planning/capital entities не объявляются производными только потому, что находятся вне Synoball.

## 6. Деньги и финансовые расчёты

[Money](../../../apps/qesto_app/lib/synoball/core/models.dart:97) использует integer minor units, JSON `value` — decimal string, сейчас два знака. QestoAccount/BudgetTransaction имеют legacy whole-unit и optional exact minor fields. Ряд budget/goal/debt/investment полей хранится в целых основных единицах. Новый transport обязан **сохранить фактическую точность каждого поля**, не округлять копейки через `double` и не повышать точность несуществующих исходных значений.

[AccountCapitalService](../../../apps/qesto_app/lib/features/capital/domain/account_capital_service.dart:171) строит read-only историю от сохранённого текущего баланса назад по операциям. Баланс — самостоятельный anchor, не сумма автоматически применённых incoming events. [Cash Flow service](../../../apps/qesto_app/lib/features/budget/services/cash_flow_calculation_service.dart) использует status, direction/type и transfer semantics. Собственные переводы не являются расходом/доходом; не меняем эту логику ради transport.

Sync должен upsert состояние/наблюдение, а не выполнить `balance += transaction.amount` при каждом получении. Норма накопления, категории, «Река денег», recurring и история ликвидности остаются read models.

## 7. Synoball: переиспользуемый pipeline и ограничения identity

```text
Source → existing Adapter → candidate/normalization
       → TransactionDeduplicator → canonical transaction + evidence
       → BudgetController projection → codec snapshot → UI
```

- [SynoballCore.ingest](../../../apps/qesto_app/lib/synoball/core/synoball_core.dart:180) ведёт records/raw/candidates/accounts, batch conflicts и review; неоднозначность не выдаёт за успешное merge.
- [TransactionDeduplicator](../../../apps/qesto_app/lib/synoball/reconciliation/deduplication.dart:28) проверяет stable canonical/provider identity с source/institution/connection/account scopes. Manual/legacy inputs не объединяются только по тексту/сумме/времени. Cross-source matching ограничен совместимостью и batch ambiguity.
- [qesto_legacy_bridge.dart](../../../apps/qesto_app/lib/synoball/adapters/qesto_legacy_bridge.dart:93) сохраняет `user-field:*` locks и category override. Автообогащение не должно стирать эти признаки.
- [deleteTransaction](../../../apps/qesto_app/lib/synoball/core/synoball_core.dart:591) оставляет deleted transaction и evidence; restore отдельный explicit command. Повторный source import не должен оживлять trash.
- [notification_identity.dart](../../../apps/qesto_app/lib/synoball/adapters/notification_identity.dart) отделяет notification OS slot от экономической операции. Для legacy identity часть алгоритма читает package/key из raw payload. Минимизация sync payload должна сохранить необходимые allowlisted proof-поля, иначе «тот же алгоритм» перестанет давать тот же результат.
- [source_identity.dart](../../../apps/qesto_app/lib/synoball/adapters/source_identity.dart) создаёт SHA-256 identity; hash не является надёжной анонимизацией чувствительных low-entropy данных.
- [SynoballIdFactory](../../../apps/qesto_app/lib/synoball/ingestion/adapter.dart:61) использует время/локальные sequence. [entityIdFor](../../../apps/qesto_app/lib/synoball/adapters/qesto_legacy_bridge.dart:10) строит `ent-$userId`. Это не доказательство глобальной уникальности.
- [SynoballState](../../../apps/qesto_app/lib/synoball/core/models.dart:1163) schema v1, model v1.0.0; `events` timestamp-based, без последовательного commit cursor и network receipt. Не использовать как outbox.

Конкретный риск phone notification + desktop statement: они могут иметь разные local account/connection IDs, и это **намеренно** влияет на match. Нужны явные workspace account/source bindings и aliases с сохранением provenance, а не новый amount/time deduplicator или снятие всех scopes.

Core/reconciliation/ingestion в основном pure Dart; можно выделить shared package для client/server после compile/parity проверки. `BudgetController` Flutter-зависим: его нельзя просто перенести на server. [SynoballApiV1](../../../apps/qesto_app/lib/synoball/api/v1/synoball_api_v1.dart:7) — in-process facade, не authenticated HTTP backend; OpenAPI draft не даёт авторизацию или commit-log.

## 8. Platform, auth и network

[AutomaticNotificationImporter](../../../apps/qesto_app/lib/features/notification_import/services/automatic_notification_importer.dart:34) single-flight; сохраняет результат до ACK delivery revision. Android [NotificationInbox.kt](../../../apps/qesto_app/android/app/src/main/kotlin/ru/qesto/qesto/NotificationInbox.kt) — encrypted native SharedPreferences/Keystore, ограниченный inbox, не общая финансовая SQL-БД. Его ACK и будущий SQL commit — разные хранилища; безопасен порядок commit → ACK с retry, не фиктивная cross-store transaction.

[BrowserProfileManager](../../../apps/qesto_app/lib/features/bank_browser/data/browser_profile_manager.dart) хранит device-local browser metadata/cache; [SberPinVault](../../../apps/qesto_app/lib/features/bank_browser/sber/sber_auth_manager.dart:11) использует secure storage profile-qualified key. Их не переносим между устройствами. Банковская авторизация не является авторизацией пользователя Qesto.

[services/deals_ingestion](../../../services/deals_ingestion/README.md) — Python HTTP server + SQLite для публичных offers, с loopback API и служебным `/sync`. Наличие SQLite здесь не означает клиентскую financial database. Этот backend нельзя открыть для приватного sync, сменив только URL. `QESTO_DEALS_API_URL`/loopback HTTP нужны текущему публичному flow, не являются допустимым remote financial endpoint.

Open Banking OAuth/FAPI scaffolding — отдельный, disabled/fake bank layer. Qesto account auth, device enrollment/revocation, private sync API, server OCC/outbox/log/cursors и financial dev/staging/prod окружения в исследованном коде отсутствуют.

## 9. Проверки и доказательства

На 08.10.2026 выполнены существующие тесты:

```text
user_financial_data_codec_test.dart
encrypted_local_key_value_store_test.dart
storage_recovery_safety_test.dart
transaction_trash_test.dart
synoball_core_test.dart
statement_reconciliation_test.dart
reconciliation_batch_test.dart
notification_identity_test.dart
automatic_notification_importer_test.dart
Итог: 63 passed, exit 0.
```

Они проверяют round-trip, fail-closed storage, recovery stages, deleted replay, exact cents, неоднозначный batch matching и ACK retry. **Не** проверяют cross-device identity, proposed server transactions, cursor или авторизацию. Полный suite/analyze/build не запускались: текущий deliverable — архитектура, production code не менялся.

SHA-256 361 source/config файла до/после исследования совпали. SDK потребовал разрешения на служебный lockfile для тестов; зависимости приложения не изменились. Тесты используют test stores/fixtures, не реальный профиль.

## 10. Неизвестные и обязательные дальнейшие проверки

1. Реальные объёмы/распределение профилей, private documents, число устройств и ожидаемый трафик не измерены.
2. Native SQLite encryption/backup/recovery на Windows и Android не проверены; нельзя обещать свойства SQLCipher без prototype.
3. Извлечение pure core в server package и политика version parity ещё не реализованы.
4. Source binding между разными install profiles не определён продуктом; masked four digits недостаточны.
5. Процедура проверки владения/входа Qesto и hosting/jurisdiction не выбраны.
6. Реальный multi-device merge старых профилей не проводился; destructive migration запрещена.
7. Stage 6B физическая перепроверка мобильных исправлений — отдельная незавершённая задача, не доказательство/блокер этого исследования.
8. `AGENTS.md`/`QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1` не найдены в проверенных путях. Если документ предоставят, проект нужно сверить с ним до реализации.
