# QESTO Sync — Stage 4f: Durable Effects Commit & Incremental UI Publication

Дата: 17 октября 2026. Платформа: Windows x64. Только синтетические codec-v7 профили.

## Итог и решение

Реализован и проверен экспериментальный путь `transaction.set_note`:

`prepare core + app effects → encrypted atomic COMMIT → container receipt → verify → owner promotion → UI delta`.

Gates A–D пройдены. Gate E подтверждает финансовую корректность двухклиентской
синхронизации, но **performance/resource gates не пройдены полностью**. Локальная
правка 10k быстрее на 40.9%, однако медиана 3.060 с чуть выше цели 3 с. Receiver
10.548 с вместо цели 6 с. Peak RSS 128.8% от full baseline, выше лимита 110%.
50k startup не укладывается в прежние 30 с. **NO-GO для production integration;
GO только для отдельного согласованного этапа устранения этих ограничений.**

Ни миграция, ни включение нового repository, ни следующий этап не выполнялись.
Рабочий Qesto, реальные `store.json`/vault, банковские адаптеры и Android не
использовались. Ни установки, ни публикации сервера, ни отправки данных в интернет.

## 1. Contracts и минимальная граница

| Контракт | Ответственность |
|---|---|
| `NotePreparationScope` | Принимает detached codec-v7 state; admission проверяет policy, identity, порядок и полноту legacy projections |
| `PreparedFinancialCommit` | Immutable binding, core journal, отдельные app effects, coverage, snapshot/effects digests и prepared identity |
| `EffectsCommitRequest` | Валидирует связанный envelope; сохраняет journal/identity в reserved local intent metadata |
| `DurableEffectsReceipt` | Private constructor, final class, per-open container authority; выдаётся только после native COMMIT |
| `DurableEffectsOwner` | Один кандидат; revision/generation/policy/identity guards, verify-before-promotion, unknown-outcome blocking |
| `SyntheticNoteDriver` | Явная opt-in фабрика внутри существующего sole-writer Windows worker |
| `CommittedTransactionNoteDelta` | Доверенный локальный presentation DTO, НЕ receipt и НЕ network patch |
| `TransactionNoteDeltaBoundary` | Additive интерфейс; только экспериментальная wrapper включает delta branch контроллера |

Receipt связан с command ID, workspace, user, lineage, base/new revisions,
domain/policy, owner generation, core+app digest, prepared identity, snapshot и
stored manifest digest, storage generation, checkpoint. Container сверяет реальные
immutable bytes в `commands`, `journal`, `delivery`, state/chunks и checkpoint.
Caller DTO не может подделать private authority. После reopen старый receipt
недействителен. Это **локальное подтверждение**, не server acceptance receipt.

В SQLite по-прежнему одна существующая транзакция: financial state, revision,
journal, immutable command и durable outbox. `_local_effects_v1` вложен в intent
той же команды; SQL schema format 1/2 и wire v1 не меняются. Старые APIs сохранены.

## 2. Полнота effects и parity

Core journal остаётся владельцем canonical transactions, events, audit и
recurring effects. App слой отдельно описывает изменения legacy transactions и
accounts, использует **существующие** `QestoReadModelService`,
`projectSberTransactions`, `applyQestoTransactionEdit` и codec-v7 mappings.
Ни нового reconciliation, ни копии финансовых правил нет.

Admission один раз сверяет persisted legacy rows с реальной проекцией. Каждая
команда затем проецирует ВСЕ затронутые journal записи, а не только target, плюс
необходимые admission corrections. Coverage различает известные effects,
derived invalidations и неподдерживаемые зависимости. Неизвестные membership,
порядок/дубликаты IDs, collection или command kind дают fail-closed отказ; при
несовпадении допустимого UI baseline используется проверенный full reload.

Проверены полные canonical state, codec-v7 roots, audit/events, category policy,
merchant enrichment, locks/tags, deleted/trash, суммы с копейками, валюты,
account/source identities, legacy/Sber projections. Эталон — прежний полный
executor и полный replay, не только суммы или число строк. Существующие goldens
не переписывались и не ослаблялись.

Обязательный stale-policy fixture действительно изменяет **21 из 60** canonical
records. Typed candidate покрывает их все. У контроллера в этом сценарии иной
admission baseline: before-image guard отклоняет частичный UI update, выполняется
одна full загрузка, все соседи совпадают с oracle. Это безопасный fallback, а не
заявление, что stale-policy уже оптимизирован частично.

## 3. Owner и отсутствие speculative UI

Owner принимает ровно один кандидат для исходной revision. После await повторно
проверяет pointer identity, revision, generation, policy, partition и receipt.
Remote apply/policy change/restore/restart инвалидируют candidate. Native COMMIT
может состояться без полученного ответа: тогда RAM не откатывается к якобы старому
durable state, UI не публикуется, дальнейшие записи блокируются.

