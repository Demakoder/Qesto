# QESTO Sync — Storage Hardening, этап 2a.1

Проверки: 10.10.2026. Итоговая сверка отчёта и 525 source hashes: 11.10.2026.
Только синтетические данные, Windows x64.

## 1. Заключение и границы готовности

**Вариант B остаётся технически пригодным кандидатом для transaction container.
Разрешение на production-интеграцию этим отчётом не даётся.** В изолированном
прототипе подтверждены обработка выбранных native I/O ошибок, восстановление
атомарной пары snapshot/outbox, ограничение WAL и recovery с двумя поколениями
ключей. Android runtime и physical-device gates открыты. Этап 2b не начат.

Production persistence, Synoball, финансовые модели, расчёты, схема и установленный
Qesto не менялись. Реальные базы и vault не открывались; их hash не снимался.
525 исходных файлов приложения/тестов/core и app pubspec/lock совпадают с
сохранённым manifest финальной проверки 2a. Ранее существовавшее dirty working
tree сохранено; оно не является изменениями данного этапа.

Основной кандидат неизменен: `sqlite3 3.5.2`, native SQLite **3.53.4**,
SQLite3MultipleCiphers **2.5.0**, SQLCipher cipher mode с HMAC. Это **не**
утверждение об использовании библиотеки Zetetic SQLCipher. SHA256 native DLL:
`fd50815dfe93dc7333b9d3002dcd4c6f5a300812a6c67f6171da59535f496ae3` — тот же,
что в 2a. Новых package dependencies, SDK upgrades и overrides нет.

Основа: [отчёт 2a](Storage_Feasibility_Report.md),
[документы A–E](../2026-10-08/README.md),
[Development Protocol](../../engineering/QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1.md).

## 2. Что уже было проверено и что добавлено

| Область | До 2a.1 | В этом этапе |
| --- | --- | --- |
| Snapshot + outbox + revision, idempotency, stale writer | Contracts и boundary crashes пройдены | Contracts повторены после общей правки; native error/crash matrix добавлена |
| WAL | Замер роста при отключённом checkpoint | Auto 1000 pages, explicit PASSIVE/TRUNCATE, pinned reader, BUSY, backpressure, 80 повторных записей |
| Checkpoint crash | Таймер, точная фаза неизвестна | Прерывания непосредственно в native xWrite/xSync/xTruncate |
| Ошибки диска | Не покрыты | Native FULL quota, injected FULL/IOERR/WRITE/FSYNC/TRUNCATE, частичная реальная запись |
| Vault | DPAPI primitive; код plugin изучен | Реальный Windows plugin проверен на отдельном support path; новый fail-closed recovery prototype |
| Rotation | DB-only rekey; нет атомарности DB+vault | Shadow DB + два ключа + DPAPI manifest, 5 interruption boundaries |
| Ownership | Рекомендация вне UI | Работающий FIFO writer isolate, отдельный reader, drain-on-close |
| Benchmarks | Auto-checkpoint отключён, CPU не измерен | 3 размера × 3 свежих AOT процесса, checkpoint policy, process CPU/RSS |
| Android | Только APK build | Не запускался: пользователь прямо отложил и эмулятор, и телефон |

Не повторялась старая полная матрица A/B/C WAL/DELETE benchmarks и полный app
run 939/12. Они остаются результатами 2a, **не** выдаются за новый прогон.

## 3. Исправленные ошибки прототипа

1. `DirectEngine.transaction` безусловно делал `ROLLBACK` после исключения.
   SQLite может уже откатить транзакцию при FULL/IOERR; вторичная ошибка скрывала
   первоначальную. Теперь проверяется `autocommit`, сохраняется исходная ошибка.
   После I/O ошибки policy запрещает новые записи до reopen. В native FULL тесте
   вызывающий код получает именно **13**, а не «нет активной транзакции».
2. `checkpoint()` игнорировал результат. Теперь возвращаются `busy`, `frames`,
   `checkpointed`; незавершённый checkpoint не называется успешным освобождением
   WAL. DB-only rekey отказывается работать при pinned reader.
3. Добавлено разделение durable receipt и maintenance: ошибка checkpoint после
   успешного commit не превращает сохранённую команду в «не сохранена». При этом
   owner становится unhealthy, следующие записи требуют reopen/reconciliation.
4. Добавлены предохранители от бесконечного роста WAL и от silent provisioning
   при отсутствующем/повреждённом vault или активной базе.

