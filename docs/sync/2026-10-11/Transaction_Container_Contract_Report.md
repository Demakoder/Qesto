# QESTO Sync — 2b.0 Transaction Container Contract & Migration Rehearsal

Дата: 11.10.2026. Windows x64. Только синтетические данные.

## 1. Заключение

**Изолированный контракт реализован и проверен. Подключать его к рабочему
профилю Qesto пока нельзя.** Проверены атомарность snapshot/command,
идемпотентность, delivery metadata, incoming page/checkpoint, migration v7,
generation recovery, WAL backpressure и аварийные сценарии.

Главные незакрытые gates:

1. После `Isolate.kill` в проверенном Windows runtime supervisor получает exit,
   но профиль остаётся заблокированным native/file handles до завершения
   процесса. Повторный writer отвергается, а не продолжает поверх живых handles.
2. Полный snapshot дорог для большой истории; измерения ниже. Flutter frame
   latency и стоимость передачи большого snapshot между isolates не измерены.
3. При pending local changes входящая страница сохраняется в shadow, локальная
   проекция остаётся неизменной, создаётся конфликт. Финансового rebase executor
   здесь нет; это не готовый клиент синхронизации.
4. Portable key recovery, безопасное retirement поколений, Android runtime и
   production security review не завершены.

Production repository, BudgetController, Synoball, codec и финансовые модели
не изменялись. Проверены **540 исходных файлов** app lib/test и shared core
lib/test: SHA-256 до/после совпадают. Реальный `store.json`, банковские профили,
production vault и ключи не читались. APK/установленный Qesto не менялись.
HTTP, сервер, cloud auth и миграция рабочего профиля не реализовывались.

## 2. Повторная проверка архитектуры

Сверены протокол разработки, документы Sync A–E и текущие исходники:

- `LocalQestoRepository`: codec v7, последовательная `_pendingSave`, блокировка
  сохранения после ошибочной загрузки. Нет command ID/CAS/remote shadow.
- `UserFinancialDataCodec`: сохраняет весь профиль, включая legacy projection,
  canonical Synoball, budgets, goals, debts, investments и пользовательскую
  классификацию. Нельзя подменить его сериализацией только SynoballState.
- `RecoverableJsonFile`: JSON primary/backup, очередь и файловый lock. Нет
  атомарной связи профиля с отдельной sync-командой.
- `BudgetController._changed` и app shell `_saveFinancialData`: многие мутации
  выполняются в памяти раньше callback сохранения. Банковский import частично
  staged, но общего mutation envelope для всех путей нет.
- Shared `qesto_synoball_core`: существующие модели, ingestion/reconciliation,
  overrides, trash и сериализация. Нового финансового алгоритма не добавлено.

**Замена одного saveUserFinancialData не решит UoW.** Для будущей интеграции
потребуется staged mutation boundary: существующие модели → immutable intent →
CAS + durable commit → публикация в UI. Это отдельный согласуемый этап.

Из 2a.1 переиспользованы native open/key validation, DirectEngine transaction,
Windows DPAPI primitive, атомарная запись manifest, WAL policy и VFS fault shim.
Новых зависимостей и обновлений SDK нет: sqlite3 3.5.2 / sqlite3mc как прежде.

## 3. Typed contract и границы

Расположение: `experiments/storage_feasibility/lib/container/`.
App ничего из этого каталога не импортирует.

