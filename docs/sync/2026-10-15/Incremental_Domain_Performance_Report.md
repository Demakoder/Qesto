# QESTO Sync — Stage 4d: Incremental Domain Execution & Memory

Дата отчёта: **15 октября 2026**. Windows x64; только синтетические fixtures.
Основа: протокол разработки v0.1, Sync A–E, Stage 4c и
`Versioned_Incremental_Domain_Proposal.md`.

## 1. Решение

**NO-GO для подключения инкрементального domain/UI execution к приложению.**
Stage 4d завершён как ограниченный эксперимент с отрицательным интеграционным
результатом и конкретным контрактным блокером. Финансовое ядро не переписано.

Повторное использование подготовленного core семантически совместимо на проверенных
сценариях и ускоряет собственно domain phase. Но полная сериализация, проверка
результата, projections и извлечение полного набора эффектов поглощают выигрыш.
Ограничение decode-кеша уменьшило peak RSS относительно Stage 4c, но замедлило
sender sync и **не выполнило budgets**. Частичные UI/SQL updates не включены.

Следующий допустимый предмет отдельного согласования — core-owned effects journal
и durable publication contract, описанные ниже. Это не разрешение на production
integration, protocol v2 или миграцию. После отчёта работа останавливается.

## 2. Граница и анализ O(N)

Перед изменениями сохранены 647 хешей исходников/артефактов и исходные результаты
Stage 4c. План: `experiments/incremental_domain_execution/PLAN.md`.

| Работа | Решение Stage 4d и основание |
|---|---|
| Codec-v7 decode, schema/owner/source identity | Полный путь при загрузке и промахе кеша; нельзя пропускать проверку чужого профиля |
| Построение core indexes, применение configured policy | Подготовленный fork допускается только при том же owner/revision/generation/policy; новый импорт/restore/remote требует reload или отдельного контракта |
| Recurring/enrichment при мутации | Сохранены исходные функции: могут затронуть другие canonical записи |
| Legacy projection и Sber projection | Полные существующие функции; dependency graph для безопасного частичного пересчёта пока отсутствует |
| Capture effects | Полное сравнение всех codec roots/core collections — корректный oracle, но O(N), не дешёвый production API |
| JSON encode, full-state digest, format-2 split/manifest | Интерфейсы v1 требуют полный документ; нельзя незаметно заменить его Merkle digest |
| Shadow + pending replay | Сохранены из-за конфликтов, lost ACK и повторной доставки |
| UI публикация | Прежний полный CommittedTransactionNote: данные + preparedCore; частичный путь не включён |
| Backup/export | Полная реконструкция остаётся обязательной; commit validation не отложена до backup |

Вывод Proposal 4c подтверждён: уменьшение SQL payload само по себе не устраняет
полные проходы финансового алгоритма, кодека и integrity/replay.

## 3. Что реализовано

### 3.1 Минимальное дополнение shared core

`SynoballCore.forkForCommand(ids, clock)` копирует core-owned списки и индексы
подготовленного core. Не вызывает заново constructor policy initialization.
Default constructor, production ID factory и финансовые методы не изменены.
Все mutation/enrichment/recurring/reconciliation функции остаются прежними.

Fork отделяет изменяемые контейнеры, но значения моделей разделяются: существующие
модели не глубоко immutable. Требуется исключительное владение и запрет внешней
мутации вложенных collections. Ни один production caller не использует новый API.
Отдельный тест shared package проверяет fork против нового полного core после
edit, repeated observation, delete/reimport/restore и изменения policy.

### 3.2 PreparedDomainOwner — изолированный POC

Owner связан с synthetic user, workspace, lineage, local revision, policy digest
и поколением загрузки. Prepare создаёт отдельный fork, не публикуя его. Promotion
проверяет command ID, revision, generation и точное совпадение durable JSON.
Ошибка/неизвестный результат/смена policy требуют invalidation/reload.
Даже reload на ту же revision отвергает старый подготовленный результат.