Также исправлены ошибки **нового harness**, не SQLite/Qesto: подмена внешней
таблицы методов MultipleCiphers мешала его внутреннему определению cipher file и
давала NOTADB до checkpoint. Перехват перенесён на underlying `win32` VFS при
`xOpen`, внешний cipher layer не меняется. Дочерние `dart run` на Windows
конфликтовали с загруженным DLL native assets — crash suites запускаются из
отдельных `dart build cli` AOT bundles. Неудачные начальные прогоны не считаются
доказательством проблем production-хранилища.

## 4. WAL/checkpoint: результаты и рекомендуемая policy

Проверено отдельно: стандартный auto-checkpoint **1000 pages** без ручных
checkpoint, запись основной DB при открытом соединении и повторное использование
WAL. `journal_size_limit` ограничивает сохранённый журнал после reset, но не
является лимитом роста при заблокированном checkpoint.

Тест с искусственно уменьшенными пределами soft **4 MiB**, hard **20 MiB**:
удерживаемый reader остаётся на revision 1, writer делает следующие commits,
TRUNCATE возвращает BUSY и backlog; затем preflight останавливает запись.
Измеренный peak WAL **17 435 872 bytes (16,63 MiB)**. После завершения reader
TRUNCATE освобождает WAL, writer продолжает 80 полных обновлений примерно 1 MiB.
Всего **89 commits**; в конце DB **2 187 264 bytes**, WAL перед финальным
checkpoint **2 179 512 bytes**, после — **0**. SHM остаётся до закрытия соединения.
WAL/SHM вручную нигде не удаляются.

Предложение для первого Windows container, проверенное как экспериментальная policy:

| Параметр | Значение / действие |
| --- | --- |
| Journal / durability | WAL, `synchronous=FULL`, temp_store=MEMORY |
| Auto-checkpoint | 1000 pages; фактический page_size учитывать в метриках |
| После commit | PASSIVE; отдельный maintenance outcome, не второй commit |
| Soft WAL | 32 MiB: пробовать освобождение, собирать backlog/reader age |
| Hard WAL admission | 256 MiB: отказ новой записи, если WAL + прогноз не помещается |
| Прогноз на одну запись | 3 × UTF-8 snapshot bytes + 2 MiB; экспериментальный запас, не доказанная верхняя граница SQLite |
| Disk headroom | Доступно ≥ 256 MiB + прогноз + min(DB bytes, прогноз); ошибка определения места = отказ записи |
| Retained WAL после reset | journal_size_limit 8 MiB |
| BUSY timeout | 100 ms в worker; нет бесконечного retry |
| TRUNCATE | При soft-pressure / drain / shutdown, без активной write transaction; результат проверять |

В прототипе TRUNCATE под pressure может встретить внешнего reader и вернуть BUSY.
В production желательно предварительно учитывать собственные reader leases:
целевой срок <1 s, предупреждение >5 s, >30 s — отмена/перезапуск **своего**
аналитического чтения; не принудительный сброс чужого reader. Это предложенные
SLO, lease scheduler здесь не реализован. При pressure — read-only доступ и
понятный retry-later статус, без потери входящей команды и без подмены профиля.

Лимит — admission policy одного writer, а не физическая quota: чужой writer,
рост outbox или изменившаяся схема могут нарушить прогноз. Перед production
нужны telemetry write-amplification и общий бюджет DB + WAL + backups + обе
key generations. Частоту TRUNCATE можно впоследствии уменьшить по измерениям,
но только сохранив backpressure и проверки receipt.

## 5. Отказы диска и crash recovery

Native shim использует тот же загруженный SQLite DLL; SQLite/VFS/шифрование
реальные. В выбранном месте он возвращает ошибку, делает половину `xWrite` через
настоящий Windows VFS или завершает процесс до/после native вызова. Harness
проверяет попадание в injection point, точный extended code, verify после reopen
и idempotent retry прежнего ID. Отсутствие попадания означает провал теста.

| Проверка | Результат |
| --- | --- |
| FULL через `max_page_count` | Реальный SQLite code 13; revision не изменился |
| FULL / generic IOERR / WRITE на WAL commit | 13 / 10 / 778; ACK не выдан, атомарное восстановление |
| Частичная native запись WAL + WRITE | 778; неполная транзакция не стала подтверждённой |
| Ошибка первого и последнего `xSync` commit | 1034; snapshot/outbox не разошлись |
| Ошибка после фактического последнего sync | ACK не выдан; reopen + same-ID retry безопасен |
| Process crash после последнего sync commit | Восстановилась **revision 2**, snapshot + outbox; retry остаётся revision 2 |
| Checkpoint write / partial write / sync / truncate | 778 / 778 / 1034 / 1546; ранее подтверждённая revision 2 сохранена |
| Crash внутри checkpoint | Подтверждённая revision 2 восстановлена во всех проверенных точках |
| Отсутствующий/неверный ключ, повреждённая/обрезанная DB | Open отклонён; исходный файл не перезаписан пустой базой |
| Writer conflict | Реальный SQLITE_BUSY 5; после освобождения writer retry успешен |

