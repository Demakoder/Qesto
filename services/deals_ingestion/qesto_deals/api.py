from __future__ import annotations

import json
import logging
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .config import DealsConfig
from .pipeline import DealsSyncPipeline
from .storage import DealsStorage

LOGGER = logging.getLogger(__name__)


class DealsApiServer:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        interval_seconds: int,
        config: DealsConfig,
        storage: DealsStorage,
        pipeline: DealsSyncPipeline,
    ) -> None:
        self.host = host
        self.port = port
        self.interval_seconds = interval_seconds
        self.config = config
        self.storage = storage
        self.pipeline = pipeline
        self._sync_lock = threading.Lock()
        self._stop = threading.Event()
        self._last_sync_report: dict[str, object] | None = None

    def serve_forever(self) -> None:
        self._sync_async()
        scheduler = threading.Thread(target=self._schedule, daemon=True)
        scheduler.start()
        handler = self._handler_type()
        server = ThreadingHTTPServer((self.host, self.port), handler)
        LOGGER.info("Qesto Deals API listening on http://%s:%s", self.host, self.port)
        try:
            server.serve_forever()
        finally:
            self._stop.set()
            server.server_close()

    def _schedule(self) -> None:
        while not self._stop.wait(self.interval_seconds):
            self._sync_async()

    def _sync_async(self) -> bool:
        if not self._sync_lock.acquire(blocking=False):
            return False

        def run() -> None:
            try:
                result = self.pipeline.sync()
                if result is not None and hasattr(result, "to_dict"):
                    self._last_sync_report = result.to_dict()
            finally:
                self._sync_lock.release()

        threading.Thread(target=run, daemon=True).start()
        return True

    def _handler_type(self) -> type[BaseHTTPRequestHandler]:
        api = self

        class Handler(BaseHTTPRequestHandler):
            def do_OPTIONS(self) -> None:  # noqa: N802
                self.send_response(HTTPStatus.NO_CONTENT)
                self._cors_headers()
                self.end_headers()

            def do_GET(self) -> None:  # noqa: N802
                parsed = urlparse(self.path)
                if parsed.path == "/health":
                    self._json(
                        HTTPStatus.OK,
                        {
                            "status": "ok",
                            "source_types": sorted(
                                {source.type for source in api.config.enabled_sources}
                            ),
                            "last_sync": api._last_sync_report,
                            **api.storage.counts(),
                        },
                    )
                    return
                if parsed.path == "/offers":
                    query = parse_qs(parsed.query)
                    raw_limit = query.get("limit", ["200"])[0]
                    try:
                        limit = int(raw_limit)
                    except ValueError:
                        self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid limit"})
                        return
                    kind = query.get("kind", [None])[0]
                    offers = api.storage.list_offers(
                        minimum_confidence=api.config.visible_confidence_threshold,
                        kind=kind,
                        limit=limit,
                    )
                    self._json(
                        HTTPStatus.OK,
                        {"offers": offers, "count": len(offers)},
                    )
                    return
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

            def do_POST(self) -> None:  # noqa: N802
                if urlparse(self.path).path != "/sync":
                    self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                    return
                started = api._sync_async()
                self._json(
                    HTTPStatus.ACCEPTED if started else HTTPStatus.CONFLICT,
                    {"started": started},
                )

            def log_message(self, format: str, *args: object) -> None:
                LOGGER.info("API %s - %s", self.address_string(), format % args)

            def _json(self, status: HTTPStatus, payload: object) -> None:
                encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(encoded)))
                self._cors_headers()
                self.end_headers()
                self.wfile.write(encoded)

            def _cors_headers(self) -> None:
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")

        return Handler
