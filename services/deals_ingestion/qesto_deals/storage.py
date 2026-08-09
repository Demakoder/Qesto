from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from .models import Offer, RawMessage


class DealsStorage:
    def __init__(self, database_path: str | Path) -> None:
        self.database_path = Path(database_path)
        self.database_path.parent.mkdir(parents=True, exist_ok=True)
        self._initialize()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path, timeout=15)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        return connection

    def _initialize(self) -> None:
        with self._connect() as connection:
            connection.executescript(
                """
                CREATE TABLE IF NOT EXISTS raw_messages (
                    source_type TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    published_at TEXT NOT NULL,
                    original_text TEXT NOT NULL,
                    original_url TEXT NOT NULL,
                    links_json TEXT NOT NULL,
                    formatted_codes_json TEXT NOT NULL,
                    status TEXT NOT NULL,
                    filter_reason TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (source_type, source_id, message_id)
                );

                CREATE TABLE IF NOT EXISTS offers (
                    id TEXT PRIMARY KEY,
                    dedupe_key TEXT NOT NULL UNIQUE,
                    kind TEXT NOT NULL,
                    merchant_id TEXT,
                    promo_code TEXT,
                    confidence INTEGER NOT NULL,
                    valid_until TEXT,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS offer_sources (
                    offer_id TEXT NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
                    source_type TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    source_url TEXT NOT NULL,
                    PRIMARY KEY (offer_id, source_type, source_id, message_id)
                );

                CREATE INDEX IF NOT EXISTS idx_offers_visible
                    ON offers(confidence DESC, updated_at DESC);
                CREATE INDEX IF NOT EXISTS idx_offers_kind
                    ON offers(kind, confidence DESC);
                """
            )

    def is_message_known(self, message: RawMessage) -> bool:
        with self._connect() as connection:
            row = connection.execute(
                """SELECT 1 FROM raw_messages
                   WHERE source_type = ? AND source_id = ? AND message_id = ?""",
                (message.source_type, message.source_id, message.message_id),
            ).fetchone()
        return row is not None

    def save_message(
        self,
        message: RawMessage,
        *,
        status: str,
        filter_reason: str | None = None,
    ) -> None:
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO raw_messages (
                    source_type, source_id, message_id, published_at,
                    original_text, original_url, links_json,
                    formatted_codes_json, status, filter_reason
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(source_type, source_id, message_id) DO UPDATE SET
                    published_at = excluded.published_at,
                    original_text = excluded.original_text,
                    original_url = excluded.original_url,
                    links_json = excluded.links_json,
                    formatted_codes_json = excluded.formatted_codes_json,
                    status = excluded.status,
                    filter_reason = excluded.filter_reason
                """,
                (
                    message.source_type,
                    message.source_id,
                    message.message_id,
                    message.published_at.isoformat(),
                    message.original_text,
                    message.original_url,
                    json.dumps(message.links, ensure_ascii=False),
                    json.dumps(message.formatted_codes, ensure_ascii=False),
                    status,
                    filter_reason,
                ),
            )

    def prepare_message_refresh(self, message: RawMessage) -> None:
        """Detach stale offers before reprocessing an editable source post."""
        identity = (message.source_type, message.source_id, message.message_id)
        with self._connect() as connection:
            offer_ids = [
                str(row["offer_id"])
                for row in connection.execute(
                    """SELECT offer_id FROM offer_sources
                       WHERE source_type = ? AND source_id = ? AND message_id = ?""",
                    identity,
                ).fetchall()
            ]
            connection.execute(
                """DELETE FROM offer_sources
                   WHERE source_type = ? AND source_id = ? AND message_id = ?""",
                identity,
            )
            for offer_id in offer_ids:
                connection.execute(
                    """DELETE FROM offers
                       WHERE id = ? AND NOT EXISTS (
                           SELECT 1 FROM offer_sources WHERE offer_id = ?
                       )""",
                    (offer_id, offer_id),
                )

    def save_offer(self, offer: Offer) -> bool:
        payload = json.dumps(offer.to_dict(), ensure_ascii=False)
        with self._connect() as connection:
            existing = connection.execute(
                "SELECT id, confidence FROM offers WHERE dedupe_key = ?",
                (offer.dedupe_key,),
            ).fetchone()
            created = existing is None
            offer_id = offer.id if created else str(existing["id"])
            if created:
                connection.execute(
                    """INSERT INTO offers (
                           id, dedupe_key, kind, merchant_id, promo_code,
                           confidence, valid_until, payload_json, created_at, updated_at
                       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        offer.id,
                        offer.dedupe_key,
                        offer.type,
                        offer.merchant_id,
                        offer.promo_code,
                        offer.confidence,
                        offer.valid_until,
                        payload,
                        offer.created_at.isoformat(),
                        offer.updated_at.isoformat(),
                    ),
                )
            elif offer.confidence >= int(existing["confidence"]):
                connection.execute(
                    """UPDATE offers SET
                           kind = ?, merchant_id = ?, promo_code = ?, confidence = ?,
                           valid_until = ?, payload_json = ?, updated_at = ?
                       WHERE id = ?""",
                    (
                        offer.type,
                        offer.merchant_id,
                        offer.promo_code,
                        offer.confidence,
                        offer.valid_until,
                        payload,
                        offer.updated_at.isoformat(),
                        offer_id,
                    ),
                )
            connection.execute(
                """INSERT OR IGNORE INTO offer_sources (
                       offer_id, source_type, source_id, message_id, source_url
                   ) VALUES (?, ?, ?, ?, ?)""",
                (
                    offer_id,
                    offer.source.source_type,
                    offer.source.source_id,
                    offer.source.message_id,
                    offer.source.url,
                ),
            )
        return created

    def list_offers(
        self,
        *,
        minimum_confidence: int,
        kind: str | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        conditions = ["confidence >= ?"]
        values: list[object] = [minimum_confidence]
        if kind:
            conditions.append("kind = ?")
            values.append(kind)
        values.append(max(1, min(limit, 500)))
        query = (
            "SELECT * FROM offers WHERE "
            + " AND ".join(conditions)
            + " ORDER BY updated_at DESC LIMIT ?"
        )
        with self._connect() as connection:
            rows = connection.execute(query, values).fetchall()
            result = []
            for row in rows:
                payload = json.loads(str(row["payload_json"]))
                sources = connection.execute(
                    """SELECT source_type, source_id, message_id, source_url
                       FROM offer_sources WHERE offer_id = ?
                       ORDER BY source_type, source_id, message_id""",
                    (row["id"],),
                ).fetchall()
                payload["sources"] = [
                    {
                        "type": source["source_type"],
                        "channel": source["source_id"],
                        "message_id": source["message_id"],
                        "url": source["source_url"],
                    }
                    for source in sources
                ]
                result.append(payload)
        return result

    def counts(self) -> dict[str, int]:
        with self._connect() as connection:
            messages = connection.execute(
                "SELECT COUNT(*) AS value FROM raw_messages"
            ).fetchone()["value"]
            offers = connection.execute(
                "SELECT COUNT(*) AS value FROM offers"
            ).fetchone()["value"]
        return {"messages": int(messages), "offers": int(offers)}