| API | Гарантия / ограничение |
|---|---|
| `readSnapshot()` | Revision + неизменяемая строка codec-v7; проверка digest |
| `commitMutation(Mutation)` | Partition, command ID, expected revision, prepared snapshot, immutable intent/dependencies |
| `lookupCommandReceipt(id)` | Локальная durability отдельно от remote acceptance |
| `readPendingCommands()` | Включает accepted, ещё не покрытые authoritative page; unresolved не удаляются |
| `markCommandAcknowledged(SyntheticReceipt)` | Receipt и delivery status в одной транзакции; cursor не двигается |
| `applyRemoteBundle(RemoteBundle)` | Shadow, projection revision, aliases, conflicts, coverage и checkpoint атомарны |
| `readCheckpoint()` | Cursor только полностью закоммиченной страницы |
| `backup()` | Online encrypted copy, проверка, recovery manifest, явный recovery point |
| `recover()` / `open(recovery:true)` | Явное действие; verified generation; запрет скрывать более новые доступные данные |
| `rotateKey()` | Dual keys → shadow copy → verify → promotion; старые файлы/ключи сохраняются |
| `close()` | Drain на writer facade, закрытие readers/DB/profile lock |

Дополнительно implementation/harness поддерживает claim/retryExpired/resume,
ограниченные reader leases и явный checkpoint. SQL доступен только backend и
диагностическому harness, не интерфейсу TransactionContainer/Flutter UI.

FinancialSnapshot — **opaque UTF-8 JSON container**, а не новая финансовая
модель. Backend проверяет version/digest; полную семантическую валидацию делает
существующий codec/domain layer. Синтетическая mutation меняет note через
существующий CanonicalTransaction.copyWith; identity, cents и direction не
пересчитываются. FinancialSnapshot/Mutation кэшируют immutable digest/body,
чтобы не хешировать один многомегабайтный вход многократно.

Workspace + profile lineage фиксированы при открытии контейнера. Это локальная
partition identity, **не авторизация** и не выбранный UI-user. Оригинальные
financial IDs/source identities не меняются; aliases находятся в sidecar.

## 4. Физическая схема прототипа

Все таблицы в одной зашифрованной SQLite DB. Snapshot хранится как TEXT с
сохранением исходной строки; это не JSON-merge SQL.

| Таблица | Назначение |
|---|---|
| identity | Partition + container format |
| state | Текущие canonical snapshot, local revision, digest |
| journal | Immutable durability journal: bootstrap / local / remote |
| commands | Immutable исходящие local commands, unique ID/revision, body/digest |
| delivery | Mutable state, attempts, lease, receipt, covered flag |
| receipts | Immutable synthetic server receipts |
| shadow | Последний authoritative snapshot; **NULL до первого remote bundle** |
| checkpoint | Cursor той же завершённой страницы |
| aliases | Source/canonical sidecar; конфликт remap и циклы отвергаются |
| conflicts | Pending projection, требующая domain rebase/review |
| bundles | Idempotency remote page, digest, resulting revision/cursor |
| migration | Immutable bootstrap manifest/digest |

`commands`, `journal`, `receipts`, `bundles`, `migration` защищены от UPDATE/DELETE
SQL triggers. Delivery меняется отдельно от immutable body. `verify()` проверяет
integrity/FK, partition, последовательность журнала, связь local revision с
command, snapshot/body digests, receipts и shadow/checkpoint.

Такое разделение устраняет ограничение 2a: **не каждая revision — исходящая
команда**. У remote/bootstrap есть journal entry, но нет fake outbox.

## 5. Транзакции и очередь

### Local UoW

Подготовленная mutation → `BEGIN IMMEDIATE` → same-ID lookup → CAS → journal +
snapshot + immutable command + delivery → `COMMIT` при synchronous=FULL →
durable receipt. Повтор ID с тем же body возвращает прежнюю revision, даже если
позже были другие изменения. Другой body под тем же ID — collision. Stale
revision отвергается, более свежий snapshot не перезаписывается.

Ошибка write/fsync означает неизвестный исход для вызывающей стороны: закрыть
соединение, открыть и проверить **тот же command ID**, не создавать новый.
Ошибка checkpoint **после** commit не отменяет durable receipt; следующие
записи блокируются до повторного открытия.

### Delivery lifecycle

- queued → inFlight с bounded lease и attempts;
- истёкший inFlight → queued, body/ID остаются прежними;
- synthetic receipt → accepted / conflict / blockedDependency /
  rejectedRequiringAttention / pausedAuthentication;
