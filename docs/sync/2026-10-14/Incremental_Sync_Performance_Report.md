# QESTO Sync — Stage 4c: Incremental Storage & Sync Performance

Дата отчёта: 14.10.2026 (Europe/Moscow). Синтетический эксперимент Windows x64.

## 1. Решение

**Изолированный прототип и исследование завершены. Перенос в production — NO-GO.**

Работают двунаправленная синхронизация заметок, полный Synoball replay и новый
зашифрованный контейнер с инкрементальной записью chunks. На профиле из 10 000
операций финансовый payload одной локальной правки уменьшился с 15 095 642 до
544 752 байт: в 27,7 раза. Это **логический payload SQL, а не физические записи SSD**.

В сопоставимом Flutter debug тесте медиана локальной правки снизилась с 5,436 до
3,914 с, sender push+pull — с 15,235 до 11,107 с, receiver apply — с 10,551 до
6,840 с. Однако:

- целевые бюджеты 3 с / 6 с не достигнуты;
- peak RSS вырос с 736,6 до 1 123,0 MiB (+52,5%);
- полный UI-сценарий 50k не прошёл существующий 30-секундный startup deadline;
- обработка, в отличие от объёма изменяемых SQL chunks, по-прежнему зависит от
  размера всего профиля.

Дальнейшее существенное ускорение требует отдельно согласованного контракта
инкрементальных domain effects, жизненного цикла policy/core и обработки
полного состояния. Эти изменения **не реализованы**. Модель финансов, Synoball,
production repository, пользовательский профиль и установленные приложения
не изменялись. Android, публичный сервер и production migration не запускались.

## 2. Основание и границы

Использованы исходное ТЗ и предоставленное владельцем продолжение разделов 9–13,
QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1, существующие эксперименты 2b.0/3a/3b/4a/4b,
общий `qesto_synoball_core`, реальный codec v7 и приложение Qesto.

Результат находится в `experiments/incremental_sync_performance/`.
Изменения существующих файлов ограничены экспериментами. Новое хранилище
выбирается только явным `incremental: true`; прежний format 1 остаётся default.
Никакая существующая база автоматически не конвертируется.

До изменений сохранены 578 SHA-256 исходных файлов, включая `apps/qesto_app/lib`,
`apps/qesto_app/test` и shared core. После изменений среди этих файлов нет ни
изменённых production/core файлов, ни пропавших файлов. Это подтверждает
сохранность охваченного исходного кода, **не является проверкой байтов рабочего
пользовательского профиля**: профиль намеренно не открывался и не переносился.

Стенд использует только помеченные synthetic directories, Windows DPAPI, настоящую
SQLite3MultipleCiphers, отдельные native writer owners и существующий loopback
PostgreSQL. Синтетические runtime credentials/build/native artifacts не включаются
в исходники. После прогонов принадлежащий стенду PostgreSQL остановлен.

## 3. Аудит и профиль затрат

Исходная цепочка:

`BudgetController → WindowsNoteBoundary worker → QestoCoordinatorDomain →`
`QestoNoteExecutor → prepareTransactionNote → shared Synoball → codec v7 →`
`encrypted Transaction Container + outbox → HTTP/backend → authoritative replay →`
`remote projection + checkpoint → controller publication → detail widgets`.

Обнаружены не только SQLite-затраты:

1. Повторное декодирование одного и того же исходного JSON при validate/read/effect.
2. Инициализация core повторно применяет configured category policy и derived state.
3. Подготовка заметки создаёт полные legacy/Sber projections.
4. Diff и before/after core digest обходят полное canonical state.
5. Codec и PostgreSQL state сериализуют полный профиль.
6. Входящий bundle требует authoritative replay и построения полной local projection.
7. Через isolate возвращается полный `CommittedTransactionNote`, а не малая delta.

### Native JIT decomposition до оптимизации

Один запуск для каждого размера; это **не сравнение с Flutter/AOT latency**.
Декомпозиция вызывает существующие публичные функции, а её полный результат
проверяется на равенство обычному `prepareTransactionNote`.