После безопасного reopen тот же immutable command ID проверяется в хранилище.
Если он отсутствует, повторяется **тот же envelope**, включая исходные время,
generation и content; новый ID не генерируется. При смерти FFI worker требуется
завершение процесса, а не второй writer в том же процессе.

Для UI изменения сначала полностью проверяются на приватном fork и копиях списков.
Только после всех before-image/revision/lifecycle guards выполняется один swap и
`notifyListeners`. Derived selectors инвалидируются общей presentation revision.
До commit UI и число уведомлений неизменны; ordinary и audit-only дают ровно одно
уведомление. Dispose/cancel/read-model refresh во время commit не дают false success.
Неизвестный UI baseline загружается полностью, с повторной проверкой lifecycle.

Найден и закрыт пробел synthetic seam: `refreshLocalReadModel` теперь меняет
presentation revision при подключённой note boundary. Default app behavior не
менялся. Record codec methods лишь открывают прежние сериализаторы без новой схемы.

## 4. Два клиента и неизменный remote path

Проверены rendered Qesto details, реальные `BudgetController`, native encrypted
owners, loopback HTTP и изолированный PostgreSQL. A → B, B → A, disjoint offline
edits, same-field conflict, duplicate ID, collision, потеря ACK и повторная page
сохраняют полное state/server равенство и исходные IDs. Incoming apply не создаёт
outbox. Pending conflict остаётся явным конфликтом, не скрывается.

Remote pages проходят прежние полный domain replay, entity/digest/version/partition
checks и атомарный state/shadow/cursor/pending apply. После него owner re-admit и UI
full reload. **Partial remote apply/publication не реализованы.** Full v1 digest не
заменялся journal digest. Новый local intent metadata не уходит в wire body.

## 5. Fault/recovery evidence

| Проверка | Результат / evidence |
|---|---|
| До prepare, после prepare, первая SQL chunk row, перед outbox/COMMIT, после COMMIT до ответа/promotion | AOT process exits, атомарный old/new state + outbox; `process-tests.jsonl`, `process-crashes.json` |
| Same-ID retry/collision, stale revision, foreign/reopened receipt, competing candidate, invalidation | `receipt-tests.jsonl`, `owner-tests.jsonl` |
| Worker death после COMMIT до UI ответа | Full child-process exit; затем reopen обнаруживает ту же команду/outbox; `integration-tests.jsonl` |
| Remote apply до checkpoint, lost ACK, repeated page, malformed effects | Прежние assertions подключены к новому driver; `integration-tests.jsonl` |
| Shutdown queued + in-flight до/после COMMIT | Нет частичного snapshot/потери durable command; `lifecycle-tests.jsonl` |
| Native VFS FULL / WRITE / FSYNC / partial write | Реальные SQLite native return codes 13 / 778 / 1034; ложного receipt нет; `native-tests.jsonl` |
| Native checkpoint error / process exit в checkpoint | Commit может уже быть durable; receipt не выдаётся на poisoned connection; после reopen тот же ID подтверждён |
| Missing/wrong/corrupt key, warm cache chunk/manifest corruption, encrypted backup/rotation, WAL reader pressure | Сохранённые storage/chunk/boundary suites + новые receipt tests |

`native-effects.json` содержит fault hit counts, native codes, revision и receipt
outcome до/после reopen. Для checkpoint fault snapshot/outbox уже revision 1, но
receipt до reopen отсутствует — это намеренная fail-closed деградация. Ошибки
fsync/write оставляют revision 0 до same-ID retry. WAL/SHM вручную не удаляются.

Native VFS injection не является реальным переполнением физического диска или
аппаратным отключением питания. Process kill не доказывает power-loss безопасность.

## 6. Воспроизводимые проверки

Все логи находятся в `results/`, агрегат — `results/summary.json`.

| Набор | Успешные тесты |
|---|---:|
| Полный новый Dart suite (coverage 9, receipt 10, owner 8, process 7, native 6, lifecycle 2, integration 15) | 57 |
| Shared core / прежние goldens | 34 |
| Stage 4e journal | 15 |
| Domain execution | 8 |
| Прежняя Windows boundary | 16 |
| Storage/chunks/native/WAL/backup contracts | 119 + 20 |
| App desktop, storage recovery, codec, Synoball, classification, Cash Flow, empty profile | 77 |
| Flutter delta / default behavior / новый двухклиентский UI | 6 + 4 + 1 |

Итого 357 проверок без повторного учёта per-gate reruns; ещё 4 benchmark-прогона.
Startup probe выполняется корректно как тестовый инструмент, но его readiness
result **false**. Зелёный exit самого probe не засчитывается как 50k PASS.