В этих сценариях не получено ни одного подтверждённого snapshot без outbox.
Это проверка конкретной матрицы, **не математическое доказательство всех сбоев**.
Outbox в прототипе содержит синтетический immutable intent + snapshot digest;
сетевой sync command protocol и сервер не реализуются.

**Классы доказательств:**

- Реальный native путь: Windows SQLite/MC/VFS, файл, DPAPI, блокировки, flush.
- Fault simulation: управляемый code/partial write на native boundary;
  max_page_count — quota SQLite, а не заполненный физический диск.
- Не проверено: реальный power cut, контроллер с ложным flush, reordered sectors,
  bad blocks, все READ/SHM/LOCK/DIR_FSYNC subcodes. Process kill сохраняет OS cache.

## 6. Key lifecycle и recovery

### Подтверждённый upstream риск

Тестирован именно установленный `flutter_secure_storage_windows 4.2.2`,
`DpapiJsonFileMapStorage`, с заменой application-support path на marked synthetic
directory. Native DPAPI не mock. При corrupt ciphertext, partial vault и
DPAPI-valid invalid JSON plugin **удаляет файл и выбрасывает ошибку**. Missing
vault возвращает пустую map. Код save пишет в основной файл без поколений и
повторяет FileSystemException в цикле. Production plugin не патчился.

Следствие: этот plugin нельзя принять как единственный recovery-critical vault
без отдельного защитного слоя или upstream исправления. Простое «если key нет —
сгенерировать» недопустимо при любых существующих encrypted artifacts.

### Реализованный синтетический two-generation прототип

`control.bin` — DPAPI-protected JSON manifest формата
`qesto.synthetic.generations.v1`: active generation, key descriptors,
minimum revision и snapshot digest в точке ротации. Ключи находятся только внутри
DPAPI envelope. DB filename вычисляется из generation number, не берётся как
произвольный путь из manifest. Отдельный `recovery.bin` хранит предыдущий валидный
manifest. Временная запись flush → same-directory Windows MoveFileEx replacement;
ошибка чтения ничего не удаляет.

Порядок при остановленном sole writer и освобождённых readers:

1. Проверить текущий manifest, DB, revision/outbox/digest; запретить provisioning
   поверх существующих DB/vault/staging artifacts.
2. Сохранить оба ключа, оставить active = старое поколение.
3. Создать **новую** DB через encrypted online backup, шифруя новым ключом.
   In-place rekey не считается crash-atomic связкой с vault.
4. Reopen новым ключом, verify; revision источника и копии должны совпасть.
5. Атомарно заменить active manifest, сохранив предыдущее состояние для recovery.
6. Старую DB и оба ключа пока сохранять. Автоматический retire не реализован;
   следующая rotation блокируется, пока явно не решена судьба прошлого поколения.
   Третье поколение не создаётся. Resume/retire workflow остаётся gate для 2b.

Пять process interruptions: до dual-key, после dual-key, во время копирования,
после verify новой DB, после promotion. До promotion выбирается старое поколение,
после — новое; финансовая revision не изменяется. Missing/corrupt/truncated/
invalid-JSON/missing-key/wrong-key vault дают fail-closed. Явное восстановление из
локального backup проверяет соответствующую DB и возвращает recovery revision;
fresh process успешно открывает её. Новый encrypted generation отклоняет старый
ключ. Исходные повреждённые байты при неуспешном обычном open сохранены.

Recovery flow для production: заблокировать запись → сохранить все артефакты →
показать причину без ключей/банковских данных → проверить доступные manifest/DB
generations → предложить **явный** выбор проверенной точки восстановления →
verify snapshot/outbox → reopen. Не называть старый backup «последними данными».
Если ключ невосстановим — не создавать пустую замену; отдельный подтверждаемый
пользователем reset/export-diagnostics workflow вне этого этапа.

**Ограничения:** DPAPI current-user envelope не является переносимым backup.
Потеря Windows identity/master keys не покрыта; portable recovery/секрет
восстановления ещё предстоит спроектировать. DPAPI обеспечивает защиту envelope,
но не anti-rollback sequence всего профиля. Registry/ACL, гарантии directory
metadata при power loss и retention поколений требуют отдельного review.
Rotation и ordinary writer здесь отдельные инструменты; взаимное исключение
между ними — обязательный контракт будущего owner, не готовая production-фича.

