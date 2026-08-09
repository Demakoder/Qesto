from __future__ import annotations

from typing import Protocol

from .config import PromoSourceConfig
from .models import RawMessage


class SourceProvider(Protocol):
    source_type: str

    def fetch(self, source: PromoSourceConfig) -> list[RawMessage]: ...