- dependency/auth resume только явно; dependency проверяется;
- conflict/rejected не превращаются автоматически в accepted/queued;
- receipt-ID collision и противоречивое изменение terminal receipt отвергаются;
- accepted остаётся pending overlay до complete page с явным coveredCommands;
- payloads и receipts не удаляются вообще: compaction вне данного этапа.

Remote commit_seq в отдельном ACK не продвигает pull cursor. Повтор lost-response
доставки идемпотентен. Backend не выполняет HTTP.

### Remote page

Проверяются partition/protocol/fromCursor/local CAS и immutable page digest.
В одной транзакции записываются shadow, local revision, aliases, conflicts,
coverage, checkpoint и page receipt. До commit cursor не виден снаружи.

Без pending применяется incoming snapshot. При pending сохраняется **вся
локальная проекция**, incoming facts доступны только в shadow и conflict.
Это безопасная консервативная граница, но не автоматический финансовый merge.
Будущий executor должен использовать shared core/approved command executors,
а не last-write-wins. Семантика утверждения «page covers command» доверена
синтетическому источнику; настоящая проверка server envelope — будущий gate.

## 6. Migration rehearsal v7

Источник создан `container_codec_fixture.dart` через **неизменённый app codec**
и существующие synthetic fixtures. Не читается filesystem production profile.

Состав проверенного полного профиля: 5 accounts, 4 legacy transactions,
3 canonical transactions (включая trash), 2 debts, 2 investment accounts,
2 goals; budgets, histories/preferences и остальные codec sections также
сохраняются. Canonical values включают 4 861,22 RUB, 15 000,25 USD, 0,13 RUB,
inflow/outflow, user note/category override/tags.

Подтверждено:

- codec encode → encrypted DB → exact string → codec decode/encode: равенство;
- повторный round-trip после новой model-based note mutation;
- ID/cents/currencies/types/deleted status сохранены;
- manifest ID + partition + source digest обязательны; mismatch отвергается;
- повтор той же migration после edits сохраняет новые изменения;
- bootstrap создаёт revision 0, не отдельные команды старых операций;
- authoritative shadow отсутствует, cursor 0 — **это не cloud enrollment**;
- процесс прерван после snapshot / до commit / после commit; resume того же
  manifest не создаёт дублей;
- missing vault или missing DB после завершённой migration не создают пустой
  новый профиль. Исходный synthetic JSON остаётся неизменным.

## 7. Key lifecycle, backup и recovery

Manifest защищён current-user DPAPI в **отдельном synthetic каталоге**.
Generation DB paths формируются кодом. Неверный ключ, повреждённый/частичный
vault, DB corruption и неподдержанный manifest — fail closed; исходные файлы
не удаляются. Старый production secure-storage plugin не менялся.

Rotation: сохранить два ключа → encrypted online backup новым ключом → verify
snapshot/journal/outbox → publish active generation. Проверены process exits
после dual-key publish, во время copy, после copy и после promotion. Writer
заблокирован на время операции; readers закрываются. Один profile lock действует
между поколениями. Вторая rotation/backup без reviewed retirement запрещена.

Явное recovery проверяет alternative readable generations. Если выбранный
backup скрывает более новые revisions **или отличающиеся receipts/delivery
metadata при той же revision**, операция отвергается. Это дополнительное
исправление, найденное при review: одного snapshot hash для safe recovery мало.

Если более новое поколение действительно повреждено/недоступно, восстановление
означает только подтверждённую recovery point, не гарантию спасения всех более
поздних writes. Повреждённые файлы/ключи остаются для salvage. Политика review
такого отката и retirement ещё не production-ready; автоматического reset нет.

### Потеря устройства / OS identity — только проект, не реализация

DPAPI не считается portable backup: доступ обычно связан с Windows credentials
и компьютером. Это свойство механизма, не резервная копия ключа для нового
устройства. [Microsoft DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).

