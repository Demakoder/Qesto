from __future__ import annotations

import unittest

from qesto_deals.telegram_source import _TelegramPreviewParser


class TelegramPreviewParserTest(unittest.TestCase):
    def test_reads_public_preview_message(self) -> None:
        parser = _TelegramPreviewParser("skidki")
        parser.feed(
            """
            <div class="tgme_widget_message js-widget_message" data-post="skidki/123">
              <div class="tgme_widget_message_text js-message_text">
                Ozon: промокод <code>SALE20</code><br/>Скидка 20%
                <a href="https://ozon.ru/product/1">Открыть</a>
              </div>
              <time datetime="2026-08-09T10:30:00+00:00"></time>
            </div>
            """
        )
        self.assertEqual(1, len(parser.messages))
        parsed = parser.messages[0]
        self.assertEqual(("SALE20",), parsed.formatted_codes)
        self.assertEqual(("https://ozon.ru/product/1",), parsed.links)
        self.assertIn("Скидка 20%", parsed.original_text)
        self.assertEqual("https://t.me/skidki/123", parsed.original_url)

    def test_ignores_messages_from_an_unexpected_channel(self) -> None:
        parser = _TelegramPreviewParser("skidki")
        parser.feed(
            """
            <div class="tgme_widget_message js-widget_message" data-post="attacker/123">
              <div class="tgme_widget_message_text js-message_text">
                Поддельный промокод <code>STEAL</code>
              </div>
            </div>
            """
        )
        self.assertEqual([], parser.messages)


if __name__ == "__main__":
    unittest.main()

