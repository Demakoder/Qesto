# QESTO Sync 4a — Windows Integration Boundary

Дата: 12.10.2026. Windows x64; исключительно synthetic codec-v7 профили.

## Результат

В реальном `BudgetController` создана optional точка подключения для staged
правки заметки. Тестовая реализация готовит профиль, применяет **существующие**
Synoball/legacy bridge/category policy, сериализует codec v7 и сохраняет snapshot
с immutable command в encrypted Transaction Container. Контроллер публикует
результат после durable commit. При отказе или неизвестном исходе новая заметка
не показывается как успешно сохранённая.

Production `QestoAppShell → LocalQestoRepository` остаётся default. В приложении
нет настройки, feature flag, automatic migration, нового экрана или обращения
к экспериментальной SQLite. Включение требует явного создания synthetic
controller и отдельной зависимости. Рабочий профиль, vault, банковские сессии,
установленное приложение и Android не открывались. Сеть/PG в 4a не используются.

Дальнейшая синхронизация требует отдельного этапа: подтверждён конкретный разрыв
между штатной note-семантикой Qesto и текущим серверным адаптером 3a. Его описание
ниже; совместимость локального staged-пути со штатным Qesto уже проверена.

## 1. Реальные границы и изменённый production-код

```text
BudgetController.setTransactionNote
        │ TransactionNoteIntent: command ID, target, note, expected revision
        ▼
TransactionNoteBoundary                     [optional DI, default отсутствует]
        ▼
WindowsNoteBoundary                         [только experiments / synthetic]
        │ supervised isolate, единственный owner
        │ read durable snapshot → codec.decode
        │ configured Synoball + QestoLegacyBridge + прежняя Sber projection
        │ codec.encode → snapshot + immutable command → SQLite commit
        ▼
CommittedTransactionNote                    [typed data + подготовленный core]
        │ lifetime/stale/cancel checks
        ▼
публикация контроллером + notifyListeners
```

Изменены ровно четыре файла app source:

| Файл в `apps/qesto_app/lib/` | Назначение |
|---|---|
| `data/mutations/transaction_note_boundary.dart` — новый | Intent, результат durable commit, ошибка с unknown outcome, отмена, DI-интерфейс |
| `features/budget/services/transaction_note_preparation.dart` — новый | Вынесена прежняя одиночная правка через bridge/core; staged preparation использует тот же код |
| `features/transaction_import/services/sber_transaction_projection.dart` — новый | Прежняя private проекция контроллера перенесена для повторного использования worker; правила не изменены |
| `features/budget/state/budget_controller.dart` | Optional dependency, note revision/recovery, публикация после commit, вызов общей прежней правки/проекции, optional clock/IDs для тестов |

`UserFinancialDataCodec`, модели/schema v7, финансовые расчёты, shared core,
repository, app shell и банковские адаптеры не редактировались. SQLite-прототип
2b.0/3b также используется без новых изменений его реализации.

Контроллер принимает подготовленный в worker core, поэтому после commit в UI
не повторяется тяжёлая constructor/enrichment работа. Перенос typed result между
isolates и добавление UI-списков всё равно имеют стоимость — она измерена ниже.

Clock/ID injection имеет прежние defaults. Детерминированные audit/event IDs
используются только synthetic tests; существующие financial IDs не заменяются.

## 2. Поведение по умолчанию и изоляция

Обычный `QestoAppShell` создаёт `BudgetController` без `noteBoundary`, с прежним
`onChanged: _saveFinancialData`. Обычный `updateTransaction` по-прежнему изменяет
in-memory state и вызывает callback сохранения. Новый `setTransactionNote` при
отсутствии boundary делегирует этому же пути. Default persistence не переключён.

Synthetic injection запрещает одновременно задавать legacy save callback: нельзя
случайно отправить этот профиль в production repository. В таком контроллере
старые финансовые команды не поддерживаются: попытка их сохранения через
`_changed` прекращается и требует reload/recreation. Эти методы всё ещё могут
менять память до save boundary, поэтому смешивать их со staged notes нельзя.
Для обычного контроллера их прежнее поведение сохранено.