До production требуется отдельный пользовательский recovery kit: encrypted
DB + целый outbox/shadow/checkpoint + authenticated versioned manifest + DEK,
обёрнутый независимым recovery key. Генерация/хранение recovery key, KDF, rotation,
потеря обоих факторов, UX и retention должны пройти security/product approval.
Восстановление — в новый изолированный каталог, verify всех данных/версий,
показ recovery point и pending count, только затем явный cutover. Без ключа —
«восстановление требуется», а не новый пустой профиль поверх ciphertext.

## 8. Ownership, concurrency и ошибки для пользователя

Реализован ContainerWriter: отдельный isolate, FIFO chain, maxQueue=32 (допустимо
1–128), onError/onExit supervisor, bounded startup, явный drain/close. Обычный
commit, incoming apply, backup, recovery и rotation проходят один owner.
Второй процесс отвергается Windows file lock; прямой overlapping backend call
также отвергается. Stale revision — дополнительная защита, не замена ownership.

До 4 query-only read leases: default 2 s, максимум 10 s, deadline timer и явное
закрытие. Проверены два одновременно открытых read snapshots и дальнейшая
запись. Длительная синхронная операция может задержать timer; WAL backpressure
остаётся последним ограничителем. Reader handles не передаются в Flutter UI.

**Runtime finding:** после принудительного kill isolate ошибка наблюдается, но
in-process reopen в данном прогоне не удался — lock остался. Нужен restart
процесса/отдельная runtime-доработка. Нельзя обещать hot restart writer после
native failure. [Dart Isolate.kill](https://api.dart.dev/dart-isolate/Isolate/kill.html)
описывает остановку isolate; он не доказывает cleanup данного FFI stack.

Проект отображения ошибок (UI не реализован):

- disk/wal pressure: «изменение не сохранено, освободите место / повторите»;
- ambiguous commit/owner lost: «проверяем результат сохранения», lookup same ID;
- vault/DB error: «требуется восстановление», без empty fallback;
- local receipt: «сохранено локально», не «принято сервером»;
- auth/conflict/rejected: удерживать очередь, показывать attention, не скрывать.

Необходим отдельный supervisor watchdog для зависшего native вызова; бесконечный
in-flight RPC не должен превращаться в fake success. В этом прототипе есть
exit/error supervision, но нет доказанного безопасного hard-timeout cleanup.

## 9. WAL и измерения

Переиспользована policy 2a.1: WAL, FULL, auto-checkpoint 1000 pages,
busy_timeout 100 ms, retained journal_size_limit 8 MiB, soft WAL 32 MiB,
hard budget 256 MiB, disk reserve 256 MiB + прогноз write amplification.
PASSIVE после записи, TRUNCATE при idle/pressure; BUSY не считается успехом.
Backup заранее проверяет место для второй копии. WAL/SHM вручную не удаляются.

Это измеренная **экспериментальная** policy, не физическая квота на любую схему
и workload. Долгий reader действительно может задерживать checkpoint;
synchronous=FULL и checkpoint имеют разные границы durability.
[SQLite WAL](https://www.sqlite.org/wal.html).

С уменьшенными тестовыми порогами soft=128 KiB/hard=3 MiB: два pinned readers,
25 small edits до backpressure, максимум WAL 1 001 192 bytes (<3 MiB). Pending
tail сохранён. После release readers checkpoint проходит, запись возобновляется.
Disk headroom=0 отклоняет mutation до изменения состояния.

### Windows AOT, 3 свежих процесса на размер

В каждом процессе: создание model-based fixture, migration, 3 изменения одного
note с перезаписью whole snapshot, FULL commit/checkpoint и reopen/verify.
Измеряется process CPU, RSS, serialization+construction и полное время.
Финальный последовательный прогон после тестов: 9 свежих AOT processes,
27 note edits. Время в миллисекундах; RSS в MiB. Медианы отдельных фаз считаются
независимо, поэтому их сумма не обязана совпадать с медианой total.

| Операций | Migration median | Note edit total median | Serialize/construct | Commit/checkpoint | CPU/edit | Peak RSS |
|---:|---:|---:|---:|---:|---:|---:|
| 1 000 | 68,1 ms | 73,5 ms | 34,1 ms | 39,9 ms | 78,1 ms | 76,8 MiB |
| 10 000 | 687,9 ms | 832,9 ms | 417,8 ms | 397,4 ms | 953,1 ms | 154,4 MiB |
| 50 000 | 3 413,9 ms | 4 060,6 ms | 2 077,1 ms | 1 965,7 ms | 4 890,6 ms | 478,9 MiB |

DB after close: 1 650 688 / 15 839 232 / 78 950 400 bytes соответственно;
WAL и SHM после штатного закрытия — 0. На 50k одна маленькая правка требует
около **4,06 s** и peak RSS около **479 MiB**. Это существенный local-first UX
риск, а не приемлемость по умолчанию: модель whole snapshot нельзя внедрять
без согласованных ограничений и следующего performance/normalization slice.

DB/WAL/SHM after close доступны в raw JSON. Это не Android benchmark, не FPS
измерение и не доказательство приемлемости задержки на телефоне. Подготовка
полного mutation snapshot также должна уйти с UI isolate при будущей интеграции.

Whole snapshot остаётся удобной lossless migration boundary, но не долгосрочной
моделью частых edits большой истории. Первые кандидаты нормализации: canonical
transaction rows + provenance links + user overrides/tombstones, затем account
facts/snapshots. Outbox/shadow/cursor уже отдельно. Единый UoW/CAS/receipt API
сохраняется; физическое row-level materialization можно заменить внутри backend.
Для снижения стоимости readSnapshot позднее нужны projection/query ports,
а не SQL из UI. Не вводить независимый финансовый calculation/cache authority.

## 10. Проверки и воспроизводимость

| Проверка | Итог |
|---|---:|
| Новые container contract/process/migration/key/WAL/ownership tests | 61 passed |
| Прежние A/B storage contracts + policy | 58 passed |
| Прежние C/reference storage contracts | 31 passed |
| Shared Synoball parity/regression | 33 passed |
| App codec/recovery/Synoball selected regression | 33 passed |
| Прежний native hardening harness, rebuilt | 31 passed |
| Прежний key hardening harness, rebuilt | 13 passed |
| Dart analyzer experiments | No issues found |
| Production source hashes | 540 / 540 unchanged |

Итого 260 checks, без skipped в перечисленных test suites. Это **не** полный
Flutter test run, не Windows app release build и не физические power-loss tests.
Собраны standalone Windows AOT probes; Qesto не собирался/не устанавливался.
Android/emulator/device проверки намеренно не запускались по указанию владельца.

Native error evidence: SQLITE_FULL=13, IOERR_WRITE=778 (включая partial native
write), IOERR_FSYNC=1034; до восстановления ACK отсутствует, snapshot/outbox
откатываются вместе. Повтор same command после reopen создаёт ровно revision 1.
Checkpoint I/O failure после commit оставляет durable revision 1 и ACK, требует
reopen, duplicate retry не создаёт revision 2. Отдельно проверен native process
exit внутри checkpoint. Это **инъекция в реальные native VFS callbacks**, не
настоящий заполненный диск/отказ контроллера/отключение питания.

Честная история неуспешных промежуточных проверок: первый тест копеек читал
несуществующее JSON-поле вместо Money; initial native harness сбрасывал свой
hit counter до assertion. Исправлены тесты, затем проверены точные native codes.
Обнаруженный owner-restart gate не замаскирован под успешный hot restart.

Основное evidence: `experiments/storage_feasibility/results/container_summary.json`,
`container_tests.jsonl`, `container_native_faults.json`, `container_owner_restart.json`,
`container_wal.json`, `container_benchmarks.json`, `container_codec_*.json`,
`container_source_check.json`, `container_analyze.txt`; regression logs рядом.
Исходный source hash baseline: `container_baseline.json` (не перезаписывать).

Воспроизведение из repo:

```powershell
& ./experiments/storage_feasibility/tool/run_container.ps1 -IncludeBenchmarks
```

Требуются имеющиеся Flutter/Dart SDK, app package config, MSVC и dependencies
из предыдущего spike. Скрипт не запускает приложение, не ищет реальный профиль
и не удаляет synthetic WAL/SHM. Native probe AOT нужен также для исключения
конфликта rebuild DLL у вложенных `dart run` в Windows.
Перечисленные команды выполнены по отдельности; синтаксис объединяющего
PowerShell wrapper проверен, единым вызовом весь wrapper повторно не запускался.

## 11. Изменённые файлы

Новые файлы в `experiments/storage_feasibility/`:

- `CONTAINER_PLAN.md`;
- `lib/container/contract.dart`;
- `lib/container/sqlite_container.dart`;
- `lib/container/writer.dart`;
- `lib/container/synthetic_scenario.dart`;
- `bin/container_probe.dart`;
- `test/container_contract_test.dart`;
- `test/container_process_test.dart`;
- `test/fixtures/container_profile_v7.json`;
- `tool/container_codec_fixture.dart`;
- `tool/container_evidence.dart`;
- `tool/container_benchmarks.dart`;
- `tool/collect_container_results.dart`;
- `tool/run_container.ps1`;
- generated `results/container_*` evidence и ignored AOT build artifacts.

Минимальные изменения **старого экспериментального**, не production кода:

- `lib/storage_spike.dart`: CheckpointStore port; прежний SpikeStore implements;
- `lib/wal_policy.dart`: generic write envelope; прежний apply делегирует ему;
- `lib/generation_vault.dart`: существующий atomic replace переиспользуемый;
- `analysis_options.yaml`: app-codec fixture, запускаемый с app config, исключён
  из analyzer другого package (он реально компилируется/исполняется в tests).
- `tool/run_hardening.ps1`: явно перечислены прежние 2a.1 tests, чтобы этот
  старый runner не требовал автоматически нового container AOT executable.

Повторные old harness обновили `results/hardening_native.json` и
`results/hardening_keys.json`; их 31/13 checks снова прошли. Данный отчёт —
`docs/sync/2026-10-11/Transaction_Container_Contract_Report.md`.
Ни одного изменённого production-файла в этом этапе.

## 12. Условия следующего согласованного этапа

До полноценного 2b/cutover нужны:

1. Решение по writer fatal cleanup/watchdog/process restart и испытания на
   обоих runtime targets. Dart isolate exit не освобождает этот Windows stack
   достаточно для доказанного hot recovery.
2. Portable recovery/security policy, reviewed generation retirement,
   rollback detection, ACL/backup authenticity, key material lifetime и
   процедура salvage. Сейчас DPAPI защищает local key material, не решает всё.
3. Согласованные пределы размера/latency/RAM; staged domain work вне UI isolate,
   benchmark на Android, при необходимости отдельный bounded normalization slice.
4. Командные executors/UoW по группам текущих mutation paths, сохранение ID и
   parity; UI не публикует mutation до durable receipt. Никакого generic JSON LWW.
5. Проверка incoming coverage/rebase/version/epoch contract до включения сети.
   Conflicts остаются видимыми, outbox не выбрасывается при logout/errors.
6. Отдельный production migration PR: source untouched, verified destination,
   explicit cutover, запрет старого клиента и rollback с потерей новых writes.
7. Отдельное разрешение владельца. Android, реальная миграция и cloud enrollment
   автоматически не начинаются.

**Этап 2b.0 ограничен этим прототипом и отчётом. Рабочий persistence не переключён.**
