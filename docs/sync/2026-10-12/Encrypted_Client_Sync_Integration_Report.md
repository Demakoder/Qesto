# QESTO Sync 3b — Encrypted Client ↔ Sync Backend

Дата: 12.10.2026. Платформа: Windows x64. Данные: **исключительно синтетические**.

## Решение

Ограниченный этап 3b выполнен: два независимых CLI-клиента с собственными
зашифрованными SQLite-контейнерами сохраняют заметки офлайн и обмениваются ими
через существующий локальный Dart/PostgreSQL backend 3a. Проверены сходимость
разных правок, сохранение конфликтующих предложений и восстановление после
конкретных сбоев процессов, доставки и ключевого файла.

**Это не готовая синхронизация рабочего Qesto.** Доказан узкий note-only сценарий
на существующих ID, с одинаковым первоначальным синтетическим профилем и новой
серверной epoch. Рабочий repository, BudgetController, банковские адаптеры,
профили, установленное приложение и Android не подключались и не изменялись.
Этап не включает миграцию production или передачу реальных данных.

Основа: протокол разработки v0.1, документы Sync A–E, отчёты
[2b.0](../2026-10-11/Transaction_Container_Contract_Report.md) и
[3a](../2026-10-11/Synthetic_Sync_Backend_Report.md).

## 1. Архитектура и повторное использование

```text
CLI A: свой device/token                      CLI B: свой device/token
       свой DPAPI vault                             свой DPAPI vault
       свой encrypted SQLite                        свой encrypted SQLite
       snapshot / outbox / receipts                  snapshot / outbox / receipts
       shadow / sync context / checkpoint            shadow / sync context / checkpoint
                    │                                      │
                    └──── loopback HTTP, API 3a ────────────┘
                                      │
                           Dart server → PostgreSQL
                           existing shared Synoball
```

Переиспользованы, без второй реализации финансовых правил:

- `storage_feasibility`: `SqliteContainer`, `ContainerWriter`, immutable command
  journal, receipts, CAS revision, exclusive owner lock, DPAPI, backup/rotation,
  SQLite3MultipleCiphers через sqlite3 **3.5.2**, FULL/WAL policy.
- `synthetic_sync_backend`: существующий push/pull, `NoteCommand`, money wire
  format, content digest, signed cursor, workspace/epoch isolation, server receipt,
  PostgreSQL commit sequence и fault server.
- `qesto_synoball_core`: тот же `SynoballCore.updateTransaction` через имеющийся
  `domain.applyNote` backend 3a. Новой дедупликации или reconciliation нет.
- Реальный `UserFinancialDataCodec` **v7** приложения, а не его копия: отдельный
  test gate проверяет decode → encode с равенством значений и порядка списков.
- Существующий полный fixture 2b.0 со счетами, бюджетами, целями, долгами,
  инвестициями и настройками. В нём меняется только синтетический Synoball-набор
  и добавляется совпадающая legacy-проекция операции для проверки комментария.

Новый пакет имеет только path dependencies на эти три экспериментальных/shared
пакета и существующий `test`. Новые внешние библиотеки не добавлялись.
Незашифрованный file client 3a не используется в качестве клиента 3b.
JSON fixtures и диагностический вывод существуют только в синтетическом harness.

### Минимальное расширение Container

Добавлен отдельный optional `SyncTransactionContainer`. Базовый интерфейс
`TransactionContainer` сохранён. В `RemoteBundle` добавлены optional `projection`
и `syncContextJson`; при их отсутствии прежняя сериализация и консервативное
поведение 2b.0 сохраняются.

`initializeRemoteContext` допускается **только явно**, на свежем контейнере:
revision=0, checkpoint=0, пустой outbox. Он создаёт внутри encrypted DB таблицу
`sync_context`, содержащую owner/device/workspace/epoch, opaque cursor, entity
revisions и применённые page identities. Автоматического обновления старых
контейнеров нет. Это изменение экспериментальной схемы, не production migration.

Для включённого sync context запрещён remote apply без пары projection/context.
Контекст включён в проверки целостности и fingerprint backup/recovery; его cursor
сверяется с числовым checkpoint. Все части remote apply сохраняются одним commit.

### Адаптер полного профиля