Анализатор: experimental package, shared core, container, worker boundary,
coordinator, Flutter runner и три затронутых app seam — без issues. `git diff
--check` exit 0; есть обычные предупреждения LF/CRLF в уже dirty worktree.
Это targeted desktop regression, **не весь набор всех тестов приложения**.
Production Windows release/Android builds и установка намеренно не выполнялись.
Собраны отдельные AOT server/client/receipt/native probes, не дистрибутив Qesto.

Промежуточные неуспешные проверки: ошибочный action fault harness исправлен на
существующий `drop-response`; три unnecessary `!` устранены после analyzer.
Ранние compile/test harness проблемы не объявлялись production-дефектами.
Открытые неуспехи: budgets, RSS и 50k startup ниже.

## 7. Matched performance

Один и тот же свежий инструментированный **full** AOT server в обеих ветках;
Flutter test debug VM, два настоящих controller/detail screens, Windows native
SQLite3MultipleCiphers. Отдельный Flutter процесс на каждую пару mode/count,
последовательно, 3 trials. Не standalone JIT Stage 4e и не production release UI.

| Операций / режим | Local, с | Sender, с | Receiver, с | Host peak RSS, MiB | Local response, JSON-equivalent bytes |
|---|---:|---:|---:|---:|---:|
| 1k full | 0.539 | 1.482 | 1.022 | 313.8 | 1 528 157 |
| 1k effects | 0.309 | 1.748 | 0.987 | 335.8 | 4 824 |
| 10k full | 5.181 | 15.368 | 10.482 | 804.2 | 15 097 157 |
| 10k effects | 3.060 | 17.508 | 10.548 | 1036.1 | 4 824 |

Таблица — медианы latency, максимум process RSS; полный oracle находится вне
timed intervals, но входит в lifetime RSS peak. Сервер/PostgreSQL RAM не включены
в host RSS. Background OS load не фиксировался; это три измерения, не SLA/p95.

Раздельные медианные local phases 10k effects: domain 496 ms (journal около 125 ms
входит внутрь domain), app projections 3.2 ms, codec encode 240 ms, container
commit + receipt issuance 1379 ms, отдельная receipt verification 8.3 ms, owner
promotion 6.3 ms, UI publication 1.35 ms. Не складывать journal с domain повторно.
Остальное end-to-end время: очереди/чтение исходного состояния, binding и full
hash/validation, envelope/dispatch. Не весь commit интервал является fsync.

Send→receive handoff full 10k: 61–70 ms, effects: 0 в доступной wall-clock
resolution. Ноль не означает бесплатную передачу. Payload — размер JSON
эквивалента, не точный объём Dart object graph; old full response дополнительно
содержит prepared core. Новая обычная note не переносит весь профиль по SendPort.

Host CPU трёх фаз: 35.625 → 33.531 CPU-секунды (медиана). Heap measurements
сохранены через VM service отдельно по isolate; **не суммируются**, поскольку
isolate-group heap может учитываться общим. Effects 10k main reported old-space
usage примерно 541–577 MiB. Main-isolate sampled gap local до 44.7 ms: delta не
делает всю работу полностью независимой от размера истории.

Server metrics остались full: например, на effects 10k server transaction
медиана около 4.51 с, domain/diff 2.43 с, PostgreSQL write preparation 1.76 с;
phases вложенные, не суммировать произвольно. HTTP за три команды: sender body
1029 bytes, responses 9667 bytes; receiver responses 8272 bytes — wire не вырос.
Подробные server CPU/RSS/phase observations и worker network/remote prepare/commit
есть в `benchmark-*.json`.

### Storage и оставшаяся O(N) работа

10k после трёх циклов: full A DB 46 575 616, WAL 31 295 552 bytes; effects A
DB 60 518 400, WAL 1 429 672 bytes. Effects B DB 60 502 016, WAL 1 969 392 bytes.
SHM effects 32 768 bytes. Это final sample, не обещание максимального размера.
Format2 счётчики A: 26 chunk writes / 4 908 311 payload bytes; B: 20 / 3 274 793.
Они не измеряют физическую write amplification SQLite и не включают все служебные
SQL bytes. Старый full path не имеет таких chunk counters.

Меньший WAL не означает меньшую DB или RAM. Остаются full snapshot encode/hash,
chunk scan/validation, копии containers/indexes, несколько представлений profile,
полный remote replay и admission после него. Sender стал медленнее; receiver
практически не ускорился. Нет основания называть весь pipeline incremental O(1).

## 8. 50k startup/resource gate

`startup-50000.json`: **FAIL / TimeoutException** на неизменном 30 s owner-ready
deadline. Полный startup attempt 45.66 с; host peak RSS около 1638.9 MiB. Это
отдельный Flutter процесс, завершён после единственного probe. Второй native
writer внутри него не открывался. Deadline, финансовая валидация, encryption и
full oracle не ослаблялись ради успешного результата.

