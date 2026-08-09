from __future__ import annotations

import hashlib
import html
import re
from datetime import date, datetime, timezone
from urllib.parse import urlparse

from .config import DealsConfig
from .filtering import clean_display_text
from .models import Offer, OfferSource, RawMessage


_PROMO_AFTER_KEYWORD = re.compile(
    r"(?i)(?:промокод(?:ом|у)?|промо(?:код)?|код|купон)\s*"
    r"(?::|—|-|–)?\s*([A-Za-zА-Яа-яЁё0-9_-]{4,20})"
)
_PERCENT = re.compile(r"(?<!\d)(?:скидк\w*\s*)?[−–-]?\s*(\d{1,3})\s*%")
_FIXED = re.compile(
    r"(?i)(?:скидк\w*|минус)\s*(?:до\s*)?(\d[\d\s]{0,8})\s*"
    r"(?:₽|руб(?:л(?:ей|я|ь)?)?\.?)(?!\w)"
)
_PRICE_PAIR = re.compile(
    r"(?i)(?:за|теперь)\s*(\d[\d\s]{0,8})\s*₽?\s*"
    r"(?:вместо|было)\s*(\d[\d\s]{0,8})\s*₽?"
)
_MINIMUM = re.compile(
    r"(?i)(?:при\s+заказе\s+от|на\s+заказ\s+от|от\s+сумм[ыа]|"
    r"покупк\w*\s+от|заказ\w*\s+от|\bот)\s*"
    r"(\d[\d\s]{0,8})\s*(?:₽|руб(?:л(?:ей|я|ь)?)?\.?)?"
)
_MAXIMUM = re.compile(
    r"(?i)(?:максим(?:ум|альная\s+скидка)|макс\.?|не\s+более)\s*"
    r"(\d[\d\s]{0,8})\s*(?:₽|руб(?:л(?:ей|я|ь)?)?\.?)?"
)
_NUMERIC_DATE = re.compile(
    r"(?i)(?:до|по|только)\s+(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?"
)
_TEXT_DATE = re.compile(
    r"(?i)(?:до|по|только)\s+(\d{1,2})\s+"
    r"(января|февраля|марта|апреля|мая|июня|июля|августа|"
    r"сентября|октября|ноября|декабря)(?:\s+(\d{4}))?"
)
_TOKEN = re.compile(r"^[A-Za-zА-Яа-яЁё0-9_-]{4,20}$")

_CODE_STOP_WORDS = {
    "промокод",
    "скидка",
    "купон",
    "акция",
    "можно",
    "действует",
    "используйте",
    "примените",
    "заказ",
    "первый",
    "повторный",
    "сегодня",
    "erid",
    "инн",
    "коды",
    "кодов",
    "коду",
    "кода",
    "кодам",
    "кодами",
    "активируем",
    "показываем",
    "суммируется",
}

_MONTHS = {
    "января": 1,
    "февраля": 2,
    "марта": 3,
    "апреля": 4,
    "мая": 5,
    "июня": 6,
    "июля": 7,
    "августа": 8,
    "сентября": 9,
    "октября": 10,
    "ноября": 11,
    "декабря": 12,
}


