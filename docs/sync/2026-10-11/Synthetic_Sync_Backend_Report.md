# QESTO Sync — Stage 3a: Synthetic Sync Backend Report

Дата: 11.10.2026. Статус: **ограниченный synthetic slice реализован и проверен**.
Это не production backend и не разрешение на передачу финансовых данных в облако.

## 1. Результат и границы

Два независимых CLI-клиента через локальный Dart-сервер и настоящую PostgreSQL
обмениваются заметкой канонической операции. Проверены повторная доставка,
конфликт правок, временно отключённый клиент, порядок commit и аварийное завершение
серверных/клиентского процессов. Финансовое изменение применяется существующим
`SynoballCore.updateTransaction`, а не альтернативной реализацией ядра.

Весь новый код находится в `experiments/synthetic_sync_backend/`. Рабочий Qesto,
`LocalQestoRepository`, финансовые модели, банковские адаптеры, установленные
Windows/Android приложения и пользовательский профиль не подключались и не менялись.
До/после совпали SHA-256 **540 файлов** app/core `lib` и `test`.
Ранее существовавшие незакоммиченные изменения репозитория сохранены.

**Итог проверок: 212 passed, 0 failed, 0 skipped; Dart analyzer — без замечаний.**
Тестовый PostgreSQL и все процессы тестовых серверов после прогона остановлены.
Синтетические файлы оставлены в игнорируемой `.runtime`, не удалялись.
Следующий этап автоматически не начинался; commit/push/PR не выполнялись.

## 2. Сверка архитектуры и зависимостей

Изучены протокол разработки, Sync A–E и реализованные границы core/container.
В частности, раздел 7 документа C уже предлагает workspace row-lock для commit
cursor; здесь эта гипотеза реализована и проверена на двух серверных процессах.

| Компонент | Решение и обоснование |
|---|---|
| Dart 3.12.2 | Совпадает с доступным SDK и shared core; Flutter backend не требуется |
| `qesto_synoball_core` 0.1.0 | Path dependency; текущая бизнес-логика, без правок пакета |
| `postgres` 3.5.20 | Единственная новая runtime-технологическая зависимость: настоящий PG wire driver, параметризованные запросы и транзакции |
| `crypto` 3.0.7 | Уже применяется в экспериментах; SHA-256 и HMAC курсоров |
| `test` 1.31.0 | Уже используемый Dart test runner; версии зафиксированы lockfile |
| `dart:io` | HTTP, процессы и файлы; без дополнительного web framework |
| PostgreSQL 17.11 Windows x64 | Изолированный переносной экземпляр EDB, не системная служба |

