# D. Implementation Roadmap

Все этапы ниже — будущая работа **после отдельного утверждения**. Этот audit не запускает ни одну миграцию/сервер/загрузку. Приоритет: финансовые инварианты → безопасность → durable recovery → удобство → scaling.

## 1. Предлагаемая последовательность

Файлы `sync/...`, `packages/...`, `services/qesto_sync/...` в таблице — предлагаемые новые места, не уже созданные production modules. Existing references указаны, чтобы scope каждого PR был проверяемым.

| Slice | Scope / файлы | Dependencies | Acceptance и проверки | Риск / rollback gate |
|---|---|---|---|---|
| 0. ADR approval | Эти A–E, owner decisions, данные нагрузки без private upload | Product/security решения E | Утверждены server trust model, native targets, auth/retention/hosting gates | Нет реализации до approval |
| 1. Shared contracts / parity | `lib/synoball/{core,ingestion,reconciliation,adapters}`, proposed `packages/qesto_financial_core`; golden/parity tests | Без backend/DB миграции; согласованный shared package boundary | Core компилируется без Flutter; одинаковые adapters/evidence/locks/trash/exact money results; injectable clock/ID strategy; legacy IDs не изменились | Extract только существующий алгоритм, не новая дедупликация; rollback обычным code revert до новых storage writes |
| 2a. Storage feasibility | Proposed isolated `lib/data/persistence/sqlite_*`; Drift vs sqlite3, encryption proof; test-only repositories | Approved dependency и native packaging | Windows/Android encrypted payload/WAL/backup inspection, crash stages, transaction rollback, restore keys; large profile benchmark | Не трогать real profile. Если encryption/parity не доказаны — остановиться, не переключать writer |
| 2b. Transaction container | `LocalQestoRepository`, `UserFinancialDataCodec`, proposed metadata/outbox tables, migration adapter | 2a | Encrypted snapshot + outbox/meta atomic; lossless v7 decode/encode; no external network; staged migration marker; foreign key check | Original JSON/key access сохранены; switch flag до cutover. После edits нельзя откатиться к старому snapshot с потерей новых writes |
| 3. Local command UoW | `BudgetController`, classification part, app shell save callback, source import callbacks; proposed `sync/local_command_store` | 1, 2b | Все live mutation paths staged → atomic snapshot+command → notify. Failure не меняет accepted UI. Native ACK только после commit. No-op refresh не outbox | Малые группы команд в отдельных PR; unknown mutation запрещает enable sync, а не silently bypass queue |
| 4. Backend + native auth | Proposed `services/qesto_sync`, shared core, Postgres schemas; client auth/vault/env config | Owner OIDC/trust/residency approval, shared core | TLS/auth/device enrollment, nonowner RLS role, cross-tenant FK, allowlist, quotas, token rotation/revoke, synthetic tenants; финансовый upload выключен | Staging only; own bank CEF не изменять. Auth/security gate блокирует real-user traffic |
| 5. Push/receipts/cursor | Server workspace gate/log/receipt + proposed `lib/sync/{coordinator,transport,apply}` | 3, 4 | Lost ACK exactly-once effect; gate всеми writers; contiguous committed cursor; atomic pages; single-flight leases; cancel safe | Kill-process/network barrier tests обязательны. Feature flag паузит transport и сохраняет очередь |
| 6. Conflicts + lifecycle | Shared command executors, revision sidecar, aliases, encrypted conflict UI, delete/restore | 5 | Ten required conflict classes, own transfers, manual locks, tombstone replay, dependent offline tail, resnapshot | Неразрешённые случаи review. Не fake success и не LWW financial tuple |
| 7a. Enrollment + existing-profile union | Proposed bootstrap manifest/preview, account/source bindings, global ID sidecar, schema compatibility | 6 + reviewed source identity spike | Empty device bootstrap; two nonempty profiles preview/consent; re-import/reinstall idempotent; source IDs сохраняются; no doubling projections | Без approved preview commit запрещён; backup+restore rehearsal; no destructive replace |
| 7b. Financial module integration | Existing transaction/category/budget/goal/debt/investment commands через shared domain adapters | 7a, shared capital/planning invariants | Exact values/locks/current balances preserved; no duplicate contribution/payment; all relation refs valid; no double application | По одному aggregate slice. Unsupported command blocked/requires attention, не сетевой generic JSON update |
| 8. Two-device acceptance | Windows release + Android release, separate synthetic QA workspace; afterward opt-in real profile | 7b, user/device availability | Все 24 сценария ниже, restart/lifecycle/background, notifications+statement same purchase, full desktop regression | QA profile isolated. Real data только после отдельного согласия, validated backup и dry-run preview |
| 9. Staging / load / security | Reproducible containers, migrations, monitoring, fault/security harness, backups | 8 | Multi-process DB lock tests, hot-workspace load, quotas, RLS/BOLA tests, log scanning, backup/PITR drill; min version rollout | Без доказанных SLO/security gates — no public enable. Restore incident changes epoch, not silent rollback |
| 10. Production rollout | Versioned compatible clients/server; opt-in cohort → staged expansion | Legal/privacy/security signoff + operations owner | RPO/RTO/alerts/runbooks/support, ownership consent, rollout/rollback rehearsal, verified metrics | Stop rollout/pause sync без удаления локальных данных. DB downgrade только verified migration, accepted records не потерять |

