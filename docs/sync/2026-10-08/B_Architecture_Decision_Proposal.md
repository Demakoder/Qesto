# B. Architecture Decision Proposal

Статус: draft для согласования. Ни одна описанная зависимость или миграция не внедрена.

## 1. Альтернативы

Оценки относительные, не коммерческие сметы. Без профиля нагрузки и договоров hosting/auth нельзя достоверно назвать стоимость в рублях.

| Критерий | A. Свой offline-first Sync API | B. PowerSync + свой write backend | C. Central backend + cache/queue |
|---|---|---|---|
| Client | SQLite + outbox, текущие модели через adapters | Flutter SDK + SQLite, upload connector | Cache/read API + optimistic queue |
| Офлайн | Полноценные финансовые команды | Хорошая основа local-first; domain upload всё равно наш | Ограничен тем, что доступно в cache; расширение до полного офлайн приближает к A |
| Synoball | Shared pure Dart core на обеих сторонах | Shared core в write backend; SDK не заменяет financial reconciliation | Shared server core; нельзя оставить вторую локальную логику |
| Конфликты | Явные OCC/field groups/domain commands | Нужен свой контракт конфликтов и команд поверх row upload | Обычно server request OCC; offline conflict replay всё равно проектировать |
| Миграция текущего JSON | Можно сначала transaction container без переписывания моделей | SQL/schema/SDK integration и адаптация command semantics | Cache переписывает существующий local-first workflow сильнее |
| Безопасность | Полный контроль и полная ответственность команды | Auth/write authorization всё равно наш backend; дополнительный replication контур | Проще один online API, но offline queue не решает privacy/auth сама |
| Lock-in | Низкий: HTTPS, SQLite, PostgreSQL, наши контракты | Средний: SDK/streams/replication config; self-host снижает hosting lock-in | Зависит от backend, protocol переносим при собственном API |
| Сложность разработки | Высокая: delivery/cursor/conflicts/fault tests | Ниже для доставки строк, но высокая для нашего domain layer | Быстрый online CRUD; высок риск потери текущего офлайн качества |
| Эксплуатация | API + Postgres + auth + backups | То же + PowerSync service/replication; managed вариант добавляет договор/тариф | API + DB + auth; очередь требует собственного ops контроля |
| Масштабирование | Workspace-serialized writes, stateless API; измерять contention | Готовая инфраструктура доставки; write reconciliation остаётся bottleneck | Обычное API scaling; offline convergence не появляется автоматически |
| Рекомендация | **Предпочтительный кандидат** | Сохранить как fallback после bounded spike | Не основной путь для Qesto |