**Ограничение:** `loadVerified` предполагает, что вызывающий слой уже проверил
durable state; сам POC не читает SQLite. `acceptDurable` проверяет переданные байты,
но не является доказательством COMMIT. Pending/server revisions/conflicts ещё не
включены в owner binding. Поэтому POC **не подключён** к coordinator/backend/UI.

### 3.3 DomainEffectsV1 — oracle contract

Версия, command ID, workspace/lineage, target, base/new revisions, policy fingerprint,
digest исходного документа; все изменённые roots/core collections; изменённые поля
canonical entities; audit/events, evidence, trash, enrichment/recurring и общие
read-model/analytics invalidations. JSON payload глубоко read-only. Применение к
другому base отклоняется. Это внутренний capture, не сетевой JSON Patch.

Фактический stale-policy тест: **одна заметка меняет 21 из 60 canonical операций**.
Прежний и новый результаты совпадают целиком. При повторной записи той же заметки
иногда изменяются только audit/events. Поэтому target-only patch и пропуск записи
при пустом changed-transactions list неприемлемы.

Полнота эффектов подтверждена через полный oracle, а не через дешёвый mutation
journal. Этот gate НЕ разрешает включить частичное обновление по одному target.

### 3.4 Memory POC в настоящем synthetic sync flow

`BoundedNoteExecutor`: максимум один exact owner+source decode entry; admission
estimate 32 MiB; стоимость = UTF-16 length ×16. Старое значение освобождается из
кеша **до** decode нового. Крупные документы идут через полный путь без retention.
На 10k server зафиксировал 29 decode misses/rejections, zero retained estimate.

Это оценка допуска, не hard RSS limit и не точный размер object graph. Использована
в клиентском coordinator и AOT synthetic server. Исполнение финансовой команды,
format 2, encryption, replay, locks и v1 protocol не менялись. Поэтому энд-ту-энд
измерения ниже относятся к **bounded-cache/full-execution**, не к prepared owner.

`streamingDigest` — отдельный off-path POC exact v1 canonical bytes: 200 generated
Unicode/numeric/nested inputs и 1k fixture совпали с прежним digest. Не активирован
в transport/storage, новый protocol не введён. Его performance benefit не заявляется.

## 4. Результаты производительности

### 4.1 Два настоящих UI/controller host

Одинаковая история и workload Stage 4c: три последовательные правки, sender
push+pull, receiver apply, full-v7 сравнение. Flutter test **debug VM**, Windows
native workers/SQLite3MultipleCiphers, AOT server, loopback PostgreSQL. Два реальных
BudgetController и TransactionDetailsScreen в **одном** Flutter test process,
не два установленных приложения. Три прогона на размер, без concurrent benchmarks.
В таблице **медианы**; сырые samples и средние также сохранены.

| 10k, вариант | Local, s | Sender, s | Receiver, s | Peak host RSS, MiB |
|---|---:|---:|---:|---:|
| Stage 4c historical full-snapshot | 5.436 | 15.235 | 10.551 | 736.6 |
| Stage 4c historical format2 + cache2 | 3.914 | 11.107 | 6.840 | 1123.0 |
| Stage 4d fresh matched full-snapshot | 5.672 | 14.975 | 10.976 | 776.0 |
| Stage 4d format2 + bounded decode | 4.226 | 16.328 | 8.508 | 948.2 |

Historical строки — сохранённые результаты прошлого этапа, не новый matched run.
Новая пара сравнивается между собой: local быстрее приблизительно в 1.34 раза,
receiver в 1.29 раза, но sender **медленнее**. Peak RSS относительно fresh baseline
выше на **22.2%**, допустимо только 10% (853.6 MiB). Снижение RSS примерно на 15.6%
к historical cache2 недостаточно и не доказывает отдельный вклад каждой причины.

| 1k, свежая пара | Local, s | Sender, s | Receiver, s | Peak, MiB |
|---|---:|---:|---:|---:|
| Full-snapshot | 0.537 | 1.524 | 1.058 | 285.2 |
| Format2 + bounded cache | 0.423 | 1.410 | 0.738 | 308.1 |