Synthetic factory создаёт новый `qesto-storage-spike-*` каталог с двумя markers,
отдельными `synthetic-4a-*` workspace/device/epoch и synthetic user. Adapter
проверяет identity, marker и resolved path перед открытием Container. Нет поиска
профилей, чтения настоящего `store.json`, доступа к secure-storage plugin рабочего
Qesto или банковскому профилю. Ключи создаются существующим synthetic DPAPI
Container только для этого каталога; missing key не вызывает reset/recreation.

Native CLI переиспользует реальные pure app-файлы через generated package-config
mapping `qesto`. Приложение не получает dependency на эксперимент. Для настоящего
Flutter-контроллера создан отдельный test package с обычным app path dependency.
Его собственный lock file фиксирует тестовые зависимости; app pubspec/lock не
меняются. Финансовые операции/codec не скопированы в эксперимент.

## 3. Mutation inventory и дальнейший перенос

Исследован центральный save path: в app `saveUserFinancialData` вызывается из
`QestoAppShell._saveFinancialData`, который сохраняет `controller.mergeInto(...)`.
Перечислены **51 public asynchronous financial method** контроллера/его
classification extension; полный список с source lines и маршрутом находится в
[`mutation-inventory.json`](../../../experiments/windows_integration_boundary/results/mutation-inventory.json).

Часть импортов уже использует staged core для проверки входа, однако публикация
результата всё ещё предшествует repository save. Это не эквивалент commit-before-UI.

| Группа существующих mutation paths | Что переносить после отдельного согласования |
|---|---|
| `updateTransaction`, `updateTransactions`; manual `addExpense` | Intent с исходной revision, существующий bridge/core, атомарная публикация всей группы, stable draft/command ID |
| Statement, `addImportedTransactions`, Sber snapshot | Переиспользовать adapters/reconciliation и существующие staged imports; snapshot + batch command + durable import result, затем UI |
| Notification confirm/import, screenshot, receipt, voice/confirm | Сохранить candidate type, direction, minor units, source identity; отдельно согласовать ACK внешней очереди после durable financial commit |
| Delete/restore/trash, `undoAction`, clear-all | Atomic tombstones/restore и action ledger; никаких новых IDs при повторе; clear-all требует собственной barrier и approved recovery |
| Categories, appearance, merges/redirects, merchant rules, tags | Persist configured policy и canonical effect вместе; re-enrichment старых операций и budgets не разделять на отдельные commits |
| Category/total budgets, upcoming add/update/delete | Сохранять существующие calculation rules; staged root changes и CAS, group commands при взаимозависимости |
| Accounts/preferences | Atomically account identity, canonical/read projection и preferences; не делать глубокий старый matching в этом slice |
| Goals/allocations/contributions/history | Сохранить резервирование/историю; транзакционные границы для связанных root sections |
| Investments/balances/contributions; debts/payments/archive | Existing canonical account mirror + root records в одном staged результате; расчёты не дублировать |
| User profile/display currency | Root-only commands; отдельное владение профильными metadata и revision |

В текущем slice staged только `setTransactionNote` с injected boundary.
Read-only analytics не изменены. Конструкторное восстановление legacy данных,
normalization/classification при load и scaffold defaults требуют отдельного
контракта bootstrap/migration; здесь доступны только уже canonical fixtures.

## 4. Commit, CAS, отмена и lifecycle

- Worker держит exclusive Container lock весь lifetime. Финансовый core, codec
  и SQLite находятся в одном supervised isolate; второго writer/delivery worker
  или второго reconciliation engine нет.
- RPC queue ограничена 16 запросами; FIFO. Один pending note intent на target.
  Stale `expectedRevision` отвергается до подготовки нового результата.