`ProfileAdapter` сохраняет корневые поля v7 и локальные raw/provenance. Он заменяет
только существующие canonical entities, затем отражает **изменившиеся** заметки
в legacy-комментариях. Незатронутые legacy-комментарии не переписываются.

Суммы передаются целыми minor units с валютой/scale=2; IDs, суммы, направление,
статус, account/source identity, пользовательские overrides и tags не должны
меняться note-командой. Неожиданное изменение защищённого поля или новая удалённая
операция останавливает применение страницы. Разрешены заметка, timestamp/trust
и конкретные merchant/category enrichment-поля, которые действительно меняет
существующий shared core. Сам core и его правила не менялись.

Ограничение: 3a передаёт canonical entities и receipts, а не полный server
audit/raw state. Локальные raw/audit не теряются, но complete audit replication
не реализована. Lossless gate доказывает сохранение полного **локального** v7
профиля в этом сценарии, а не тождество всех audit-журналов двух устройств.

## 2. Цепочка local commit → push → receipt → pull → checkpoint

1. Intent `transaction.set_note` проходит существующий shared core.
2. Full snapshot и immutable wire command записываются одной SQLite-транзакцией.
   Только после commit возвращается `local_ack`. Сеть при этом не нужна.
3. Coordinator читает queued commands и отправляет существующий ID/body. На
   повторном запросе ID не пересоздаётся и команда не редактируется.
4. HTTP 200 недостаточен: проверяются protocol/domain version, workspace/epoch,
   change ID, digest, target, commit sequence, status и entity revision.
   Valid receipt сохраняется локально. **Push receipt не двигает pull cursor.**
5. Pull валидирует страницу целиком: последовательность bundle, receipts,
   revisions, money, protected fields, page boundaries. Собственная accepted
   заметка сверяется с entity в её journal position, не с концом страницы.
6. Полученные receipts могут быть сохранены до remote transaction. Crash здесь
   оставляет accepted command непокрытой и старый cursor для безопасного replay.
7. Одним commit сохраняются incoming shadow, full-profile projection, sync
   metadata, применённый bundle, covered commands и checkpoint.

Transport разрешает только `http://127.0.0.1`, не следует redirects; ограничены
response size, connect/request timeouts. На transient socket/HTTP/timeout/503 —
до трёх попыток с паузами 100/200 ms. Auth/version/invalid receipt останавливают
операцию сразу. Это loopback test authentication, не TLS/OIDC production.

Один owner держит SQLite lock весь срок жизни CLI. Normal SQLite work выполняет
`ContainerWriter` в isolate; coordinator сериализует изменения. Фонового
scheduler/второго delivery worker в эксперименте нет.

## 3. Результат двухклиентского сценария

Сервер действительно остановлен между bootstrap и двумя local edits. Оба клиента
подтвердили commit с checkpoint=0. После запуска сервера:

- A отправил заметку операции 0; его checkpoint остался 0 до pull.
- B получил заметку A, сохранив собственную pending-заметку операции 1.
- B отправил свою правку; после pull canonical transactions A и B совпали,
  оба checkpoints=2, оба pending outboxes пусты.
- Новая правка A после этого доставилась B при следующем pull.
- Проверены точные minor units **486122 RUB / 1500025 USD / 13 RUB**,
  deleted-операция, user category override и locks/tags.
- Все unrelated корневые разделы остались прежними; raw provenance сохранился.
  Реальный v7 codec roundtrip прошёл для обоих результатов.
- Два native DB-файла не имеют plaintext SQLite header и строки private note.
  DPAPI vault bytes не менялись при обычных edit/sync. Дополнительно выполнены
  унаследованные native encryption/key tests — поиск строки сам по себе не
  считается доказательством криптографической стойкости.

Источник: `experiments/encrypted_client_sync/results/two_encrypted_clients.json`
и соответствующий integration test.

### Конфликт

При двух правках одного поля сервер сохраняет A, B получает явный conflict receipt
с proposed/current note и revisions. У B authoritative shadow=A, локальное
предложение=B; immutable command остаётся в outbox. `sync` возвращает
`requires_attention`, не `synchronized`. Повторные процессы/sync не меняют обе
версии и не создают новые серверные effects. Нет безусловного last-write-wins.

На один target допускается одна outstanding-команда. Автоматического разрешения
конфликта и общего rebase нет; это явное ограничение, а не скрытая потеря правки.

## 4. Fault / recovery / regression

