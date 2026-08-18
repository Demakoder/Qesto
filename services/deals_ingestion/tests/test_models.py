from __future__ import annotations

import unittest
from datetime import datetime, timezone

from qesto_deals.models import (
    MAX_FORMATTED_CODES_PER_MESSAGE,
    MAX_LINKS_PER_MESSAGE,
    MAX_MESSAGE_TEXT_CHARS,
    MAX_MESSAGE_URL_CHARS,
    RawMessage,
)


class RawMessageSafetyTest(unittest.TestCase):
    def test_untrusted_message_fields_are_bounded_before_storage(self) -> None:
        message = RawMessage(
            source_type="max",
            source_id="channel",
            message_id="1",
            published_at=datetime.now(timezone.utc),
            original_text="x" * (MAX_MESSAGE_TEXT_CHARS + 1),
            original_url="https://example.test/" + "x" * MAX_MESSAGE_URL_CHARS,
            links=tuple("https://example.test" for _ in range(100)),
            formatted_codes=tuple("CODE" for _ in range(100)),
        )

        self.assertEqual(MAX_MESSAGE_TEXT_CHARS, len(message.original_text))
        self.assertEqual(MAX_MESSAGE_URL_CHARS, len(message.original_url))
        self.assertEqual(MAX_LINKS_PER_MESSAGE, len(message.links))
        self.assertEqual(
            MAX_FORMATTED_CODES_PER_MESSAGE,
            len(message.formatted_codes),
        )


if __name__ == "__main__":
    unittest.main()
