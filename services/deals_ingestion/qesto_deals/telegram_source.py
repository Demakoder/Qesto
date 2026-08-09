from __future__ import annotations

import logging
from datetime import datetime, timezone
from html.parser import HTMLParser
from urllib.request import Request, urlopen

from .config import PromoSourceConfig
from .models import RawMessage

LOGGER = logging.getLogger(__name__)


class TelegramWebPreviewProvider:
    source_type = "telegram"

    def __init__(self, timeout_seconds: int = 20) -> None:
        self.timeout_seconds = timeout_seconds

    def fetch(self, source: PromoSourceConfig) -> list[RawMessage]:
        if source.type != self.source_type:
            raise ValueError(
                f"Telegram provider cannot fetch source type {source.type!r}"
            )
        normalized = source.id.removeprefix("@").strip()
        request = Request(
            f"https://t.me/s/{normalized}",
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (compatible; QestoDeals/1.0; "
                    "+https://github.com/Demakoder/Qesto)"
                )
            },
        )
        with urlopen(request, timeout=self.timeout_seconds) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            html = response.read().decode(charset, errors="replace")
        parser = _TelegramPreviewParser(normalized)
        parser.feed(html)
        parser.close()
        LOGGER.info("Fetched %s messages from @%s", len(parser.messages), normalized)
        return parser.messages


class _TelegramPreviewParser(HTMLParser):
    def __init__(self, expected_channel: str) -> None:
        super().__init__(convert_charrefs=True)
        self.expected_channel = expected_channel
        self.messages: list[RawMessage] = []
        self._current: dict[str, object] | None = None
        self._div_depth = 0
        self._text_container_depth: int | None = None
        self._in_code = False
        self._code_buffer: list[str] = []

    def handle_starttag(self, tag: str, attrs_list: list[tuple[str, str | None]]) -> None:
        attrs = dict(attrs_list)
        classes = set((attrs.get("class") or "").split())
        if self._current is None:
            data_post = attrs.get("data-post")
            if tag == "div" and data_post and "js-widget_message" in classes:
                channel, _, raw_id = data_post.rpartition("/")
                if channel and raw_id.isdigit():
                    self._current = {
                        "channel": channel,
                        "message_id": int(raw_id),
                        "text": [],
                        "links": [],
                        "codes": [],
                        "published_at": None,
                    }
                    self._div_depth = 1
            return

        if tag == "div":
            self._div_depth += 1
            if "js-message_text" in classes:
                self._text_container_depth = self._div_depth
        if self._text_container_depth is not None and tag == "br":
            self._append_text("\n")
        if self._text_container_depth is not None and tag == "code":
            self._in_code = True
            self._code_buffer = []
        if tag == "a" and attrs.get("href"):
            links = self._current["links"]
            assert isinstance(links, list)
            links.append(attrs["href"])
        if tag == "time" and attrs.get("datetime"):
            self._current["published_at"] = attrs["datetime"]

    def handle_endtag(self, tag: str) -> None:
        if self._current is None:
            return
        if tag == "code" and self._in_code:
            code = "".join(self._code_buffer).strip()
            if code:
                codes = self._current["codes"]
                assert isinstance(codes, list)
                codes.append(code)
            self._in_code = False
            self._code_buffer = []
        if tag != "div":
            return
        if self._text_container_depth == self._div_depth:
            self._text_container_depth = None
        self._div_depth -= 1
        if self._div_depth == 0:
            self._finish_message()

    def handle_data(self, data: str) -> None:
        if self._current is None or self._text_container_depth is None:
            return
        self._append_text(data)
        if self._in_code:
            self._code_buffer.append(data)

    def _append_text(self, value: str) -> None:
        assert self._current is not None
        text = self._current["text"]
        assert isinstance(text, list)
        text.append(value)

    def _finish_message(self) -> None:
        assert self._current is not None
        channel = str(self._current["channel"])
        message_id = int(self._current["message_id"])
        published_at = _parse_datetime(self._current.get("published_at"))
        text = _normalize_text("".join(self._current["text"]))
        links = tuple(dict.fromkeys(str(item) for item in self._current["links"]))
        codes = tuple(dict.fromkeys(str(item).strip() for item in self._current["codes"]))
        if text:
            self.messages.append(
                RawMessage(
                    source_type="telegram",
                    source_id=channel,
                    message_id=str(message_id),
                    published_at=published_at,
                    original_text=text,
                    original_url=f"https://t.me/{channel}/{message_id}",
                    links=links,
                    formatted_codes=codes,
                )
            )
        self._current = None
        self._div_depth = 0
        self._text_container_depth = None


def _parse_datetime(value: object) -> datetime:
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return datetime.now(timezone.utc)


def _normalize_text(value: str) -> str:
    lines = [" ".join(line.split()) for line in value.replace("\r", "").split("\n")]
    return "\n".join(line for line in lines if line).strip()