| Фаза | 1k, мс | 10k, мс | 50k, мс |
|---|---:|---:|---:|
| Codec decode | 44,6 | 346,3 | 1 856,8 |
| Core initialization + configured policy | 24,2 | 178,5 | 909,1 |
| Core update | 10,9 | 64,9 | 411,8 |
| Legacy projection | 6,5 | 18,8 | 110,0 |
| Sber presentation projection/policy | 20,8 | 185,0 | 1 052,1 |
| Codec encode | 44,5 | 235,7 | 1 208,5 |
| Canonical entities diff | 58,0 | 297,0 | 1 512,2 |
| Before + after core hashes | 88,8 | 639,6 | 3 477,4 |
| Full encrypted container commit | 151,3 | 1 232,8 | 5 702,1 |

Полный codec payload: 1 526 642 / 15 095 642 / 75 482 338 байт.
На 50k native decomposition завершилась, peak RSS JIT-host — 1 698 910 208 байт,
включая тестовый runtime/компилятор. Это не RSS установленного Flutter приложения.

### Покрытие 13 требуемых измерений

| Участок | Полученное измерение / ограничение |
|---|---|
| Decode | Отдельно в native decomposition и instrumented AOT executor |
| Synoball + policy | Отдельные native фазы; на сервере общий вызов production preparation |
| Canonical/legacy projections | Отдельные legacy/Sber фазы; canonical входит в core |
| Changed entities | Полный diff; обычная заметка — 1 canonical entity, отдельный regression — несколько |
| JSON encode | Отдельная фаза; полные before/after hashes также измерены |
| Isolate transfer | Реальный envelope SendPort round-trip: 4,7–5,5 мс / 78,5–143,7 мс / 750–833 мс для 1k/10k/50k |
| SQLite/WAL | Время commit envelope, payload/chunks, DB/WAL/SHM, backpressure и native fault tests |
| HTTP | Coordinator network time и UTF-8 body bytes; latency включает server work, это не чистая задержка сети |
| Server Synoball | На 10k AOT: 458–558 мс для core/policy/projections |
| PostgreSQL | Подготовка сериализации/SQL/effects tail: 785–860 мс; полный server transaction: 2 064–2 223 мс |
| Incoming validation/replay | Receiver remote_prepare на 10k: 2 860–3 426 мс, включая проверку и projection |
| Receiver commit | 1 693–2 390 мс на 10k; включает storage envelope, не только fsync |
| Publication/UI | Микросекундная controller publication; фактический pump двух detail widgets, медиана 32,5 мс на 10k |

SendPort probe измеряет **двустороннее копирование envelope + scheduling**, не
точную одностороннюю передачу production UI. Его logical codec size не равен
внутреннему формату Dart IPC. CPU измерен через GetProcessTimes: kernel+user CPU
процесса, включая оба worker isolates. CPU PostgreSQL и суммарный системный CPU
отдельно не измерены; Windows-квантование может давать 0 для короткой фазы.

Ограничение сохранённой телеметрии: поле
`server.phases.codec_decode.input_bytes` содержит длину Dart String в UTF-16 units,
не UTF-8 bytes (на 10k: 15 095 204 против 15 095 642). Оно не использовалось для
вывода об объёме записи. В `profile-baseline.input_bytes`, server `bytes`, HTTP и
`written_payload_bytes` измерены именно UTF-8 bytes. Нулевые bytes остальных
phase-записей означают «не инструментировано», а не отсутствие обработки данных.

## 4. Выбор архитектуры

| Вариант | Стоимость и миграция | Безопасность/восстановление | Производительность и развитие |
|---|---|---|---|
| A: финансовые SQL-таблицы | Нужен полный mapping canonical/evidence/locks/trash и schema evolution | Много новых финансовых инвариантов и parity gates; восстановление через модель | Потенциально малая запись/чтение, но core пока всё равно O(N) |
| B: versioned opaque chunks | Минимальное storage-only изменение, codec v7 остаётся контрактом | Lossless reconstruction, ordered manifest + hashes, прежняя атомарная transaction | Малые изменения записывают мало chunks; полное чтение/compute остаётся O(N) |
| C: гибрид | Нужно определить границу ownership полей и containers | Риск рассогласования SQL и opaque частей; сложнее migration/recovery | Перспективен после контракта domain effects, не как быстрый обход модели |