| Сценарий | Метод проверки | Подтверждённый результат |
|---|---|---|
| Crash до local commit, два места | Native CLI process exit(86) | Ни нового snapshot, ни outbox; следующий процесс открывает прежнее состояние |
| Crash после commit до push | Native CLI process exit(86) | Snapshot и та же immutable-команда восстановлены; server head ещё 0 |
| Push разорван до server commit | Gate в реальном server process + kill | Server head 0; retry того же ID затем даёт один effect |
| Ответ потерян после server commit | Drop-response hook backend | Server head 1; очередь не подтверждается без receipt; retry не даёт второй effect |
| Crash при записи receipt | Native client exit внутри транзакции | Queued command и старый cursor; повтор безопасен |
| Crash при incoming apply, два места | Native client exit до checkpoint / до commit | Старые projection/shadow/checkpoint восстанавливаются; replay применяется |
| Повтор уже применённой страницы | Закрытие/повторное открытие encrypted DB | No-op без новой local revision |
| PostgreSQL restart | Реальный stop/resume только owned cluster | Receipt и journal сохранены; второй клиент получает правку |
| Missing/corrupt key vault | Удаление через rename / порча только synthetic vault | Fail closed; DB не сброшена, новый пустой vault не создаётся; explicit recovery исходным ключом |
| Concurrent writer / stale revision | Второй CLI при открытом owner, CAS и ID collision | Отказ; существующая очередь не повреждена |
| Incompatible remote state | Мутации ответа: revision/amount/seq/version/epoch | До применения; local revision и checkpoint прежние |
| HTTP200 без receipt, auth/version errors | Подставной response/ошибка transport в тесте | Одна попытка, нет ACK и cursor movement |
| Backup или rotation | Два отдельных encrypted клиента, reopen | Sync context/checkpoint сохранены |
| Избыточные клиентские credentials | Strict client config parser + отдельные CLI configs | DB password, cursor signing key, чужие principal records отвергаются |

Процессные аварии — не аппаратное отключение питания. Не заявляется hot restart
после `Isolate.kill` с живыми FFI handles. Подменённые ответы и test hooks явно
отделены от настоящего перезапуска PostgreSQL/клиентских процессов.

Последний полный прогон завершён **12.10.2026 19:47:24 UTC**: **235 тестов**,
без ошибок и skips. Машиночитаемый итог:
[`summary.json`](../../../experiments/encrypted_client_sync/results/summary.json).

| Набор | Passed |
|---|---:|
| Новый 3b: integration + adapter/identity | 23 |
| Backend 3a regression | 27 |
| Shared Synoball parity/regression | 33 |
| Storage contracts/process/hardening policy | 119 |
| App codec/storage recovery/Synoball compatibility/safety | 33 |

`dart analyze` нового пакета и storage prototype — без замечаний. Собраны AOT
CLI client, benchmark и прежний container probe. SHA-256 проверка **540 файлов**
app/shared `lib` и `test` не выявила изменений относительно начала 3b.
Это не проверка всех файлов репозитория и не чтение production-профиля.

Форматирование 18 Dart-файлов проверено: 0 изменений. Дополнительная проверка
38 сохраняемых файлов пакета/отчёта на совпадение с пятью фактическими synthetic
secret values из isolated configs — совпадений нет. `.runtime`, builds и
`.dart_tool` исключены из Git. Это scoped leak check, не полный security audit.

Полная Flutter UI-suite и Windows release приложения не запускались: UI и
production integration здесь отсутствуют. Выполнены перечисленные применимые
app regressions. Android/эмулятор/физический телефон не использовались.

## 5. Производительность и стоимость full snapshot

Финальный AOT прогон: 3 последовательные правки для каждого размера, два
ContainerWriter owners с отдельными encrypted DB в одном benchmark-процессе,
настоящие HTTP/PG. Для функциональных тестов выше используются независимые CLI
процессы. На каждом benchmark trial проверяются сходимость и checkpoint.

