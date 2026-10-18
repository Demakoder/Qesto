# QESTO Sync — Stage 4b: Windows Synthetic UI ↔ Sync Backend

Дата: 13.10.2026. Статус: **ограниченный synthetic этап выполнен**. Production integration не включена. Следующий этап не начат.

## 1. Результат и границы доказательства

Два независимых настоящих `BudgetController` и Flutter widget host Qesto синхронизируют `transaction.set_note` в обе стороны через существующий Coordinator и локальный Dart/PostgreSQL backend. У каждого клиента отдельные encrypted SQLite, device ID, DPAPI-protected ключ и durable outbox. Реальный HTTP работает через loopback; финансовая обработка, codec и SQLite находятся в одном writer isolate на профиль.

Использованы разрешённые ТЗ widget/controller test hosts вместо двух устанавливаемых Windows окон. В hosts используются настоящие `QestoButton`, `TransactionDetailsScreen`, тема и controller Qesto. Тестовый note-only action вызывает `BudgetController.setTransactionNote`; общий редактор всех финансовых полей не подключается к ограниченному synthetic engine.

**Ни рабочий профиль, ни vault, ни банковские сессии, ни пользовательские документы не открывались.** Установленный Qesto не заменялся; Windows release приложения и APK не собирались. Собраны AOT server/client probes эксперимента. Приложение по умолчанию по-прежнему использует `LocalQestoRepository`.

Это доказательство узкого synthetic контракта, а не готовность облачной синхронизации, onboarding второго непустого профиля или production performance.

## 2. STOP GATE: исходное расхождение и исправление

Сохранённый результат 4a (`experiments/windows_integration_boundary/results/server-semantics-gate.json`) подтверждал: сумма и заметка одинаковы, но **canonical tags различались**. Приложение выполняет штатный bridge с configured policy/locks, а первоначальный сервер 3a менял только `userNote`. Entity приложения — `ent-synthetic-4a-user`, не голый user ID.

Добавлен минимальный optional domain port, а не второй финансовый алгоритм:

- `QestoNoteExecutor` вызывает **существующий** `prepareTransactionNote`, `UserFinancialDataCodec` и shared Synoball через штатный Qesto bridge/policy.
- `QestoCoordinatorDomain` использует тот же executor для локальной подготовки и строгого replay серверного эффекта.
- Existing `CommandIds(changeId)` и контролируемый clock обеспечивают полное сравнение audit/events. Existing transaction/account IDs не меняются.
- Полное v7 JSON и полный `SynoballState.toJson()` сравниваются без исключения tags, locks, overrides, provenance, сумм, направления, статуса, merchant enrichment, canonical/legacy projection, audit/events.
- Fixture содержит RUB 4 861,22; USD 15 000,25; удалённую операцию; ручную категорию, user tags, field locks и настроенное merchant rule. Правка удалённой операции запрещена. Clearing note тоже проверен.
- Отдельный тест настоящего **default** `BudgetController.updateTransaction` совпадает с server executor при одинаковых clock/IDs. Wrong owner, `local-user`, неправильный entity binding и trash отклоняются.

Оба gate были выполнены **до подключения UI networking**. Runner повторяет их первым шагом; harness требует успешные `semantic-parity.json` и `controller-semantic-gate.json`. Предыдущий narrow executor остаётся default для обратной совместимости 3a/3b; Qesto executor подключён только явно в новом эксперименте.

## 3. Архитектура и точка публикации

Локальный путь:

`Qesto UI → BudgetController.setTransactionNote → WindowsNoteBoundary FIFO owner → Coordinator.edit → общий executor/core/codec → atomic snapshot + immutable command + outbox → committed UI publication`.

Сетевой/входящий путь через **того же владельца**:

`push → проверка receipt → pull → проверка всей страницы и exact replay → atomic shadow + projection + checkpoint + coverage → BudgetController.syncTransactionNotes → notifyListeners`.

Нет второго независимого SQLite writer. Нет вызова legacy `onChanged` при incoming publication; constructor запрещает одновременно boundary и legacy save callback. Нет новых пользовательских настроек, публичного sync UI или изменений `QestoAppShell`.

Граница возвращает `localOnly`, `synchronized`, `requiresAttention`, `unavailable`. Локальный ACK не называется синхронизацией. После unknown commit/worker loss/disposal требуется explicit reload; успех в закрытый/stale controller не публикуется.

Неподдерживаемые финансовые команды отклоняются **первым guard до mutation**. Source inventory проверяет 52 public async entry points: 50 blocked mutators и 2 разрешённых note/sync paths. Создание нового периода отдельно guarded; чтение уже существующего периода допустимо. Реальные тесты проверяют edit/batch edit/delete/budget/category/period: полный in-memory JSON, notifications, DB revision и outbox не меняются. Это не универсальная sandbox-защита от произвольной прямой мутации публичных списков сторонним кодом.