**Реализован B.** A/C рассмотрены, но не внедрены. Решение и бюджеты записаны в
`DECISION.md` после baseline profiling и до оптимизированных benchmarks.

### Единственное authoritative представление

В format 2 `state`/`shadow` содержат versioned manifests. Сами финансовые bytes
лежат в `json_chunks(scope, slot, body, hash)`. Полного дублирующего JSON snapshot
на диске нет. Local projection и server shadow остаются разными слоями существующего
sync-контракта, не независимыми финансовыми моделями.

Chunks разделяются по детерминированным лексическим границам JSON: корневые поля
и группы из 32 разделителей на record-level глубине. Строки, escape sequences,
Unicode и форматирование сохраняются без перекодировки значений. Изменение длины
заметки не сдвигает все последующие byte offsets. Номер slot — физическая позиция,
не financial ID. Вставка/перестановка коллекции может изменить много chunks.

Manifest содержит версию, scope, упорядоченные hashes и полный document digest.
Чтение проверяет количество/порядок строк, hash каждого chunk и root digest.
Каждая запись вычисляется из **полного результата существующего executor**, а не
из предположения «изменилось только поле note».

В одной SQLite transaction фиксируются все связанные chunks, manifests,
revision/journal и immutable command/outbox. Remote apply в той же transaction
фиксирует shadow, projection, context/revisions, receipts, coverage, aliases,
conflicts и checkpoint. Incoming apply не создаёт исходящую команду.

Остались полными JSON: sync context/revision map, определённые журнальные структуры,
server PostgreSQL state. Не объявляем эту схему полной нормализацией или O(changes).

### Кеши и ownership

- Один FIFO writer owner на профиль, работа вне main isolate — существующая модель.
- Decoded executor cache: максимум 2 точных input Strings, привязанных к owner.
  Никаких skipped validation/rules/replay или межпользовательского кеша.
- Storage read cache: state/shadow, DB identity + total_changes + data_version +
  manifest. Raw test writes инвалидируют кеш; другой DB handle не переиспользует его.
- Байты, подготовленные во время записи, публикуются в read cache **только после
  COMMIT**. Rollback не публикует speculative state. Ошибка чтения после commit
  помечает owner требующим reopen; неизвестный ACK разрешается lookup/retry того же ID.
- Вновь открытая база восстанавливается из encrypted rows и проверяет hashes,
  а не доверяет старым кешам.

Кеши ограничены числом элементов, **не размером в байтах**. Их RAM-стоимость стала
существенной; эти настройки не рекомендуются для production без нового решения.

## 5. Найденные и исправленные проблемы

1. **Pull-derived receipts сохранялись отдельно от remote apply.** Теперь сначала
   валидируется вся страница, затем её receipts и coverage коммитятся вместе с
   финансовым состоянием/cursor. Push ACK остаётся отдельно durable по прежнему
   контракту. Регрессия проверяет rollback всех частей до checkpoint.
2. **Первый chunk prototype всё ещё перечитывал/хешировал полный JSON сразу после
   успешной записи.** Добавлена post-commit promotion только точных записанных bytes.
   First-pass evidence сохранено, а не заменено улучшенным результатом.
3. **Кеш не должен скрывать raw corruption.** Ключ инвалидируется по DB changes/version;
   тесты сначала прогревают кеш, затем портят row/manifest/hash и требуют отказа.
4. **50k startup failure маскировался вторичным LateInitializationError тестового
   harness.** Добавлены ready guard и cleanup частично открытых owners. Исходный
   провал 50k сохранён; после cleanup-only исправления 50k не перезапускался.
5. На финальном review устранён deprecated `dispose` у sqlite statement; отдельно
   повторён chunk suite и добавлена format-2 проверка missing/corrupt/wrong key,
   восстановления исходного ключа и key rotation с сохранением pending command.

## 6. Benchmarks

