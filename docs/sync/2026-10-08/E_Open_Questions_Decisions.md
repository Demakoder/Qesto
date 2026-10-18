# E. Open Questions / Decisions

## 1. Выводы, которые можно принять по коду

| Решение | Основание |
|---|---|
| Offline-first сохранить | Сейчас оба clients работают с local financial state; cache-only усложнит/ухудшит существующий flow |
| Synoball — единственный reconciliation algorithm | Уже есть evidence/locks/repeated import/trash; sync transport не новый deduplicator |
| Нужен atomic persisted mutation + outbox | Сейчас recoverable snapshot и save queue без сетевого command log |
| Primary/derived разделить | Canonical facts/balances/plans primary; Cash Flow/liquidity/recurring/chart values derived |
| `local-user` не cloud owner | Default installation identity не authenticated account |
| Source ID != command ID != device ID | Existing source scopes и OS notification keys имеют разные значения |
| Revisions/cursor не по device clock | Нет глобальной chronology; timestamp и pre-commit sequence могут пропускать записи |
| Credentials/CEF/PIN/native permission local-only | Это device secrets и OS state, не финансовые entities |
| Public deals backend не расширять одним URL | Другие данные/security/ownership и transaction requirements |
| Delete/restore отдельные intents | Existing Synoball trash semantics; old import не restoration |

Эти выводы не разрешают внедрить новые зависимости/модели. Рекомендуемые SQLite/Postgres/HTTPS и shared Dart server остаются ADR proposal.

## 2. Решения владельца продукта до реализации

| ID | Вопрос | Рекомендация / tradeoff |
|---|---|---|
| P1 | Принимаем вариант A: собственный offline-first Sync API, SQLite container, PostgreSQL, shared Synoball? | Да как основной кандидат; PowerSync оставить bounded alternative spike при слишком дорогой delivery реализации |
| P2 | Может ли Qesto server видеть нормализованные суммы/даты/accounts/merchant и минимальные proofs? | Для server reconciliation — да, по явному consent. Это **не E2EE**. Если нет — другой ADR encrypted relay/client authority до любых uploads |
| P3 | Первые платформы: Windows + Android? | Да, не включать Web/iOS/Mac в первый acceptance обещанием; остальной core переносим позже |
| P4 | Как пользователь входит в Qesto: OIDC provider и восстановление доступа? | Existing trusted native OIDC с external browser+PKCE. Не писать handmade password server в sync PR |
| P5 | Где dev/staging/prod и кто управляет ключами/backups/инцидентами? | Separate environments; hosting/data residency и ops owner утвердить до реальных данных |
| P6 | Один personal workspace или совместный семейный доступ уже в MVP? | Один personal workspace. Namespace/membership заранее, sharing roles отложить |
| P7 | Что делать со вторым непустым профилем при enrollment? | Preview + consent + staged merge; никогда silently replace. Account linking только по подтверждённой identity |
| P8 | Original PDFs/receipts/screenshots/full notifications надо переносить? | По умолчанию нет. Parsed facts/minimal proof да; attachment cloud отдельный opt-in encrypted/retention slice |
| P9 | Один bank collector на source binding в первом MVP? | Предпочесть Desktop collector; phone notification observations допустимы. Одновременные bank sessions одного source требуют policy, не latest device clock |
| P10 | Retention: корзина, verbose receipts, server log, backups; user erase/recovery? | Compact idempotency/tombstone barriers на жизнь workspace; draft log 90 дней обсуждаем. Legal erase и user-visible trash срок отдельные решения |
| P11 | Logout/unlink/local wipe/cloud erase UX? | Четыре различимых действия с pending-warning; local data сохраняется при logout по умолчанию |
| P12 | Какой delivery SLA и offline срок обещаем? | Foreground near-real-time measured target; mobile background best effort. Не обещать точный ежечасный или мгновенный background sync |
| P13 | Разрешение на будущий copied real-profile test/upload? | Только отдельно после security/storage/parity gates и backup; текущая задача его не разрешает |

Для начала небольшого first PR достаточно утвердить P1/P3 и границы shared-core slice. P2/P4/P5/P8/P10 обязательны **до** реального сетевого контура и financial upload; нет необходимости отвечать на все вопросы ради самого architecture-only отчёта.

