# ADR: standard-first foundation Open Banking ЦБ

- Статус: принято
- Дата: 2026-08-13
- Область: Synoball Core / Qesto

## Контекст

Окончательные банковские реализации, регистрационные данные участника, сертификаты и стабильные schema artifacts пока отсутствуют. При этом архитектура должна быть готова к стандартному Open API Банка России и не создавать банковские исключения внутри Synoball.

Главные риски ранней «интеграции»: утечка токена или payload, случайный внешний запрос, смешение consent и connection, жёсткая привязка к URL/формату одного банка, приблизительная модель Account/Entry и незаметное изменение финансовой статистики Qesto.

## Решение

1. Создать отдельный `synoball/open_banking` bounded context.
2. Версионировать security profiles и прикладной API независимо.
3. Оставить каноническую схему Synoball неизменной; CBR подключается как `regulatedApi` только после mapper boundary.
4. Представлять Institution, Consent, Connection, AuthorizationSession и credential/token binding отдельными сущностями.
5. Сохранять протокольные значения и неизвестные extensions; не использовать закрытые enum для расширяемых permission/status/error code.
6. Не переписывать сотни CBR Account/Entry fields вручную. Сформировать generated raw-schema boundary.
7. Инъецировать transport, clock, randomness, JOSE, JWKS, certificate и signing dependencies через порты.
8. Поставлять только fail-closed реализации и in-memory fixtures. Внешний I/O блокируется централизованно и отсутствует в provider path.
9. Не менять UI Qesto до отдельного решения о реальном подключении.

## Последствия

Положительные:

- банк или новая редакция стандарта добавляются адаптером/версией, а не изменением Synoball;
- безопасность тестируется pure-функциями до появления credentials;
- неизвестные расширения не приводят к потере данных или parse failure;
- приблизительные raw DTO не загрязняют доменную модель;
- существующие выписки, Excel, чеки, голос, ручной ввод и Android-уведомления остаются независимыми.

Ограничения:

- foundation не подключается к реальному банку;
- mapper намеренно отсутствует до официальной schema generation;
- включить сеть одной настройкой невозможно;
- conformance, HSM/keystore, mTLS, participant registration и UX остаются будущей работой.

## Инварианты безопасности

- Никаких банковских URL, токенов, ключей и сертификатов в репозитории или пользовательском storage.
- Никаких access token в query, целых payload/token в логах и audit.
- Sandbox/production provider profiles и external transport недоступны в текущей сборке.
- Mock не маскируется под production cryptography.
- Consent никогда не считается технической connection и наоборот.
- `Revoked`/`Rejected` consent не возвращается в `Authorised`.
- К CBR raw data нельзя обращаться без подходящего consent; к Synoball mapping нельзя перейти без pinned schema mapper.

## Условия пересмотра

ADR пересматривается после публикации новой обязательной редакции ЦБ, доступности официальной schema/codegen input, выдачи participant credentials или решения начать sandbox interoperability testing.
