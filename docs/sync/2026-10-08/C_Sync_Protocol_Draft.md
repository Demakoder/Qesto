# C. Sync Protocol Draft

**Не реализованный контракт.** Все endpoint names, JSON и числовые limits ниже — проект для утверждения и последующих tests.

## 1. Области идентичности и версии

| Поле | Назначение / правило |
|---|---|
| `auth_subject` | Identity OIDC provider; server определяет owner/membership, client не назначает владельца |
| `workspace_id` | Opaque global UUID, финансовое пространство; все domain refs/queries scoped им |
| `device_id` | Server-enrolled installation; связан с session, не пароль и не достаточное право доступа |
| `profile_lineage_id` | Устойчивая lineage исходного локального профиля и bootstrap manifest; сохраняется при проверенном restore |
| `entity_id` | Global opaque UUID новых entities; existing local IDs доступны через immutable alias map |
| `change_id` | UUID immutable logical command; primary idempotency key `(workspace_id, change_id)` |
| `client_epoch` / `client_seq` | Persisted queue generation и monotonic local counter; диагностика/order dependency, не server cursor |
| `revision` | Server-owned per-entity revision; client не может увеличить её самостоятельно |
| `base_revision` | Известная client shadow revision, на которой основана правка |
| `depends_on_change_id` | Предыдущая local command, outcome которой нужен следующей |
| `source_observation_id` | Stable source identity/provenance, отдельно от delivery/command UUID |
| `workspace_epoch` | Server dataset generation; после восстановлений/несовместимого reset старые cursors отвергаются |
| `protocol_version` / `domain_version` / `storage_version` | Независимые wire/core/local schema versions; codec v7 не становится HTTP version |

`createdAt`, `updatedAt`, `occurredAt`, bank business date и device clock не определяют delivery order. New UUID не заменяет bank provider ID. Alias mapping `(workspace, lineage, entity kind, legacy ID) → global ID` не удаляет original candidate/provider identity.

Wire деньги: decimal **string minor units** + currency + explicit scale. Например `{"minor_units":"486122","currency":"RUB","scale":2}`. Ни IEEE double, ни formatted UI text. Current Money codec допускает два знака; другие scales требуют отдельной domain поддержки, сейчас reject. Whole-unit planning поля сохраняют исходную семантику через typed mapper, не произвольно считают их копейками.

Business date без времени остаётся date-only. UTC instant и исходная timezone/date precision сохраняются, если доступны. Transport не сдвигает дату операции на день из-за UTC conversion.

Wire bootstrap — отдельная allowlisted lossless проекция синхронизируемого subset, **не полный UserFinancialDataCodec payload**. Local raw originals/diagnostics/credential refs остаются в local encrypted snapshot. Minimal proof DTO должен пройти existing-core parity; until then соответствующий source upload не включается.

## 2. Локальная durable модель

Первый container может содержать:

```text
financial_snapshot(workspace/local partition, local_version, encrypted codec payload)
sync_shadow(workspace, generation, encrypted canonical payload / revisions)
outbox(change_id, workspace, immutable body, digest, client_seq, dependency,
       status, attempts, next_attempt, lease_owner/expiry)
sync_meta(workspace, cursor, epoch, active_generation, protocol/core versions)
identity_aliases(workspace, lineage, kind, old_id, canonical_id)
conflicts(conflict_id, change_id, encrypted base/local/remote, resolution state)
bootstrap_staging(manifest_id, generation, page hashes, encrypted payload)
```

Это proposal metadata, не новые финансовые сущности. Отдельные таблицы vs encrypted aggregate rows определить storage spike. Queue body/refs/base никогда не принадлежат «текущему выбранному пользователю» по умолчанию: partition зафиксирован при создании.

**Local mutation transaction:** актуальный local_version → staged domain command → save snapshot + append outbox + increment local_version → COMMIT → publish UI. Недопустимы network calls внутри этой transaction и native ACK до неё. Изменение в памяти при disk failure не выдаём за persisted success.

