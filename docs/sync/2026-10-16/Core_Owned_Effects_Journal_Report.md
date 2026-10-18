# QESTO Sync — Stage 4e: Core-Owned Effects Journal & Domain Contract

Завершено **16 октября 2026**, Windows x64, Dart 3.12.2. Только синтетические данные.
Основа: протокол разработки v0.1, Sync A–E, Stage 4c/4d,
`Domain_Effects_Contract_and_Blockers.md`, `Versioned_Incremental_Domain_Proposal.md`.

## 1. Решение и граница GO

**GO для следующего отдельно согласованного экспериментального этапа.**
Для существующей команды `transaction.set_note` ядро формирует полный журнал
своих persisted collections при выполнении команды, без последующего полного
сравнения истории. Результат проверен полным независимым oracle, включая
изменения соседних операций, constructor policy normalization и audit-only.

**NO-GO для немедленного подключения к production или частичному UI/storage apply.**
Core journal не является полным результатом приложения и не доказывает SQLite
COMMIT. Полная сериализация, receipt verification и действующий Sync Coordinator
не заменены. Новых финансовых команд, протокола, миграций или сервера нет.

Доказательство ограничено текущей версией моделей и проверенными сценариями.
Это не универсальное доказательство для произвольных будущих mutation paths.
Дополнительные вызовы import/delete/restore/policy в тестах — probes существующего
ядра, а не расширение набора поддерживаемых сетевых команд.

## 2. Карта мутаций

Полная карта: [Mutation_Map.md](../../../experiments/core_effects_journal/Mutation_Map.md).

| Путь | Что реально меняется |
|---|---|
| Constructor / восстановление | configured policy по всем canonical, включая trash; recurring streams и canonical flags |
| Правка заметки через существующий app bridge | canonical поля/locks/tags/enrichment, timestamps, audit/events, потенциально соседние recurring записи |
| `setCategoryPolicy` | category/redirect/rule/tag/confidence/subcategory и derived recurrence; не только target |
| Import / repeated observation | accounts/connections/consents, raw/records/candidates/batch, canonical, evidence, source identities, audit/events |
| Pending / confirmation | candidate state, reconciliation/конфликт, canonical/evidence/recurrence |
| Delete / reimport / restore | tombstone, suppression повторного импорта, явное восстановление, account snapshot/виртуальный счёт при отсутствии оригинала |
| Account linking / merging | mapping/alias в существующих events, accounts и canonical account IDs; отдельной aliases collection нет |

Перехвачены 15 существующих списков: entities, institutions, connections, consents,
accounts, rawPayloads, ingestionRecords, candidates, transactions, evidence,
receipts, importBatches, recurringStreams, events, auditEntries. Runtime indexes
не являются отдельными persisted financial facts; их контейнеры по-прежнему
копируются в fork. Account linking/merging изучены по коду; отдельная новая sync
команда или исчерпывающий новый E2E-тест каждого такого пути не заявляются.

## 3. Реализованный PoC и совместимость

В shared core добавлены opt-in `CoreJournalPreparation` и tracked list boundaries.
Списки оборачиваются **до** constructor policy normalization. Каждый setter,
append/removal регистрирует exact before/after конкретной записи. Повторные
записи в один slot coalesce; после структурного удаления позиции переоцениваются.
Полного before/after обхода профиля при формировании журнала нет.

Default constructor и прежний `forkForCommand` продолжают использовать обычные
списки. Existing financial methods, reconciliation, deduplication, trust policy,
adapters, models, production ID factory и расчёты не переписаны. Для derived
recurring list только в journal path применяется эквивалентная замена содержимого
вместо шума clear/addAll; полный результат проверяется oracle.

Приложение в эксперименте использует настоящие `applyQestoTransactionEdit`,
`QestoReadModelService`, `projectSberTransactions` и codec-v7. Второй финансовый
executor не создан. App seam ограничен синтетическими fixtures и одной note-командой.
Новая runtime dependency отсутствует: добавлен только SDK `dart:collection`.

Обычные shared/core goldens и app tests остались независимыми от нового режима.
Нет новых call sites журнала в приложении или действующих coordinator-пакетах.

## 4. Контракт журнала

Полная спецификация: [Journal_Contract.md](../../../experiments/core_effects_journal/Journal_Contract.md).