### Исходный Stage 4b сохранён

`results/baseline-4b-*` — копии прежних результатов, не перезаписанные новой схемой.
Исходный 10k: local 4,10–4,62 с, sender 11,72–13,46 с, receiver 8,26–8,68 с,
peak 696,6 MiB. Старый benchmark имел другой UI workload; эти числа не являются
контрольной группой нового rendered-UI сравнения.

### Сопоставимый контроль и новая схема

Одинаковые fixtures, 3 последовательные правки для каждого размера, Flutter test
debug VM, 2 настоящих BudgetController + отрисованные TransactionDetailsScreen,
AOT server и native encrypted SQLite. Ни baseline, ни optimized не сравниваются
здесь с Flutter release AOT. Это два UI-host в одном test process, **не два
установленных самостоятельных desktop executable**. Отдельные native processes
используются в crash/restart tests.

| Размер / метрика | Старый путь, медиана | Новый путь, медиана | Изменение |
|---|---:|---:|---:|
| 1k local edit | 562,7 мс | 367,0 мс | −34,8% |
| 1k sender push+pull | 1 470,6 мс | 1 237,9 мс | −15,8% |
| 1k receiver | 1 009,9 мс | 810,8 мс | −19,7% |
| 10k local edit | 5 436,4 мс | 3 913,6 мс | −28,0% |
| 10k sender push+pull | 15 235,0 мс | 11 107,5 мс | −27,1% |
| 10k receiver | 10 551,0 мс | 6 840,0 мс | −35,2% |
| 10k host CPU, 3 фазы вместе | 35 703 мс | 25 938 мс | −27,4% |
| 1k peak host RSS | 287,4 MiB | 326,8 MiB | хуже |
| 10k peak host RSS | 736,6 MiB | 1 123,0 MiB | +52,5%, хуже |

На 10k max main-isolate timer gap: 54,93 → 57,23 мс. Pump двух detail widgets:
медиана 38,89 → 32,52 мс. Это не display frame/raster p95 и не гарантия 60 FPS.
Peak RSS — process high-water mark, включает историю аллокаций обоих controllers,
worker isolates и harness. Три прогона не дают статистически надёжного p95;
цифры являются локальным инженерным ориентиром.

Предварительно установленные budgets:

| Budget на 10k | Результат |
|---|---|
| Local ≤ 3 с | FAIL: 3,914 с |
| Receiver ≤ 6 с | FAIL: 6,840 с |
| Peak RSS рост ≤ 10% | FAIL: +52,5% |
| Financial SQL payload < 5% полного профиля | PASS: 3,61% |
| Желательное ускорение ≥ 2x | Не достигнуто end-to-end |

### Bytes, диск, server

- Обычная local note: 1 changed canonical entity, 3 financial chunks,
  544 752 байт включая manifest против 15 095 642 байт полного v7.
- После первого local+sender sync на 10k: A суммарно записал 1 633 267 байт
  financial chunk payload (8 chunks), B — 1 089 471 (6 chunks).
  Outbox/context/SQL metadata и physical I/O в эти числа не входят.
- Первый 10k sample: baseline A DB 46 563 328 / WAL 0 / SHM 98 304 байт;
  incremental A DB 60 493 824 / WAL 1 429 672 / SHM 32 768.
  К третьей правке DB A 60 502 016 байт. Меньшая запись не означает меньшую базу.
- HTTP payload не изменился: первая правка A sent body 343 / received 3 230 байт,
  B received 2 765. Не учтены HTTP/TCP headers; сеть не является причиной полного
  15 MB финансового encode. Основная стоимость на стороне исполнения/replay.
- Сервер продолжает записывать полный PostgreSQL state около 15,1 MB.
  Cached decode уменьшает повторную работу, но schema/protocol v1 не заменены.

### 50k

Native decomposition и реальный envelope handoff завершились. Полный Flutter
benchmark **FAIL**: WindowsNoteBoundary.open не уложился в неизменённые 30 секунд.
Дальнейшие local/push/pull не измерены. Тайм-аут не увеличивали ради зелёного теста.
Нельзя заявлять, что новая архитектура end-to-end проверена на 50 000 операций.

