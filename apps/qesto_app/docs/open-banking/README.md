OPEN BANKING FOUNDATION ONLY.
LIVE BANK CONNECTIVITY IS INTENTIONALLY DISABLED.

# Фундамент Open Banking ЦБ для Synoball и Qesto

## Статус

Этот модуль — протокольная и архитектурная подготовка, а не подключение к банку. В поставляемой конфигурации `openBanking.enabled=false`, `mode=disabled`. В Qesto не добавлены кнопки подключения банка, OAuth-переходы, сетевые запросы, настоящие токены, сертификаты, client secret или приватные ключи.

Единственный исполняемый провайдер — детерминированный in-memory fake для тестов. Он не открывает сокеты. Sandbox и production profile нельзя создать. Любой вызов disabled transport, crypto provider, certificate store, client assertion signer или detached JWS signer завершается `OpenBankingNotEnabledError`.

## Архитектурная граница

```text
Стандарты ЦБ / OpenID
        ↓
версионированный raw protocol layer
        ↓
provider profile + provider adapter
        ↓
CBR mapper boundary (пока Disabled)
        ↓
каноническая модель Synoball
        ↓
read models Qesto
```

Ни один банковский формат не меняет общую схему Synoball. Будущий Сбер, Т-Банк или ВТБ реализует `OpenBankingProvider` и объявит фактические capabilities. Отдельного «адаптера Сбера» в ядре нет.

## Модули

| Модуль | Назначение |
|---|---|
| `core/` | branded identifiers, время, версии, provenance, секреты, audit, redaction, runtime guard |
| `security/fapi_sec_1_6_2024/` | OAuth 2.0/OIDC, PKCE S256, signed request object, confidential client auth, JARM, JOSE/JWKS contracts, ID Token и mTLS binding |
| `security/fapi_paok_1_0_2024/` | CIBA poll/ping/push, metadata, hints, notification token и pure polling state machine |
| `api/cbr_2025_12_v2/` | `acis-pe`, URI builder, headers, consent, permissions, lifecycle, envelope/errors, raw-schema boundary и account endpoint families |
| `ports/` | transport, JOSE, JWKS, certificate, randomness и signing interfaces; production implementations отсутствуют |
| `providers/` | provider contract, fail-closed disabled provider и in-memory fake bank |
| `mapping/` | точка будущего преобразования официальных generated DTO в `SynoballAccount`/`TransactionSeed`; сейчас fail-closed |
| `source/` | общий каталог финансовых источников с отдельным выключенным `cbrOpenApi` |

Версии протокола безопасности и прикладного API независимы:

- `FAPI.SEC-1.6-2024`;
- `FAPI.PAOK-1.0-2024`;
- `CBR-OAPI-2025-12-v2`.

Обновление одной версии не требует переименования или скрытой подмены другой.

## Реализованные защитные правила

- `state` и `nonce` — секретные значения не короче 20 UTF-8 байт;
- PKCE допускается только с `S256`;
- redirect URI сравнивается точно, production требует HTTPS;
- access token в query запрещён;
- extended profile запрещает public client и допускает только `private_key_jwt` или `tls_client_auth`;
- signed request object требует проверенной подписи, корректных `iss`/`aud`, authoritative parameters и окна `exp - nbf ≤ 60 минут`;
- JARM либо hybrid `code id_token` защищает authorization response;
- ID Token проверяется после JOSE: issuer, audience/azp, time, nonce, `c_hash`/`at_hash` result;
- CIBA допускает ровно один user hint, ограничивает binding message и notification token, не допускает ранний/параллельный poll;
- access token должен быть не истёкшим, иметь scope и совпадать с mTLS certificate thumbprint;
- `SecretValue`, лог sanitizer и audit не сериализуют секреты и целые банковские payload;
- неизвестные metadata fields, permission/status и RU.CBR/participant error extensions не ломают parser.

## Consent и Connection

Consent resource, пользовательская OAuth/OIDC-авторизация и техническая connection — разные сущности. Известный жизненный цикл consent:

```text
AwaitingAuthorisation → Authorised → Revoked
                     ↘ Rejected
```

`Revoked → Authorised` и `Rejected → Authorised` запрещены без создания нового consent. Connection имеет собственные состояния (`planned`, `disabled`, `connecting`, `active`, `degraded`, `disconnected`, `revoked`, `failed`).

## Raw schema и нормализация

Сотни полей Account/Statement/Entry не переписаны вручную. `CbrRaw*` сейчас является нейтральной оболочкой и точкой для будущей генерации из официальной машиночитаемой спецификации, закреплённой по checksum/version:

```text
официальная CBR schema
        ↓ code generation
generated CbrRaw DTO
        ↓ version-specific mapper
Synoball normalized entities
```

До этого `DisabledCbrAccountMapper` и `DisabledCbrEntryMapper` намеренно бросают ошибку. Это не позволяет приблизительной структуре повредить статистику Qesto. Источник будущих данных получает provenance `CBR_OPEN_API`, а в существующей канонической модели соответствует `SynoballSourceType.regulatedApi`.

Endpoint foundation содержит `/accounts`, `/balances`, `/statements` и их account-scoped варианты. Собственный обязательный `/transactions` endpoint не придуман: операции будут поступать из официальной модели Statement/Entry конкретной версии.

## Тестовая стратегия

Новые unit-тесты проверяют:

- базовые OAuth/OIDC и extended FAPI правила;
- metadata/extension parsing, secret redaction, disabled ports;
- JARM, ID Token, mTLS binding и HTTP security;
- CIBA hints, modes и polling state machine;
- восемь обязательных permission combinations и provider capabilities;
- consent state machine и сохранение исходного time offset;
- URI/header/envelope/error contracts;
- пять fake-bank сценариев: happy path, rejection, revocation, expiry, provider error;
- отсутствие догадок в raw mapper boundary и независимость Synoball.

## Как безопасно продолжить после публикации окончательных материалов

1. Зафиксировать официальные schema-файлы, checksum, дату и effective date в `STANDARD_SOURCES.md`.
2. Сгенерировать raw DTO в новом version directory, не редактируя старую версию.
3. Реализовать version-specific mapper и fixture contract tests с официальными примерами.
4. Провести threat model, криптографический review, conformance и interoperability tests.
5. Подключить сертифицированные keystore/HSM, mTLS, JOSE/JARM и secure secret storage через существующие порты.
6. Реализовать один sandbox transport за `assertExternalIoAllowed`, allowlist хостов и отдельную build-time policy. Не переиспользовать generic HTTP client приложения.
7. Только после отдельного решения безопасности разрешить `sandbox`; production остаётся отдельным этапом.
8. После регистрации участника и подтверждённой совместимости добавить UI, consent wording, revoke/reconnect UX и пользовательскую поддержку.

Изменение YAML или одного feature flag само по себе никогда не должно включать сеть: необходимы transport, crypto, certificates, provider registration и policy gate одновременно.

## Что намеренно не реализовано

- live/sandbox bank network calls;
- browser redirects и deep links OAuth;
- выпуск, хранение или refresh настоящих токенов;
- реальные key/certificate stores, JWS/JWE и mTLS;
- PAR endpoint calls, dynamic client registration и scheduler;
- регистрация конкретного банка;
- приблизительные Account/Entry DTO и CBR → Synoball mapping;
- интерфейс подключения банка.

См. [официальные источники](STANDARD_SOURCES.md) и [архитектурное решение](ADR-open-banking-cbr-foundation.md).