**Не пройдены все основные 10k budgets:** local ≤3s; receiver ≤6s; RSS ≤110%;
желательные 2×. **50k actual UI startup failed:** `WindowsNoteBoundary.open`
превысил существующие 30 секунд. Deadline не увеличен; 50k end-to-end не подтверждён.

### 4.2 Domain decomposition — не end-to-end

Отдельный Dart JIT process на вариант/размер, одна разминка + три измерения.
Одинаковые fixtures, clocks/IDs; полный oracle и capture/reconstruction за пределами
таймера domain. Полное совпадение codec и canonical состояния на 1k/10k/50k.

| Count | Full domain, ms | Prepared domain, ms | Full + encode, ms | Prepared + encode + receipt verification, ms | Full effects capture prepared, ms |
|---|---:|---:|---:|---:|---:|
| 1k | 39.8 | 23.8 | 53.6 | 51.0 | 191.3 |
| 10k | 414.6 | 243.6 | 578.8 | 570.0 | 1967.5 |
| 50k | 1933.0 | 1194.4 | 2800.6 | 2979.6 | 9857.2 |

Средние трёх измерений. SQLite commit здесь **не выполняется**; receipt verification
— локальная проверка совпадения строк. Собственно domain phase ускорена, однако
безопасный полный envelope не получил существенного ускорения, а на 50k замедлился.
Capture даже при одной изменённой
операции масштабируется по **всей истории**. Это доказанный технический блокер,
а не обещание O(1) после простой замены кеша. Таблица — повторный замер финальной
версии с deep read-only effects; ранние exploratory результаты сохранены отдельно
в `results/exploratory-before-deep-freeze/` и не используются как acceptance.

### 4.3 Память: фактический VM allocation profile

Отдельные прогоны 10k через VM service на loopback; GC/reset перед командой,
профиль после domain+encode(+receipt), **до** oracle/effects capture. Это измеренный
heap в одной точке, не peak RSS/не полный live-heap census после финального GC.

| VM sample | Full, MiB | Prepared, MiB |
|---|---:|---:|
| heapUsage | 125.7 | 184.2 |
| `_TwoByteString` | 29.2 | 58.0 |
| `_OneByteString` | 27.1 | 43.7 |
| `_List` | 33.6 | 39.9 |
| `CanonicalTransaction` | 4.27 | 4.27 |
| `BudgetTransaction` | 3.97 | 3.97 |

Дублирование full JSON при encode/receipt validation заметно дороже самих новых
canonical objects. POC не удаляет эту проверку без durable token/immutable prepared
result. Копирование старого и нового профиля, shadow+projection, storage caches,
SendPort и два controller graphs остаются. Отсюда нет основания считать 32 MiB
decode admission общим лимитом процесса.

### 4.4 Остальные измерения

- Fresh 10k bounded host CPU для трёх фаз: среднее **29.375 CPU-s** против
  **35.911 CPU-s** baseline. Это GetProcessTimes host с обоими worker isolates,
  без CPU PostgreSQL/AOT server. Максимальный main-isolate timer gap: 39.4 ms
  против 46.9 ms. Pump UI 27–75 ms — не release raster/frame p95.
- Native worker startup/reopen (по одному прогону, sync binding, без render):
  1k full **0.874/0.179 s**, bounded **0.927/0.216 s**;
  10k full **6.607/1.849 s**, bounded **8.672/2.325 s**.
- Повторный SendPort probe полного CommittedTransactionNote: 10k two-way copy +
  scheduling **95–121 ms**, 50k **687–747 ms**. Logical codec UTF-8 size:
  1,526,642 / 15,095,642 / 75,482,338 bytes. Это **не** размер VM wire allocation
  и не one-way measurement; payload остаётся полным.
- 10k bounded server transaction: 4.832–5.108 s; domain+diff 2.601–2.884 s;
  PostgreSQL write preparation 1.857–1.972 s. Полный записываемый state payload
  15,096,411 → 15,097,928 bytes на команду. Не физические дисковые writes.