- Версия `qesto.experimental-core-effects.v1`.
- Immutable binding: command ID, workspace, lineage, target/kind, base revision,
  generation, domain version и policy fingerprint.
- Ordered writes: collection, index, ID, created/updated/deleted, exact before/after,
  changed fields. Сохраняются порядок и даже существующие повторные IDs.
- Read-only наборы changed canonical IDs и collections выводятся из writes.
- Locks/overrides/provenance/recurring/tombstones передаются существующими полями,
  а не новым финансовым толкованием. Tombstone — update, не удаление SQL-строки.
- Final configured policy и признак её изменения во время исполнения.
- Conservative read-model/recurring/app-projection invalidations, в том числе при
  изменении политики на пустом наборе данных.
- `coreCollectionsComplete = true` означает **только 15 core collections текущей
  версии**. App roots, UI, storage, pending/shadow/conflicts этим флагом не покрыты.

Неизвестная версия, непроверенный top-level model subclass, custom policy subclass,
неподдерживаемый JSON/list operation или async callback приводят к отказу.
Не создаётся успешный пустой профиль или якобы полный пустой результат.
Внешний caller должен сохранить прежний полный путь либо показать ошибку.

Binding — локальная метаинформация, не authority/подпись/receipt. Actual policy
fingerprint проверяет app seam; generic core callback считается trusted local code.
Изменение политики запрещает reuse без повторного admission. Историческая
command-ID идемпотентность и выбор победителя двух команд — задача будущего owner/container.

## 5. STOP GATE: полнота и финансовая семантика

Новый независимый verifier replay-ит journal поверх полного исходного core JSON
с expected-before проверками и сравнивает **все поля всех collections** с обычным
Synoball. Для note-команд дополнительно сравниваются весь codec-v7, реальные legacy
projections и прежний `DomainEffectsV1` full oracle. Сравнение не ограничено суммой
или количеством записей; map/list values и числовые типы проверяются.

| Сценарий | Подтверждённый результат |
|---|---|
| Заметка / повтор / очистка / Unicode | Exact core + full codec + старый oracle совпадают |
| Повтор той же заметки | Проверена последовательность до audit-only; canonical без изменений, audit/events сохранены |
| Stale policy, 60 операций | **21 из 60** canonical IDs изменяются; journal совпадает с oracle по IDs и всем полям |
| User category, note, amount locks | Existing repeated import сохраняет ручные изменения; exact minor units и EUR проверены |
| Recurring/enrichment и смена policy | Соседние canonical/stream/category effects не потеряны |
| Повторный импорт и похожая отдельная покупка | Existing reconciliation/evidence совпадают, отдельная покупка остаётся отдельной |
| Pending notification / receipt | Существующие confirmation, provenance и receipt collections совпадают |
| Delete/reimport/restore | Tombstone подавляет повторный импорт; явное restore и missing-account fallback совпадают |
| Ошибка до результата / повтор | Base не меняется; повтор с теми же ID/clock из исходного состояния даёт exact результат |
| Restart | Полное состояние сериализуется/восстанавливается и выполняется заново; неизвестная версия отвергается |
| Same-target кандидаты | Подготовки изолированы; expected-before не позволяет применить второй поверх результата первого |
| Stale/foreign binding | Revision/generation/policy/workspace/lineage и немедленный reuse command ID отвергаются |
| Негативный контроль | Пропущенная запись, unregistered field и изменение nested JSON `1` → `1.0` обнаруживаются |

Особенность existing bridge: второй одинаковый note edit может ещё менять порядок
служебных tags; третий становится действительно audit-only. Это не «исправлялось»
ради теста: сохранено фактическое старое поведение и exact parity.

Артефакт stale-policy: `results/stale-policy-gate.json`. Все 9 timing combinations
(3 режима × 3 размера), warmup и trials, а также 3 allocation-прогона проверяют
полный codec parity. Oracle остаётся дорогим проверочным инструментом вне capture.

## 6. Mutable ownership и найденные ошибки

У прежних моделей изменяемы tags, consent scopes, connection capabilities,
receipt items/userCorrections, batch warnings, stream transactionIds, произвольный
nested event payload и policy rules/redirects/validTagIds. Обычный fork разделяет
значения моделей, поэтому «копия списка» сама по себе не обеспечивает isolation.

В новом opt-in admission контейнеры отделяются и замораживаются один раз. Между
prepared forks разделяются immutable records; новые значения замораживаются на
записи. Journal before/after также detached/deep read-only. Исходный публичный API
моделей глобально immutable не объявляется и не меняется.