## 7. Ownership и производительность

Рекомендуется **один long-lived writer isolate на профиль**, без raw SQLite
handles в UI. Получение/подготовка canonical данных, JSON, digest и commit вне UI;
SQL transaction содержит revision CAS, snapshot, outbox и sync metadata.
Ни сети, ни пользовательского ожидания внутри transaction.

В `WriterOwner` явная FIFO цепочка: `ReceivePort.listen(async ...)` сам по себе
не сериализует работу после await. Проверено 10 одновременно отправленных
команд: все завершились в порядке revision до close, новая команда после начала
закрытия отвергнута. Отдельный connection читает старую revision во время записи.
При shutdown: прекратить приём → drain принятых команд → best-effort checkpoint →
close. Не требовать успешного checkpoint для сохранности уже durable commit.

Нужны ещё production supervisor/error ports, отмена запросов, лимиты очереди,
реакция на смерть isolate и cross-process ownership. Прототип FIFO не заменяет
их; неожиданный kill writer проверен через отдельный native harness.

### AOT Windows, checkpoint policy включена

3 свежих процесса на размер, каждый: initial snapshot + 3 полные перезаписи
с изменением первых 100 notes. Это shared canonical serializer, не реальный
профиль. CPU = process kernel+user GetProcessTimes; RSS = весь процесс, не
аллоцированная память только SQLite. Начальная сериализация включает создание
canonical объектов. Warm OS caches; один компьютер, не throughput SLA.

| Операций | Initial total median | Model + JSON median | Commit + checkpoint median | Initial CPU median | Перезапись total median | Peak RSS после серии |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 000 | 41,5 ms | 9,7 ms | 32,2 ms | 46,9 ms | 54,1 ms | 47,4 MiB |
| 10 000 | 379,3 ms | 83,8 ms | 295,4 ms | 343,8 ms | 507,9 ms | 102,9 MiB |
| 50 000 | 1 872,6 ms | 457,7 ms | 1 414,9 ms | 2 046,9 ms | 2 800,8 ms | 256,7 MiB |

50k JSON ≈38,63 MB. После четырёх записей основная DB **78 905 344 bytes**;
после финального close WAL/SHM отсутствуют штатно. На 50k maintenance уменьшает
WAL до нуля после каждого checkpoint; это не значит нулевой пик внутри commit.
В 2a при auto-checkpoint=0 после четырёх записей WAL был ≈277,8 MB.
Сравнение показывает цену maintenance и контроль оставшихся файлов, а не
универсальное ускорение или улучшение RAM относительно другой методики 2a.

Главный isolate продолжал 10-ms timer: худший измеренный интервал **32 ms**.
Это проверка отсутствия многосекундной блокировки event loop, **не Flutter FPS**.
Целое opaque snapshot приемлемо как ограниченный bridge, но не долговечная
безлимитная модель: при 50k одна правка уже стоит нескольких секунд и сотен MB RAM.

Граница для дальнейшего перехода без нового финансового ядра:
`readSnapshot(revision)`, `commit(expectedRevision, commandId, canonicalResult)`,
`lookupReceipt(commandId)`, `readOutbox`, `backup/recover/rotate`.
Репозиторий не должен знать физическую форму snapshot; codec version отделён от
container schema. Позже можно заменить один BLOB на частично нормализованные
таблицы под той же SQL transaction/revision/outbox. Reconciliation остаётся shared
Synoball. Сейчас никаких production interfaces или таблиц не нормализовано.

## 8. Проверки и evidence

| Текущий прогон | Итог |
| --- | --- |
| Native WAL/fault/crash/recovery release scenarios | 31 passed |
| DPAPI generations/key/restart scenarios | 13 passed |
| Windows secure-storage plugin host tests | 5 passed; destructive upstream behavior воспроизведено |
| Storage A/B contracts + policy regressions | 58 passed |
| Старые C contracts | 31 passed |
| Shared Synoball parity/golden | 33 passed |
| App storage recovery / codec / core / safety / compatibility | 33 passed |
| FIFO owner / shutdown | passed: 10 queued commands, late write rejected |
| Значимые benchmarks | 9 AOT runs, 36 snapshot commits |
| Dart experiment analyze / Flutter probe analyze | No issues found |
| Windows native shim (/W4 /WX), three AOT harness bundles | Build passed |