- Последний 10k sender SQLite DB 60,502,016 bytes, WAL 1,429,672, SHM 32,768;
  receiver DB 60,502,016, WAL 1,969,392, SHM 32,768. Между первой и третьей
  итерациями sender DB вырос на 8,192 bytes, receiver на 311,296. Это steady
  workload samples, не долгосрочный growth forecast. Совокупный sender chunk
  payload трёх local+remote циклов 4,908,311 bytes; нельзя делить его на три и
  выдавать за одиночную local write.
- HTTP sender bodies суммарно 1,029 sent / 9,667 received bytes за три цикла;
  небольшой HTTP payload не устраняет local replay/JSON costs. Это не весь TCP/TLS.

## 5. Parity, recovery и security

**358 успешных test executions**, включая четыре matched benchmark tests;
**один неуспешный 50k startup gate** отдельно. Наборы частично повторяют сценарии,
поэтому это не 358 уникальных тестов. Девять анализаторов: `No issues found!`.

| Suite | Passed |
|---|---:|
| Новые native domain/cache/digest + existing sync scenarios | 22 |
| Два UI hosts | 3 |
| Resource-pressure fault simulation | 3 |
| Startup/reopen probes | 4 |
| Windows boundary/shutdown regression | 16 |
| Shared core parity/goldens + prepared fork | 34 |
| Format2 native faults/storage/handoff/sync regression | 35 |
| Encrypted client | 23 |
| Backend/RLS/conflicts/idempotency | 27 |
| Storage contracts/recovery/hardening | 119 |
| App/desktop/classification/codec/trash/write-safety | 68 |
| Matched UI benchmarks 1k/10k | 4 |

Проверены полные canonical/codec-v7 состояния, legacy projections, audit/events,
exact minor units/currencies, source evidence/identities, tags/locks/overrides,
policy, tombstones и unrelated roots. Прежние golden expectations не менялись.

Проверки отказов:

- До commit, после chunk row, после financial snapshot до outbox, перед commit;
  native process death после commit до ACK; повтор immutable ID.
- Remote crash до checkpoint, lost server ACK, повторная page delivery,
  offline edits и same-field conflict. Cursor не продвигается отдельно от состояния.
- Prepared owner: stale revision/policy/generation/tenant, неправильные receipt
  bytes/ID, speculative fork не публикуется; failed/unknown outcome → invalidation.
- Повреждение chunk/manifest/hash с прогретым cache; missing/corrupt/wrong keys;
  encrypted backup с pending commands, pinned WAL readers/backpressure,
  native VFS FULL/write/fsync/partial/checkpoint faults и checkpoint process kill.
- Queued/in-flight shutdown, drain/cancel, disposed/stale controller, worker loss.
- Три места transaction fault проверены при выделенных и затронутых **64 MiB**
  плюс явно брошенном OutOfMemoryError: после reopen исходный snapshot, revision 0,
  outbox пуст. Это **симуляция ошибки под ограниченной нагрузкой**, НЕ настоящий
  VM/OS OOM. Native OOM и аппаратный power loss остаются недоказанными.

Важно: durable/crash tests относятся к существующему полному sync/storage пути
и bounded cache. Они не доказывают crash safety ещё не подключённого prepared-owner
protocol. Неуспешные ранние новые тесты исправлены как ошибки тестовых конструкций
(required account fields, audit ID prefix, ожидание transaction change при no-op);
старые expectations/финансовые правила для прохождения не менялись.

## 6. Минимальный требуемый контракт и STOP boundary

Подробный RFC: `experiments/incremental_domain_execution/Domain_Effects_Contract_and_Blockers.md`.

1. Core-owned journal всех authoritative writes, включая constructor-policy
   normalization и derived recurrence. Нельзя восстанавливать его только по target
   или audit list. Полный oracle остаётся тестовым эталоном.
2. Owner binding дополнить server sequence, pending-set digest, conflicts и domain
   version; policy/import/remote/restore обязаны обновлять поколение согласованно.
3. Prepared result с исключительным владением и durable token от container,
   который связывает effects/command ID/revision. Promotion только после COMMIT;
   unknown outcome → reload. Это позволит убрать повторный encode **без потери
   доказательства**, а не просто удалить проверку для ускорения.