Это не один огромный PR. Каждый row при необходимости делится ещё мельче; общий audit scope не даёт разрешение менять всё сразу.

## 2. Какой первый PR сделать после согласования

**`Shared Synoball parity boundary / no network`**:

- Утвердить typed command envelopes/ID+revision sidecar contract в tests, пока не подключать к production writer.
- Выделить минимальный pure Dart boundary существующего core для client/server compilation; не переносить Flutter controller целиком.
- Сохранить backward-compatible public imports/adapters и все current schema/ID defaults, сравнить exact canonical results на текущих fixtures.
- Добавить contract tests для money/type/status/manual locks/trash/source identity и clock/ID determinism. Независимые source observations остаются source observations, не aggregate diff.
- Не добавлять auth UI, server deployment, SQLite migration или raw upload в этот PR. Следующий отдельный PR — bounded native storage/encryption spike.

Такой первый шаг выявляет реальную возможность одного финансового ядра до затрат на network. Если извлечение требует массового refactor — уменьшить boundary до existing algorithms и остановиться на parity contract, а не обходить core серверной новой реализацией.

## 3. Правила безопасных миграций и rollout

1. `storage_version`, `wire_version`, `domain_version` независимы; compatibility matrix заранее фиксируется.
2. Server expand migration → compatible client release → feature opt-in → поздний contract cleanup. Никакой принудительной old-client записи в новую схему.
3. Migration source snapshot и keys/recovery procedure сохраняются до подтверждённого восстановления; verify digest первичных данных до и после.
4. Migration временного файла/БД имеет manifest/marker и idempotent resume. Повторный запуск не создаёт новые canonical IDs или duplicate goals/accounts.
5. Сначала synthetic/non-sensitive profiles и copied fixtures. Реальный профиль не превращать в экспериментальную нагрузку; cloud upload требует отдельного согласия.
6. После новых local/remote accepted writes rollback не означает «скопировать старую backup поверх». Нужен обратимый lossless export с текущей outbox/identity либо совместимый forward fix.
7. Feature flag отключает network и возвращает offline-only UI, но metadata/queued edits сохраняет. Запретить запуск old app, который не понимает активный storage version.
8. Server clear/reset при публичной работе — не обычный rollback. PITR/epoch/reconciliation и incident report; нельзя скрыть потерю acknowledged writes.

## 4. Обязательная test matrix: 24 сценария

`Unit` — pure command/codec tests; `Integration` — real SQLite/Postgres/API/auth tests; `E2E` — Windows+Android QA accounts. Эти тесты **запланированы**, не выполнены текущим audit.