| Метрика | 1 000 canonical operations | 10 000 canonical operations |
|---|---:|---:|
| Local core + serialization + commit, диапазон | 104–109 ms | 1 452–1 496 ms |
| CPU этого local шага | 109 ms | 1 563–1 672 ms |
| Sender push + receipt + собственный pull | 320–359 ms | 4 581–4 814 ms |
| Receiver pull + apply | 212–239 ms | 1 765–2 257 ms |
| Full snapshot JSON | 0,73 MiB | 7,13 MiB |
| Peak RSS benchmark-процесса | 79,5 MiB | 207,6 MiB |
| WAL во время trials | 2,31 MiB | 22,22 → 14,91 → 8,00 MiB |
| DB после закрытия | 2,35 MiB | 22,14 MiB |

FULL, auto-checkpoint=1000 pages, soft WAL=32 MiB, hard WAL=256 MiB. Disk floor
256 MiB + write-amplification headroom не ослаблялся. CPU/RSS не включают отдельные
процессы Dart server и PostgreSQL; RSS включает обе клиентские стороны harness.
Это короткие workstation-замеры, не p95/load test и не оценка Flutter UI frames.
Полные samples:
[`benchmarks.json`](../../../experiments/encrypted_client_sync/results/benchmarks.json).

Исторический результат 2b.0 для **50 000** операций: whole local edit ~4,06 s,
из них serialization ~2,08 s и commit ~1,97 s, peak RSS ~479 MiB. Это прежний
отдельный benchmark, **не новый 3b 50k end-to-end run** и не строго сопоставимый
профиль. Уже текущие 10k timings подтверждают серьёзную стоимость full snapshot.
Нельзя объявить opaque snapshot окончательно пригодным для production.

## 6. Найденные проблемы и исправления

1. Форматы full v7 и server SynoballState различаются: нельзя заменять весь
   пользовательский профиль ответом сервера. Добавлен узкий сохраняющий адаптер
   и actual-codec gate; неизвестные financial mutations отвергаются.
2. Консервативный remote apply 2b.0 удерживал весь локальный snapshot при любой
   pending-команде. Для доказанного different-target note case добавлена explicit
   projection, без изменения старого default и без переписывания queued intents.
3. Numeric checkpoint без durable cursor/revision metadata недостаточен для
   restart. Metadata теперь внутри encrypted remote commit, backup и integrity.
4. Первоначальная проекция могла затирать unrelated legacy fallback comment.
   Теперь изменяются только заметки, реально изменившиеся в canonical; отдельный
   regression покрывает локальную правку, incoming и projection.
5. При review обнаружено, что harness передавал CLI полный server config.
   Разделены client-only credentials; каждый CLI принимает только собственный
   identity/token/epoch. Серверные credentials остаются только у server/harness.
6. Initial tests выявили реальный `merchantConfidence` enrichment при existing
   `applyNote`. Уточнён явный allowlist адаптера; суммы, identities и пользовательские
   overrides не ослаблены. Производственную category policy это ещё не доказывает.
7. Native subprocess JSON первоначально декодировался неверной кодировкой;
   harness явно использует UTF-8. Это исправление тестового транспорта.
8. Backup + rotation подряд в одном fixture упирались в имеющийся two-generation
   retention gate. Проверки разделены на два клиента, gate не отключён. Общая
   compaction/retention policy остаётся обязательным следующим ограничением.
9. 11 октября 10k benchmark остановился с **StoragePressure** при свободных
   ~326 MB на C:. Порог не уменьшался. Удалены только 142 закрытых owned synthetic
   контейнера этого этапа (~66,8 MB), идентичность которых сверена с manifests;
   WAL/SHM отдельно не удалялись. После появления свободного места на C: выполнены
   полные успешные 1k/10k прогоны. Попытка разместить новый synthetic temp на D:
   была отклонена ОС; окончательные результаты получены на C:, не обходом отказа.

Предварительные неуспешные JSONL сохранены отдельно (`tests-first/second/third`),
а не выданы за зелёный итог. `observed_disk_pressure.json` сохраняет ресурсный
отказ. Финальный `summary.json` относится к завершённому повторному прогону.

## 7. Изменённые файлы и воспроизведение

Только три существующих **экспериментальных** файла расширены:

- `experiments/storage_feasibility/lib/container/contract.dart`;
- `experiments/storage_feasibility/lib/container/sqlite_container.dart`;
- `experiments/storage_feasibility/lib/container/writer.dart`.

Новый `experiments/encrypted_client_sync/`:

- `.gitignore`, `pubspec.yaml`, `pubspec.lock`, `PLAN.md`, `README.md`;
- `lib/bootstrap.dart`, `client_identity.dart`, `coordinator.dart`,
  `profile_adapter.dart`, `transport.dart`;