**Pull/ACK transaction:** сохранить server shadow/revisions/aliases/conflicts, применить authoritative bundle, переиграть допустимый pending tail, обновить конкретные receipt statuses/checkpoint и projection → COMMIT → notify. Incoming sync apply не создаёт новый outbox item.

Предложенные queue states: `queued`, `in_flight` (lease), `accepted`, `conflict`, `blocked_dependency`, `rejected_requires_attention`, `paused_auth`. In-flight lease после crash возвращает retry **той же** command. Conflict/rejected body сохраняется, не удаляется как будто accepted. Accepted receipt сохраняется до безопасной compaction; marker не зависит от наличия HTTP response в памяти.

## 3. Логические endpoints

Все private endpoints — HTTPS + bearer session + server device/membership validation. Cursor, `device_id` и UUID не заменяют auth.

| Proposal endpoint | Контракт |
|---|---|
| `GET /sync/v1/capabilities` | Supported/min versions, core versions, limits; без private финансов |
| `POST /sync/v1/devices` | Enrollment authenticated device; server назначает ID/привязку session |
| `POST /sync/v1/workspaces/{w}/bootstrap-imports` | Создать idempotent staged import manifest существующего профиля |
| `PUT /sync/v1/workspaces/{w}/bootstrap-imports/{m}/pages/{n}` | Idempotent bounded chunks + hash; пока не live state |
| `POST /sync/v1/workspaces/{w}/bootstrap-imports/{m}/preview` | Validate refs, canonical/projection consistency, account bindings, conflict summary |
| `POST /sync/v1/workspaces/{w}/bootstrap-imports/{m}/commit` | Owner consent + expected workspace revision; atomic approved import; retry stable receipt |
| `POST /sync/v1/workspaces/{w}/push` | Commands grouped into logical atomic units, outcomes/receipts |
| `GET /sync/v1/workspaces/{w}/changes?cursor=...` | Ordered committed bundles, bounded page, watermark |
| `POST /sync/v1/workspaces/{w}/snapshots` | Создать согласованный immutable snapshot manifest при H |
| `GET /sync/v1/workspaces/{w}/snapshots/{s}/pages/{n}` | Authenticated snapshot chunk; pinned manifest/hash |
| `POST /sync/v1/workspaces/{w}/conflicts/{c}/resolve` | Новая explicit resolution command с current revision |
| `POST /sync/v1/workspaces/{w}/checkpoints/ack` | Optional durable applied-cursor ACK для retention/diagnostics; не даёт право удалить tombstones |
| `POST /sync/v1/devices/{d}/revoke` | Owner revokes session/device; не удаляет финансовые entities |

Endpoint envelope versioned; command kinds из registry: manual create/update, external observation ingest, category/rule change, account observation, goal/debt/investment/planning mutation, delete/restore. **Не** unrestricted JSON Patch к owner/revision/trust/payload fields и не generic replace-whole-profile.

## 4. Push пример

```json
{
  "protocol_version": 1,
  "domain_version": "synoball-current-approved",
  "workspace_epoch": "epoch-example-1",
  "device_id": "device-example-a",
  "request_id": "batch-example-101",
  "commands": [
    {
      "change_id": "change-example-10",
      "client_epoch": "queue-example-1",
      "client_seq": "10",
      "kind": "transaction.set_category",
      "target": {"kind": "transaction", "id": "tx-example-1"},
      "base_revision": "7",
      "depends_on_change_id": null,
      "payload": {"category_id": "cat-example-sport", "scope": "transaction"}
    }
  ]
}
```

Illustrative IDs здесь для читаемости; production валидирует UUID/alias format. Category override/locks определяет server shared command executor, не произвольная установка `trustLevel=verified` клиентом. Body `user_id`/`owner_id` недопустим; owner из auth. Legacy refs разрешаются только в workspace/lineage scope.

