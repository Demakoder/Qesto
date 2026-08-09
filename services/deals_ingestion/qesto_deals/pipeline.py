from __future__ import annotations

import logging
from collections.abc import Iterable

from .config import DealsConfig
from .extractor import RuleBasedOfferExtractor
from .filtering import MessageFilter
from .models import SyncReport
from .source_provider import SourceProvider
from .storage import DealsStorage

LOGGER = logging.getLogger(__name__)


class DealsSyncPipeline:
    def __init__(
        self,
        *,
        config: DealsConfig,
        providers: Iterable[SourceProvider],
        storage: DealsStorage,
    ) -> None:
        self.config = config
        self.providers = {provider.source_type: provider for provider in providers}
        self.storage = storage
        self.filter = MessageFilter(config.blocked_keywords)
        self.extractor = RuleBasedOfferExtractor(config)

    def sync(self) -> SyncReport:
        report = SyncReport()
        for source in self.config.enabled_sources:
            try:
                provider = self.providers.get(source.type)
                if provider is None:
                    raise ValueError(f"No provider registered for {source.type!r}")
                messages = provider.fetch(source)
                report.sources_processed += 1
                report.messages_seen += len(messages)
                for message in messages:
                    if not self.storage.is_message_known(message):
                        report.new_messages += 1
                    self.storage.prepare_message_refresh(message)
                    accepted, reason = self.filter.evaluate(message)
                    if not accepted:
                        report.filtered_messages += 1
                        self.storage.save_message(
                            message,
                            status="filtered",
                            filter_reason=reason,
                        )
                        continue
                    offers = self.extractor.extract(message)
                    self.storage.save_message(
                        message,
                        status="processed" if offers else "no-offers",
                    )
                    for offer in offers:
                        if self.storage.save_offer(offer):
                            report.offers_created += 1
                        else:
                            report.duplicates_found += 1
            except Exception as error:  # A failed source must not stop the others.
                report.sources_failed += 1
                message = (
                    f"{source.type}:{source.id}: {type(error).__name__}: {error}"
                )
                report.errors.append(message)
                LOGGER.exception("Deal source failed: %s", message)
        LOGGER.info(
            "Sync complete: sources=%s failed=%s new=%s filtered=%s "
            "offers=%s duplicates=%s",
            report.sources_processed,
            report.sources_failed,
            report.new_messages,
            report.filtered_messages,
            report.offers_created,
            report.duplicates_found,
        )
        return report