- Один SQLite commit содержит full snapshot и immutable command. Существующие
  journal/hash/DPAPI/WAL/backup/key contracts не заменены.
- Повтор command ID с теми же target/note возвращает durable результат без нового
  financial effect; другой note под тем же ID отвергается. Intent не переписывается.
- Worker выполняет явный async yield после подготовки. Отмена, обработанная до
  commit, оставляет прежнее состояние и пустую очередь для этого intent.
- После commit отмена/потеря ответа означает reload/recovery, а не rollback.
  Неизвестная storage ошибка после начала commit также трактуется как unknown;
  исключение — доказанный test hook отказа до commit.
- Контроллер проверяет command/user/revision, disposal, generation, presentation
  и cancellation перед публикацией. На unknown outcome включает sticky
  `noteRecoveryRequired`; неподтверждённая заметка не появляется в UI.
- `close()` прекращает приём новых requests и дожидается принятой очереди.
  `close(cancelPending: true)` отменяет pending работу до commit. Уже совершённый
  commit сохраняется независимо от закрытия/уничтожения UI.
- Worker error/exit завершает pending requests с unknown outcome. Auto-restart
  отсутствует. После `Isolate.kill` нужен **полный process restart**: FFI handles
  не считаются надёжно освобождёнными. Kill проверяется только в child process.

Постоянный engine lease/фоновые задачи в этом локальном slice не реализованы.
При расширении на sync тот же owner должен последовательно обслуживать local
mutation и remote apply; независимый второй writer недопустим.

## 5. Сравнение финансовых результатов и проверки

Сравнены настоящий `BudgetController.updateTransaction + LocalQestoRepository`
(synthetic MemoryKeyValueStore) и настоящий controller с native encrypted boundary.
При детерминированных clock/audit IDs полные encoded финансовые результаты равны.
Проверены configured custom category, redirect, merchant rule, valid user tags,
manual override, locks, canonical/legacy note projection, deleted transaction,
точные **486122 RUB / 1500025 USD / 13 RUB**, ID и сохранение всех остальных
корневых разделов. Cash Flow до/после изменения заметки совпал.

Здесь используются actual profile classification и Qesto bridge, а не default
server policy. JSON equality дополнена проверками финансовых значений, categories,
account/goal/debt/investment структуры и Cash Flow, плюс существующими regressions.

Actual Flutter widget test проверяет прежний текст/0 notifications до commit,
работающий UI button во время native ожидания и ровно одну публикацию после него.
Отказы до commit и после commit до ответа оставляют старый UI; последний случай
имеет durable revision=1 и требует reload. Dispose после commit также не публикует
изменение в уничтоженный UI. Проверены stale UI и отсутствие скрытого fallback.

| Проверка | Результат |
|---|---|
| Native process exit после snapshot / до COMMIT | Snapshot и outbox откатились; новый процесс видит revision=0 |
| Native process exit после COMMIT до reply | Новый процесс видит revision=1 и одну pending command |
| Worker death | Fail closed; следующий независимый process открывает прежний Container |
| Same ID / collision / concurrent stale CAS | Один effect, collision/stale отклонены |
| Missing/corrupt synthetic vault | Явный отказ, bytes retained; explicit восстановление тестовым исходным ключом открывает сохранённую revision |
| Второй process writer | Отвергнут exclusive ownership lock |
| Cancel до/после commit | До: revision=0; после: revision=1 с reload-required |
| Shutdown cancel/drain/error | Pending precommit отменён либо принятую команду дренирует owner; shutdown error не вызывает silent reopen |
| Production-looking/unmarked path | Отказ до доступа к store |

Process crash tests не доказывают аппаратное отключение питания. Controlled
pre/post-commit exceptions отделены от native process exit. Унаследованные
storage contracts/process/fault tests запущены дополнительно.

Финальный прогон завершён **12.10.2026 20:52:23 UTC**: **321 passed**, errors=0,
skips=0. [`summary.json`](../../../experiments/windows_integration_boundary/results/summary.json):

