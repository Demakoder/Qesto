from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .http_safety import DEFAULT_MAX_RESPONSE_BYTES, validate_https_base_url


@dataclass(frozen=True)
class PromoSourceConfig:
    type: str
    id: str
    enabled: bool = True
    channel_id: str | None = None


@dataclass(frozen=True)
class MaxProviderConfig:
    api_base_url: str
    api_token_env: str
    backfill_limit: int
    retry_attempts: int
    retry_backoff_seconds: float


@dataclass(frozen=True)
class DealsConfig:
    promo_sources: tuple[PromoSourceConfig, ...]
    max_provider: MaxProviderConfig
    request_timeout_seconds: int
    max_response_bytes: int
    visible_confidence_threshold: int
    database_path: Path
    blocked_keywords: tuple[str, ...]
    blocked_link_hosts: tuple[str, ...]
    merchants: dict[str, tuple[str, ...]]

    @property
    def enabled_sources(self) -> tuple[PromoSourceConfig, ...]:
        return tuple(source for source in self.promo_sources if source.enabled)


def default_config_path() -> Path:
    return Path(__file__).resolve().parent.parent / "config" / "sources.json"


def load_config(path: str | Path | None = None) -> DealsConfig:
    config_path = Path(path) if path else default_config_path()
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    database_path = Path(payload.get("database_path", "data/deals_max.sqlite3"))
    if not database_path.is_absolute():
        database_path = config_path.parent.parent / database_path

    raw_sources = payload.get("promo_sources")
    if raw_sources is None:
        # Backwards-compatible loader for old local configs.
        raw_sources = [
            {"type": "telegram", "id": channel, "enabled": True}
            for channel in payload.get("telegram_sources", ())
        ]
    sources = tuple(
        PromoSourceConfig(
            type=str(item["type"]).strip().casefold(),
            id=str(item["id"]).removeprefix("@").strip(),
            enabled=bool(item.get("enabled", True)),
            channel_id=(
                str(item["channel_id"]).strip()
                if item.get("channel_id") is not None
                else None
            ),
        )
        for item in raw_sources
    )

    max_payload = payload.get("max", {})
    return DealsConfig(
        promo_sources=sources,
        max_provider=MaxProviderConfig(
            api_base_url=validate_https_base_url(
                str(max_payload.get("api_base_url", "https://api.maximeter.ru"))
            ),
            api_token_env=str(
                max_payload.get("api_token_env", "MAXIMETER_API_TOKEN")
            ),
            backfill_limit=max(1, min(int(max_payload.get("backfill_limit", 50)), 100)),
            retry_attempts=max(1, int(max_payload.get("retry_attempts", 3))),
            retry_backoff_seconds=max(
                0.0, float(max_payload.get("retry_backoff_seconds", 1))
            ),
        ),
        request_timeout_seconds=max(
            1, min(int(payload.get("request_timeout_seconds", 20)), 60)
        ),
        max_response_bytes=max(
            64 * 1024,
            min(
                int(payload.get("max_response_bytes", DEFAULT_MAX_RESPONSE_BYTES)),
                10 * 1024 * 1024,
            ),
        ),
        visible_confidence_threshold=int(
            payload.get("visible_confidence_threshold", 50)
        ),
        database_path=database_path,
        blocked_keywords=tuple(payload.get("blocked_keywords", ())),
        blocked_link_hosts=tuple(payload.get("blocked_link_hosts", ())),
        merchants={
            key: tuple(value) for key, value in payload.get("merchants", {}).items()
        },
    )
