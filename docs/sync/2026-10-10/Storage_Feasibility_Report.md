# Qesto Sync — Storage Feasibility Report

Дата: 10.10.2026. Этап **2a**, изолированный synthetic-only spike.

**Результат:** Windows feasibility подтверждена для A/B/C. Предварительно
рекомендован **B: sqlite3 + SQLite3MultipleCiphers**. Android A/B release APK
собран и проверен статически, но не запускался на устройстве. Полный acceptance
2a ещё не пройден. **Production migration / этап 2b не начинать.**

Рабочий Qesto остаётся 1.0.68+69. Не было установки поверх Qesto, обращения к
реальному store.json/банковскому профилю, миграции, сервера, сети синхронизации
или передачи финансовых данных. Зависимости добавлены только в эксперимент.

## 1. Контекст и граница

Сверены документы [A–E](../2026-10-08/README.md), предыдущий
[Shared Core & Parity Report](../2026-10-09/Shared_Synoball_Core_Parity_Report.md),
production persistence, codec v7, shared core, ключи и recovery. Предоставленный
[AI Development Protocol v0.1](../../engineering/QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1.md)
добавлен в репозиторий; содержимое совпадает с исходным после нормализации CRLF.

Текущее хранение — LocalQestoRepository, цельный профиль codec v7, AES-GCM envelope
`qesto:aes-gcm:v1:`, master key `qesto.local-storage.master-key.v1`, платформенный
secure storage и RecoverableJsonFile с staged/backup/rename/lock. Это не SQLite
и не атомарный snapshot + durable outbox. Ни один из этих production-модулей
не изменён данным spike.

Эксперимент повторно использует shared canonical models/serializer. Финансовые
алгоритмы, IDs, reconciliation, дедупликация, override/locks, trash и расчёты
не переписаны. Opaque fixture, созданный существующим codec v7, проходит
byte-for-byte round trip, включая 4861,22 ₽, USD, override, note tag и удаление.
Benchmark использует SynoballState, **не весь реальный профиль codec v7**.

## 2. Сравнение кандидатов

| Свойство | A: Drift + MC | B: sqlite3 + MC | C: SQLite + AES-GCM payload |
| --- | --- | --- | --- |
| Windows x64 AOT runtime | Проверен | Проверен | Проверен |
| Android | APK A/B собран; runtime не проверен | Тот же APK; runtime не проверен | В APK не включён; Android не проверен |
| Подключение | NativeDatabase.opened, hooks | Direct FFI, hooks | Отдельный root hook ordinary SQLite |
| Шифрование | Page encryption MC, SQLCipher cipher mode, HMAC включён | То же | AES-GCM-256 отдельных BLOB, nonce + ciphertext + MAC, row AAD |
| Служебные SQL данные | В page encryption | В page encryption | Schema, IDs команд, revisions, kind names открыты |
| Атомарность | Drift transaction | BEGIN IMMEDIATE + COMMIT/ROLLBACK | Та же direct transaction |
| Поддержка | Уместен при typed queries/reactive tables; добавляет ORM слой | Минимальная граница для opaque snapshot/outbox; SQL проверяет проект | Нужны crypto envelope, AAD/key versions и отдельный аудит метаданных |
| Миграции | Механизм Drift существует, наша production migration не проектировалась | Нужен явный schema/version contract, ещё не реализован | Нужны SQL и envelope migrations, ещё не реализованы |
| Состояние | Работоспособная альтернатива на Windows | Предварительный выбор на Windows | Работает, но не выбран default |