## 7. Safety, fault, recovery и semantic parity

### Подтверждённые сценарии

- Одна заметка, повторная правка той же операции, последовательные разные операции.
- Две offline disjoint edits, A → B и B → A, конфликт того же поля и restart.
- Повтор immutable command ID, collision/stale revision rejection, lost server ACK.
- Полное сравнение canonical state, tags, audit/events, legacy projections и всего v7
  между клиентами и сервером, а не только сумм/количеств.
- Отдельный stale-policy fixture: правка заметки имеет эффекты в нескольких
  canonical entities; новый executor и chunks сохраняют полный результат старого.
- Неизменность unrelated root sections, точных money/source/locks/override/trash
  покрывается полной fixture equality и сохранёнными shared/parity regressions.
- Interrupted local update после первой chunk row, после state до outbox,
  непосредственно до commit и после commit до ответа.
- Remote process death до checkpoint: ни частичный профиль, ни cursor не остаются;
  повтор страницы применяется один раз и не создаёт исходящую команду.
- Порча chunk row, manifest и hash отвергается; база не сбрасывается и не заменяется
  пустым профилем. Проверяются случаи с уже прогретым read cache.
- Encrypted backup/recovery сохраняет state bytes, revisions и pending immutable
  commands. Format 2 прошёл wrong/missing/corrupt key и успешную смену ключа.
- SQL format 1, old coordinator/backend и ранее существовавшие regression suites
  проходят с default-настройками.

### Native faults format 2

| Инъекция | Наблюдение |
|---|---|
| SQLITE_FULL | Extended code 13, ACK нет, reopen → revision 0, тот же ID → revision 1 |
| xWrite failure | 778, ACK нет, reopen/retry сохраняет атомарность |
| xSync failure | 1034, ACK нет, reopen/retry сохраняет атомарность |
| Partial write | 778, без подтверждения частичного нового состояния |
| Checkpoint error после commit | ACK уже durable, reopen required, revision 1; retry того же ID остаётся revision 1 |
| Native process exit во время checkpoint | Exit 86; reopen → revision 1, одна pending command |

Это реальные вызовы native SQLite через fault-injecting VFS на synthetic files,
**не физическое отключение питания и не доказательство всех аппаратных отказов**.
Dart exception hooks дополнительно проверяют transaction rollback; они обозначены
отдельно от native I/O injection. Отдельная многогигабайтная реальная переполненная
файловая система в этом этапе не создавалась.

### WAL и диск

Сохранена существующая policy: synchronous FULL, auto-checkpoint 1000 pages,
busy_timeout 100 мс, journal_size_limit 8 MiB после reset; soft 32 MiB / hard
256 MiB, disk floor 256 MiB и консервативный projected-write headroom.
BUSY не интерпретируется как успешный checkpoint; отказ записи/checkpoint требует
reopen, а post-commit ошибка не отменяет durable ACK.

Format-2 pinned-reader test с уменьшенными лимитами: 29 commits, peak WAL 1 001 192
байт ниже hard 3 MiB, затем backpressure; после закрытия reader снова возможна
запись, DB/WAL/SHM = 151 552 / 45 352 / 32 768 байт. WAL/SHM вручную не удаляются.

Headroom пока оценивается консервативно от полного payload. Это может блокировать
большие профили раньше фактической потребности chunks. Уменьшать guard без измеренного
write-amplification bound не стали. Новый soak на сотнях тысяч команд не выполнен;
это открытая проверка, не закрытая тремя benchmark edits.

## 8. Результаты проверок

Машиночитаемый индекс: `experiments/incremental_sync_performance/results/summary.json`.