| № | Сценарий | Метод / fault injection | Проверяемый результат |
|---|---|---|---|
| 1 | Desktop create → Mobile | E2E manual operation 123.45 RUB, pull + restart | Один canonical ID, exact cents/type/date/category; totals одинаковы |
| 2 | Mobile create → Desktop | Обратный E2E, income/refund/expense | Direction/status и minor precision не теряются |
| 3 | Оба devices offline, разные records | Network isolate, edits, reconnect в обеих очередностях | Все intents приняты, no lost updates |
| 4 | Оба offline, одна record | Unit + integration disjoint/same-field/financial tuple | Disjoint safe merge; опасное conflict сохранилось с обеими версиями |
| 5 | Сеть исчезла до отправки | Offline после local commit | Snapshot+outbox durable; после restart доставка той же command |
| 6 | Потеря после server commit до ACK | Proxy/drop response after commit barrier | Retry возвращает receipt, money effect один |
| 7 | Многократный replay | Sequential/concurrent duplicate requests; changed body same ID | Один результат, altered body rejected; compacted old receipt не создаёт заново |
| 8 | App закрыт во время sync | Kill before/after local commit, page apply, receipt commit | Active checkpoint только complete state; pending queue восстановлена |
| 9 | Server restart | Kill before/after DB commit, same requests | State/receipt/log/head либо все есть, либо все отсутствуют |
| 10 | Device отсутствовал долго | Trim replication log, retain tombstones, reconnect | Full staged snapshot + pending rebase, no resurrection |
| 11 | Delete на A, edit на B | Offline stale edit после deleted bundle | Trash остаётся, proposal conflict не исчез; restore explicit |
| 12 | Два sources одной покупки | Notification phone + statement desktop с подтверждёнными binding | Existing core match: one fact + both evidence; two true same-amount purchases остаются разными |
| 13 | Manual correction imported operation | Lock amount/category/note → repeated bank update | Manual values/locks preserved; source evidence добавлено без overwrite |
| 14 | Истёк auth | Expired access, refresh success/failure/reuse/lost response | Single refresh; relogin pause безопасен, outbox retained |
| 15 | Concurrent sync cycles | UI button + resume + background worker, leases expire | Single logical progress; duplicate delivery still safe; no queue corruption |
| 16 | Tenant A пытается B | Authenticated fuzz refs/cursors/receipts/snapshot IDs/aliases and property assignments | Ни read, ни write чужих данных; RLS runtime role реально enforced |
| 17 | Разные schema/API/core versions | Old client/new server и обратное, unknown enum | Explicit gate/compatible path, no silent loss of cents/tombstones |
| 18 | Новый device с empty DB | Enrollment + multi-page snapshot + change during bootstrap | State на H и subsequent changes >H, complete refs |
| 19 | Новый device с existing data | Two lineages: manual ID collision + same bank evidence + different plans | Preview consent; preserve both valid intents; repeat import idempotent |
| 20 | Logout с pending | Logout → different login → original login | Команды не уходят другому tenant; оригинальная queue возобновляется без loss |
| 21 | Revoke offline device | Revoke server session while client offline, reconnect | Writes/reads denied; pending proposals remain local, accepted pre-revoke unchanged |
| 22 | Cursor expired/history compacted | 410 и epoch reset | Staged resnapshot, retained pending edits, tombstone barriers и aliases |
| 23 | Большая history paginated | Concurrent writes + page bounds + oversize unit chunking | Ordered bundles ≤pinned H; no incomplete logical unit/cursor advance |
| 24 | Damaged/incomplete checkpoint | Corrupt staging/page hash/cursor metadata, crash cutover | Last valid active generation retained; fail closed/recovery, no empty autosave |

## 5. Дополнительные тесты для опасных границ

