from __future__ import annotations

import html
import json
import logging
import os
import re
import time
from collections.abc import Callable, Mapping
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .config import MaxProviderConfig, PromoSourceConfig
from .models import RawMessage

LOGGER = logging.getLogger(__name__)
_URL = re.compile(r"https?://[^\s<>\]\[(){}\"']+")
_ZERO_WIDTH = re.compile("[\u200b\u200c\u200d\ufeff]")
JsonLoader = Callable[[Request, int], Mapping[str, Any]]


class MaxSourceConfigurationError(RuntimeError):
    pass


class MaxSourceProvider:
    """Reads public MAX channel posts through MAXimeter's documented REST API."""

    source_type = "max"

    def __init__(
        self,
        config: MaxProviderConfig,
        *,
        timeout_seconds: int = 20,
        api_token: str | None = None,
        json_loader: JsonLoader | None = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        self.config = config
        self.timeout_seconds = timeout_seconds
        self.api_token = api_token or _load_token(config.api_token_env)
        self._json_loader = json_loader or _load_json
        self._sleep = sleep

    def fetch(self, source: PromoSourceConfig) -> list[RawMessage]:
        if source.type != self.source_type:
            raise ValueError(f"MAX provider cannot fetch source type {source.type!r}")
        token = self.api_token or _load_token(self.config.api_token_env)
        if not token:
            raise MaxSourceConfigurationError(
                f"Не задан {self.config.api_token_env}. Добавьте токен MAXimeter "
                "в services/deals_ingestion/.env"
            )
        self.api_token = token

        channel_id = source.channel_id or source.id
        query = urlencode(
            {
                "channel_id": channel_id,
                "limit": self.config.backfill_limit,
                "order_by": "date",
                "order": "desc",
            }
        )
        request = Request(
            f"{self.config.api_base_url}/v1/posts?{query}",
            headers={
                "Accept": "application/json",
                "User-Agent": "QestoDeals/2.0 (+https://github.com/Demakoder/Qesto)",
                "X-API-Token": token,
            },
        )
        payload = self._request_with_retry(request)
        raw_posts = payload.get("posts")
        if not isinstance(raw_posts, list):
            raise ValueError("MAX API response does not contain a posts list")

        messages: list[RawMessage] = []
        for raw_post in raw_posts:
            if not isinstance(raw_post, Mapping):
                continue
            parsed = self._to_message(source, raw_post)
            if parsed is not None:
                messages.append(parsed)
        LOGGER.info("Fetched %s messages from MAX %s", len(messages), source.id)
        return messages

    def _request_with_retry(self, request: Request) -> Mapping[str, Any]:
        for attempt in range(1, self.config.retry_attempts + 1):
            try:
                return self._json_loader(request, self.timeout_seconds)
            except HTTPError as error:
                retryable = error.code == 429 or 500 <= error.code < 600
                if not retryable or attempt == self.config.retry_attempts:
                    if error.code == 401:
                        raise MaxSourceConfigurationError(
                            "MAXimeter отклонил API-токен (HTTP 401)"
                        ) from error
                    if error.code == 402:
                        raise MaxSourceConfigurationError(
                            "Подписка MAXimeter неактивна (HTTP 402)"
                        ) from error
                    raise
                retry_after = error.headers.get("Retry-After") if error.headers else None
                delay = _retry_delay(
                    attempt, self.config.retry_backoff_seconds, retry_after
                )
            except (URLError, TimeoutError, OSError):
                if attempt == self.config.retry_attempts:
                    raise
                delay = self.config.retry_backoff_seconds * (2 ** (attempt - 1))
            LOGGER.warning("MAX request failed; retrying in %.1f seconds", delay)
            self._sleep(delay)
        raise RuntimeError("MAX request retry loop ended unexpectedly")

    @staticmethod
    def _to_message(
        source: PromoSourceConfig, post: Mapping[str, Any]
    ) -> RawMessage | None:
        text = _preprocess_max_text(str(post.get("text") or ""))
        message_id = str(post.get("id") or "").strip()
        if not text or not message_id:
            return None
        url = str(post.get("url") or "").strip()
        if not url:
            url = f"https://max.ru/{source.id}/{message_id}"
        return RawMessage(
            source_type="max",
            source_id=source.id,
            message_id=message_id,
            published_at=_parse_datetime(post.get("published_at")),
            original_text=text,
            original_url=url,
            links=tuple(dict.fromkeys(_clean_url(item) for item in _URL.findall(text))),
        )


def _load_json(request: Request, timeout_seconds: int) -> Mapping[str, Any]:
    with urlopen(request, timeout=timeout_seconds) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, Mapping):
        raise ValueError("MAX API returned a non-object JSON response")
    return payload


def _load_token(environment_name: str) -> str | None:
    direct = os.environ.get(environment_name, "").strip()
    if direct:
        return direct
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if not env_path.exists():
        return None
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        if name.strip() == environment_name:
            return value.strip().strip("'\"") or None
    return None


def _preprocess_max_text(value: str) -> str:
    value = _ZERO_WIDTH.sub("", html.unescape(value)).replace("\r", "")
    lines = [" ".join(line.replace("\xa0", " ").split()) for line in value.split("\n")]
    return "\n".join(line for line in lines if line).strip()


def _parse_datetime(value: object) -> datetime:
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _clean_url(value: str) -> str:
    return value.rstrip(".,;:!?\u00bb")


def _retry_delay(attempt: int, base: float, retry_after: str | None) -> float:
    if retry_after:
        try:
            return min(max(float(retry_after), 0.0), 60.0)
        except ValueError:
            pass
    return base * (2 ** (attempt - 1))