- `bin/client.dart`, `bin/benchmark.dart`;
- `test/harness.dart`, `test/adapter_test.dart`, `test/integration_test.dart`;
- `tool/run.ps1`, `collect_results.dart`, `source_evidence.dart`,
  `codec_gate.dart`, `benchmarks.dart`, `owned_temp_inventory.dart`;
- `results/`: summary, benchmarks, two-client proof, source baseline/check,
  analyzers и JSONL новых/регрессионных проверок; отдельно historical attempts
  и disk-pressure/owned-artifact inventory.

Также добавлен настоящий отчёт. Предыдущие dirty изменения приложения не относятся
к 3b и не были откатаны. Backend 3a и shared core в этом этапе не редактировались.

Из `experiments/encrypted_client_sync`:

```powershell
./tool/run.ps1
```

Prerequisites и локальные SDK paths описаны в README. Нужны подготовленный owned
PG cluster 3a, его fault/regression executables, native metrics DLL storage,
fixture v7 и существующий app package config. Runner не запускает Qesto,
пересобирает CLI/benchmark, сохраняет machine-readable результаты и останавливает
owned PostgreSQL в `finally`. Runtime credentials/builds исключены из Git.
Отчёт не содержит ключей или bearer tokens. Source baseline не перезаписывается
автоматически; для другой checkout её отличие требует review.

## 8. Что препятствует рабочему Windows Qesto

- Нет production repository adapter, migration/rollback или approved key lifecycle.
  Runtime не читает рабочий профиль, поэтому отсутствие изменений подтверждается
  границей доступа и source hashes, а не сравнением реальных финансовых данных.
- Bootstrap работает только с одинаковыми fixtures при server head=0. Присоединение
  нового устройства к существующей истории/nonzero epoch не реализовано.
- Только `set_note` для существующей операции. Accounts/budgets/goals/debts и прочие
  разделы сохраняются локально, **не синхронизируются** между устройствами.
- Нужны production policy parity и mapping canonical ↔ legacy, включая custom
  category rules. Использование default enrichment в synthetic core не позволяет
  безопасно переносить это предположение на реальный профиль без проверки.
- Нет conflict-resolution command/UI, generic rebase, полного audit/source payload
  replication. Outstanding target блокирует следующую note-команду до решения.
- Full snapshots дороги; commands/page identity history не compacted. Нужны
  измеримые retention/GC/cursor-expiry правила без потери idempotency и recovery.
- В isolate вынесен SQLite, но whole-core/JSON работа пока в CLI coordinator
  isolate. Во Flutter следует вынести весь дорогой pipeline, определить CAS,
  публикацию состояния после durable commit, shutdown и background ownership.
- Только test authentication, ignored plaintext test token config и loopback HTTP.
  Нет production OIDC/TLS/session lifecycle, публичного deployment или cross-device
  key recovery. Шифрование клиентской DB не является end-to-end encryption:
  synthetic server имеет доступ к canonical данным.
- Не доказаны hardware power-loss, hot restart после `Isolate.kill`, Android
  runtime/physical-device gate или работа на больших реальных профилях.

## 9. Минимальный следующий PR — предложение, не выполненная работа

**Windows repository / UnitOfWork seam, выключенный по умолчанию, только synthetic
rehearsal.** За отдельным согласованием:

1. Зафиксировать узкий интерфейс local intent → existing core → full v7 snapshot
   + immutable command → durable ACK → UI publication; existing persistence
   остаётся default, никаких auto-migrations и real-profile reads.
2. На synthetic v7 profiles сравнить результаты со штатным repository/codec и
   реальной configured category policy; не дублировать финансовую логику.
3. Определить одного writer owner и lifecycle; вынести core+serialization+SQL
   вне UI isolate. Проверить CAS, shutdown, restart, stale UI и rollback boundary.
4. До включения реального sync отдельно закрыть nonzero bootstrap, explicit
   conflict resolution, identity/auth/key recovery и retention gates.

Этот PR подготовит безопасную границу интеграции, **не разрешит синхронизацию
рабочего профиля**. Переход к следующему этапу, production migration и сетевой
передаче реальных данных в рамках 3b не выполнялись. Работа остановлена на отчёте.