[PowerSync Flutter SDK](https://docs.powersync.com/client-sdks/reference/flutter) предоставляет SQLite/read synchronization и upload integration. [Поддерживаемые платформы](https://docs.powersync.com/resources/supported-platforms) включают нужные native targets; exact compatibility выбранной версии надо проверить. [Self-hosting](https://docs.powersync.com/intro/self-hosting) возможен, но это не отменяет write backend, auth и domain validation. Лицензия, условия поддержки, data residency и стоимость выбранной редакции — отдельная проверка, не утверждение «бесплатно».

WatermelonDB полезен как источник требований к consistent snapshot и transactional push, но не как готовая Flutter dependency. Его описанный [sync algorithm](https://watermelondb.dev/docs/Implementation/SyncImpl) содержит client-wins field merge; для amount/currency/direction Qesto такой default недостаточен. Из [Backend guide](https://watermelondb.dev/docs/Sync/Backend) берём требования согласованности и валидации, не чужую финансовую семантику.

### Дополнительный минимальный вариант: JSON + outbox внутри одного envelope

Технически можно добавить очередь в текущий зашифрованный snapshot и заменить файл одним recoverable write. Это уменьшает первую миграцию, но оставляет rewrite всего профиля, слабую многопроцессную OCC, собственную реализацию paging/shadow/checkpoint и риск memory-before-save. Допустим как ограниченный эксперимент, не предпочтительная production основа. Добавить отдельный outbox-файл рядом со snapshot **нельзя**: два rename не являются одной atomic transaction.

## 2. Рекомендуемая структура

```text
Flutter UI (Desktop / Android)
       │ existing domain command adapters
       ▼
Local Unit of Work ── shared Synoball core / planning invariants
       │ single SQLite transaction
       ├── encrypted financial snapshot + local version
       ├── durable immutable command outbox
       └── server shadow / aliases / conflicts / checkpoint
       │ publish UI after commit
       ▼
Sync coordinator ── HTTPS /sync/v1 ── Auth + device authorization
                                      │
                                 Dart domain backend
                                 shared Synoball core
                                      │ one DB transaction
                                 PostgreSQL workspace state
                                 revision / receipts / commit log
                                      │
                              other devices pull committed bundles
```

Модульный монолит, не микросервисы. Dart backend — предпочтение ради одного executable financial core; конкретный HTTP framework выбрать bounded spike, не устанавливать сейчас. Extract core означает перенос существующего алгоритма в общий package, не переписывание на Python/SQL. Planning-команды controller нельзя копировать на server без выделения shared pure domain invariants; до этого опасные concurrent aggregate updates безопасно отклоняются, а не вычисляются вторым алгоритмом.

Python `deals_ingestion` остаётся отдельным public-data сервисом. Его HTTP исключения и token не переиспользуются как financial security boundary.

### Клиентская зависимость

Кандидат: SQLite через Drift. [Native Drift](https://drift.simonbinder.eu/platforms/vm/) поддерживает mobile/desktop; [transaction API](https://drift.simonbinder.eu/dart_api/transactions/) позволяет commit связанных statements, а notify происходит после завершения. Direct `sqlite3` — альтернатива с меньшим ORM слоем, но ручными schema/queries/migrations. Ни один вариант сам не предоставляет sync protocol.

Обязательный gate: encrypted persistence и crash/backup tests на Windows/Android. SQLCipher/native packaging — кандидат, не проверенная совместимость. Допустимая альтернатива для первого slice — AES-GCM encrypted snapshot/outbox/shadow payload columns с device secure-storage key; идентификаторы и metadata могут оставаться видимыми и это надо оценить. WAL, backups, conflict bodies и staged snapshot должны иметь ту же защиту. Не заменять текущее encrypted storage обычной plaintext SQLite.

Первый storage slice может хранить codec v7 snapshot в одной строке + служебные таблицы. Не требуется немедленно разбить весь финансовый профиль на SQL entities. Сохраняется price of whole-state recompute/write; нормализация таблиц — только после измерений.

## 3. Прохождение локального изменения

1. UI вызывает существующее намерение: изменить категорию, добавить операцию, goal contribution и т.д.
2. Unit of Work читает актуальную local version, строит staged state через текущую бизнес-логику и проверяет инварианты.
3. В **одной SQLite transaction** записывает новый financial state и immutable command/outbox с base server revision, refs и локальной sequence. При conflict local version — retry из актуального state, не сохранение stale snapshot.
4. Commit успешен → публикуется новое состояние и notify. При storage failure UI не сообщает «сохранено»; старое persisted state и outbox согласованы.
5. Coordinator отправляет команду. Server проверяет tenant/device, дозволенные поля, dependency/base revision и domain constraints; применяет существующий core и коммитит state + receipt + log.
6. Client применяет receipt/server bundle к shadow, сохраняет pending local tail поверх него, атомарно отмечает ACK. Другие devices получают то же committed canonical state.

Входящий remote state не создаёт исходящую user command. `Synoball.events` не превращаются автоматически в transport outbox: многие неполные и содержат diagnostics. Local undo должен генерировать новую явную command с revision, не вернуть старый snapshot поверх чужих изменений.

## 4. Identity и одна дедупликация

Отделяем `auth_subject`, `workspace_id`, `device_id`, `profile_lineage_id`, `entity_id`, `change_id`, `source_observation_id`. Existing ID не выбрасываем: legacy mapping/alias сохраняется, все references переводятся согласованно. Новые entities/commands — cryptographically random UUID; timestamps остаются business/display data, не порядок доставки.

### Покупка: уведомление телефона + выписка компьютера

1. Phone offline создаёт provisional canonical A + notification proof; Desktop offline — B + statement proof.
2. Server получает **external observation commands**, связывает подтверждённые workspace accounts/source namespaces через binding, запускает существующие normalization/reconciliation/dedup rules.
3. Если Synoball доказал один факт — возвращает canonical target и aliases A/B, обе evidence сохранены. Неоднозначность остаётся review, обе записи не объявляются автоматически одной только по сумме/времени.
4. Client атомарно применяет alias к transaction refs, evidence, receipts, goals/debt refs и pending command refs через alias lookup. Immutable queued command body не переписывается: server тоже разрешает старые refs по aliases; новому command допустим новый canonical ref.
5. Удалённый target не оживает: source replay разрешается в tombstone, restoration только explicit command.

Нельзя удалять connection/account scope из deduplicator ради совпадения. Binding слой нормализует только **подтверждённые** equivalence, сохраняет original source identity и provenance. Полный номер счёта/устойчивый bank ID предпочтительнее masked four digits; если доказательств нет — предложить пользователю account linking, а не угадать.

Remote canonical bundle не надо снова `ingest(manual)` или подавать как новый bank observation. Shared server core занимается новыми external facts; доставка уже согласованного canonical state — idempotent replication. Нужен отдельный safe canonical apply adapter, это transport boundary, не новый deduplicator.

Core/model/policy версии передаются явно. Если clients не могут выполнять тот же algorithm version, ingest upload приостанавливается с `UPGRADE_REQUIRED`; существующие локальные данные остаются доступными.

## 5. Матрица sync policy

| Данные | Направление | Primary / derived | Политика |
|---|---|---|---|
| Canonical transactions, manual overrides/locks, trash | Local commands → server canonical → clients | Primary | OCC, aliases/evidence, explicit restore |
| Accounts и balance observations | Source/manual → server → clients | Primary anchor | Absolute observation, provenance и source version; не transaction delta |
| Categories/rules/redirects/tags | Двустороннее | Primary policy | Atomic связанные правки, ручные override защищены |
| Budget periods/category plans | Двустороннее | Primary plans | Key/revision constraints; stale overwrite conflict |
| Goals + allocations + contributions/history | Двустороннее | Primary aggregate/event facts | Idempotent command, shared invariants; не повторить contribution |
| Investments/debts + snapshots/payments | Двустороннее | Primary capital facts | Связанные metadata/canonical accounts атомарны |
| Upcoming/planned expenses | Двустороннее | Primary plan | Не observed transaction; конфликт по revision |
| User name/currency/financial preferences | Двустороннее | Primary preference | Independent fields допустимо merge; ownership не client field |
| Receipt parsed facts / minimal source proof | По необходимости | Primary evidence | Allowlist, размер/retention; важны для reconciliation |
| Source originals: PDF/XLS/HTML/image/full SMS | По умолчанию local | Local sensitive originals | Optional encrypted blob workflow только отдельным решением |
| Capital/Cash Flow/charts/recurring/quality totals | Нет wire writes | Derived | Пересчитать существующими сервисами из canonical+plans |
| Bank PIN/cookies/CEF cache/OTP/adapter secrets | Никогда | Device secrets | Не включать в export/bootstrap/push |
| Permission state/native notification inbox | Local | OS/device state | Sync financial result только после persist; permission badge local |
| Theme/scroll/routes/public deals cache | Local | Presentation/cache | Не финансовая синхронизация |

## 6. Конфликты: безопасная политика

Server revision — отдельная authoritative metadata, не `updatedAt` устройства. Base revision и per-field revision map позволяют merge независимых полей, если домен разрешает. Financial tuple `amount/currency/direction/type/account` — единая группа, не пять произвольно смешиваемых полей. Технические tags, pending/posted и transfer markers тоже могут менять финансовый смысл: не объединять их слепым union.

| Сценарий | Решение | Что сохраняем |
|---|---|---|
| Две offline edits разных objects | Применить независимо | Обе команды/receipts |
| Одна операция, разные независимые поля: note и category | Merge только при совместимых base/field revisions и locks | Provenance обеих правок |
| Одно поле на двух devices | `CONFLICT`; нет unconditional LWW | Base, local proposal, remote current |
| amount vs currency/type/account | Financial group conflict | Оба предложения целиком, не гибрид суммы и валюты |
| Delete vs stale edit | Tombstone остаётся; edit сохраняется как conflict | Данные edit для решения; не silent loss и не resurrection |
| Explicit restore | Нужна актуальная tombstone revision и domain validation | Предыдущий lifecycle, refs, evidence |
| Category merge/delete и bulk category edits | Atomic logical unit, redirects/ref constraints | Rule scope и все зависимые changes; при опасных conflicts abort/review |
| Bank fact после user correction | Existing Synoball user locks/override имеют приоритет | Исходное evidence плюс пользовательское значение |
| Notification и statement той же покупки | Existing core + confirmed source bindings | Один доказанный canonical fact, обе evidence; ambiguity review |
| Две последовательные offline edits того же объекта | `depends_on_change_id`; receipt обновляет base только полей, реально записанных predecessor | Исходный base остальных полей остаётся; первая conflict блокирует dependent tail |
| События/ответы пришли не по порядку | Server revision + ordered pull bundles; stale response не затирает tail | Shadow и replay pending overlay; ACK только конкретной command |
| Bank/manual balance updates | Source binding + observation provenance; сомнительная chronology conflict | Оба absolute observations, не LWW по device clock |
| Goal contributions с двух devices | Unique contribution commands и shared aggregate invariants | Нет lost sum; если shared server executor не готов — conflict вместо арифметического guess |
| Investment/debt edit vs linked account update | Atomic aggregate revision | Не допускаем разные balances у двух частей одной сущности |

Конфликт — сохранённый результат, не сетевой retry и не «всё успешно». В UI нужно показать предмет конфликта и safe resolve options. Resolution — новая command, привязанная к current revision. Для общего eventual convergence допустимо согласованное состояние «conflict requires attention», а не обязательное автоматическое исчезновение конфликта.

## 7. Balance semantics и double application

Текущее account balance уже хранится независимо. Bank import передаёт absolute balance; canonical transaction меняет историю/аналитику, не повторно остаток. Server/client не выполняют новое бухгалтерское списание на каждую доставку.

Нужна metadata observation sidecar: source binding, ingest operation identity, observed business time если банк его дал, collection time и time confidence. Текущий account model не имеет универсального timestamp наблюдения. Clock телефона нельзя объявить доказательством более свежего bank balance. На первом этапе можно назначить один bank collector на binding (обычно Desktop), а manual/bank concurrent updates требуют review. Это решение продукта, не уже существующая гарантия.

Transfer source semantics сохраняются. Если core подтвердил internal transfer даже с одной стороной, Cash Flow остаётся internal; sync не требует искусственно создать вторую операцию. Если обе стороны реально есть — linked updates можно доставить atomic bundle. Текущий per-account reconstruction scope не расширяется этой задачей.

## 8. Ошибки и фон

Coordinator single-flight на workspace/device, bounded batches, persisted outbox lease для background worker. Foreground triggers: launch/resume, local commit (debounce), восстановление сети, ручная кнопка. Идемпотентность всё равно обязательна: single-flight не заменяет её.

Стартовые параметры для измерения: debounce 0.5–2 s, максимум 100 команд/2 MiB batch, timeout 20–30 s, exponential backoff + jitter, cap 5 min; `Retry-After` уважать. Это proposal, не performance SLA. Validation/conflict не ретраить бесконечно; auth требует refresh/relogin; offline/error не удаляет queued data. Пауза/отмена отменяет transport, не commit/queue.

Foreground изменения отправляются почти сразу; hourly banking collection не ограничивает data sync. Android [WorkManager](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work) выполняет deferred work с constraints, periodic work имеет минимум 15 минут и не точное время запуска. Нельзя обещать near-instant background delivery на спящем телефоне. FCM/WS при необходимости лишь invalidation hint; reliable state всё равно восстанавливается pull.

Отложить Kafka, CRDT, микросервисы и full event sourcing. Достаточны PostgreSQL transactions, mutable canonical state, durable receipts и bounded replication log. WebSocket не нужен для первого работающего slice.

## 9. Threat model и защита

| Угроза | Защита / остаточный риск |
|---|---|
| Перехват сети / malicious endpoint | HTTPS, certificate validation, approved endpoint/environment; не переносить исключения банковского CEF trust на Sync API |
| Пользователь A запрашивает ID B | Auth membership/object checks на каждый запрос + tenant-scoped queries/RLS/FK; cursor не даёт право доступа |
| Client назначает owner/revision/trust | Allowlisted commands, owner/revision вычисляет server; user-confirmed data не дают bank provenance |
| Украден refresh/device | Secure storage, refresh rotation, server-side device/session revocation; pending edits isolated |
| Повтор запроса / crash / старый device | Durable receipt + base revision + tombstone + resnapshot |
| Избыточный raw payload / log leak | Минимизация, redaction, quotas; не логировать amount/merchant/raw/token/request bodies |
| Rooted/unlocked device | Storage encryption не защищает активный compromised runtime; честный security scope |
| Server operator/DB compromise | Least privilege, encrypted disks/backups/keys, auditing; recommended mode **не E2EE**, server видит нормализованные facts |

Qesto login: native Authorization Code + PKCE S256 через системный внешний браузер, не через bank CEF. Это разные контуры: Сбер остаётся во встроенном браузере, Qesto OIDC — external user agent по [RFC 8252](https://www.rfc-editor.org/rfc/rfc8252). Native app — public client, embedded secret не секрет. State/nonce/verifier и redirect registration обязательны. Конкретный OIDC provider ещё выбрать.

Short-lived access token; refresh token в platform vault; для public clients — rotation с reuse detection или sender-constrained tokens по [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700). Рекомендуем rotation, один refresh flight. Потерянный refresh response не должен бесконечно replay старый token: provider policy/re-auth, outbox сохраняется. Device ID не является credential. Для немедленного revoke server проверяет device/session status/version на каждом API request; только JWT expiry не даёт мгновенного отзыва.

Валидация issuer/audience/expiry/signature, object/property authorization, resource limits и safe errors сверяются с [OWASP API Top 10](https://api-security.owasp.org/editions/2023/en/0x11-t10/) и [REST Security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html). Для native хранения/transport — checklist [OWASP MAS](https://mas.owasp.org/), не заявление о сертификации.

PostgreSQL RLS — второй слой, не замена auth. Runtime role не owner/superuser/BYPASSRLS; `FORCE ROW LEVEL SECURITY` где применимо; tx-local tenant context только из verified auth, pool reset. Composite workspace FK исключают cross-tenant references. Backup/admin/migration roles отдельные. Эти caveats существенны: владельцы/privileged roles могут обходить политики ([PostgreSQL RLS](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)).

### E2EE: отдельное решение, не маркетинговое обещание

Полное end-to-end encryption canonical facts лишает server возможности обычного Synoball reconciliation и server domain validation. Возможная другая архитектура — authoritative trusted client и encrypted relay; она меняет conflicts, recovery, доступность и multi-device trust. Селективно открытые amount/identity metadata для match уже не дают полного E2EE финансов.

Рекомендация для варианта A: TLS + encrypted storage/backups + owner-authorized server access к минимальным нормализованным данным; device secrets никогда не upload. До согласия продукта на этот trust model — **не включать реальную передачу**. Источники, retention, consent, hosting/residency, удаление из backups и применимость требований защиты персональных данных требуют отдельной юридической проверки до production; этот отчёт не устанавливает регуляторную квалификацию Qesto.

Logout с pending outbox: остановить transport, сохранить encrypted local workspace и предупреждение; не переassign командам нового пользователя. Войти тем же пользователем → resume; другим → другой partition. Local wipe, удаление cloud workspace и unlink device — три разных явных действия. Revoke offline-device запрещает новые server requests после возвращения, но не удаляет уже downloaded данные с отсутствующего устройства волшебным образом.

## 10. Миграция: без незаметного объединения старых профилей

| Миграция | Сейчас → proposal | Влияние и gate | Rollback |
|---|---|---|---|
| M1 Storage container | Encrypted codec v7 file → encrypted SQLite snapshot + metadata/outbox | Existing financial IDs/values остаются; source untouched, lossless canonical comparison; staged migration marker | До cutover — старый writer. После новых edits — только verified reverse export/новый совместимый client, не stale backup |
| M2 Global identity sidecar | Local IDs → alias map + lineage + global UUID | Не rewrite provider IDs/hash; atomic reference mapping, restore manifest | Disable sync; keep alias tables/data; не отбрасывать новый accepted ID |
| M3 Command boundary | Whole snapshot save → staged command + local transaction | Все live write paths проходят boundary; failure не показывает successful save | Feature flag только до включения dual-device writes; сохранённая очередь не удаляется |
| M4 Sync metadata | Нет auth/revisions → namespace/version/shadow/cursor/receipts/conflicts | Аддитивные metadata, core model semantics прежние | Pause transport, local-only mode; не выполнять старый client по новому DB |
| M5 Two-profile enrollment | Два независимых JSON profiles → workspace imports | Preview/consent, immutable manifests, core reconciliation + reviewed account bindings | Quarantine bootstrap до acceptance; после commit — compensating commands, не truncate server |

Bootstrap workflow:

1. Backup **с ключами/доступом к secure storage по безопасной процедуре**, snapshot digest и migration manifest. Copy одного `store.json` без key material/recovery access не является доказанным восстановлением на другом компьютере.
2. Desktop existing profile становится первым seed только после owner consent. Canonical/evidence/trash/plans сохраняются, не AI anonymized export.
3. Второй device с пустым профилем получает snapshot. Если там реальные данные — сначала preview union: account bindings, collisions, manual edits, budgets, tombstones, pending review. Не заменить локальное содержимое серверным автоматически.
4. Same legacy ID в разных lineage не означает same entity. Same confirmed bank identity можно согласовать existing core; two same manual purchases не объединяем по content.
5. Повторный bootstrap/reinstall с тем же manifest idempotent. Reinstall without manifest не даёт доказательства identity manual rows: предложить pull existing workspace или staged import/review, не автоматически создать копии.
6. Старый app без sync metadata не пишет в новый DB; нужен version gate, не silent downgrade. Schema/API/core versions независимы.

Local migration lossless для **всего** codec-снимка. Network bootstrap — allowlisted проекция только синхронизируемых primary facts/proofs, не upload `store.json` или полного codec JSON. Полные raw payloads, local diagnostic/undo history, device credential references и browser state не отправляются. Их локальное сохранение не означает наличие server backup этих оригиналов. Lossless для синхронизируемого subset проверяется отдельно от сохранности local-only данных.

Trash suppression anchors/aliases хранятся дольше replication log. При cursor expiry — full resnapshot с сохранённым pending outbox и последующим rebase, не erase-and-download. Подробная delivery политика — документ C.

## 11. Laptop → staging → production

Одинаковые API/model contracts; endpoint, issuer/audience, DB credentials, encryption keys и environment namespace отличаются. Не смешивать test/prod workspace IDs, tokens или queues.

| Среда | Размещение | Требование |
|---|---|---|
| Local dev | Dart API + Postgres + выбранный OIDC, отдельные synthetic profiles | Backend loopback; reproducible migrations; real-user upload выключен |
| Remote dev | TLS tunnel к local gateway | Public HTTPS + та же auth, rate limits и endpoint allowlist; tunnel не заменяет auth |
| Staging | Container images + durable Postgres + TLS gateway | Separate issuer/secrets/data; crash/restore/security/load gates |
| Production | Те же images/API; выбранный hosting | Backups + restore drills, monitored availability, incident/runbook и legal/privacy approval |

Containerization оправдана воспроизводимостью backend/auth/DB, не обязательным Kubernetes. Stateless API replicas возможны; workspace write lock находится в DB и действует между процессами. Different workspaces пишутся параллельно, одна hot workspace — ограничение throughput, подлежит измерению. Heavy parsing вне критической DB lock; final validation/commit под lock. Cache/Redis/WS вводить только при измеренной необходимости.

Health endpoint не раскрывает финансы; readiness проверяет DB/schema/auth key availability. Metrics: queue age, ACK latency, retry/conflict/cursor reset rate, bundle size, DB lock wait, backup age; no financial bodies. Репликационный log не заменяет backup. Нужны encrypted full backup + point-in-time recovery, проверенная процедура восстановления и resnapshot epoch после потери server state. Retention/RPO/RTO пока решения, не обещанные SLA.

## 12. Ограничения рекомендации

- Это больше собственного protocol/fault testing, чем подключение SDK; команда должна поддерживать его.
- Первоначальный snapshot container остаётся O(profile size), нужна проверка больших histories и memory use.
- Source binding и existing profile union — реальная domain работа, не generic row CRUD.
- Server видит нормализованные данные; full E2EE нельзя обещать в этой схеме.
- Android background near-instant delivery не гарантируется ОС.
- Production scale, native encryption и server core extraction пока не доказаны тестами. Roadmap и gates — документ D.
