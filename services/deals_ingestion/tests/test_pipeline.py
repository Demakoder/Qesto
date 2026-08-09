from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path

from qesto_deals.config import PromoSourceConfig, load_config
from qesto_deals.models import RawMessage
from qesto_deals.pipeline import DealsSyncPipeline
from qesto_deals.storage import DealsStorage


class _PartiallyFailingMaxProvider:
    source_type = "max"

    def fetch(self, source: PromoSourceConfig) -> list[RawMessage]:
        if source.id == "broken":
            raise TimeoutError("test timeout")
        return [
            RawMessage(
                source_type="max",
                source_id=source.id,
                message_id="1",
                published_at=datetime(2026, 8, 9, tzinfo=timezone.utc),
                original_text="Самокат: промокод PIPE500 — скидка 500 ₽",
                original_url=f"https://max.ru/{source.id}/1",
            )
        ]


class DealsSyncPipelineTest(unittest.TestCase):
    def test_one_failed_channel_does_not_stop_other_channels(self) -> None:
        base = load_config()
        config = replace(
            base,
            promo_sources=(
                PromoSourceConfig(type="max", id="broken"),
                PromoSourceConfig(type="max", id="working"),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            storage = DealsStorage(Path(directory) / "pipeline.sqlite3")
            pipeline = DealsSyncPipeline(
                config=config,
                providers=(_PartiallyFailingMaxProvider(),),
                storage=storage,
            )
            report = pipeline.sync()

        self.assertEqual(1, report.sources_failed)
        self.assertEqual(1, report.sources_processed)
        self.assertEqual(1, report.offers_created)
        self.assertIn("max:broken", report.errors[0])


if __name__ == "__main__":
    unittest.main()