Официальные основания: [документация драйвера](https://pub.dev/packages/postgres),
[переносные сборки EDB](https://www.enterprisedb.com/download-postgresql-binaries),
[row locks PostgreSQL](https://www.postgresql.org/docs/17/explicit-locking.html).
Архив получен по HTTPS с EDB; воспроизводимый SHA-256:
`80379B2C04D51C30225532E0AE04509899141E9957ED096FE749D7FD9DF8F82F`.
Это локально зафиксированный digest, **не утверждение о независимой подписи вендора**.

Подтверждённая конфигурация PG: `listen_addresses=127.0.0.1`, `fsync=on`,
`synchronous_commit=on`, SCRAM-SHA-256. Скачивались только публичные инструменты и
зависимости; финансовые данные не передавались внешним сервисам.

## 3. Архитектура и схема БД

```text
CLI A: собственный файл команд/состояния       CLI B: собственный файл
                 ↓ loopback HTTP ↓
             Dart server process 1 / process 2
                 ↓ проверка token → owner/device/workspace
             PostgreSQL transaction + workspace FOR UPDATE
                 ↓ существующий SynoballCore.updateTransaction
             state + revisions + receipt + bundle + head
                 ↓ COMMIT
             ответ / повтор / incremental pull
```

| Таблица | Содержимое и ограничения |
|---|---|
| `experiment_identity` | Обязательный marker синтетической БД; проверяется перед запуском API |
| `workspace` | PK workspace, owner, epoch, transactional bigint head, сериализованное состояние Synoball, per-entity revisions JSONB |
| `command_receipt` | PK `(workspace, change_id)`, canonical body, digest, финальный результат, unique `(workspace, seq)` |
| `change_bundle` | PK `(workspace, seq)`, change ID и полный bundle; FK к receipt по ID и seq |

`command_receipt` и `change_bundle` запрещают UPDATE/DELETE триггерами; app role
имеет только SELECT/INSERT на них. На workspace — SELECT/UPDATE, без создания и
удаления. Таблицы включают RLS по установленному сервером workspace context.
`qesto_sync` не superuser, не владелец таблиц, без BYPASSRLS/CREATEDB/CREATEROLE.
DDL/создание тестовых workspace выполняет отдельный harness через отдельную роль.
Обычным серверным процессам admin password не передаётся.

Один push — один `runTx`: проверка прав/epoch, lock, повторная проверка receipt,
revision check, исполнение core, запись state/revisions/head, receipt, bundle,
COMMIT. Только после успешного COMMIT возвращается accepted/conflict receipt.
Доменный конфликт сохраняется как результат без финансовой мутации. Все SQL
значения команды передаются параметрами, не конкатенируются с SQL.

**Граница доказательства:** trusted server code — единственный API writer.
RLS страхует пропущенный/чужой scope в запросе, но владелец украденных DB credentials
может выставить другой session context. Прототип не доказывает безопасность при
компрометации приложения/администратора БД. Будущие writers также обязаны соблюдать
write gate; произвольный административный UPDATE в доказательство не входит.

## 4. Минимальный API и test identity

Сервер слушает исключительно `InternetAddress.loopbackIPv4`; адрес слушателя не
настраивается внешним параметром. Обычный entry point — `bin/server.dart`.
Fault controls отсутствуют в этом entry point и недоступны через HTTP.

На запросе обязательны:

- `Authorization: Bearer <локальный случайный test token>`;
- `X-Device-Id`, совпадающий с привязанным к token устройством;
- `X-Protocol-Version: 1`, `X-Domain-Version: 1`.

Серверная конфигурация связывает token с user/device/workspace. Тело запроса не
выбирает владельца. Путь, command body, device, workspace owner и epoch сверяются
на сервере. Имеются отдельный посторонний пользователь и workspace для негативных
тестов. Запросы с Origin отклоняются; браузерные cookie/CORS flow не реализованы.
Это статическая тестовая allowlist, **не production-аутентификация**.

| Endpoint | Реализовано |
|---|---|
| `GET /sync/v1/capabilities` | Версии, единственная команда, максимальный body |
| `GET /sync/v1/workspaces/{w}/snapshot` | Согласованный bootstrap двух fixture-операций и курсора |
| `POST /sync/v1/workspaces/{w}/push` | Одна команда `transaction.set_note` |
| `GET /sync/v1/workspaces/{w}/changes` | Полные ordered bundles, `cursor`, `limit` 1–100 |

Команда:

```json
{
  "protocol_version": 1,
  "domain_version": 1,
  "workspace_id": "workspace-example",
  "workspace_epoch": "epoch-example",
  "device_id": "device-a",
  "change_id": "note-edit-1",
  "kind": "transaction.set_note",
  "transaction_id": "synthetic-tx-0",
  "base_revision": "0",
  "note": "Synthetic note"
}
```

Unknown/missing поля и unsupported команды отклоняются; нет JSON Patch, изменения
денег, произвольного присваивания trust/revision/owner или profile replacement.
Body максимум 16 KiB, note максимум 4096 UTF-8 bytes; null запрещён, пустая строка
очищает видимый текст. Чтение body имеет общий deadline 5 секунд, сохраняет не
более разрешённого объёма; максимум 16 активных обработчиков на процесс.

Receipt содержит workspace/epoch/versions, change ID, digest, status,
`commit_seq`, target и revision. Conflict дополнительно содержит base revision,
предложенную заметку, текущую заметку и revision. Другая заметка со старым change ID
получает `IDEMPOTENCY_KEY_REUSED`, ничего не применяя. Повтор того же тела возвращает
прежний receipt, в том числе после неизвестного клиенту успешного commit.

Деньги в wire entity: `{"minor_units":"486122","currency":"RUB","scale":2}`.
Ревизии и seq также передаются десятичными строками. Внутренний сериализатор Money
shared core не изменён. Entity bundle содержит каноническую операцию целиком,
а не частичный непроверенный JSON patch.

## 5. Commit-order cursor

Каждый writer берёт `workspace ... FOR UPDATE` и держит lock до окончания
транзакции. `head + 1` — transactional bigint, **не nextval/sequence, timestamp
или UUID order**. После rollback номер не опубликован. Второй writer не может
назначить и зафиксировать следующий номер, пока первый не завершится.

И состояние, и head, и запись журнала появляются одной транзакцией. Retry
существующего receipt не увеличивает head. Conflict получает отдельный seq,
чтобы второй клиент также увидел сохранённое предложение.

Pull читает head и журнал из repeatable-read transaction. H фиксируется в
HMAC-SHA256 cursor вместе с workspace/epoch/protocol/domain/after. Последующие
страницы ограничены H; после последней страницы новый цикл может получить новый H.
Проверяются непрерывность seq и полнота страницы. `commit_seq` в push receipt
сам по себе **никогда не продвигает клиентский pull cursor**.

Фактическое доказательство, `results/commit_order_evidence.json`:

- два разных серверных PID: **26468 и 27396**;
- первый остановлен harness-барьером непосредственно перед commit;
- ожидание второго подтверждено через `pg_stat_activity.wait_event_type = Lock`;
- pull в этот момент видит committed H = **0**, не незавершённую запись;
- после release receipts получают **1, 2**; клиент последовательно доходит до **2**.

Отдельный тест: при H=2 после первой страницы возникает commit 3. Вторая страница
заканчивает именно H=2; commit 3 доставляется следующим циклом, не теряется.

## 6. Shared core и два клиента

Сервер восстанавливает `SynoballState`, создаёт `SynoballCore` и вызывает существующий
`updateTransaction(transaction.copyWith(userNote: ...), actorId: ...)`.
Clock и ID factory контролируются в parity-тесте. Идентификаторы финансовых
операций/счетов не переназначаются. ID новых test audit/events имеют namespace
immutable change ID; production ID factory не изменён.

**Важно:** штатный `updateTransaction` также обновляет timestamps/trust и может
пересчитать derived merchant/category metadata. Прототип не подменяет это собственной
«упрощённой» финансовой логикой: публикует все изменившиеся canonical transactions
с серверными revisions. Parity сравнивает полный результат с прямым вызовом core
при тех же clock/IDs. Отдельно проверены точные суммы/валюты, направления, status,
financial IDs, user category override и tags; сериализация восстанавливается.

Воспроизведённая цепочка независимых **client executable processes**:

| Событие | Результат |
|---|---|
| A сохраняет и отправляет `a1` | revision/seq 1, заметка `A first`; A pull cursor ещё 0 |
| B делает pull и отправляет `b1` | revision/seq 2, `B reply` |
| A отключён; B отправляет `b2` | revision/seq 3, `While A offline` |
| A возвращается и читает страницы по одной | получает все 1–3; A и B имеют одинаковые entities и seq=3 |

`synthetic-tx-0` сохранила **486122 minor units RUB**, направление outflow;
`synthetic-tx-1` — **1500025 minor units USD**, inflow. Wire и результаты сохранены
в `results/two_client_scenario.json`, без токенов или DB credentials.

### Почему не подключён контейнер 2b.0

Тот контейнер принимает целый codec-v7 snapshot и при pending local commands
сохраняет projection, фиксируя конфликт; полноценный domain rebase ещё не доказан.
Подключение его как «готового sync client» скрыло бы этот незакрытый gate.

В 3a отдельный ограниченный adapter хранит только synthetic canonical entities,
immutable pending commands, receipts, hash применённых страниц и checkpoint.
Сохранение страницы — один flushed sibling file + rename. Client process exit
**перед сохранением** оставляет прежний файл; повторный pull безопасно применяет
ту же страницу. Повтор уже применённой страницы ничего не меняет.
Pending proposals не стираются incoming pull и не объявляются принятой операцией.

Это **не** encrypted SQLite и не production persistence, нет optimistic projection,
автоматического rebase, concurrent local writer или доказательства устойчивости
rename к аппаратному сбою. Исходники 2b.0 не менялись; его тесты выполнены отдельно.

## 7. Проверки и воспроизводимые результаты

Финальный полный запуск выполнен единой командой:

```powershell
cd C:\Users\ARM\Documents\Qesto\experiments\synthetic_sync_backend
./tool/run.ps1 -IncludeRegressions
```

Exit code **0**, timestamp сводки `2026-10-11T12:56:18.511238Z`.
`results/summary.json` содержит версии, PG settings, счётчики, analyzer и source check.

| Набор | Passed | Failed / skipped |
|---|---:|---:|
| Новые protocol/domain + real PostgreSQL integration | 27 | 0 / 0 |
| Shared Synoball parity/regression | 33 | 0 / 0 |
| Container 2b.0 + storage contracts/hardening policy | 119 | 0 / 0 |
| Выбранные app persistence/core compatibility tests | 33 | 0 / 0 |
| **Всего** | **212** | **0 / 0** |

Применимые app tests: `storage_recovery_safety_test`, `user_financial_data_codec_test`,
`synoball_core_test`, `shared_synoball_core_compatibility_test`, `synoball_safety_test`.
В storage run вошли `container_contract_test`, `container_process_test`,
`contract_test`, `hardening_policy_test`.

| Обязательный отказ/сценарий | Наблюдение |
|---|---|
| Повторный push | Receipt идентичен; head/receipt/bundle/audit остаются по одному |
| Потеря ответа после commit | Клиент оставляет command; retry получает сохранённый accepted |
| Завершение сервера после state, до receipt | Реальное завершение процесса; rollback head/receipt/bundle до 0; retry даёт 1 |
| Завершение перед COMMIT | Аналогично: не возникает подтверждённого частичного изменения |
| Завершение после COMMIT | До retry уже head=1 и одна receipt; retry не создаёт вторую мутацию |
| Два writer / две разные операции | Два сервера и CLI-процесса, оба изменения сохранены, head=2 |
| Одинаковая command на двух серверах | Один результат и один commit |
| Конкурентные заметки одной операции | Один accepted, один immutable conflict; обе proposals сохранены |
| Ошибка БД | Настоящая ошибка PG `SELECT 1/0` после state write; transaction откатывается полностью |
| Чужой workspace/device/token/cursor | Чтение и мутация запрещены; оба head остаются 0 |
| RLS | Без scope чтение пусто; из чужого scope UPDATE затрагивает 0 строк; DELETE запрещён |
| Повтор страницы / неправильная sequence | Повтор idempotent; неправильная page не меняет файл/checkpoint |
| Падение клиента до checkpoint | Отдельный процесс завершён с кодом 87; файл byte-for-byte прежний; повторный pull успешен |
| Версии domain/protocol/epoch | Несовместимость отклоняется до мутации |
| SQL-подобная Unicode заметка | Сохранена как текст; схема цела |
| Oversized body / подделанный cursor | Отклонены; дополнительных commits нет |
| Обычный executable без hooks | Успешный обмен; тестовый fault-файл на него не действует |

Компиляция AOT обычного сервера, fault server и client worker прошла.
`dart analyze` — **No issues found**. `git diff --check` — exit 0 (предупреждения
LF/CRLF относятся к ранее изменённым файлам; они не переписывались).

Не запускались полный UI suite, Windows release Qesto, Android, эмулятор/телефон,
network/cloud rollout. Они не требуются изолированному backend slice и не
объявляются проверенными. Также не повторялся весь native key/IO harness 2a.1:
storage-код не менялся, выбранные 119 контрактных проверок перечислены выше.

### Найденные и исправленные проблемы экспериментального harness

1. Windows `Process.run(pg_ctl ...)` ждал EOF у pipe, унаследованного фоновым PG,
   хотя pg_ctl завершился. Управление переведено на ожидание exit code и закрытие
   подписок; запуск/остановка кластера проверены финальным runner.
2. Первоначальное прерывание чтения oversized HTTP body отменяло поток и могло
   оборвать соединение раньше ответа 413. Теперь лишние bytes не сохраняются,
   конечный body дочитывается в пределах общего deadline, возвращается 413.
   Финансового commit в ошибочном варианте также не было.
3. Исправлены замечания analyzer/опечатка в дополнительном тесте; первоначальные
   неполные прогоны не выданы за финальные. Последний общий runner завершился успешно.

Native process termination — не отключение питания. SQL error injection — не
доказательство реакции на физический I/O failure PostgreSQL. Эти границы сохранены.

## 8. Изменённые/созданные файлы

Все перечисленные файлы **новые для этапа 3a**, кроме создаваемых/обновляемых
generated results. Production-файлы не изменялись.

В `experiments/synthetic_sync_backend/`:

- `.gitignore`, `pubspec.yaml`, `pubspec.lock`, `PLAN.md`, `README.md`;
- `lib/protocol.dart`, `lib/config.dart`, `lib/domain.dart`, `lib/database.dart`,
  `lib/server.dart`, `lib/client.dart`;
- `sql/schema.sql`, `bin/server.dart`;
- `test/protocol_domain_test.dart`, `test/integration_test.dart`, `test/harness.dart`;
- `tool/cluster.dart`, `tool/fault_server.dart`, `tool/client_worker.dart`,
  `tool/source_evidence.dart`, `tool/collect_results.dart`, `tool/run.ps1`,
  `tool/download_postgres.ps1`;
- `results/source_baseline.json`, `source_check.json`, `tests-first.jsonl`,
  `tests.jsonl`, `shared-core-tests.jsonl`, `storage-regression-tests.jsonl`,
  `app-regression-tests.jsonl`, `analyze.txt`, `summary.json`,
  `two_client_scenario.json`, `commit_order_evidence.json`.

Отчёт: `docs/sync/2026-10-11/Synthetic_Sync_Backend_Report.md`.
`.runtime` и `build` игнорируются: там ZIP/бинарники, PostgreSQL cluster, случайные
test secrets и синтетические клиентские файлы. Production APK/EXE не собирались
и не устанавливались. Создание синтетической схемы — не миграция Qesto.

## 9. Открытые риски и план до дальнейшей интеграции

**3a достигнут в заявленной узкой области; публикация или real-data integration — NO-GO.**

1. Отдельно согласовать production auth: OIDC/PKCE, issuer/audience/expiry,
   device registration/revocation, membership и transactional permission recheck.
   Test token allowlist нельзя просто перенести в production.
2. Выбрать и проверить защищённое размещение: TLS, secrets lifecycle, backup/restore,
   DB least privilege, observability без финансовых payload, quotas и security review.
   В этом этапе ничего не размещалось и внешние endpoints не открывались.
3. Закрыть 2b.0 gates: encrypted client container integration, staged Unit of Work,
   pending-tail/rebase contract, owner crash recovery, portable keys и Android runtime.
4. Для расширения beyond note: versioned domain command registry, audit/security
   policy каждого kind, primary-fact bootstrap/aliases/tombstones; только существующий
   core. Synthetic fixture не доказывает полноту банковского ingestion на сервере.
5. Snapshot сейчас малый и целиком; state — opaque core JSON. Нужны большие synthetic
   нагрузки, CPU/RAM/latency и границы workspace serialization, pool/worker ownership.
   Финансовая логика выполняется в server isolate; масштабируемость не доказана.
6. Добавить retention/compaction/expiring cursors, восстановление epoch и safe
   rebootstrap, включая доставку ранее созданных conflict proposals новому клиенту.
   Сейчас история не удаляется, cursor не истекает, generic restore отсутствует.
7. Client file adapter не имеет шифрования, production durability и multi-writer
   гарантий. Старые pending commands/receipts/page hashes хранятся без compaction.
   Чекпоинт после process-exit проверен, power-loss между flush/rename — нет.
8. RLS context доверяет серверу. Более сильное разграничение внутренних writers и
   запрет обхода commit gate следует спроектировать до появления admin repair,
   импорта и других сервисов. Прямой SQL с украденной service credential вне модели.

Следующий ограниченный эксперимент/этап выбирает владелец продукта отдельно.
До этого никаких реальных банковских профилей, cloud auth, production migrations
или синхронизации между установленными Windows/Android приложениями не включать.