A/B испытывались с **SQLite3MultipleCiphers**, а не с отдельной библиотекой
Zetetic SQLCipher. Современные hooks поддерживают выбор native assets;
не добавлялись старые sqlite3_flutter_libs/sqlcipher_flutter_libs или подмена DLL
production-приложения. [Drift encryption](https://drift.simonbinder.eu/platforms/encryption/),
[sqlite3 3.5.2](https://pub.dev/packages/sqlite3/versions/3.5.2).

C использует тот же primitive/package AES-GCM, что production, но специальный
binary test-envelope. Он **не** доказывает совместимость файлов с production
JSON envelope и не является его новой реализацией в приложении.

## 3. Версии, packaging и release gates

Среда: Flutter **3.44.6**, Dart **3.12.2**, Windows x64. Android compile/target SDK
36, min SDK 24. APK release-mode, но с локальной debug signing — только тест.

| Зависимость | Зафиксированная версия |
| --- | --- |
| sqlite3 | 3.5.2 |
| drift | 2.35.2 |
| hooks | 2.0.2 |
| cryptography / crypto | 2.9.0 / 3.0.7 |
| ffi / test | 2.2.0 / 1.31.0 |
| Android flutter_secure_storage / path_provider | 10.3.1 / 2.1.5 |

CLI lock: native_toolchain_c 0.19.3, meta 1.19.0. Android lock: 0.19.2 и 1.18.0.
record_use 0.6.0. Lockfiles сохранены для каждого root package.

Попытки sqlite3 **3.7.0 и 3.6.0** не разрешились для текущего Flutter: hooks 2.2+
через record_use требует meta >=1.19, SDK закрепляет 1.18. Использован совместимый
3.5.2 + прямой pin hooks 2.0.2, **без dependency overrides и изменения SDK Qesto**.
Это осознанный compatibility pin, не утверждение о «последней» версии пакета.

Реально загруженная Windows библиотека во всех A/B/C:

- SQLite **3.53.4**, integer **3053004**;
- source ID `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`;
- A/B: `sqlite3mc_version()` → **SQLite3 Multiple Ciphers 2.5.0**;
- cipher mode `sqlcipher`, `hmac_use=1`, `hmac_check=1`;
- WAL, synchronous FULL (2), temp_store MEMORY (2), THREADSAFE=1;
- полные compile options, включая OMIT_PROGRESS_CALLBACK/UNTESTABLE, сохранены
  в release JSON. Версия Dart wrapper не подменяет native version.

SHA256 Windows DLL совпадают с asset manifest sqlite3-3.5.2:

```text
MC:    fd50815dfe93dc7333b9d3002dcd4c6f5a300812a6c67f6171da59535f496ae3
plain: 2bf39f2aadafdc59a90b260f582a8fccebc5b89eb94175fdbaa9148c1e1f084d
```

Release opener выполняет обычные throw-проверки: key 32 bytes, собственный
marked synthetic path, actual patched SQLite version, наличие MC для A/B,
отсутствие MC для C; ключ устанавливается до первого чтения схемы. Existing DB
без authenticated experiment marker, empty/corrupt DB и missing key отвергаются,
не сбрасываются и не инициализируются заново. PRAGMA key сама по себе не является
проверкой ключа; выполняется реальное чтение схемы и authenticated guard.
[MC pragmas](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/).

WAL-reset bug исправлен в 3.51.3 и указанных backports 3.50.7/3.44.6. В прототипе
есть conservative runtime gate и unit negative cases. Загруженный 3.53.4 проходит;
собственный воспроизводитель исходной native race не реализован.
[SQLite WAL-reset](https://www.sqlite.org/wal.html#the_wal_reset_bug).

## 4. Transaction container

Одна экспериментальная схема/один storage contract для A/B/C:

```text
key_guard  — authenticated identity/key check
state      — singleton revision + snapshot BLOB
outbox     — command ID + unique revision + immutable payload BLOB
sync_meta  — checkpoint / server-shadow / conflict-proposals
```

Apply заранее формирует snapshot, immutable command с digest и три metadata
payload. В транзакции проверяет повтор command ID и expected revision, пишет
snapshot/outbox/revision/metadata. ACK выдаётся только после commit.

Повтор того же ID с тем же command возвращает сохранённую revision; другой
command с тем же ID отвергается. Stale writer не может перезаписать state.
SQL triggers запрещают изменение/удаление логических outbox commands. Это
storage idempotency, **не альтернативная Synoball-дедупликация**.

Verify проверяет integrity_check, число и непрерывность command revisions,
доступность/аутентификацию payload, digest последнего snapshot и revision всех
трёх metadata. Snapshot без соответствующей команды недопустим.

Checkpoint/shadow/conflicts сейчас синтетические предложения с revision, а не
готовый sync protocol. Outbox acknowledgement, pruning, schema upgrades, actual
server shadows и atomic DB+vault key handover не реализованы.

## 5. Windows fault/concurrency/encryption results

| Проверка | A/B/C | Что именно установлено |
| --- | --- | --- |
| До транзакции, после snapshot, после outbox | Pass, WAL + DELETE | Точные Dart checkpoints; процесс exit без finally; rollback сохраняет прежнее состояние |
| Сразу после commit / lost ACK | Pass, WAL + DELETE | После reopen команда сохранена; retry не создаёт новую revision |
| Два соединения | Pass | Stale rejection, отсутствие lost update |
| Два writer процесса | Pass, WAL + DELETE | Оба читают rev0 до barrier; ровно один COMMITTED, второй StaleRevision |
| WAL reader + writer | Pass | Reader сохраняет rev2 во время commit rev3; после своего COMMIT видит rev3 |
| Online backup живой БД | Pass | Keyed target, reopen и verify с сохранённым ключом |
| Crash во время backup | Pass | Точный промежуточный page-copy callback; partial target rejected, source intact |
| После recovery/reopen | Pass | Процесс прерван после verify, повторный reopen согласован |
| Kill вокруг commit | Согласованное восстановление; точная native phase **не проверена** | 45/50/55/65 ms после readiness и 50 ms pause; допустимые durable rev0/rev1 |
| Kill при checkpoint | Integrity pass; точная native phase **не проверена** | Таймерный kill после GO, не перехват xWrite/xSync |
| Неправильный/отсутствующий ключ | Pass | Нет чтения/замены существующего snapshot и plaintext fallback |
| DB-only key rotation | Pass | Old key отвергнут, new key открывает ту же БД; прежний backup открывается old key |

Все точные boundary faults проверены для 3 кандидатов × 2 journal modes × 4
точки. Отдельно 6 двухпроцессных writer сценариев. Timed-kill observations
записаны без попытки превратить их в доказательство power-loss/torn-write.

Сканировались DB, committed WAL, unlocked SHM, активные WAL/rollback journals
и online backup: synthetic financial marker не найден. Для A/B DB header не
plaintext SQLite header. В C SQL metadata остаются открытыми намеренно, financial
payload зашифрован. Tamper/row-substitution C отвергается через GCM/AAD.

SHM — служебный индекс, его полное шифрование не заявляется. Во время write на
Windows SHM ranges заблокированы, активный scan его пропускает; отдельно сканирует
unlocked SHM. temp_store=MEMORY препятствует SQL temp-file spill в данном опыте.
Это marker-based inspection, **не исчерпывающий forensic/security audit**, не
доказательство secure erase, отсутствия swap/crash dumps или всех native temp paths.

Successful parent runs удаляют только собственные marked temporary directories.
Early interrupted prototypes могли оставить исключительно synthetic temp files;
профили/общий temp каталог не удалялись. Очистка файлов не обещает стирание с SSD.

Backup выполнен Online Backup API, не копированием только main DB при живом WAL.
Проверка успешного восстановления требует сохранённого ключа; файл без ключа
не объявляется recoverable backup. [SQLite backup](https://www.sqlite.org/backup.html).

### WAL или DELETE

Оба режима выдержали выполненные Windows контракты. WAL продемонстрировал полезную
reader/writer concurrency; преимущества write throughput над DELETE в наших
замерах нет. **Условная рекомендация WAL + FULL**, если нужны параллельные readers,
с единственным writer owner, ограничением read transactions, явной checkpoint
policy и контролем BUSY. DELETE — допустимый более простой кандидат, если
concurrent readers не нужны. Окончательный mobile default не утверждён.

wal_autocheckpoint=0 применён специально для наблюдения WAL, не рекомендован для
production. При четырёх full-snapshot commits 50k A/B накопили ~278 MB WAL.
Перед 2b нужны границы WAL, проверка результата checkpoint и disk-space/BUSY/error
policy. Нельзя вручную удалять живой WAL ради «очистки».

## 6. Keys, vault и recovery

**Windows:** synthetic 256-bit DB key обёрнут direct DPAPI current-user, затем
проверены новое process reopen и отказ на повреждённом wrapped blob. Это проверка
primitive, не crash-durability всей реализации flutter_secure_storage.
DPAPI обычно привязан к пользователю/компьютеру, а не даёт автоматически
переносимый backup. [Microsoft DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).

При read-only исследовании установленного flutter_secure_storage_windows 4.2.2
найден риск: decrypt/parse failure может удалить vault file. Production plugin
не патчился и реальный vault не открывался. Нужны recovery policy и отдельные
synthetic interrupted-write/corrupt-vault tests до интеграции.

**Android:** retained plugin 10.3.1 использует AndroidKeyStore для wrapping key,
RSA-OAEP + AES-GCM для vault. Hardware backing зависит от устройства, не от имени
plugin; требуется KeyInfo/security-level measurement. 32-byte DB key после
unwrap находится в Dart/native RAM — он не становится non-exportable Keystore
key. [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

Исследование production выявило ещё один future-migration риск: текущий
_loadOrCreateMasterKey при missing vault key создаёт новый ключ, даже если старые
encrypted values существуют; decrypt затем fails, repository write guard защищает
финансовый профиль. Это не менялось здесь. В будущем DB-exists + key-missing должен
сразу приводить к recovery-required, а не к new-key/new-empty-state.

**Ротация:** проверен только DB rekey / transactional payload re-encryption.
Нет атомарной транзакции между SQLite и OS vault. Нужны two-generation keys,
authenticated key-version/recovery manifest, staged cutover и crash tests до
retirement старого ключа. В C меняется ciphertext, не логический immutable command.

**Переустановка/другое устройство:** безопасный перенос требует отдельно согласованного
encrypted backup с recoverable wrapped DB key / recovery secret. Простое копирование
DB и device-bound vault не решает задачу. Такой recovery workflow не реализован,
реальная переустановка/потеря ключа не проводилась. Защита at-rest не защищает
от активного скомпрометированного процесса, имеющего право unwrap/decrypt.

## 7. Android: build не равен runtime

Создан отдельный APK `ru.qesto.storage.qesto_storage_probe`, **0.1.0+1**.
APK 54 044 004 bytes, SHA256:

```text
16ac9d0961274b067ec72d8228d696deab37a344d4e5224ce1b56d196d56c3cc
```

Aapt: min24/target36, allowBackup=false, INTERNET отсутствует; native MC `.so`
для arm64-v8a/armeabi-v7a/x86_64. Исходные native assets совпадают с checksum
manifest sqlite3-3.5.2; финальные APK hashes совпадают с Gradle stripped assets,
поэтому ожидаемо отличаются от unstripped download hashes. Подробности в inventory.

Probe использует отдельный secure-storage namespace и собственный app-support
directory. Повторный запуск должен reuse key/revision; при missing key с existing
DB генерация запрещена. Кнопка вызывает A/B native info, key round trip, apply,
verify, online backup и in-process releaseSafety.

**Не проверены на Android:** загрузка actual native runtime, version/cipher
gate, Keystore, restart/reboot retention, crashes, performance, backup/reinstall,
C. APK не установлен; пользователь подтвердил «пока без телефона». Windows
subprocess harness не является Android crash test. Runtime gate открыт.

## 8. Benchmark — повторяемый Windows AOT

36 samples: 3 trials × 12 candidate/size/mode combinations; fresh process для
каждой комбинации, fresh DB для каждого trial. Размер snapshot: 770 038 /
7 716 753 / 38 627 047 bytes. Сохраняются настоящие minorUnits, валюты/типы и
synthetic model data, не production profile.

Ниже медианы ms; память — process peak RSS MB (decimal), не только SQLite.

| Кандидат | Операций | Mode | Write | Load | 3 batches | Reopen+verify | Peak RSS MB |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| A | 1 000 | WAL | 17.531 | 0.623 | 88.589 | 21.364 | 62.9 |
| A | 10 000 | WAL | 159.043 | 39.242 | 976.753 | 299.210 | 147.6 |
| A | 50 000 | WAL | 878.672 | 232.940 | 6 051.645 | 1 149.850 | 431.1 |
| A | 50 000 | DELETE | 845.593 | 206.109 | 6 194.499 | 1 079.437 | 431.5 |
| B | 1 000 | WAL | 18.608 | 0.858 | 98.442 | 22.149 | 61.9 |
| B | 10 000 | WAL | 178.077 | 43.256 | 1 085.517 | 217.523 | 135.0 |
| B | 50 000 | WAL | 921.614 | 220.197 | 6 927.139 | 1 335.615 | 391.4 |
| B | 50 000 | DELETE | 776.301 | 195.610 | 6 762.497 | 1 273.081 | 376.4 |
| C | 1 000 | WAL | 82.337 | 59.663 | 277.610 | 131.760 | 67.3 |
| C | 10 000 | WAL | 1 153.795 | 645.038 | 3 893.796 | 1 411.038 | 263.2 |
| C | 50 000 | WAL | 4 828.328 | 3 230.306 | 21 095.792 | 10 123.191 | 917.7 |
| C | 50 000 | DELETE | 6 227.100 | 3 142.713 | 21 135.343 | 7 280.660 | 923.2 |

Write includes digest/encryption staging + commit, excludes initial model
serialization. Serialization at 50k: ~514–559 ms. Load includes reading/decryption
and byte equality, not full domain reconstruction. Three batches each update
100 notes, regenerate/serialize and rewrite the whole snapshot. Reopen+verify
includes integrity/digest checks and reread after clean close; this is **not a
cold-start or power-loss recovery benchmark**. Crash correctness measured separately.

Current RSS after reopen at 50k: A/B ~293–299 MB, C ~255–260 MB; peak differs
substantially. Max RSS is cumulative for trials within that process, not a per-DB
allocation measurement. Whole-snapshot cost and model allocations must leave UI
isolate. This spike does not implement production worker/isolate ownership.

50k files before final close/checkpoint: A/B WAL ~277.8 MB, SHM 557 056 bytes,
main DB 4096; DELETE main ~78.9 MB. C WAL ~155.8 MB, SHM 327 680, DELETE main
~77.4 MB. Main DB alone is not total storage. Raw sizes/ranges for all samples
are retained in windows_benchmarks.json.

A/B differences do not establish a performance winner. C's observed cost is
for the tested Dart cryptography path; native/hardware AES-GCM was not measured.
Single machine, warm OS caches, three trials, no Android measurements or verified
CPU/storage model: no claim of production throughput/SLA. Whole-snapshot growth
remains important even with native page encryption.

## 9. Проверки до/после и найденные проблемы

| Проверка | Итог |
| --- | --- |
| Baseline: encrypted store + Synoball core/safety + shared compatibility, 4 файла | 27 passed до реализации |
| Новые A/B contract tests | 55 passed |
| Новые C contract tests | 31 passed |
| Shared core standalone parity/golden | 33 passed |
| Полный существующий app test run | **939 passed, 12 skipped**, финальный запуск 82 s |
| Existing JSON subprocess crash/recovery | 8 passed |
| App / spike / plain_runner / Android probe analyze | No issues found |
| Windows A/B и C AOT bundles | Build passed; release harness passed |
| Android A/B release APK | Build passed; device runtime не проверен |

12 skips — существующие private corpora, explicitly supplied screenshot и
opt-in Windows native bridge checks. Новых skip ради зелёного результата нет.
Root analyzer исключает independent packages и fixture emitter, запускаемый
с app package config; independent analyzers выполнялись отдельно.

Найденные и исправленные ошибки **прототипа**, не приложения: retained stdin
subscription останавливала crash worker; validation до открытия Drift delegate
могла оставить raw handle; исправлен idempotent explicit close; учтены locked
SHM ranges; исправлены три Android lint findings. Debug Drift warnings про несколько
_DriftDb ожидаемы в tests с независимыми connections; общий QueryExecutor не
переиспользуется, предупреждение не скрыто. `dart compile exe` первоначально
не поддержал packaging hooks — release воспроизводится `dart build cli`.
Android SDK XML tool-version warning сохранился, сборка успешна; SDK не обновлялся.

525 hashes app lib/test, shared core lib и app pubspec/lock совпали до/после
финальной validation series; manifest сохранён. Это контроль финального цикла,
не доказательство отсутствия всех ранее существовавших незакоммиченных изменений.
Рабочее дерево заранее dirty; эти изменения сохранены и не присвоены spike.
Реальное пользовательское хранилище не открывалось и его checksum не снимался;
неизменность профиля не выдаётся за отдельную hash-проверку. Executable write paths
ограничены marked synthetic directories; production imports отсутствуют кроме
read-only codec fixture emitter, которому профиль не передаётся.

## 10. Изменённые файлы / evidence

Текущий slice добавляет только:

- `docs/engineering/QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1.md` — предоставленный протокол;
- этот `docs/sync/2026-10-10/Storage_Feasibility_Report.md`;
- `experiments/storage_feasibility/README.md`, `PLAN.md`, `.gitignore`,
  `analysis_options.yaml`, `pubspec.yaml/lock`;
- `lib/storage_spike.dart`, `lib/probe_harness.dart`, `lib/windows_key_probe.dart`;
- `bin/probe.dart`, `test/contract_test.dart`, `test/fixtures/financial_snapshot_v7.json`,
  `tool/emit_v7_fixture.dart`;
- `plain_runner/pubspec.yaml/lock`, `bin/probe.dart`, `test/contract_test.dart`;
- `android_probe` separate Flutter/Android scaffold + `lib/main.dart`,
  `pubspec.yaml/lock`, main manifest и документация;
- `results/windows_release_mc.json`, `windows_release_payload.json`,
  `windows_benchmarks.json`, `build_inventory.json`, `validation_summary.json`,
  `production_source_final_validation.json`.

Generated build/cache/sdk-local files, executable bundles/APK/DBs/keys не включаются
в Git. Нет изменений CI, app dependencies, app UI, BudgetController, repository,
codec, adapters или shared business logic в этом slice. PR/push не выполнялись.

Прямая evidence:
[reproducer](../../../experiments/storage_feasibility/README.md),
[MC release](../../../experiments/storage_feasibility/results/windows_release_mc.json),
[C release](../../../experiments/storage_feasibility/results/windows_release_payload.json),
[benchmarks](../../../experiments/storage_feasibility/results/windows_benchmarks.json),
[build inventory](../../../experiments/storage_feasibility/results/build_inventory.json),
[validation](../../../experiments/storage_feasibility/results/validation_summary.json),
[source manifest](../../../experiments/storage_feasibility/results/production_source_final_validation.json).

## 11. Решение и gate перед 2b

Предварительный выбор **B** обусловлен минимальным transaction contract для
opaque snapshot/outbox и меньшим ORM surface, не победой в benchmark. A сохраняется
как валидная альтернатива при необходимости typed/reactive tables. C не выбран
default из-за clear service metadata, дополнительных envelope обязанностей и
измеренной стоимости full-snapshot Dart GCM; это не общий запрет payload encryption.

Доступность native packaging Windows/Android технически показана, но реальная
двухплатформенная работоспособность **ещё не доказана**. MC имеет MIT license;
перед distribution нужны полный third-party notice/SBOM и аудит всех включённых
crypto components, а не только верхнеуровневого пакета.
[MC license](https://github.com/utelle/SQLite3MultipleCiphers/blob/main/LICENSE).

До разрешения production transaction container / migration необходимо:

1. Physical Android release runtime/key/restart/reboot/negative/fault/performance
   gate для выбранного кандидата; hardware level отдельно, без обещания StrongBox.
2. Exact native commit/checkpoint I/O fault injection, включая disk-full/I/O errors
   и оборванные записи; timer kill не достаточен. Power-loss assurance не заявлена.
3. Утвердить key lifecycle/recovery, DB+vault staged rotation и interrupted-key-write
   tests; backup/reinstall/device move только с recoverable key.
4. Выбрать worker ownership, journal/checkpoint/bounds/BUSY policy и outbox lifecycle.
   Экспериментальный append-only outbox сейчас не имеет ACK/pruning.
5. Отдельное ТЗ 2b с backup/rollback/migration validation, compatibility pin policy,
   schema/envelope versions, лицензиями и человеческим согласованием.

**Сейчас можно обсуждать дизайн следующего этапа, но не начинать migration.**
2a дала воспроизводимый Windows положительный результат и Android test artifact;
неполные gates не замаскированы успешной компиляцией. На этом работа остановлена.