Пример final receipt:

```json
{
  "protocol_version": 1,
  "workspace_epoch": "epoch-example-1",
  "results": [
    {
      "change_id": "change-example-10",
      "status": "accepted",
      "commit_seq": "104",
      "entity_revisions": [
        {"kind": "transaction", "id": "tx-example-1", "revision": "8"}
      ],
      "aliases": [],
      "bundle_ref": "bundle-example-104"
    }
  ],
  "pull_required": true
}
```

Receipt **не продвигает pull cursor до 104**: client мог ещё не получить 101–103. Для own accepted state client может применить приложенный bundle/revision к shadow, затем normal pull повторит его idempotently. Older receipt не откатывает более новый shadow и не стирает offline edits 11/12.

ACK receipt и server bundle следует сохранять вместе либо помечать command accepted только с достаточным server result для безопасного overlay. Одна только потерянная строка «успех» не основание удалять pending edit.

## 5. Server validation и atomic unit

Каждый logical unit неделим: например category merge + redirects/ref updates, canonical investment account + metadata snapshot, import batch после полной reconciliation. Batch независимых units может иметь разные outcomes; зависимые commands останавливаются на первой конфликтной. Transport chunk не становится доменной границей.

Server validation order:

1. Auth issuer/aud/expiry, active session/device, workspace membership, request quotas.
2. Wire/core version, strict schema/allowlisted kinds/fields, sizes/types, money/date validity.
3. Receipt lookup по change ID; identical retry возвращает сохранённый outcome.
4. Workspace write gate, повторная session/device проверка и receipt lookup внутри transaction, alias/ref ownership.
5. Base/per-field revision + dependency, shared domain constraints; external observations — существующий adapter/core и разрешённый source binding.
6. State/revisions/receipt/conflict/aliases/log/head одной DB transaction; ответ только после COMMIT.

Source observations — пользовательские imported facts, не криптографически доказанная банковская подпись. Source kind/device binding предотвращают неправильный scope, но server не может объявить присланный DOM фактом, независимо подтверждённым самим банком. Confidence/trust рассчитываются допустимой domain policy, не принимаются через mass assignment.

Крупный statement/bootstrap сначала staged целиком с manifest и контрольными данными. Существующая batch reconciliation и printed controls выполняются до live commit; разбивка на сетевые страницы не должна превратить ambiguous/full-document batch в набор first-row-wins chunks.

## 6. Идемпотентность и потерянный ACK

Unique constraint `(workspace_id, change_id)`, immutable body digest и final receipt сохраняются **в той же transaction, что и финансовый результат**. `request_id` идентифицирует envelope для диагностики; дедупликация transport опирается на commands, даже если повторная упаковка batch отличается.

Digest — server SHA-256 над versioned deterministic encoding validated command: sorted object keys, ordered arrays, strict strings/integers, money string, no unknown fields. Client сохраняет неизменяемый body. Alias resolution происходит при выполнении, не меняет original digest. Same change ID + иной payload → `IDEMPOTENCY_KEY_REUSED`, ничего не применять.

```text
Client send C → Server COMMIT(state + receipt C + log)
             → connection lost before ACK
Client retries C → receipt lookup → same final outcome, no second financial change
```

Конкурентные одинаковые requests также сериализуются gate/unique constraint и повторным receipt lookup. Transient failures до commit не создают final accepted receipt; retry допустим. Conflict/rejection final для конкретного immutable body; разрешение — новая command ID, не «исправить тело старой».

Политика proposal: compact accepted IDs/digests/outcomes/created entity IDs и alias suppression живут всё время workspace. Verbose diagnostic receipt body можно compact после согласованного retention, например 90 дней; это **не** отменяет idempotency позднего replay. Old retry получает `accepted_compacted` + canonical refs/current revisions и pull/resnapshot, не создаёт operation снова. Data erasure удаляет workspace и его metadata целиком с revoke/epoch isolation; старый token/manifest не создаёт его заново автоматически.