class RuleBasedOfferExtractor:
    def __init__(self, config: DealsConfig) -> None:
        self.config = config
        aliases: list[tuple[str, str, str]] = []
        for merchant_id, values in config.merchants.items():
            for alias in values:
                aliases.append((alias.casefold().replace("ё", "е"), merchant_id, values[0]))
        self._merchant_aliases = sorted(aliases, key=lambda item: len(item[0]), reverse=True)

    def extract(self, message: RawMessage) -> list[Offer]:
        display_text = clean_display_text(message.original_text)
        promo_codes = self._promo_codes(message)
        header_merchant_id, header_merchant_name = self._merchant(
            self._header_context(message.original_text)
        )
        target_url = self._target_url(message.links)
        post_valid_until = self._valid_until(
            message.original_text, message.published_at
        )
        now = datetime.now(timezone.utc)

        if promo_codes:
            offers = []
            for index, code in enumerate(promo_codes):
                context, code_display_text = self._code_context(
                    message.original_text, code
                )
                line_merchants = self._merchant_matches(code_display_text)
                if len(line_merchants) == 1:
                    merchant_id, merchant_name = line_merchants[0]
                else:
                    merchant_id, merchant_name = (
                        header_merchant_id,
                        header_merchant_name,
                    )
                offers.append(
                    self._build_offer(
                        message=message,
                        display_text=clean_display_text(code_display_text),
                        context=context,
                        promo_code=code,
                        merchant_id=merchant_id,
                        merchant_name=merchant_name,
                        target_url=target_url,
                        valid_until=(
                            self._valid_until(context, message.published_at)
                            or post_valid_until
                        ),
                        index=index,
                        now=now,
                    )
                )
            return offers

        offer_type = self._offer_type(message.original_text, has_code=False)
        if offer_type == "unknown":
            return []
        return [
            self._build_offer(
                message=message,
                display_text=display_text,
                context=message.original_text,
                promo_code=None,
                merchant_id=header_merchant_id,
                merchant_name=header_merchant_name,
                target_url=target_url,
                valid_until=post_valid_until,
                index=0,
                now=now,
            )
        ]

    def _build_offer(
        self,
        *,
        message: RawMessage,
        display_text: str,
        context: str,
        promo_code: str | None,
        merchant_id: str | None,
        merchant_name: str | None,
        target_url: str | None,
        valid_until: str | None,
        index: int,
        now: datetime,
    ) -> Offer:
        discount_type, discount_value = self._discount(context)
        minimum_order = self._amount(_MINIMUM, context)
        maximum_discount = self._amount(_MAXIMUM, context)
        customer_type = self._customer_type(context)
        offer_type = self._offer_type(context, has_code=promo_code is not None)
        confidence = self._confidence(
            has_code=promo_code is not None,
            merchant_id=merchant_id,
            offer_type=offer_type,
            discount_value=discount_value,
            minimum_order=minimum_order,
            valid_until=valid_until,
            target_url=target_url,
        )
        dedupe_key = (
            f"promo:{promo_code.casefold()}"
            if promo_code
            else f"source:{message.source_type}:{message.source_id}:"
            f"{message.message_id}:{index}"
        )
        offer_id = hashlib.sha256(dedupe_key.encode("utf-8")).hexdigest()[:24]
        return Offer(
            id=offer_id,
            type=offer_type,
            merchant_id=merchant_id,
            merchant_name=merchant_name,
            title=self._title(
                display_text,
                merchant_name,
                offer_type,
                discount_type,
                discount_value,
                customer_type,
            ),
            display_text=display_text,
            promo_code=promo_code,
            discount_type=discount_type,
            discount_value=discount_value,
            currency="RUB" if discount_type == "fixed" else None,
            minimum_order=minimum_order,
            maximum_discount=maximum_discount,
            customer_type=customer_type,
            valid_until=valid_until,
            target_url=target_url,
            original_text=message.original_text,
            source=OfferSource(
                source_type=message.source_type,
                source_id=message.source_id,
                message_id=message.message_id,
                url=message.original_url,
            ),
            confidence=confidence,
            created_at=now,
            updated_at=now,
            dedupe_key=dedupe_key,
        )

    def _promo_codes(self, message: RawMessage) -> list[str]:
        result: list[str] = []
        candidates = [
            *((raw, True) for raw in message.formatted_codes),
            *((raw, False) for raw in _PROMO_AFTER_KEYWORD.findall(message.original_text)),
        ]
        for raw, formatted in candidates:
            candidate = raw.strip(" \t:—–-.,!()[]{}\"").upper()
            if self._valid_code(candidate, formatted=formatted) and candidate not in result:
                result.append(candidate)
        return result

    def _valid_code(self, value: str, *, formatted: bool) -> bool:
        folded = value.casefold().replace("ё", "е")
        if not _TOKEN.fullmatch(value) or folded in _CODE_STOP_WORDS:
            return False
        if value.isdigit() or value.startswith("@"):
            return False
        if folded.startswith(("http", "www", "erid", "инн")):
            return False
        if re.fullmatch(r"\d{1,2}[._-]\d{1,2}(?:[._-]\d{2,4})?", value):
            return False
        if any(char.isdigit() for char in value) or any("A" <= char <= "Z" for char in value):
            return True
        return formatted and value == value.upper()

    def _merchant(self, text: str) -> tuple[str | None, str | None]:
        matches = self._merchant_matches(text)
        return matches[0] if matches else (None, None)

    def _merchant_matches(self, text: str) -> list[tuple[str, str]]:
        normalized = text.casefold().replace("ё", "е")
        result: list[tuple[str, str]] = []
        occupied_ranges: list[tuple[int, int]] = []
        for alias, merchant_id, merchant_name in self._merchant_aliases:
            start = normalized.find(alias)
            if start < 0:
                continue
            end = start + len(alias)
            if any(start < occupied_end and end > occupied_start for occupied_start, occupied_end in occupied_ranges):
                continue
            match = (merchant_id, merchant_name)
            occupied_ranges.append((start, end))
            if match not in result:
                result.append(match)
        return result

    def _target_url(self, links: tuple[str, ...]) -> str | None:
        for value in links:
            value = html.unescape(value)
            parsed = urlparse(value)
            host = (parsed.hostname or "").casefold().removeprefix("www.")
            if parsed.scheme not in {"http", "https"} or not host:
                continue
            if any(host == blocked or host.endswith(f".{blocked}") for blocked in self.config.blocked_link_hosts):
                continue
            if parsed.path.casefold().endswith(
                (".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".mp4")
            ):
                continue
            return value
        return None

    def _discount(self, text: str) -> tuple[str, int | None]:
        percent = _PERCENT.search(text)
        if percent:
            value = int(percent.group(1))
            if 0 < value <= 100:
                return "percent", value
        fixed = _FIXED.search(text)
        if fixed:
            return "fixed", _digits(fixed.group(1))
        pair = _PRICE_PAIR.search(text)
        if pair:
            current, previous = _digits(pair.group(1)), _digits(pair.group(2))
            if previous > current:
                return "fixed", previous - current
        return "unknown", None

    def _customer_type(self, text: str) -> str:
        normalized = text.casefold().replace("ё", "е")
        if any(item in normalized for item in ("первый заказ", "первые заказы", "на первый", "для новых", "новым пользовател", "новые пользовател", "первая покупк")):
            return "new"
        if any(item in normalized for item in ("повторный заказ", "повторные заказ", "повторные покупк", "старых пользовател")):
            return "repeat"
        if "для всех" in normalized:
            return "all"
        return "unknown"

    def _offer_type(self, text: str, *, has_code: bool) -> str:
        if has_code:
            return "promo_code"
        normalized = text.casefold().replace("ё", "е")
        if "кэшбэк" in normalized or "cashback" in normalized:
            return "cashback"
        if "бесплатн" in normalized and "достав" in normalized:
            return "free_delivery"
        if "подарок" in normalized:
            return "gift"
        if any(item in normalized for item in ("скидк", "акци", "распродаж", "₽", "%", "вместо")):
            return "deal"
        return "unknown"

    def _valid_until(self, text: str, published_at: datetime) -> str | None:
        normalized = text.casefold().replace("ё", "е")
        if "только сегодня" in normalized:
            return published_at.date().isoformat()
        numeric = _NUMERIC_DATE.search(normalized)
        if numeric:
            return _safe_date(
                int(numeric.group(1)),
                int(numeric.group(2)),
                _full_year(numeric.group(3), published_at.year),
                published_at.date(),
            )
        textual = _TEXT_DATE.search(normalized)
        if textual:
            return _safe_date(
                int(textual.group(1)),
                _MONTHS[textual.group(2)],
                int(textual.group(3) or published_at.year),
                published_at.date(),
            )
        return None

    def _header_context(self, text: str) -> str:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        return lines[0] if lines else ""

    def _code_context(self, text: str, code: str) -> tuple[str, str]:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        token = re.compile(
            rf"(?<![A-Za-zА-Яа-яЁё0-9_-]){re.escape(code)}"
            rf"(?![A-Za-zА-Яа-яЁё0-9_-])",
            re.IGNORECASE,
        )
        matching_indexes = [
            index for index, line in enumerate(lines) if token.search(line)
        ]
        if not matching_indexes:
            return text, text

        offer_indexes: set[int] = set(matching_indexes)
        for index in matching_indexes:
            previous_index = index - 1
            if previous_index >= 0 and self._looks_like_offer_description(
                lines[previous_index]
            ):
                offer_indexes.add(previous_index)
        offer_lines = [lines[index] for index in sorted(offer_indexes)]
        heading = self._nearest_section_heading(lines, matching_indexes[0])
        context_lines = ([heading] if heading else []) + offer_lines
        return "\n".join(context_lines), "\n".join(offer_lines)

    def _looks_like_offer_description(self, line: str) -> bool:
        normalized = line.casefold().replace("ё", "е")
        if line.startswith("🔖"):
            return False
        if any(marker in normalized for marker in ("промокод", "купон", "➕ промо")):
            return False
        return line.startswith("➡️") or any(
            marker in normalized
            for marker in ("скидк", "бесплат", "кешбек", "кэшбэк", "₽", "%")
        )

    def _nearest_section_heading(
        self, lines: list[str], before_index: int
    ) -> str | None:
        for line in reversed(lines[:before_index]):
            normalized = line.casefold().replace("ё", "е")
            if len(line) > 180:
                continue
            if re.match(r"^\d+[.)]\s*", line) and any(
                marker in normalized
                for marker in ("промокод", "перв", "повтор", "магазин", "ресторан")
            ):
                return line
        return None

    def _amount(self, pattern: re.Pattern[str], text: str) -> int | None:
        match = pattern.search(text)
        return _digits(match.group(1)) if match else None

    def _confidence(
        self,
        *,
        has_code: bool,
        merchant_id: str | None,
        offer_type: str,
        discount_value: int | None,
        minimum_order: int | None,
        valid_until: str | None,
        target_url: str | None,
    ) -> int:
        if has_code:
            score = 30
            score += 30 if merchant_id else 0
            score += 15 if discount_value is not None else 0
            score += 10 if minimum_order is not None else 0
            score += 5 if valid_until else 0
            score += 10 if target_url else 0
        else:
            score = 35 if merchant_id else 0
            score += 20 if offer_type != "unknown" else 0
            score += 25 if discount_value is not None else 0
            score += 10 if valid_until else 0
            score += 10 if target_url else 0
        return min(score, 100)

    def _title(
        self,
        display_text: str,
        merchant_name: str | None,
        offer_type: str,
        discount_type: str,
        discount_value: int | None,
        customer_type: str,
    ) -> str:
        subject = merchant_name or {
            "cashback": "Кэшбэк",
            "free_delivery": "Бесплатная доставка",
            "gift": "Подарок при покупке",
            "promo_code": "Промокод",
        }.get(offer_type, "Акция")
        discount = ""
        if discount_value is not None:
            discount = (
                f" — скидка {discount_value}%"
                if discount_type == "percent"
                else f" — скидка {discount_value} ₽"
            )
        customer = {
            "new": " на первый заказ",
            "repeat": " на повторный заказ",
            "all": " для всех",
        }.get(customer_type, "")
        if discount_value is None and customer_type == "unknown":
            first_line = next(
                (line.strip() for line in display_text.splitlines() if line.strip()),
                subject,
            )
            return first_line[:140]
        generated = f"{subject}{discount}{customer}".strip()
        if generated not in {"Акция", "Промокод"}:
            return generated[:140]
        first_line = next((line.strip() for line in display_text.splitlines() if line.strip()), generated)
        return first_line[:140]


def _digits(value: str) -> int:
    return int(re.sub(r"\D", "", value))


def _full_year(value: str | None, fallback: int) -> int:
    if not value:
        return fallback
    parsed = int(value)
    return 2000 + parsed if parsed < 100 else parsed


def _safe_date(day: int, month: int, year: int, published: date) -> str | None:
    try:
        candidate = date(year, month, day)
        if candidate < published and (published - candidate).days > 180:
            candidate = date(year + 1, month, day)
        return candidate.isoformat()
    except ValueError:
        return None
