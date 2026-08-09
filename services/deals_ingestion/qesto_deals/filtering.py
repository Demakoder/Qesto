from __future__ import annotations

import re

from .models import RawMessage


OFFER_KEYWORDS = (
    "промокод",
    "промо",
    "скидка",
    "скидки",
    "купон",
    "акция",
    "распродажа",
    "кэшбэк",
    "cashback",
    "бесплатная доставка",
    "подарок",
    "₽",
    "%",
)


class MessageFilter:
    def __init__(self, blocked_keywords: tuple[str, ...]) -> None:
        self.blocked_keywords = tuple(item.casefold() for item in blocked_keywords)

    def evaluate(self, message: RawMessage) -> tuple[bool, str]:
        normalized = message.original_text.casefold().replace("ё", "е")
        for blocked in self.blocked_keywords:
            if blocked.casefold().replace("ё", "е") in normalized:
                return False, f"blocked:{blocked}"
        if message.formatted_codes:
            return True, "formatted-promo-code"
        if not any(keyword.casefold() in normalized for keyword in OFFER_KEYWORDS):
            return False, "no-offer-keywords"
        return True, "accepted"


_LEGAL_LINE = re.compile(
    r"(?i)(?:^|\n)\s*(?:реклама\.?|инн\b|ооо\b.*инн|erid\b|рид\b)[^\n]*"
)
_SUBSCRIBE_LINE = re.compile(
    r"(?i)(?:^|\n)\s*[^\n]*(?:подписывай(?:тесь|ся)|наш канал|канал в max|"
    r"канал в вк|скидочн\w* бот|администратор)[^\n]*"
)
_TELEGRAM_SIGNATURE = re.compile(r"(?im)^\s*@[-_a-zA-Z0-9]{4,}\s*$")
_EXCESS_BLANKS = re.compile(r"\n{3,}")


def clean_display_text(value: str) -> str:
    cleaned = _LEGAL_LINE.sub("", value)
    cleaned = _SUBSCRIBE_LINE.sub("", cleaned)
    cleaned = _TELEGRAM_SIGNATURE.sub("", cleaned)
    cleaned = _EXCESS_BLANKS.sub("\n\n", cleaned)
    return cleaned.strip(" \n\t•—-|➡️🎁💝🔥⭐")