- **Commit order counter:** два независимых API процесса. T1 держит workspace lock после назначения seq; T2 пытается писать, читатель pull. T2 не commit раньше; rollback T1 не создаёт невидимый поздний seq. Повторить с admin/bootstrap writers. Этот тест обязателен, обычный sequential unit test доказательством не является.
- **Consistent snapshot:** concurrent updates/delete/restore во время materialization; все pages соответствуют одному H, а changes >H восстанавливают complete final state.
- **Idempotency retention:** после compaction verbose receipt + log старый accepted change снова отправлен — не выполняется повторно.
- **Clock skew:** phone ±30 дней/неверный timezone; sorting cursor/revisions не меняется, business date сохраняется с precision.
- **Dependency base:** offline X1 category → X2 note; другой device меняет note до принятия X1. Receipt X1 не повышает base чужой note; X2 получает conflict. Повторить для amount → amount и чужой amount между commands.
- **Source namespaces:** два разных bank accounts с одинаковыми last4 и суммой; разные install connections; ambiguous binding не merge. Не регенерировать historical provider hash после ID mapping.
- **Minimal proof parity:** full local notification payload и allowlisted sync proof дают одинаковую identity/review/tombstone suppression; package/key sensitivity оценена.
- **Source batch staging:** две observations, претендующие на target, в разных network chunks; full batch conflict одинаков с unsplit import. Printed document controls нельзя обойти pagination.
- **Planning intents:** два goal contributions, retry одного, conflict target amount; investment balance+metadata atomic; debt payment не превращён transport в несуществующее списание.
- **Own transfer:** 15 000 RUB между primary/savings, один или оба real source legs по existing semantics. Expenses/income не растут, aggregate current liquidity не уменьшается от replay.
- **Native ACK window:** crash после local commit+outbox, до Android inbox ACK. Redelivery сохраняет одну canonical transaction и одну logical financial effect.
- **Storage encryption:** искать sensitive test strings в DB/WAL/backup/staging/outbox/conflicts/logs; проверять malformed/future schema fail closed и восстановление device key.
- **Limits:** bounded request, command count, source payload, dependency depth, conflict growth, bootstrap pages; malicious slow/oversized client не держит lock бесконечно.
- **Cancellation:** client отменяет in-flight request после server commit; later retry получает accepted receipt, пользователь не видит повторно созданную операцию.

## 6. Как проверять инварианты, а не только количество строк

| Инвариант | Метод доказательства |
|---|---|
| Нет необъяснимой потери acknowledged data | Test oracle по accepted command receipts + canonical IDs/aliases, verify every effect либо current state, либо explicit later delete/conflict; restart/PITR drills отдельно |
| Нет duplicate economic event от delivery | Repeat/permutation tests; source evidence count и canonical facts отдельно; uniqueness change ID сама по себе недостаточна для разных sources |
| Pending intents не исчезают | Durable outbox audit: every command accepted/conflict/rejected/queued; snapshot+queue tx crash tests; no silent eviction |
| Cross-tenant запрет | Two real test subjects, API object/property tests + direct runtime DB role RLS queries; foreign refs/aliases/snapshots scoped |
| Деньги точны | Compare sorted canonical primary facts `(ID, minor, currency, direction, status, date precision, account, overrides, semantic tags)`; current balances отдельно; totals по existing services |
| Все devices converge | После quiescence и успешных retries compare server shadow hashes/aliases/revisions; local projections равны при same core/config, conflicts явно равны и доступны для решения |
| Relations согласованы | Referential integrity для transaction/evidence/receipt/category/period/goal/debt/investment; alias application не оставляет dangling refs |
| Recovery без reinstall | Каждый fault test завершается resume/pull/rebase на той же installation; no delete-all workaround |

Derived volatile fields (`referenceDate`, transient diagnostics, generated render state) не включать в equality oracle как primary truth. Но финансовые locks, deleted evidence и existing whole-vs-minor semantics исключать нельзя.

## 7. Desktop/mobile regression и реальная проверка

Перед enable: полный Flutter suite/analyze, Windows release build, Android release build; текущий desktop banking, cancellation, statement import, category edits/trash, capital graphs и AI export не меняют поведение. Повторно проверить Android notification type/direction/cents safety; не использовать mobile editor как доказательство sound sync.

На двух физических devices: synthetic QA profile с mixed income/expense/refund/internal transfer, account balances, goal/debt/investment и pending source. Проверить foreground/resume/offline/logout/revoke/restart. Только после gates и пользовательского согласия — copied real-profile dry-run preview, затем opt-in sync и reconcile report. Не требуется переносить банковские credentials на phone.

Текущий audit выполнил **63 существующих локальных теста**, не эту matrix. Не готовая функция, не production readiness и не новая APK.

## 8. Операционная готовность

Нужны owner для on-call/updates, RPO/RTO, encrypted backup/PITR restore, secret/key rotation, expired cursor runbook, conflict support, protocol min-version policy, tenant erase procedure, alert thresholds. Load target установить по измеренным history sizes/devices/active-user rate. Нельзя объявить поддержку тысяч пользователей на основании выбранных названий технологий.

Ноутбук через tunnel — тестовый deployment того же API. Его выключение должно приводить к безопасной local queue, а не потере данных или требованию сбросить приложение. Перенос на staging/prod меняет config/deployment, не financial model и основные wire guarantees.
