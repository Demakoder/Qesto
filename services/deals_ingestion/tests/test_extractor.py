from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from qesto_deals.config import load_config
from qesto_deals.extractor import RuleBasedOfferExtractor
from qesto_deals.filtering import MessageFilter, clean_display_text
from qesto_deals.models import RawMessage
from qesto_deals.storage import DealsStorage


PUBLISHED = datetime(2026, 8, 9, 12, tzinfo=timezone.utc)


def message(
    text: str,
    *,
    channel: str = "skidki",
    message_id: int = 1,
    codes: tuple[str, ...] = (),
    links: tuple[str, ...] = (),
    source_type: str = "telegram",
) -> RawMessage:
    source_url = (
        f"https://max.ru/{channel}/{message_id}"
        if source_type == "max"
        else f"https://t.me/{channel}/{message_id}"
    )
    return RawMessage(
        source_type=source_type,
        source_id=channel,
        message_id=str(message_id),
        published_at=PUBLISHED,
        original_text=text,
        original_url=source_url,
        links=links,
        formatted_codes=codes,
    )


class ExtractorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = load_config()
        cls.extractor = RuleBasedOfferExtractor(cls.config)
        cls.filter = MessageFilter(cls.config.blocked_keywords)

    def test_simple_promo_code(self) -> None:
        offer = self.extractor.extract(message("Самокат, промокод: SALE500"))[0]
        self.assertEqual("SALE500", offer.promo_code)
        self.assertEqual("samokat", offer.merchant_id)
        self.assertEqual("promo_code", offer.type)

    def test_multiple_formatted_promo_codes(self) -> None:
        offers = self.extractor.extract(
            message(
                "AliExpress: скидка по двум промокодам",
                codes=("A3SALE", "A5SALE"),
            )
        )
        self.assertEqual(["A3SALE", "A5SALE"], [item.promo_code for item in offers])

    def test_list_post_is_split_into_code_specific_offers(self) -> None:
        offers = self.extractor.extract(
            message(
                """Все актуальные промокоды Купер
Важная информация об использовании кодов на сайте
Условия могут меняться без предупреждения
Следите за обновлениями публикации
3. Промокоды Купер на ПОВТОРНЫЕ заказы для отдельных магазинов
🔖 MMRT1 — скидка 400₽ от 4500₽ в Магнит
🔖 MKM3 — скидка 20% (макс. 900₽) от 3500₽ в Магнит Косметик
🔖 DXJM — скидка 400₽ от 2800₽ в Дикси""",
                codes=("MMRT1", "MKM3", "DXJM"),
            )
        )
        by_code = {offer.promo_code: offer for offer in offers}

        self.assertEqual("magnit", by_code["MMRT1"].merchant_id)
        self.assertEqual("magnit_cosmetic", by_code["MKM3"].merchant_id)
        self.assertEqual("dixy", by_code["DXJM"].merchant_id)
        self.assertEqual("fixed", by_code["MMRT1"].discount_type)
        self.assertEqual(400, by_code["MMRT1"].discount_value)
        self.assertEqual("repeat", by_code["MMRT1"].customer_type)
        self.assertIn("MMRT1", by_code["MMRT1"].display_text)
        self.assertNotIn("MKM3", by_code["MMRT1"].display_text)
        self.assertNotIn("Все актуальные", by_code["MMRT1"].display_text)

    def test_repeated_code_lines_share_one_card_with_relevant_text(self) -> None:
        offers = self.extractor.extract(
            message(
                """Промокоды Купер на первый заказ
🔖 epn500 — скидка 500 р на заказ от 2500 р
🔖 epn500 — скидка 40% на заказ от 1000 р
Подписывайтесь на канал""",
                codes=("epn500", "epn500"),
            )
        )

        self.assertEqual(1, len(offers))
        self.assertEqual(2, offers[0].display_text.count("epn500"))
        self.assertNotIn("Подписывайтесь", offers[0].display_text)

    def test_code_line_is_joined_with_preceding_product_line(self) -> None:
        offers = self.extractor.extract(
            message(
                """Подборка выгодных предложений
➡️ OZON — дополнительная скидка 15% на товары DAV
➕ Промокод — K4D785BEC164
➡️ Другая акция со скидкой 30%
➕ Промокод — OTHER30""",
                codes=("K4D785BEC164", "OTHER30"),
            )
        )
        by_code = {offer.promo_code: offer for offer in offers}

        self.assertEqual("ozon", by_code["K4D785BEC164"].merchant_id)
        self.assertEqual(15, by_code["K4D785BEC164"].discount_value)
        self.assertIn("OZON", by_code["K4D785BEC164"].display_text)
        self.assertNotIn("Другая акция", by_code["K4D785BEC164"].display_text)

    def test_percent_discount(self) -> None:
        offer = self.extractor.extract(message("Ozon: скидка 25% по коду OZON25"))[0]
        self.assertEqual(("percent", 25), (offer.discount_type, offer.discount_value))

    def test_fixed_discount(self) -> None:
        offer = self.extractor.extract(message("Купер: промокод FOOD500, скидка 500 ₽"))[0]
        self.assertEqual(("fixed", 500), (offer.discount_type, offer.discount_value))

    def test_new_customer(self) -> None:
        offer = self.extractor.extract(message("Самокат: код NEW20 на первый заказ"))[0]
        self.assertEqual("new", offer.customer_type)

    def test_repeat_customer(self) -> None:
        offer = self.extractor.extract(message("Додо: код DODO20 на повторный заказ"))[0]
        self.assertEqual("repeat", offer.customer_type)

    def test_minimum_order(self) -> None:
        offer = self.extractor.extract(
            message("Яндекс Еда: промокод EDA400, скидка 400 ₽ при заказе от 1500 ₽")
        )[0]
        self.assertEqual(1500, offer.minimum_order)

    def test_maximum_discount(self) -> None:
        offer = self.extractor.extract(
            message("Ozon: промокод SALE20, скидка 20%, максимум 700 ₽")
        )[0]
        self.assertEqual(700, offer.maximum_discount)

    def test_deal_without_promo_code(self) -> None:
        offer = self.extractor.extract(message("Ozon — товар за 1990 ₽ вместо 3490 ₽"))[0]
        self.assertIsNone(offer.promo_code)
        self.assertEqual("deal", offer.type)
        self.assertEqual(1500, offer.discount_value)

    def test_ad_without_offer_is_filtered(self) -> None:
        accepted, reason = self.filter.evaluate(
            message("Реклама. ООО Пример, ИНН 7700000000, erid ABC123")
        )
        self.assertFalse(accepted)
        self.assertEqual("no-offer-keywords", reason)

    def test_inn_and_erid_are_not_promo_codes(self) -> None:
        offers = self.extractor.extract(
            message("Ozon: скидка 10%. ИНН 7700000000, erid ABC123")
        )
        self.assertTrue(offers)
        self.assertTrue(all(item.promo_code is None for item in offers))

    def test_unsafe_category_is_blocked(self) -> None:
        accepted, reason = self.filter.evaluate(message("Скидка 30% на алкоголь и вино"))
        self.assertFalse(accepted)
        self.assertTrue(reason.startswith("blocked:"))

    def test_legal_advertising_details_are_removed_from_display_text(self) -> None:
        cleaned = clean_display_text(
            "Ozon: скидка 20% по коду SALE20\nРеклама. ООО Пример, ИНН 123\nerid X"
        )
        self.assertIn("Ozon", cleaned)
        self.assertNotIn("ИНН", cleaned)
        self.assertNotIn("erid", cleaned)

    def test_primary_link_excludes_telegram_shorteners_and_images(self) -> None:
        offer = self.extractor.extract(
            message(
                "Ozon: скидка 10% по коду SALE10",
                links=(
                    "https://t.me/admin",
                    "https://ya.cc/short",
                    "https://cdn.example/image.png",
                    "https://www.ozon.ru/product/1",
                ),
            )
        )[0]
        self.assertEqual("https://www.ozon.ru/product/1", offer.target_url)

    def test_same_promo_from_two_channels_is_deduplicated(self) -> None:
        first = self.extractor.extract(
            message("Самокат: промокод SALE500", channel="skidki", message_id=1)
        )[0]
        second = self.extractor.extract(
            message(
                "Самокат: код SALE500",
                channel="promokody_ru",
                message_id=2,
                source_type="max",
            )
        )[0]
        with tempfile.TemporaryDirectory() as directory:
            storage = DealsStorage(Path(directory) / "test.sqlite3")
            self.assertTrue(storage.save_offer(first))
            self.assertFalse(storage.save_offer(second))
            offers = storage.list_offers(minimum_confidence=0)
        self.assertEqual(1, len(offers))
        self.assertEqual(2, len(offers[0]["sources"]))
        self.assertEqual(
            {"telegram", "max"}, {source["type"] for source in offers[0]["sources"]}
        )

    def test_same_code_with_different_detected_merchants_is_deduplicated(self) -> None:
        first = self.extractor.extract(
            message("Ozon: промокод SAME20", channel="skidki", message_id=1)
        )[0]
        second = self.extractor.extract(
            message("Лента: промокод SAME20", channel="kuponych", message_id=2)
        )[0]
        with tempfile.TemporaryDirectory() as directory:
            storage = DealsStorage(Path(directory) / "test.sqlite3")
            storage.save_offer(first)
            storage.save_offer(second)
            offers = storage.list_offers(minimum_confidence=0)

        self.assertEqual(1, len(offers))
        self.assertEqual(2, len(offers[0]["sources"]))

    def test_refresh_removes_stale_offers_from_edited_post(self) -> None:
        old_message = message(
            "Купер: промокод OLD500, скидка 500 ₽",
            codes=("OLD500",),
        )
        new_message = message(
            "Купер: промокод NEW500, скидка 500 ₽",
            codes=("NEW500",),
        )
        with tempfile.TemporaryDirectory() as directory:
            storage = DealsStorage(Path(directory) / "test.sqlite3")
            storage.save_message(old_message, status="processed")
            storage.save_offer(self.extractor.extract(old_message)[0])
            storage.prepare_message_refresh(new_message)
            storage.save_message(new_message, status="processed")
            storage.save_offer(self.extractor.extract(new_message)[0])
            offers = storage.list_offers(minimum_confidence=0)

        self.assertEqual(["NEW500"], [offer["promo_code"] for offer in offers])

    def test_fixture_corpus(self) -> None:
        fixture_path = Path(__file__).parent / "fixtures" / "telegram_posts.json"
        fixtures = json.loads(fixture_path.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(fixtures), 20)
        for fixture in fixtures:
            raw = message(
                fixture["text"],
                channel=fixture["channel"],
                message_id=fixture["message_id"],
                codes=tuple(fixture.get("codes", ())),
            )
            accepted, _ = self.filter.evaluate(raw)
            self.assertEqual(fixture["accepted"], accepted, fixture["text"])
            if accepted:
                self.assertTrue(self.extractor.extract(raw), fixture["text"])


if __name__ == "__main__":
    unittest.main()
