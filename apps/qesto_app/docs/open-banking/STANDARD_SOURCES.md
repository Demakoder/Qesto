# Реестр стандартов и первичных источников

Дата проверки источников: 2026-08-13. Для реализации использовались только официальные публикации Банка России и OpenID Foundation.

| Standard | Version | Publication/adoption date | Effective date | Internal module | Implementation status | Official source |
|---|---|---|---|---|---|---|
| Open API Банка России, общий пакет | 19.12.2025 | 19.12.2025; страница обновлена 24.12.2025 | зависит от документа пакета | `api/cbr_2025_12_v2` | базовая прикладная линия; повторно проверить перед интеграцией | [Банк России — Прикладные стандарты](https://www.cbr.ru/fintech/api/prikladnye-standarty/) |
| FAPI.SEC | `1.6-2024` | приказ № ОД-1615 от 07.10.2024 | по приказу/стандарту | `security/fapi_sec_1_6_2024` | модели и pure validators; crypto/transport отключены | [Банк России — FAPI.SEC-1.6-2024](https://www.cbr.ru/crosscut/lawacts/file/9908) |
| FAPI.ПАОК | `1.0-2024` | приказ № ОД-1616 от 07.10.2024 | по приказу/стандарту | `security/fapi_paok_1_0_2024` | CIBA foundation и state machine; scheduler/network отсутствуют | [Банк России — FAPI.PAOK-1.0-2024](https://www.cbr.ru/crosscut/lawacts/file/9907) |
| Согласие на доступ к счетам физлиц | `2.0.0` | 19.12.2025 | 01.10.2026 | `api/cbr_2025_12_v2/consent.dart` | raw model, permissions, lifecycle и endpoints | [Банк России — стандарт согласия физлиц](https://www.cbr.ru/Content/Document/File/185572/20251219_od_2892.pdf) |
| Сведения о счетах физлиц | `2.0.0` | 19.12.2025 | 01.10.2026 | `api/cbr_2025_12_v2/accounts.dart` | endpoint families и generated-schema boundary; поля DTO не выдуманы | [Банк России — стандарт сведений о счетах физлиц](https://www.cbr.ru/Content/Document/File/185573/20251219_od_2894.pdf) |
| Общие требования к Open API | пакет 19.12.2025 | 19.12.2025 | проверить по применимой редакции | `api/cbr_2025_12_v2/http.dart` | HTTP/envelope/error/header foundation | [Банк России — общие требования](https://www.cbr.ru/Content/Document/File/185562/20251219_od_2889.pdf) |
| Описание взаимодействия по счетам | пакет 19.12.2025 | 19.12.2025 | проверить по применимой редакции | `providers/`, `mapping/` | разделены consent, authorization и account access | [Банк России — описание взаимодействия](https://www.cbr.ru/Content/Document/File/185563/20251219_od_2890.pdf) |
| CIBA Core | 1.0 | final 2021 | final | `security/fapi_paok_1_0_2024` | poll/ping/push contract и token errors | [OpenID Foundation — CIBA Core 1.0](https://openid.net/specs/openid-client-initiated-backchannel-authentication-core-1_0.html) |
| JARM | final | final 2022 | final | `security/fapi_sec_1_6_2024` | authorization response model/validator; JOSE disabled | [OpenID Foundation — JARM](https://openid.net/specs/oauth-v2-jarm-final.html) |
| FAPI reference set | current registry | continuously maintained | n/a | справочный | cross-check; не подменяет профиль ЦБ | [OpenID Foundation — FAPI Specifications](https://openid.net/wg/fapi/specifications/) |

## Правило обновления

Перед sandbox-интеграцией нужно проверить effective dates, наличие новой редакции, опубликованные OpenAPI/schema artifacts, migration notes и conformance requirements. Любое несовместимое изменение получает новый каталог версии; существующий parser/mapper не переписывается «на месте».

FAPI 2.0 рассматривается как направление развития, но не подменяет обязательный для этой основы `FAPI.SEC-1.6-2024`. Возможные DPoP/PAR требования добавляются только после подтверждения применимой редакцией ЦБ и отдельным ADR.