## 3. Блокирующие technical/security gates

1. **Native encrypted SQLite**: packaging Windows/Android, protected keys, WAL/backup/staging protection, crash recovery. Dependency выбрать по proof, не рекламному описанию.
2. **Shared core parity**: server compilation и same outputs/locks/trash/source identity; planning invariants не скопировать независимой арифметикой.
3. **Identity binding**: old account/connection/provider hashes и workspace aliases; original provider identities не регенерировать после remapping. Неразрешённый binding → review, не false merge.
4. **Minimal source proof**: notification legacy matching читает package/key raw; allowlisted payload должен сохранять semantics без full private text. Пока parity не доказана — не заявлять lossless cloud reconciliation.
5. **Auth/device security**: OIDC choice, session revoke, refresh loss policy, tenant isolation в API/DB/exports/logs. Tunnel не security gate.
6. **Local UoW coverage**: каждый mutation path snapshot+command atomic; memory-before-save устранить scoped changes. Unknown/uncovered path запрещает enable sync.
7. **Commit-order proof**: multi-process integration с блокировкой writers/rollback, consistent snapshot и atomic page apply; unit tests alone недостаточны.
8. **Consent/legal/hosting**: data categories, processor access, residency, retention/backups/erase и incident policy. Нужна проверка профильным специалистом; точная правовая применимость в этом техническом отчёте не установлена.
9. **Backup usability**: оригинальный encrypted file без recovery key не универсальный переносимый backup. Проверить restore, не только наличие копии.

## 4. Можно отложить

- Full normalized SQL domain schema: начать encrypted codec transaction container; benchmark определит необходимость.
- WebSocket/FCM ускорение, presence, live collaborative editing. Базовый pull остаётся reliable механизмом.
- CRDT, Kafka, microservices, multi-region writers, distributed event sourcing.
- Семейные workspace/роли, banking credentials roaming, automatic collector failover.
- Original attachments/cloud OCR/reprocessing, thumbnail storage и blob encryption.
- Полная историческая привязка каждой покупки к карте, per-card reconstructed chart — другой scope.
- Web/iOS/Mac shipping, тонкая UI-полировка conflict screens и preference roaming.
- Commercial hosting tier и точная смета — после profiling, требований residency/SLO и supplier review.

## 5. Технический долг выбранного решения

| Долг | Как ограничить |
|---|---|
| Snapshot container переписывает профиль | Замер и пределы размера; eventual normalized tables только при необходимости |
| Свой sync protocol требует поддержки | Frozen v1 guarantees, fault harness, compatibility matrix, owner/runbooks |
| Alias/source binding сложнее global UUID | Один authoritative mapping, immutable provenance, referential tests; не удалить историю identities |
| Server/client versions финансового core | Shared package и parity gate, min-domain version, deterministic inputs; нельзя незаметно разойтись |
| Workspace write serialization | Short critical section, quotas, measured lock contention; different users параллельно |
| Old-client rollback усложняется | Expand/contract, durable metadata, safe export и explicit version gate |
| Server-readable facts не E2EE | Честная privacy policy/consent, минимизация/least privilege; изменение trust model требует нового ADR |
| Conflict UX и поддержка | Persist proposals + reasons + safe resolver; не считать конфликт accepted edit |
| Local undo не cross-device undo | Revision-aware compensating command; не restore whole old snapshot |
| Tombstone/receipt barriers долговечны | Минимальные scoped metadata, erase policy; не обещать бесконечную raw retention |

## 6. Статус согласования

Предложение готово для решения владельца продукта. Production-код не менялся; текущие financial storage/банк/мобильные flows оставлены как есть. Ни source migration, ни backend, ни APK, ни PR текущим исследованием не создавались.

Рекомендуемый следующий шаг после утверждения — slice 1 из документа D: shared Synoball parity boundary **без network и миграции профиля**. Затем отдельный storage/encryption prototype. Если требуется strict E2EE, сначала перепроектировать server-authoritative reconciliation и recovery, а не прикрутить encryption к этому протоколу задним числом.