| Suite | Passed |
|---|---:|
| Boundary/native tests + server semantics gate | 17 |
| Actual Flutter controller/widget | 7 |
| 1k/10k benchmark correctness | 2 |
| App financial/desktop regressions | 143 |
| Shared Synoball parity | 33 |
| Storage contracts/process/hardening policy | 119 |

App regressions включают desktop shell, classification/UI, transaction editor,
pending notification safety, write guard, trash, Sber financial integrity/import/
savings transfers, actual codec, recovery и shared compatibility. Это выбранная
применимая regression suite, не полный прогон всех app tests.

`dart analyze` полного приложения, нового пакета и отдельного Flutter runner —
без замечаний. Native AOT probe собран и запущен. Установленный Windows release
не заменялся; release bundle приложения в этом slice не собирался. Android,
публичный deployment и пользовательские профили не тестировались.

Baseline capture перед изменениями: 540 app/shared source/test files. После:
543, изменены/добавлены только четыре перечисленных seam-файла, unexpected=0.
[`source_check.json`](../../../experiments/windows_integration_boundary/results/source_check.json)
содержит `passed=false` для **буквального равенства** baseline (изменения намеренные)
и `boundary_scope_passed=true` для согласованной границы. Repository/codec/core
не входят в changed set. Предыдущие dirty изменения пользователя сохранены.

## 6. Benchmarks и responsiveness

Реальный Flutter test **debug VM**, native encrypted SQLite worker, по три
последовательных note mutations для каждого профиля. На каждом trial сравниваются
полные финансовые результаты с прежним контроллером; при этом нормализованы только
генерируемые audit/event IDs и bookkeeping timestamps.

[`flutter-benchmarks.json`](../../../experiments/windows_integration_boundary/results/flutter-benchmarks.json):

| Метрика | 1 000 операций | 10 000 операций |
|---|---:|---:|
| Worker preparation: decode/core/projection/encode/snapshot | 103–121 ms | 1 142–1 714 ms |
| Container commit path | 116–134 ms | 1 010–1 042 ms |
| Whole staged note до UI publication | 272–292 ms | 2 715–3 313 ms |
| Primary-isolate timer gap во время staged note | 8,8–10,2 ms | 25,7–39,1 ms |
| Timer gap прежнего пути | 39–55 ms | 431–462 ms |
| Snapshot JSON | ~1,46 MiB | ~14,40 MiB |
| Peak process RSS | ~192 MiB | ~463 MiB |

Commit metric включает Container API bookkeeping/WAL/vault work, не только
нативный вызов SQL COMMIT. Preparation + commit не покрывают всё wall time:
остаются snapshot read/queue lookup/validation, message copy и UI publication.
Всё это входит в whole staged timing. RSS включает тестовый Flutter runtime,
оба controller results и worker; это не release memory budget.

Старый путь здесь сохраняет в **MemoryKeyValueStore**, новый — в настоящую
зашифрованную SQLite. Их whole-save timings нельзя трактовать как сравнение двух
одинаковых disk backends. Timer gaps показывают именно блокировку первичного
isolate. Использован 8ms timer и отдельная widget interaction проверка; это не
raster-frame p95, реальный 60fps guarantee или долгий нагрузочный тест.

Worker заметно уменьшает зависание UI, но full snapshot остаётся слишком дорогим
для обычной незаметной правки на 10k. Нужен отдельный approved feasibility slice
частичной нормализации: canonical transaction/field changes и command journal в
одной транзакции, projection/materialized snapshot по policy, сохранение codec-v7
export/backup/reconciliation. Нельзя просто пропустить сохранение unrelated полей
или ослабить durable outbox. Полная нормализация здесь не реализована.

## 7. Технические проблемы и ограничения