## 9. Изменённые файлы и сохранность default path

Сверены 628 baseline hashes. Из прежних исходников изменены только:

1. `apps/qesto_app/lib/data/mutations/transaction_note_boundary.dart` — additive delta DTO/interface.
2. `apps/qesto_app/lib/data/persistence/user_financial_data_codec.dart` — открытые record mappings, те же codec-v7 поля.
3. `apps/qesto_app/lib/features/budget/state/budget_controller.dart` — opt-in publication/fallback/lifecycle guards.
4. `packages/qesto_synoball_core/lib/core/effects_journal.dart` — guarded presentation fork, не новый executor.
5. `experiments/storage_feasibility/lib/container/sqlite_container.dart` — private receipt authority/part.
6. `experiments/encrypted_client_sync/lib/coordinator.dart` — optional synthetic local commit callback.
7. `experiments/windows_integration_boundary/lib/windows_note_boundary.dart` — optional driver, FIFO coordination, delta reply, handoff measurement.
8. `experiments/windows_synthetic_ui_sync/lib/harness.dart` — optional driver injection; default прежний.

Новые extension-файлы вне нового пакета:

- `experiments/storage_feasibility/lib/container/durable_effects.dart`.
- `experiments/windows_integration_boundary/lib/synthetic_note_driver.dart`.

Новый пакет `experiments/durable_effects_integration/`:

- `lib/{prepared_commit,durable_owner,storage_request,windows_driver,harness}.dart`.
- `bin/{receipt_probe,client_probe,native_effects_probe,server}.dart`.
- `test/{coverage,receipt,owner,process,native,lifecycle,integration}_test.dart`.
- `flutter_runner/test/{delta,defaults,sync,benchmark,startup}_test.dart`.
- `tool/{configure_app_seam,source_evidence,run_tests,regressions,flutter_checks,app_regression,analyze,benchmarks,summarize,artifact_manifest}.dart`.
- Package/runner pubspec и lockfiles, PLAN, Gates A–E, этот отчёт и results.

Полный перечень source/evidence artifacts с SHA-256 — `results/artifact_manifest.json`.
Новых внешних библиотек алгоритма нет: используются уже разрешённые path packages
и существующий runtime/dependency graph. Core/backend/storage financial IDs,
codec и HTTP версии, модели, расчёты и production repository не изменены.
Default shell не создаёт effects factory/boundary; whole-profile legacy path
остаётся доступным. Реальные профили намеренно **не читались даже для хэшей**.
Утверждение о scope основано на code paths/source diff, не на чтении vault.

## 10. Review, риски и следующий согласуемый шаг

Выполнен отдельный self-review authority/receipt, stale lifecycle, immutable ID,
full-fallback, thread ownership и default-off wiring. Независимого второго
reviewer в этом запуске не было. Существующий большой dirty worktree сохранён;
его изменения не приписываются Stage 4f и автоматически не коммитились.

Открытые риски: высокий RSS, 50k admission/deadline, full remote replay и sender
regression, O(N) snapshot/index work, экспериментальная зависимость app projection
от текущей версии bridge/Sber semantics. Изменение этих зависимостей требует нового
coverage review и parity, а не автоматического принятия старого journal contract.
Сервер продолжает доверять прежнему полному domain validation, не UI effects.

Для следующего отдельного slice предложено профилировать lifetime retained
profile/core/cache, сократить повторный admit после неизменившегося pull только с
доказанным revision/policy guard, затем рассмотреть versioned remote publication.
Это **предложения, не реализованные изменения**. Разбор startup должен сохранять
fail-closed и существующий deadline; массовую переработку/миграцию не начинать.

На этом Stage 4f остановлен. Разрешения на production integration не выводятся
из успешных тестов; отрицательные performance и resource results остаются gates.

## Воспроизведение

Из каталога пакета, на подготовленном Windows окружении из предыдущих stages:
`dart pub get --offline`, затем `dart tool/configure_app_seam.dart`. SQLite hook —
sqlite3mc. Использовать сохранённый synthetic PostgreSQL cluster только loopback
(`../synthetic_sync_backend/tool/cluster.dart resume` из его каталога).
Собрать четыре `bin/*` через `dart build cli -t ... -o build/<name>`, затем ещё раз
configure seam. Запустить `dart tool/run_tests.dart all`, `dart tool/regressions.dart
storage chunks shared journal domain boundary`, `dart tool/flutter_checks.dart
delta|defaults|sync`, `dart tool/app_regression.dart`, `dart tool/analyze.dart`.
Отдельно без других build/test процессов — `dart tool/benchmarks.dart`, затем
`dart tool/flutter_checks.dart startup`. В конце source verification, summarize,
artifact manifest; synthetic cluster остановить. Production app запускать не нужно.