4. Typed legacy/canonical UI updates из существующих projection functions с
   revision/generation guard; fallback full load при неизвестных зависимостях.
   Текущий BudgetController не переписывать.
5. PostgreSQL partial persistence только после полного effect contract под прежним
   workspace lock, с receipts/log/conflicts/RLS. Direct UPDATE note запрещён.
6. v1 full SHA-256 нельзя заменить комбинацией chunk hashes без нового протокола.
   Возможный v2 — отдельная совместимость/dual-verification/migration задача,
   сейчас только RFC, не implementation.

Рекомендуемая memory policy: один owner и один speculative fork, bounded очередь;
byte-budgeted decode cache; общий budget для storage verified strings вместо
двух независимых entry-count caches; request-scoped server buffers; никакой
публикации RAM state до durable acknowledgement. Storage budget/typed UI delta
пока **предложены, не реализованы**.

## 7. Изменённые файлы

Вне нового эксперимента:

- `packages/qesto_synoball_core/lib/core/synoball_core.dart` — additive fork API.
- `packages/qesto_synoball_core/test/prepared_fork_test.dart` — regression API.
- `experiments/incremental_sync_performance/flutter_runner/test/benchmark_test.dart`
  — optional harnessFactory/label/outputDirectory, прежние defaults сохранены.
- Этот отчёт: `docs/sync/2026-10-15/Incremental_Domain_Performance_Report.md`.

Новый `experiments/incremental_domain_execution/`:

```text
.gitignore, pubspec.yaml, pubspec.lock, PLAN.md, README.md
Domain_Effects_Contract_and_Blockers.md
lib/effects.dart
lib/prepared_owner.dart
lib/bounded_executor.dart
lib/streaming_digest.dart
lib/harness.dart
bin/profile_domain.dart
bin/server.dart
test/domain_owner_test.dart
test/bounded_executor_test.dart
test/streaming_digest_test.dart
test/sync_integration_test.dart
test/resource_pressure_test.dart
test/startup_probe_test.dart
flutter_runner/pubspec.yaml, pubspec.lock
flutter_runner/test/benchmark_test.dart
flutter_runner/test/two_ui_hosts_test.dart
tool/capture_baseline.ps1
tool/configure_app_seam.dart
tool/run_checks.ps1
tool/verify_sources.ps1
tool/collect_results.dart
results/ — JSON/JSONL/logs: baseline, source hashes, tests, allocation, benchmarks
```

Повторный handoff test обновил generated evidence
`experiments/incremental_sync_performance/results/isolate-handoff.json`; копия
сохранена в новом results. Build/.runtime/Flutter generated files игнорируются.
Новых сторонних библиотек для алгоритма нет: переиспользованы pinned experiment
dependencies; VM allocation profile получен стандартным developer/JSON-RPC.

## 8. Сохранность и оставшиеся ограничения

`source-verification.json`: app lib/test и прежние shared goldens **не изменены**
от зафиксированного baseline; неожиданных изменений исходников нет. Существовавший
dirty worktree сохранён. Production storage default, модели/IDs, банковские
адаптеры, установленные Windows/Android приложения и user profiles не изменялись.
Реальные профили не читались, даже для hash verification — это запрещено scope.

Локальный синтетический PostgreSQL остановлен, VM profiling endpoints закрылись.
Не было cloud/public deployment, Android работы, data migration, Git push или PR.

Открыты: полный effects journal, immutable/durable publication contract, typed UI
delta, revision-bound server owner, incremental integrity compatibility, 50k
startup, native OOM и release-mode/end-to-end memory gate. **Продолжать внедрение
без отдельного согласования нельзя.**

Машиночитаемая сводка и первичные доказательства:
`experiments/incremental_domain_execution/results/summary.json` и соседние файлы.
Полный перечень артефактов с SHA-256: `results/artifacts.json` (кроме самого manifest,
build/runtime и Flutter-generated metadata).
`run_checks.ps1 -Benchmarks -Regressions` воспроизводит suites; standalone domain
и allocation commands приведены в README. Успешная компиляция не использована
вместо проверки финансовой семантики.