## 7. Commit-safe cursor: доказательство

Не `updated_at > lastSync`, не UUID/time sort и не `nextval` до commit.

Proposal: одна row `workspace_head(workspace_id, epoch, head_seq)`; **каждый** writer (API, bootstrap, admin repair, conflict resolution) берёт `SELECT ... FOR UPDATE` в transaction и удерживает lock до конца. Sequence — обычный transactional bigint этой строки, не PostgreSQL sequence object.

```text
BEGIN
  authorize + lock workspace_head FOR UPDATE
  recheck receipt + permissions + versions
  execute domain unit
  s := head_seq + 1
  UPDATE workspace_head SET head_seq = s
  save canonical changes/revisions/aliases + receipt
  INSERT change_bundle(workspace, epoch, seq=s, complete unit)
COMMIT
```

Server-owned final outcomes, которые должны реплицироваться (включая conflict records), получают bundle. Retry существующей receipt не увеличивает head; никакого финансового изменения повторно нет.

**Почему нет пропуска:** writer A с номером s удерживает row lock. Writer B не может назначить s+1 и commit раньше A; после rollback A его transactional head/log не видимы и B использует следующий от реально committed head. State/log/head появляются одной transaction. Reader, увидев H, может получить все committed bundles ≤H; незакоммиченный writer не оставит «поздний номер ниже cursor». Different workspaces независимы. Row-lock lifetime и MVCC сверены с [PostgreSQL locks](https://www.postgresql.org/docs/current/explicit-locking.html) и [transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html).

Это свойство верно **только если нет writer вне gate**; DB role/API boundaries и tests обязаны это обеспечить. Parsing/network вне lock; опасный доменный final commit внутри. Для одной hot workspace throughput сериализован — осознанная цена корректности, сначала измерить.

## 8. Pull, страницы и checkpoint

На начало цикла server pin committed watermark H и проверяет retention. Cursor opaque authenticated token содержит workspace/epoch/protocol/last_applied_seq/pinned_H/expiry; MAC защищает от подмены, но отдельная auth всё равно обязательна. Body сырых внутренних seq можно показывать для диагностики, client не конструирует cursor сам.

```json
{
  "workspace_epoch": "epoch-example-1",
  "watermark": "104",
  "bundles": [
    {
      "seq": "104",
      "origin_change_id": "change-example-10",
      "entities": [
        {
          "kind": "transaction",
          "id": "tx-example-1",
          "revision": "8",
          "deleted": false,
          "fields": {"user_category_override": "cat-example-sport"}
        }
      ],
      "aliases": []
    }
  ],
  "next_cursor": "opaque-signed-cursor-example",
  "has_more": false
}
```

Illustration abbreviated: production bundle обязан содержать полный канонический entity или versioned patch с проверенным base revision; нельзя применить неполный patch к неизвестной версии. Для v1 предпочтителен complete entity per changed ID + explicit tombstone/alias, несмотря на больший payload.

Reader получает `(last_seq, H]` в order seq, целыми bundles. Head, retention и страницы читаются из согласованного DB view; v1 — primary, не случайное смешивание primary head с lagging read replica. Cursor сохраняется только вместе с **всеми** page changes в одной local transaction. Повтор страницы безопасен по entity revision/bundle identity. Несоответствие ожидаемой sequence/epoch/hash — fail closed, cursor не двигать; повтор/rebootstrap, а не «пропустить непонятное».

Pagination не режет logical unit. Oversize unit: immutable chunk manifest + hashes; client stages все части, проверяет completeness, затем один atomic apply и advancement. До этого partial entities не видны и cursor прежний. Ограничить размер logical units; большие imports validate/stage заранее, не держать HTTP/DB lock во время загрузки файла.

Shadow authoritative state отделён от optimistic visible state. Pending edits overlay сохраняется при pull; auto-rebase только безопасных disjoint fields/commands, остальные conflict. Command refs, tombstones и aliases применяются до dependent records в unit; whole-unit deferred FK validation предотвращает broken refs.

Предпочтительный cycle: recover leases → pull/rebase → push eligible units → apply receipts → pull до нового watermark. Ни API порядок, ни network response order не заменяют revision checks. При net-loss прогресс только в durable checkpoint/receipts.

## 9. Snapshot, expired cursor и damaged checkpoint

Full snapshot — immutable server materialization **на одном H** из согласованного DB snapshot, с manifest/hash/page count/schema/core version. Нельзя делать каждый page SQL query по изменяющимся live tables и называть это consistent full snapshot. Экспорт bounded; server не держит бесконечную transaction пока телефон неделями скачивает. Живые changes >H забираются после snapshot.

При `CURSOR_EXPIRED` / `WORKSPACE_EPOCH_CHANGED`:

1. Остановить push старой epoch; сохранить encrypted outbox, aliases, local base/proposals.
2. Fetch snapshot в **новую staging generation**, validate hashes/refs/schema и manifest.
3. Replay/rebase pending commands по безопасным правилам на новый shadow; конфликтное предложение сохранить, не потерять.
4. Atomic cutover active generation + financial state + pending outcomes + cursor at H.
5. Pull >H, возобновить допустимые commands. Incomplete download/crash остаётся staging, старый active state не повреждён.

Новый device с пустым профилем использует этот же snapshot workflow. Existing profile проходит bootstrap preview/consent, не overwrite. Повреждённый local checkpoint: quarantine повреждённой generation, last valid snapshot/outbox backup, resnapshot с сохранением восстановимых pending commands; unrecoverable data обозначить явно, не заменить empty profile и autosave. Recovery backups включают outbox/cursor/keys по проверенной процедуре.

Server backup restore с потерей уже acknowledged commits — инцидент, не обычный network retry. Изменить workspace epoch, revoke/reconcile affected sessions, использовать receipts/client retained accepted changes для repair review; не обещать zero loss вне утверждённого RPO/PITR. Клиенты не уничтожают retained records при reset.

## 10. Удаление, restoration, retention

- `entity.delete` переводит в tombstone с server revision/deleted time/actor/original lifecycle и минимальными dedup suppression refs. В корзине доступен existing explicit restore.
- Generic stale upsert/edit не делает tombstone live. Edit сохраняется как delete-vs-edit conflict.
- `entity.restore` требует base tombstone revision и explicit user intent; refs/accounts восстанавливаются/проверяются shared rules. Это не отмена старым profile snapshot.
- Replication log можно compact до agreed retention. Tombstone identities/aliases и receipt keys нельзя удалять по одному лишь log TTL.
- Device, offline дольше retention, проходит resnapshot до дальнейшего push; pending tail не удаляется, tombstones видимы в snapshot/suppression set.
- Пока workspace живёт — минимальные resurrection barriers остаются. Если требуется физическое удаление чувствительных deleted bodies раньше, сохранять минимальный approved identity barrier; legal erasure vs replay policy согласовать отдельно.
- Clear device data, unlink device, delete cloud account/workspace — отдельные confirmed commands. Cloud erase включает revoke, staged imports, keys/backups retention procedure; новый enrollment не переиспользует erased workspace автоматически.

Proposal log retention 90 дней и verbose receipt TTL — только исходные значения для обсуждения. Единый «удалить tombstones через 90 дней» **не предлагается**.

## 11. Conflicts и очередные dependent commands

Server хранит current revision и per-field/group last changed revision. Для поля, изменённого после client base, same-field conflict; unchanged independent field может merge после domain validation. Если history/base недоступны — conservative conflict, не доверять подставленному client base value.

Две offline edits X1 → X2: X2 содержит dependency X1, исходную shadow base, touched fields и ожидаемые результаты predecessor для зависимых полей. **Нельзя просто поднять весь base_revision X2 до receipt revision X1.** Receipt мог включать уже существовавшую чужую правку, которую offline пользователь не видел.

Правило: server выводит базу каждого затронутого field/group из original shadow revision и доказанной command dependency. Только поле, реально изменённое accepted predecessor и совпадающее с ожидаемым optimistic результатом, получает predecessor field revision; остальные сохраняют original base. Нужны versioned per-field base/dependency metadata и server receipt с реально изменёнными полями. При недостаточном proof — conflict, не слепой rebase.

Пример: X1 меняет category, X2 — note; другой device изменил note до commit X1. Даже если X1 принят на более новой overall revision, X2 note конфликтует с чужой note. Если X1 менял amount и X2 намеренно меняет amount ещё раз — dependency позволяет сравнить с результатом X1, но не скрыть последующее изменение другим устройством. Если X1 conflict/rejected, X2 `blocked_dependency`. Immutable command не мутируется для retry; явный rebase/resolve создаёт новый ID и сохраняет superseded intent history.

Conflict response хранит safe base/local/remote данные в encrypted client/server state. Для category auto update manual locks остаются, для finance tuple не blind merge. Conflict resolution проверяет current revision и scope заново. Server response не должен раскрывать чужой object даже при invalid refs.

## 12. Errors, cancellation, auth и compatibility

| HTTP / domain code | Поведение |
|---|---|
| 400 `INVALID_COMMAND` / 422 `DOMAIN_VALIDATION_FAILED` | Сохранить proposal requires attention; не tight retry |
| 401 `AUTH_EXPIRED` | Один refresh flight; при неудаче pause + relogin; outbox не удалить |
| 403 `DEVICE_REVOKED` / `ACCESS_DENIED` | Stop transport; local edits isolated, не отправлять новым owner |
| 404 scoped object absent | Не раскрывать существование чужой записи; correction/review |
| 409 `REVISION_CONFLICT` / `DELETED_CONFLICT` | Persist conflict, block dependencies |
| 409 `IDEMPOTENCY_KEY_REUSED` | Protocol/security error; не повторно применять |
| 410 `CURSOR_EXPIRED` / epoch mismatch | Staged resnapshot/rebase |
| 413 `BATCH_TOO_LARGE` | Split independent units; oversized atomic unit staged, не half-commit |
| 426 `UPGRADE_REQUIRED` | Local read/allowed offline commands сохраняются, несовместимый sync pause |
| 429 | Respect Retry-After, bounded jitter backoff |
| 5xx / timeout / offline | Same immutable command retry; unknown outcome не считать failure с rollback денег |
| Cancel | Stop waiting/sending; server уже мог commit, следующий retry выяснит receipt |

Capabilities содержит min/max wire/core versions и required features. Minor additive fields не меняют значение денег; unknown required enum/financial field — fail closed. Rollout expand → compatible clients → enable feature → contract later. Нельзя автоматически downcast удаление/копейки/internal transfer к старой схеме. Смена endpoint окружения создаёт другую namespace; tokens/queue/cursor не смешиваются.

Security validation обязательна для push, pull, snapshot pages, receipts и conflict resolve. Membership derived server-side; device revocation проверяется и перед domain commit в transaction. In-flight commit до завершения revoke допустим как уже принятый факт; после committed revoke новые writes/read запрещены. При logout pending financial data сохраняется только в своём encrypted partition, user решает дальнейшее действие.

## 13. Что ещё не определено

Точные DTO registry, server framework, OIDC provider, encrypted SQLite packaging, base/per-field metadata layout, quotas, legal retention, full-snapshot materialization implementation и measured SLO — предмет этапов D и согласований E. JSON выше показывает гарантии, а не повод немедленно создавать production endpoints.