| Набор | Успешных прохождений | Результат |
|---|---:|---|
| Новый native/storage/sync/handoff suite | 34 | PASS |
| Два actual Flutter UI-host | 3 | PASS |
| Backend 3a regression | 27 | PASS |
| Encrypted client 3b regression | 23 | PASS |
| Storage contracts/process/policy | 119 | PASS |
| Shared core parity/goldens | 33 | PASS |
| Старый 4b semantic/integration | 15 | PASS |
| Qesto desktop/classification/write-safety/trash/codec/recovery/shared/Synoball subset | 68 | PASS |
| Matched baseline 1k/10k | 2 | PASS |
| Matched incremental 1k/10k | 2 | PASS |
| Финальное повторение chunk suite + дополнительный key/rotation regression | 13 | PASS |
| Flutter 50k end-to-end | 0; 1 failed | FAIL, startup timeout |

Итого 339 успешных **прохождений**, не 339 уникальных определений: наборы частично
пересекаются, последний chunk suite повторён после review. Семь analyzers —
No issues found. Последний deprecated-member diagnostic устранён и analyzer
повторён. Сборки Windows AOT experiment server/client/native probes успешны.
Dart SDK 3.12.2, Windows x64; sqlite3 package 3.5.2 с SQLite3MultipleCiphers.
`git diff --check` с учётом Windows CRLF — exit 0; новые исходники проверены
анализаторами и Dart formatter.

Полный Flutter suite всего приложения и production Windows release build в этом
этапе не запускались: приложение не менялось. Выполнен указанный desktop/persistence
regression subset. Не выполнялась новая проверка Android/physical devices или
публичного deployment. Сохранены старые golden/parity tests, их ожидания не ослаблялись.

После timing runs были только safety/diagnostic/test правки: commit-read poisoning,
50k harness cleanup, современный statement close, дополнительные проверки ключей
и collector. Финальные safety/regression suites относятся к исправленному коду;
latency samples не следует считать точным performance certification каждой
последующей незначительной правки. Новый release benchmark остаётся отдельным gate.

## 9. Файлы

Ниже полный список исходных изменений Stage 4c; не весь накопленный dirty worktree.

### Изменены существующие экспериментальные файлы

```text
experiments/storage_feasibility/lib/container/contract.dart
experiments/storage_feasibility/lib/container/sqlite_container.dart
experiments/encrypted_client_sync/lib/bootstrap.dart
experiments/encrypted_client_sync/lib/coordinator.dart
experiments/encrypted_client_sync/lib/transport.dart
experiments/windows_integration_boundary/lib/windows_note_boundary.dart
experiments/windows_synthetic_ui_sync/lib/harness.dart
experiments/windows_synthetic_ui_sync/lib/qesto_coordinator_domain.dart
experiments/windows_synthetic_ui_sync/lib/qesto_note_executor.dart
experiments/windows_synthetic_ui_sync/bin/server.dart
experiments/windows_synthetic_ui_sync/test/integration_test.dart
experiments/windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart
experiments/synthetic_sync_backend/lib/domain_executor.dart
experiments/synthetic_sync_backend/lib/database.dart
```

Новые файл/пакет:

```text
experiments/storage_feasibility/lib/container/chunked_json.dart
experiments/incremental_sync_performance/
  .gitignore
  pubspec.yaml
  pubspec.lock
  PLAN.md
  DECISION.md
  README.md
  Versioned_Incremental_Domain_Proposal.md
  lib/cached_executor.dart
  lib/harness.dart
  lib/measure.dart
  bin/server.dart
  bin/client_probe.dart
  bin/profile_baseline.dart
  test/chunk_storage_test.dart
  test/native_chunk_fault_test.dart
  test/sync_integration_test.dart
  test/profile_baseline_test.dart
  test/handoff_profile_test.dart
  flutter_runner/pubspec.yaml
  flutter_runner/pubspec.lock
  flutter_runner/test/two_ui_hosts_test.dart
  flutter_runner/test/benchmark_test.dart
  tool/capture_baseline.ps1
  tool/configure_app_seam.dart
  tool/run_checks.ps1
  tool/collect_results.dart
docs/sync/2026-10-14/Incremental_Sync_Performance_Report.md
```

Новые evidence-файлы в `experiments/incremental_sync_performance/results/`:

```text
baseline-4b-summary.json, baseline-4b-ui-sync-benchmarks.json,
baseline-4b-semantic-parity.json, baseline-4b-controller-semantic-gate.json,
source-baseline.json, source-verification.json, summary.json,
profile-baseline.json, profile-baseline-run.jsonl, isolate-handoff.json,
chunk-write-evidence.json, chunk-wal-pressure.json, native-chunk-faults.json,
two-owner-parity.json, two-ui-hosts.json,
native-tests.jsonl, native-final.jsonl, chunk-tests.jsonl, chunk-final-review.jsonl,
flutter-tests.jsonl, ui-final.jsonl, flutter-50k.jsonl,
flutter-baseline-1000-10000.json, flutter-incremental-1000-10000.json,
flutter-incremental-first-pass.json,
flutter-matched-baseline.jsonl, flutter-matched-incremental.jsonl,
backend-regression.jsonl, client-regression.jsonl, storage-regression.jsonl,
shared-parity.jsonl, old4b-regression.jsonl, app-regression.jsonl,
analyze-initial.txt, analyze-incremental_sync_performance.txt,
analyze-storage_feasibility.txt, analyze-encrypted_client_sync.txt,
analyze-windows_integration_boundary.txt, analyze-windows_synthetic_ui_sync.txt,
analyze-synthetic_sync_backend.txt, analyze-flutter-runner.txt
```

Перезапуск прежних suite может обновлять их generated results/build/.dart_tool.
Это не изменение production source. Временные encrypted fixtures и native/AOT
build output не являются поставляемыми приложениями. Точная source-verification
покрывает 578 заранее снятых файлов; bin/test seams вне снимка перечислены вручную.

## 10. Воспроизведение

Из `experiments/incremental_sync_performance/`:

```powershell
./tool/run_checks.ps1 -Regressions
./tool/run_checks.ps1 -Benchmarks -Regressions
dart tool/collect_results.dart
```

Нужны существующие pinned SDK/cache/native VFS shim и owned synthetic PostgreSQL
cluster предыдущих этапов. Скрипт запускает локальный cluster и останавливает его
в finally. `capture_baseline.ps1` запрещает перезапись существующего baseline.
Pub/native hooks могут потребовать доступ к SDK/Pub cache. Benchmark запускается
последовательно, без параллельной нагрузки других тестов.

`collect_results` падает при неожиданно неуспешном обязательном suite/analyzer или
изменении production source. Известный 50k gate и budgets выводятся отдельно как
FAIL; успешный exit collector **не означает production readiness**.

## 11. Что осталось предложением; безопасная миграция

Подробности: `Versioned_Incremental_Domain_Proposal.md` в новом эксперименте.

Не реализованы:

- versioned mutation-result contract shared core со всеми changed IDs,
  tombstones, audit/events и derived invalidations;
- разделение загрузки состояния с актуальной policy и применения новой policy;
- долгоживущий revision/policy-bound domain owner с малой UI delta;
- PostgreSQL manifest/chunk schema под прежним workspace transaction lock;
- protocol v2 / authenticated incremental digests вместо whole-core digests;
- production migration/activation, retention/compaction и расширение команд.

Предлагаемая будущая миграция — только после отдельного решения: остановить writer,
сохранить encrypted source+outbox+key backup, создать новую staging generation,
экспортировать полное v7, построить chunks, реконструировать и сравнить bytes/values,
IDs/locks/trash/evidence/все root sections/pending commands, проверить recovery,
затем явно и атомарно переключить generation. Не переписывать профиль in-place,
не удалять WAL/SHM, не восстанавливать пустую базу при ошибке и не откатываться к
состоянию, теряющему новые accepted/pending commands.

## 12. Итоговая граница

**Можно принять Stage 4c как измеренный storage-only эксперимент и технически
обоснованную границу дальнейшей оптимизации. Нельзя принимать его как готовое
production incremental storage.**

Основные открытые риски: RAM, O(N) full-core work и hashes, whole PostgreSQL state,
50k startup, write-budget overestimation, долгоживущие журналы/телеметрия,
release-process profiling и отдельный migration/recovery review.

Финансовые/security гарантии не ослаблялись ради быстродействия. Следующий этап
не начат; рабочие данные и установленные Qesto остаются на прежнем пути.