## 4. Identity, версии и входящий replay

- Явный synthetic bootstrap только в свежем workspace epoch при server head 0; набор и полные значения canonical entities совпадают с fixture. Это не merge/onboarding реальных профилей.
- Проверяются user, `ent-user`, workspace, device, epoch, local revision, server entity revision и immutable command ID. В том числе при повторном открытии owner до выдачи локальных данных проверяет сохранённый binding/context.
- `financial_profile = qesto.note.v1` и fingerprint настроенной classification policy передаются в bootstrap/receipt/pages и проверяются. Общий protocol/domain version остаётся существующим v1.
- После первой синхронизации следующая заметка отправляется с **base_revision 1**, а не с local revision или исходным нулём.
- Для incoming peer commands также проверяется `accepted revision == command base_revision + 1`, не только для receipt собственной outbox.
- Серверный bundle содержит неизменный wire command, execution time и before/after core digests. Клиент выполняет общий executor на authoritative shadow и сравнивает **все** полученные canonical entities/tags и set changed IDs с bundle. Дополнительные side effects настроенных правил не скрываются.
- Вся страница валидируется до изменения checkpoint/projection. Revisions, partition, protocol/domain, policy fingerprint, tags, execution time, core digest и receipt/entity revision tampering отклоняются с прежним durable состоянием.
- Uncovered локальные предложения replay поверх shadow с сохранённым исходным intent/time. Immutable command не переписывается; shadow authoritative. Для same-field conflict предложенная заметка сохраняется в локальной projection, серверная — в shadow/receipt, outbox остаётся `conflict`.

## 5. Проверенные сценарии

| Сценарий | Результат |
|---|---|
| Настоящий UI A → local commit → server → UI B; B → A | Пройдено. До локального commit новый текст отсутствует; после него `localOnly`; после доставки `synchronized` |
| Сервер действительно остановлен, локальные правки разных операций | Оба ACK durable; после restart сходятся полный v7 и весь core, включая audit/events |
| Remote change при pending на другой операции | Сохраняет локальное предложение, принимает remote, затем сходится |
| Обе стороны правят одну заметку | Нет LWW: обе версии и `requiresAttention`, сохранение после повторного sync/restart |
| Повторный push / потеря ответа после server commit | Один server head/receipt/bundle; тот же immutable intent; retry не создаёт новую команду |
| Процесс падает после записи snapshot / перед local commit | Rollback и snapshot, и outbox; ACK отсутствует |
| Процесс падает после local commit до ответа | Durable outbox восстановлен новым процессом и доставлен |
| Процесс падает перед remote checkpoint | Projection/cursor полностью откатились; replay после restart применён один раз |
| Повторная доставка той же страницы | Без новых revisions, без команд и без повторных effects |
| Wrong/corrupt/missing key | Fail closed; DB bytes сохранены, пустой профиль не создаётся; восстановление из сохранённого synthetic ключа явное |
| Cancel / before-commit error / stale revision | Нет durable или UI изменений; post-commit unknown outcome требует reload |
| Disposed UI во время sync | Нет stale-success publication; explicit reload required |
| Неподдерживаемая команда / немаркированный path / чужой device | Ранний отказ; нет обращения к production repository |
| Unrelated v7 root sections / configured tags+rules / копейки и валюты | Сохраняются; полное server/client equality |

Crash tests — настоящие native process exits на конкретных SQL/harness границах, не доказательство всех аппаратных power-loss сценариев. Подробные VFS/disk/key hardening contracts прежнего storage этапа также повторно пройдены.

## 6. Результаты проверок

Финальный набор: **390 успешных test cases** (21 в Stage 4b и 369 regression cases). Дополнительный повтор two-UI suite — ещё 3 успешных исполнения, не включённых второй раз в 390.

| Suite | Passed |
|---|---:|
| 4b native integration + pure semantic gate | 15 |
| 4b Flutter controller gate + two UI hosts/safety/disposal + 1k/10k benchmarks | 6 |
| Backend 3a regressions | 27 |
| Encrypted client 3b regressions | 23 |
| Local Windows boundary 4a | 17 |
| Actual controller/default repository 4a | 7 |
| Storage contract/process/fault/key regressions | 119 |
| App desktop/classification/editors/trash/bank/integrity/codec/recovery regressions | 143 |
| Shared Synoball full parity/goldens | 33 |

Восемь analyzer runs без замечаний: новый эксперимент, его Flutter runner, приложение (полный analyzer/Flutter code context), shared core, backend 3a, client 3b, boundary 4a, storage. Existing goldens не изменены. App tests — применимый regression набор, **не весь многотысячный app test suite**. Отдельный installed-app/real-bank smoke test не выполнялся: это запрещённый scope для synthetic этапа.