Проверено отсутствие изменения base через исходные tags/nested events, запрет
редактирования prepared state/journal, сохранение старого candidate после следующего
fork и запрет поздних записей из сохранённого callback. Scope закрывается и при успехе,
и при исключении. Это не sandbox для враждебного стороннего callback.

При review исправлены:

1. Возможность позднего `restoreTransaction` испортить private ID index до отказа
   tracked append: guard поставлен **перед** записью индекса, есть regression test.
2. Отсутствующая invalidation при policy-only изменении пустого core.
3. Риск молчаливого стирания custom policy/model subclass семантики при ownership copy:
   experimental boundary теперь явно отказывает.
4. Слишком мягкое числовое сравнение `1 == 1.0` в JSON oracle; неподдерживаемые JSON значения
   и nonfinite event values не превращаются в успешный пустой результат.
5. В profiler harness исправлено недопустимое VM RPC `reset:false`; false параметры
   теперь не отправляются. Это ошибка harness, не финансового ядра.

40 намеренно прерванных подготовок (1k fixture): после forced GC **0 из 40 core**
удерживаются weak references; base unchanged. Heap вырос с 15,75 до 24,77 MiB из-за
совокупной runtime/JIT/test работы. Это не доказательство нулевого роста RSS,
реального OOM, power loss или storage crash recovery.

## 7. Методика и производительность

Артефакты: `experiments/core_effects_journal/results/summary.json` и исходные JSON.
Каждый mode/size — отдельный процесс Windows Dart JIT: warmup + 3 trials, ниже медианы.
Final timings запущены отдельно от regression suite. Один и тот же synthetic fixture,
existing note bridge и полные app projections. Initial admission измерено отдельно.
Independent full oracle выполняется после замеров. Это **не** Flutter UI latency,
HTTP, sender/receiver или SQLite commit benchmark.

| Метрика, миллисекунды | 1k | 10k | 50k |
|---|---:|---:|---:|
| Domain без capture: prepared fork + existing core | 6,98 | 81,51 | 444,84 |
| Domain + journal, включая seal | 7,01 | 71,40 | 463,53 |
| Только запись effects внутри recorder | 0,077 | 0,080 | 0,090 |
| App projections после journal | 17,77 | 194,50 | 1165,71 |
| Старый full-state diff capture | 199,21 | 2424,60 | 13000,74 |
| Encode journal result | 0,173 | 0,144 | 0,131 |
| Encode full-diff result | 14,45 | 186,59 | 898,16 |
| Полная prototype preparation с journal, без oracle | 24,76 | 264,76 | 1629,37 |
| Полная preparation + старый full-diff, без oracle | 238,37 | 2909,28 | 15681,51 |
| Однократный journal admission + initial projection | 63,60 | 453,17 | 2606,32 |

Full preparation — медиана суммы фаз каждого trial, а не сумма медиан. Recorder
counter не включает ownership-copy, fork/index copies, финальный seal/encoding и
core scans. Нельзя выдавать 0,080 ms за стоимость всей команды. Разница 71 vs 82 ms
не доказывает ускорение финансового алгоритма: это вариативность JIT/GC и процессов.
На 50k journal domain немного дороже baseline; O(N) core работа остаётся.

По этим standalone фазам prototype preparation дешевле full-diff примерно в
9,6 / 11,0 / 9,6 раза. **Выходы различаются по границе:** старый diff содержит app
roots, новый — core effects плюс прежние полные projections. Это не готовая замена
полного эффекта приложения и не заявление об ускорении действующей sync в 11 раз.

Во всех обычных timed edits изменена 1 canonical operation. Размер journal result
около **3 813 bytes**; full-diff payload (summary + rootValues + coreValues) —
2 341 387 / 23 389 387 / 117 056 098 bytes. Это не wire bytes и не одинаковые scopes.
Stale-policy fixture отдельно доказывает, что 21 изменённая запись не сокращается до 1.

### CPU

Медиана process CPU для journal domain: 0 / 62,5 / 453,1 ms; старый full-diff capture:
250 / 3250 / 18078,1 ms. На маленьких фазах Windows process CPU counter имеет грубую
дискретность (около 15,6 ms); ноль **не** означает отсутствие CPU работы. CPU может
превышать wall time из-за runtime потоков. Полные исходные значения сохранены.

