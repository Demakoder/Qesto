from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime
from typing import Any

MAX_MESSAGE_TEXT_CHARS = 12_000
MAX_MESSAGE_URL_CHARS = 2_048
MAX_LINKS_PER_MESSAGE = 50
MAX_FORMATTED_CODES_PER_MESSAGE = 50
MAX_FORMATTED_CODE_CHARS = 256


@dataclass(frozen=True)
class RawMessage:
    source_type: str
    source_id: str
    message_id: str
    published_at: datetime
    original_text: str
    original_url: str
    links: tuple[str, ...] = ()
    formatted_codes: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not self.source_type or len(self.source_type) > 32:
            raise ValueError("Raw message source type is invalid")
        if not self.source_id or len(self.source_id) > 128:
            raise ValueError("Raw message source id is invalid")
        if not self.message_id or len(self.message_id) > 128:
            raise ValueError("Raw message id is invalid")
        object.__setattr__(
            self,
            "original_text",
            self.original_text[:MAX_MESSAGE_TEXT_CHARS],
        )
        object.__setattr__(
            self,
            "original_url",
            self.original_url[:MAX_MESSAGE_URL_CHARS],
        )
        object.__setattr__(
            self,
            "links",
            tuple(
                value[:MAX_MESSAGE_URL_CHARS]
                for value in self.links[:MAX_LINKS_PER_MESSAGE]
            ),
        )
        object.__setattr__(
            self,
            "formatted_codes",
            tuple(
                value[:MAX_FORMATTED_CODE_CHARS]
                for value in self.formatted_codes[:MAX_FORMATTED_CODES_PER_MESSAGE]
            ),
        )

    @property
    def channel(self) -> str:
        """Compatibility alias used by the source-independent extractor."""
        return self.source_id

    @property
    def key(self) -> str:
        return f"{self.source_type}:{self.source_id}:{self.message_id}"


@dataclass(frozen=True)
class OfferSource:
    source_type: str
    source_id: str
    message_id: str
    url: str

    @property
    def channel(self) -> str:
        return self.source_id

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.source_type,
            "channel": self.source_id,
            "message_id": self.message_id,
            "url": self.url,
        }


@dataclass(frozen=True)
class Offer:
    id: str
    type: str
    merchant_id: str | None
    merchant_name: str | None
    title: str
    display_text: str
    promo_code: str | None
    discount_type: str
    discount_value: int | None
    currency: str | None
    minimum_order: int | None
    maximum_discount: int | None
    customer_type: str
    valid_until: str | None
    target_url: str | None
    original_text: str
    source: OfferSource
    confidence: int
    created_at: datetime
    updated_at: datetime
    dedupe_key: str

    def to_dict(self, sources: list[dict[str, Any]] | None = None) -> dict[str, Any]:
        result = asdict(self)
        result["source"] = self.source.to_dict()
        result["sources"] = sources or [self.source.to_dict()]
        result["created_at"] = self.created_at.isoformat()
        result["updated_at"] = self.updated_at.isoformat()
        result.pop("dedupe_key", None)
        return result


@dataclass
class SyncReport:
    sources_processed: int = 0
    sources_failed: int = 0
    messages_seen: int = 0
    new_messages: int = 0
    filtered_messages: int = 0
    offers_created: int = 0
    duplicates_found: int = 0
    errors: list[str] = field(default_factory=list)

    @property
    def channels_processed(self) -> int:
        return self.sources_processed

    @property
    def channels_failed(self) -> int:
        return self.sources_failed

    def to_dict(self) -> dict[str, Any]:
        result = asdict(self)
        # Keep old counters for clients/log tools that still expect them.
        result["channels_processed"] = self.sources_processed
        result["channels_failed"] = self.sources_failed
        return result