Machine-readable evidence:

- `experiments/windows_synthetic_ui_sync/results/summary.json`;
- `semantic-parity.json`, `controller-semantic-gate.json`, `two-ui-hosts.json`, `two-owner-parity.json`;
- `native-tests.jsonl`, `flutter-tests.jsonl` и семь regression JSONL;
- `source-verification.json`, `mutation-safety-inventory.json`;
- `ui-sync-benchmarks.json`.

Перед 4b сохранены SHA-256 **543 application/shared lib/test/golden files**. Из этого набора изменены только `transaction_note_boundary.dart` и `budget_controller.dart`. Models, repository, codec, core, расчёты, банк, app tests и shared goldens совпадают с исходными hashes. Это **source evidence**, не checksum рабочего профиля: запрещённое хранилище намеренно не читалось.

## 7. Производительность

Финальный прогон: Windows Flutter test **debug VM**, два controller + worker isolate; AOT backend, PostgreSQL/HTTP loopback, native encrypted SQLite3MultipleCiphers с существующей checkpoint policy. По 3 trial на размер. Это не release UI/frame/WAN benchmark.

| Метрика | 1 000 операций | 10 000 операций |
|---|---:|---:|
| Local edit, caller → durable ACK + publication | 0,382–0,423 с | **4,100–4,622 с** |
| A outbound push + own pull/replay/publication | 1,143–1,237 с | 11,717–13,461 с |
| B receive + apply + publication | 0,772–0,878 с | **8,260–8,676 с** |
| A network wall time (HTTP + backend execution) | 0,477–0,494 с | 3,883–4,123 с |
| B remote validate/replay/prepare | 0,375–0,412 с | 4,463–4,980 с |
| B remote atomic SQL commit | 0,152–0,163 с | 1,606–1,683 с |
| B direct controller publication | 0,018–0,033 мс | 0,136–0,164 мс |
| Max main-isolate 8ms timer gap across three phases | 13,506 мс | **62,040 мс** |
| RSS host process (includes both worker isolates) | 188,7–196,8 MiB | 457,9–473,0 MiB |
| Peak RSS host process | до 219,2 MiB | **до 696,6 MiB** |
| DB per client | ~4,56–4,57 MiB | ~44,41–44,42 MiB |
| Sampled WAL client A | ~4,53 MiB | 0–29,85 MiB |

**В 4a локальная правка 10k занимала 2,7–3,3 с; в 4b ~4,1–4,6 с.** Не объявляется production-ready. Дополнительные decode/validation/full-profile serialization и strict authoritative replay дороги. Удалённое применение тоже переписывает весь projection + shadow/context. Один квадратичный серверный поиск заменён index map по уже существующим IDs; финансовое поведение не менялось.

Малое время `_publishNoteState` не означает отсутствие jank: оно не включает передачу большого object graph из isolate, decode/validation и построение кадров. Timer gap — индикатор event-loop stalls, **не raster frame p95**. RAM не включает отдельный PostgreSQL/server process; это ограничение измерений. Sampled WAL — не абсолютный peak для всей сессии; прежние long-run checkpoint/pressure tests подтверждены отдельным storage suite.

### Отдельная рекомендация (не реализована)

Следующий согласованный performance slice: отдельно спроектировать partial normalization canonical transactions/source/provenance и durable command journal; менять только затронутые rows, хранить versioned root sections отдельно, публиковать в UI bounded change sets. API transaction container, atomic command/outbox/checkpoint contract и Synoball executor должны остаться теми же. Нужны baseline/profiling и новые parity tests прежде изменения schema. Не ослаблять tags/audit/replay ради скорости. Полная normalization или data migration в 4b не выполнена.

## 8. Найденные ограничения и исправления интеграции

1. Исправлен исходный tags/locks/policy semantic gap общим executor; проверка не отключалась.
2. Устранён поздний отказ unsupported synthetic commands после memory mutation: guards перенесены/добавлены в начало entry points, отдельно закрыта synchronous period allocation. Старый 4a тест усилен полным equality памяти и отсутствием recovery flag; ожидается typed `NoteBoundaryFailure`, а не прежний late `StateError`.
3. Reopen теперь проверяет device/workspace/context/owner до публикации state.
4. Disposal после durable incoming apply конвертируется в unknown outcome / explicit reload, а не необработанный lifecycle error.
5. Flutter test framework подменял HTTP заглушкой 400: synthetic bootstrap перенесён в отдельный isolate; реальный worker transport не мокается.
6. Runner использует read-only package mapping фактического pure app кода и direct test entry после native hooks; не копирует financial source и не меняет production pubspec.
7. Native asset build/test runs в одном Flutter runner выполняются последовательно: параллельная сборка пыталась заменить занятую DLL. Межпакетные независимые проверки допустимы.
8. Key test первоначально предполагал обязательное наличие recovery manifest; исправлен harness для реально отсутствующего optional backup. Сам storage recovery flow не изменялся.

