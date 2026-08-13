# Synoball Core v1

Synoball — внутреннее финансовое ядро Qesto и будущий нейтральный инфраструктурный слой. Qesto остаётся первым клиентом и отвечает за UI, UX, пользовательские бюджеты, настройки и ассистента.

## Границы

```text
Manual / Voice / Android / Receipt / Statement / Legacy / CBR fixture
                              ↓
                         Adapters v1
                              ↓
             RawPayload + IngestionRecord + Candidate
                              ↓
                Deduplication + SourceTrustPolicy
                              ↓
             CanonicalTransaction + SourceEvidence
                              ↓
              Merchant / Category / Recurring enrichment
                              ↓
          FinancialState / Analytics read models / AI Context
                              ↓
                      Qesto / Synoball API v1
```

## Инварианты

- Сумма всегда абсолютна; направление хранится в `FinancialDirection`.
- Деньги хранятся в minor units и выдаются через API строкой decimal.
- Raw payload не удаляется после parsing.
- Connection создаётся только для постоянного канала. Разовый manual/voice/receipt/statement создаёт только ingestion.
- Candidate с низким доверием может оставаться pending. Voice всегда требует подтверждения.
- Объединение не удаляет evidence.
- Более надёжный источник может улучшить canonical fields по централизованной trust policy.
- Legacy records не объединяются между собой автоматически.
- Financial State, analytics и AI Context всегда пересчитываемы и не являются source of truth.
- Бюджеты и пользовательские планы Qesto не превращаются в observed transactions.
- Provider credentials не входят в state, events, logs или AI Context.

## Локальное хранение

В текущем прототипе `SynoballState` сериализуется внутрь локального `UserFinancialData` v2. Коллекции raw/canonical/evidence разделены логически, хотя физически находятся в одном JSON-документе. Это временная local-first persistence implementation; интерфейсы core не зависят от SharedPreferences и могут быть перенесены в SQLite или backend storage.

## Versioning

- Synoball schema: `1`.
- Canonical model: `1.0.0`.
- Adapters: собственная строка `adapterVersion`.
- CBR fixture adapter: `mock-1.0.0`.
- Internal/OpenAPI contract: `v1`.

Изменение внешней схемы источника требует новой версии adapter, но не должно менять canonical API без отдельной версии Synoball.

## Events и audit

Core создаёт события `transaction.created`, `transaction.updated`, `transaction.merged` и `financial_state.updated`. Подтверждение candidate и пользовательские изменения создают audit entries с actor, entity, purpose и временем. События сейчас локальные и готовы к подключению stream/webhook transport.

## Partial success

Bulk adapter обрабатывает candidates независимо. Ошибка одной записи переводит ingestion/import batch в partial и сохраняет успешные records. Provider error нормализуется в `SynoballErrorCode`; исходное диагностическое сообщение остаётся вне пользовательской аналитики.