### Heap/RSS и allocations

Отдельные 10k allocation processes: GC/reset до workload, sample после domain + full
app projection + effect encoding, **до первого oracle**. После workload GC нет.

| Режим | VM heap usage, MiB | Process peak до oracle, MiB |
|---|---:|---:|
| Domain без capture | 40,79 | 307,65 |
| Journal | 69,69 | 304,38 |
| Full diff | 320,10 | 543,39 |

Journal имеет собственную память/ownership overhead; снижение peak относительно
baseline без capture на 3 MiB — шум, а не обещанная оптимизация. Full diff существенно
дороже. Top allocation classes в journal: lists/strings/closures; в full diff
преобладают one-/two-byte strings и lists. Подробные VM class samples сохранены.

Timing-process peak после trial 0 включает предыдущие oracle allocations: для 50k
journal около 1,01 GiB, full diff около 1,77 GiB. Это **не** peak hotpath journal.
Отдельный allocation profile выполнен на 10k, не на всех размерах. CIM hardware
inventory был недоступен в sandbox; CPU model/physical RAM не выдумываются.

## 8. Разделение ответственности

| Слой | В Stage 4e |
|---|---|
| Synoball | Core-owned persisted effects + conservative invalidations |
| App bridge / configured policy | Существующие преобразования edit intent; policy supplied/validated, не новый executor |
| Legacy/Sber/read/UI projections | Existing full calculation; dependency graph и incremental contract ещё не реализованы |
| codec-v7 unrelated roots | Полное сравнение подтверждает сохранение; не объявлены частью core journal |
| Durable container | Не менялся; нужен атомарный commit, command/outbox и verified receipt |
| Owner/controller/UI | Никакой speculative публикации/partial patch; действующий путь сохранён |

Полный app effect может требовать projection contract даже при полном core journal.
При неизвестных зависимостях должен оставаться full fallback, а не partial UI update.

## 9. Durable publication: только проект

[Durable_Publication_Proposal.md](../../../experiments/core_effects_journal/Durable_Publication_Proposal.md)
описывает typed boundary:

`Prepare → Effects → Atomic DB Commit → Durable Receipt → Promote Owner → Publish UI`.

Будущий receipt связывает workspace/lineage, command ID, base/new revision,
domain/policy version, digest **core + app effects**, storage generation и owner
generation. Выдаётся только container после реального COMMIT. Не RAM bool и не
публично сконструированный DTO. До COMMIT candidate можно отбросить; после неизвестного
исхода необходимо resolve command ID/reload, не притворный rollback.

Реализации receipt/commit/promotion здесь **нет**. `prepareNext` в тестах — последовательность
кандидатов, не доказательство сохранения. Конкурирующие команды не выбираются журналом;
единственный writer + storage OCC должны отклонить stale base/generation. Смена policy,
remote apply и restart требуют invalidation/revalidation owner. Sync v1 не изменён.

## 10. Тесты и результаты до/после

| Проверка | Результат |
|---|---|
| Shared standalone до изменений | 34 passed |
| Shared standalone после | 34 passed, goldens не обновлялись |
| Новые parity/lifecycle/negative tests | 15 passed |
| Stage 4d owner/bounded executor/digest regressions | 8 passed |
| Выбранные настоящие Flutter app regressions | 112 passed, 1 штатно skipped |
| Dart analyze: shared / новый experiment / Stage 4d | Везде No issues found |
| 1k/10k/50k benchmark parity | Все 9 комбинаций + 3 allocation processes passed |
| Abort retention probe | 40 aborts, base unchanged, 0 retained cores после GC |
| Source/golden baseline | 564 файла, 2 ожидаемых изменения, missing/unexpected = 0 |
| git diff --check | Exit 0; только существующие LF/CRLF warnings |

Итого после изменений **169 успешных тестов**, плюс 1 skipped. Skip:
`recurring_pipeline_test.dart: local snapshot: unchanged facts, codecs and diagnostic counts`
— `Private local fixture not supplied`. Реальные профили не подключались ради его прохождения.

App selection включает Synoball core/safety/compatibility, classification,
financial_write_safety, trash, codec/recovery, recurring и desktop_shell. Это **не**
весь многотысячный app suite. Полный Windows release build, физический UI, Android,
настоящие SQLite faults и live bank не запускались: в этой задаче новый путь не интегрирован.