## 9. Изменённые файлы этого этапа

Production source (только optional seam/guards; default storage unchanged):

- `apps/qesto_app/lib/data/mutations/transaction_note_boundary.dart`;
- `apps/qesto_app/lib/features/budget/state/budget_controller.dart`.

Existing synthetic backend:

- `experiments/synthetic_sync_backend/lib/domain_executor.dart` — optional port/default existing executor;
- `lib/database.dart`, `lib/server.dart` — explicit executor, metadata/effects, test restart port;
- `lib/testing/server_process.dart`, `test/harness.dart` — shared process harness, no copied financial logic.

Existing encrypted-client experiment:

- `experiments/encrypted_client_sync/lib/coordinator_domain.dart`;
- `lib/coordinator.dart`, `lib/bootstrap.dart` — optional domain, existing defaults retained, phase timings and precommit hook.

Existing Windows boundary experiment:

- `experiments/windows_integration_boundary/lib/note_sync_binding.dart`;
- `lib/windows_note_boundary.dart` — same writer owner with Coordinator;
- `pubspec.yaml`, `pubspec.lock`, `flutter_runner/pubspec.lock` — **experiment-only** dependency wiring;
- `flutter_runner/test/controller_boundary_test.dart` — strengthened early-rejection assertion.

New `experiments/windows_synthetic_ui_sync/`:

- `.gitignore`, `pubspec.yaml`, `pubspec.lock`, `PLAN.md`, `README.md`;
- `lib/qesto_note_executor.dart`, `lib/qesto_coordinator_domain.dart`, `lib/harness.dart`;
- `bin/server.dart`, `bin/client_probe.dart`;
- `test/semantic_parity_test.dart`, `test/integration_test.dart`;
- `flutter_runner/.gitignore`, `pubspec.yaml`, `pubspec.lock`;
- `flutter_runner/test/semantic_gate_test.dart`, `two_ui_hosts_test.dart`, `benchmark_test.dart`;
- `tool/configure_app_seam.dart`, `tool/native_assets_seed.dart`, `tool/run.ps1`, `tool/collect_results.dart`;
- `results/` — source baseline, gates, runs, benchmarks, analyzers, summary.

Новый `crypto` dev dependency только для byte-level source hashes, уже существовал в resolved synthetic graph; новой runtime зависимости приложения нет. `.runtime/`, `.dart_tool/`, builds и synthetic credentials ignored. Предыдущие dirty worktree изменения сохранены, не включались автоматически в новый Git/PR.

## 10. Безопасность и блокеры следующего внедрения

- HTTP bind только `127.0.0.1`; clients имеют лишь собственный synthetic token/identity, без admin credentials. Bootstrap явно synthetic и не принимает `local-user` как cloud identity.
- Owned synthetic PostgreSQL кластер использовался только для тестов. Native пути требуют existing marker и synthetic identity; нет production store discovery или fallback.
- DPAPI/vault fail closed; ciphertext не содержит plaintext note и не начинается с обычного SQLite header. Wrong-key tests сохраняют DB bytes. Все fault file operations ограничены свежими synthetic каталогами.
- Unknown worker termination нельзя «горячо» лечить вторым writer: нужен полный process restart / explicit reload согласно 4a contract.
- Доказана только note mutation. Конфликт отображается как статус, обе версии durable; публичный conflict-resolution UX и другие command types не реализованы.
- Page-history/replay и цельный snapshot имеют O(N) стоимость и неограниченный долгосрочный journal/history рост. Требуются отдельно согласованные retention/checkpoint/normalization/performance правила.
- Policy/profile versioning, auth/OIDC, TLS, multi-device onboarding непустых профилей, восстановление production keys и physical Android gate остаются отдельными задачами.
- Полный repository/storage/core refactor, production schema migration, реальные данные, Android integration/public deployment в этом этапе **не выполнялись**.

## 11. Заключение

Acceptance 4b выполнен на двух настоящих synthetic UI/controller hosts с реальными PostgreSQL/HTTP и encrypted native SQLite, строгой семантикой и fault/restart проверками. Это безопасная тестируемая integration boundary для дальнейшего проектирования. В production автоматически не переносится: 10k latency/RAM и onboarding/key/conflict UX требуют отдельных решений владельца продукта.

После отчёта работа остановлена. Установка, миграция, Android и следующий этап не начаты.
