from __future__ import annotations

import json
import unittest
from pathlib import Path
from urllib.error import HTTPError

from qesto_deals.config import MaxProviderConfig, PromoSourceConfig, load_config
from qesto_deals.extractor import RuleBasedOfferExtractor
from qesto_deals.filtering import MessageFilter
from qesto_deals.max_source import MaxSourceConfigurationError, MaxSourceProvider


FIXTURE_PATH = Path(__file__).parent / "fixtures" / "max_posts.json"


def provider_config(*, attempts: int = 3) -> MaxProviderConfig:
    return MaxProviderConfig(
        api_base_url="https://api.maximeter.test",
        api_token_env="MAXIMETER_API_TOKEN_FOR_TEST",
        backfill_limit=50,
        retry_attempts=attempts,
        retry_backoff_seconds=0,
    )


class MaxSourceProviderTest(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
        self.source = PromoSourceConfig(
            type="max",
            id="promokody_ru",
            channel_id="68782637867198",
        )

    def test_maps_twenty_max_posts_to_source_neutral_messages(self) -> None:
        requests = []

        def load(request, timeout):
            requests.append((request, timeout))
            return self.payload

        provider = MaxSourceProvider(
            provider_config(), api_token="secret", json_loader=load
        )
        messages = provider.fetch(self.source)

        self.assertEqual(20, len(messages))
        self.assertEqual("max", messages[0].source_type)
        self.assertEqual("promokody_ru", messages[0].source_id)
        self.assertEqual("1001", messages[0].message_id)
        self.assertEqual("https://max.ru/promokody_ru/1001", messages[0].original_url)
        self.assertIn("channel_id=68782637867198", requests[0][0].full_url)
        self.assertEqual("secret", requests[0][0].get_header("X-api-token"))

    def test_extracts_external_links_but_keeps_permalink_separate(self) -> None:
        provider = MaxSourceProvider(
            provider_config(), api_token="secret", json_loader=lambda _r, _t: self.payload
        )
        messages = provider.fetch(self.source)
        ozon = next(item for item in messages if item.message_id == "1002")
        self.assertEqual(("https://www.ozon.ru/product/123",), ozon.links)
        self.assertNotIn(ozon.original_url, ozon.links)

    def test_fixture_corpus_passes_common_filters_and_extractor(self) -> None:
        provider = MaxSourceProvider(
            provider_config(), api_token="secret", json_loader=lambda _r, _t: self.payload
        )
        messages = provider.fetch(self.source)
        expected = {
            str(post["id"]): post["expected_accepted"]
            for post in self.payload["posts"]
        }
        config = load_config()
        message_filter = MessageFilter(config.blocked_keywords)
        extractor = RuleBasedOfferExtractor(config)
        for message in messages:
            accepted, _ = message_filter.evaluate(message)
            self.assertEqual(expected[message.message_id], accepted, message.original_text)
            if accepted:
                self.assertTrue(extractor.extract(message), message.original_text)

    def test_retries_rate_limit_without_stopping_source(self) -> None:
        calls = 0

        def load(_request, _timeout):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise HTTPError(
                    "https://api.maximeter.test/v1/posts",
                    429,
                    "rate limited",
                    {"Retry-After": "0"},
                    None,
                )
            return self.payload

        provider = MaxSourceProvider(
            provider_config(attempts=2),
            api_token="secret",
            json_loader=load,
            sleep=lambda _seconds: None,
        )
        self.assertEqual(20, len(provider.fetch(self.source)))
        self.assertEqual(2, calls)

    def test_missing_token_has_actionable_error(self) -> None:
        provider = MaxSourceProvider(provider_config(), api_token=None)
        provider.api_token = None
        with self.assertRaisesRegex(MaxSourceConfigurationError, r"\.env"):
            provider.fetch(self.source)

    def test_config_enables_telegram_and_disables_max(self) -> None:
        config = load_config()
        self.assertTrue(config.enabled_sources)
        self.assertTrue(
            all(item.type == "telegram" for item in config.enabled_sources)
        )
        self.assertTrue(
            all(not item.enabled for item in config.promo_sources if item.type == "max")
        )


if __name__ == "__main__":
    unittest.main()