При разработке были исправленные compile/test ошибки harness (поля моделей, тестовый
copyWith ID, audit-only expectation, VM reset argument). Cache permissions мешали
первому Flutter запуску; повтор с доступом к SDK cache прошёл. Исторические exploratory
логи не считаются финальными результатами. Authoritative: `*-after.jsonl`,
`app-regression.jsonl`, `4d-regression.jsonl`, `summary.json`, analyzer logs.

## 11. Изменённые файлы, безопасность и риски

Из существующих файлов в этом этапе изменены только:

1. `packages/qesto_synoball_core/lib/core/synoball_core.dart` — opt-in list hooks,
   prepared fork wiring, optional guards, derived list replacement.
2. `packages/qesto_synoball_core/test/runtime_contract_test.dart` — в allowlist
   pure SDK imports добавлен `dart:collection`; остальные ожидания/goldens сохранены.

Новые shared файлы:

- `packages/qesto_synoball_core/lib/core/effects_journal.dart`
- `packages/qesto_synoball_core/lib/core/owned_records.dart`

Новые experimental файлы под `experiments/core_effects_journal/`:

- `.gitignore`, `pubspec.yaml`, `pubspec.lock`, `PLAN.md`, `README.md`;
- `Mutation_Map.md`, `Journal_Contract.md`, `Durable_Publication_Proposal.md`;
- `lib/app_probe.dart`, `lib/oracle.dart`, `lib/vm_probe.dart`;
- `test/journal_test.dart`, `test/lifecycle_test.dart`, `test/boundary_test.dart`;
- `bin/benchmark.dart`, `bin/retention_probe.dart`;
- `tool/configure_app_seam.dart`, `tool/capture_baseline.ps1`, `tool/run_checks.ps1`,
  `tool/benchmark.ps1`, `tool/verify_sources.ps1`, `tool/summarize_results.dart`,
  `tool/write_manifest.ps1`;
- машиночитаемые `results/*`, перечисленные в `results/artifact-manifest.json`.

Этот отчёт — `docs/sync/2026-10-16/Core_Owned_Effects_Journal_Report.md`.
Ранее существовавшие незакоммиченные изменения сохранены. Сверка исходников не является
хешированием реального профиля: пользовательское хранилище вообще не читалось и не менялось.
Никакой установки приложения, data migration, production storage switch, bank navigation,
Android, публичного сервера, cloud/OIDC или передачи финансовых данных не выполнялось.
VM profiler использовал только временный локальный loopback, процессы завершились.

Остающиеся риски/ограничения:

- Completeness зависит от текущих model fields/serializers; нужен обязательный oracle
  gate при добавлении коллекций/вложенных mutable значений/мутаций.
- Исходные обычные модели и старый fork не стали глубоко immutable глобально.
- Admission и list/index fork остаются O(N); recurrence/policy по-прежнему могут
  сканировать историю. Journal overhead пропорционален attempted writes/размеру
  записей, не гарантированно только числу конечных изменений.
- Требуется app projection contract; пока нельзя заменить полный durable/UI result.
- Local binding не доказывает актуальность реальной DB revision. Нет нового crash,
  lost-ACK, stale receipt или commit fault доказательства — это gate следующего этапа.
- Benchmark JIT/GC шумный, 3 trials; это не production SLA и не AOT/UI latency.
- Полное покрытие всех 51+ финансовых путей намеренно не заявляется.

## 12. Минимальный Stage 4f — только после согласования

1. Сохранить одну note-команду и synthetic Windows; сформулировать полный typed
   `PreparedFinancialCommit` с отдельными core/app effects и dependency coverage.
2. Реализовать receipt-bound atomic commit в экспериментальном container, включая
   command/outbox, revisions и storage generation; прежний full verify оставить oracle.
3. Проверить crash до/после COMMIT, unknown outcome/lost ACK, повтор command ID,
   два same-target candidate, foreign/stale receipt, remote/policy invalidation/restart.
4. Только после этих gates разрешить owner promotion и один ограниченный UI patch;
   все неизвестные projection dependencies должны использовать полный existing result.
5. Повторить full codec/core/legacy parity, encrypted-storage security/recovery и
   реальные synthetic Windows UI measurements. Production решение отдельно.

**Stage 4e завершён. Stage 4f, миграция и подключение к действующей синхронизации
автоматически не начаты.**