Новых skips нет. Android host tests выше исполнялись **на Windows** и не являются
Android runtime evidence. Не делались emulator detection/setup, телефон, APK
install, production build/install, migration и отправка финансовых данных.

Машиночитаемые результаты: `experiments/storage_feasibility/results/`
`hardening_summary.json`, `hardening_native.json`, `hardening_keys.json`,
`hardening_benchmarks.json`, `hardening_*tests.jsonl`, `hardening_contracts_*.jsonl`,
`hardening_shared_parity.jsonl`, `hardening_app_regression.jsonl`, analyzer logs.
`hardening_baseline.json` ссылается на сохранённые 525 hashes 2a; первоначальная
попытка 2a.1 capture с неверным корнем была отброшена, затем все 525 проверены.

Воспроизведение: из каталога эксперимента PowerShell
`./tool/run_hardening.ps1 -IncludeBenchmarks`. Нужны указанные в скрипте локальные
Dart/Flutter и MSVC BuildTools. Отдельные команды реально выполнены; aggregate
script — удобная последовательность тех же команд, не ещё один полный прогон.
Бинарные файлы и синтетические DB/ключи не добавляются в Git.

## 9. Изменённые файлы этого этапа

Только относительно состояния 2a:

- Изменён `experiments/storage_feasibility/lib/storage_spike.dart`: rollback,
  checkpoint result, optional auto threshold и guard DB-only rekey.
- Новые `lib/wal_policy.dart`, `lib/native_faults.dart`, `lib/generation_vault.dart`,
  `lib/writer_owner.dart` — всё внутри storage experiment.
- Новые `bin/hardening.dart`, `bin/key_hardening.dart`,
  `bin/ownership_benchmark.dart`.
- Новые `test/hardening_policy_test.dart`,
  `android_probe/test/windows_vault_hardening_test.dart`.
- Новые `tool/fault_shim.c`, `tool/build_fault_shim.ps1`,
  `tool/run_hardening.ps1`, `tool/collect_hardening_results.dart`.
- Новый `HARDENING_PLAN.md`, дополнение `README.md`, текущий отчёт и
  перечисленные `results/hardening_*` evidence artifacts.

## 10. Gates перед 2b / production

1. Android native runtime, persistent key, restart, backup и fault/performance
   на эмуляторе и **отдельно физическом устройстве**. Отложено пользователем.
2. Выбор recovery-capable Windows vault: текущий plugin без защиты неприемлем.
   Shadow rotation доказана локально, не интегрирована с production lifecycle.
3. Owner supervision, reader leases, queue budgets, second-process exclusion,
   взаимоисключение writer/rotation/backup и проверка abrupt app lifecycle.
4. Portable key recovery, anti-rollback policy, retention backups/generations и
   согласие пользователя на откат к явно указанной recovery revision.
5. Размер/частота whole-snapshot commits, write amplification, общий disk budget
   и переходный предел по RAM/latency. В частности, 50k не обещает быстрые edits.
6. Настоящие power-loss/storage tests и независимый review recovery protocol.
   Injected native errors не снимают этот риск.

**Итог:** storage-гипотеза усилена воспроизводимыми Windows доказательствами.
Можно обсуждать отдельный ограниченный план 2b, сохраняя перечисленные gates;
считать хранилище production-ready и переносить рабочие профили пока нельзя.
На этом этап 2a.1 остановлен.

### Технические источники

- [SQLite WAL](https://www.sqlite.org/wal.html): reader end marks, один writer,
  automatic checkpoint и FULL durability.
- [Checkpoint PRAGMA](https://www.sqlite.org/pragma.html#pragma_wal_checkpoint):
  результат checkpoint и режимы; отсутствие BUSY не означает нулевой backlog PASSIVE.
- [SQLite autocommit](https://www.sqlite.org/c3ref/get_autocommit.html): некоторые
  ошибки автоматически откатывают transaction, состояние нужно проверять.
- [SQLite VFS I/O methods](https://sqlite.org/c3ref/io_methods.html): граница
  native fault injection; это не имитация бизнес-ошибки в Dart.
- [Windows DPAPI](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata):
  user/machine binding и integrity envelope, не переносимый recovery key.
- [MultipleCiphers SQLCipher mode](https://utelle.github.io/SQLite3MultipleCiphers/docs/ciphers/cipher_sqlcipher/):
  cipher configuration, отдельная библиотека от Zetetic.
- Windows plugin 4.2.2: pinned local source
  `flutter_secure_storage_windows/lib/src/flutter_secure_storage_windows_ffi.dart`,
  `DpapiJsonFileMapStorage.load/save`; runtime reproduction находится в host tests.