1. **Подтверждённый server semantics gate.** Qesto note проходит existing
   `canonicalFromQesto`, включая field locks/legacy tags. Server 3a меняет
   `canonical.copyWith(userNote)` с default policy и другой audit purpose.
   На одинаковом synthetic input совпали ID/money/note, но различаются **tags**.
   [`server-semantics-gate.json`](../../../experiments/windows_integration_boundary/results/server-semantics-gate.json)
   фиксирует этот ожидаемый блокер. Для production нужен тот же configured policy
   и существующий bridge на обеих сторонах, а также согласование `userId` и
   canonical `entityId=ent-userId`. Прямое подключение 3a здесь не заявляется.
2. Wire command использует existing `transaction.set_note`, но base entity
   revision=0 допустима только для свежей synthetic epoch и одного pending intent
   на target. Nonzero bootstrap, дальнейшие server revisions, remote cursor/context
   и command compaction требуют следующего интеграционного контракта.
3. Остальные mutators всё ещё меняют memory до save. Injected controller предназначен
   только для notes; смешанные старые/новые financial writes блокируются на save
   boundary и требуют reload. Общая неизменяемость public списков/controller state
   не создана и не обещается — нужен последовательный перенос групп из inventory.
4. RPC supervision ловит owner exit/error; нет автоматического timeout-and-restart
   долгого commit, поскольку его исход нельзя безопасно объявить отменённым.
   Caller сохраняет command ID и после полного restart проверяет durable результат.
5. Full snapshot latency/RSS и response-copy паузы остаются заметными. Release
   frame measurements и долгие shutdown/load stress tests ещё нужны.
6. Hot restart с FFI handles, аппаратные сбои питания, полный UI ↔ backend,
   conflict-resolution UI, authentication и device/key recovery не закрыты.

Во время проверки были исправлены проблемы **test harness**: relative imports
в package URI не выходили к настоящим app-файлам (заменены явным generated mapping),
native ожидание widget test попадало под fake clock (перенесено в `runAsync`),
и лишний import оставлял analyzer info в старом логе. Initial failed JSONL сохранён
отдельно. Последний полный runner завершился успешно; ранние отказы не скрыты.

## 8. Новые файлы, воспроизведение и следующий минимальный этап

Помимо четырёх app-файлов добавлен `experiments/windows_integration_boundary/`:

- `PLAN.md`, `README.md`, `.gitignore`, `pubspec.yaml`, `pubspec.lock`;
- `lib/windows_note_boundary.dart`, `lib/synthetic_fixture.dart`;
- `bin/probe.dart`;
- `test/boundary_test.dart`, `test/server_semantics_gate_test.dart`;
- `flutter_runner/pubspec.yaml`, lock/ignore и controller/widget/benchmark tests;
- `tool/run.ps1`, `configure_app_seam.dart`, `check_sources.dart`,
  `collect_results.dart`, `mutation_inventory.dart`;
- JSONL/analyzer/source/benchmark/inventory/semantics evidence в `results/`.

Runtime/build/package configs игнорируются Git; новых test bearer tokens или
server credentials нет. Container keys остаются только в отдельных synthetic
DPAPI vaults. Runner не запускает Qesto и не открывает PostgreSQL.

```powershell
cd C:\Users\ARM\Documents\Qesto\experiments\windows_integration_boundary
./tool/run.ps1
```

Следующий минимальный этап предлагается отдельно: **synthetic Windows test UI ↔
loopback backend для заметок**. Сначала согласовать и покрыть parity server adapter
с уже созданным app preparation/bridge и configured policy, owner/entity binding
и entity revisions; затем разместить coordinator remote apply/push/pull в том же
writer owner, соединить две synthetic UI sessions и проверить offline/conflict/
restart/publication. Не добавлять реальные данные или автоматически переключать
LocalQestoRepository. Частичную нормализацию оценить отдельным scope до включения
пользователям.

4a заканчивается на проверенной точке подключения и этом отчёте. Следующий этап,
production migration, network sync и установка приложения не выполнялись.
