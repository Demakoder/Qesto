from __future__ import annotations

import hmac
import json
import logging
import threading
import time
from collections import defaultdict, deque
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from .config import DealsConfig
from .pipeline import DealsSyncPipeline
from .storage import DealsStorage

LOGGER = logging.getLogger(__name__)


class BoundedThreadingHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 32

    def __init__(self, server_address: tuple[str, int], handler: type, limit: int = 32):
        self._request_slots = threading.BoundedSemaphore(limit)
        super().__init__(server_address, handler)

    def process_request(self, request: object, client_address: object) -> None:
        if not self._request_slots.acquire(blocking=False):
            try:
                request.close()  # type: ignore[attr-defined]
            finally:
                return
        try:
            super().process_request(request, client_address)  # type: ignore[arg-type]
        except BaseException:
            self._request_slots.release()
            raise

    def process_request_thread(self, request: object, client_address: object) -> None:
        try:
            super().process_request_thread(request, client_address)  # type: ignore[arg-type]
        finally:
            self._request_slots.release()


class _ClientRateLimiter:
    def __init__(self, maximum_requests: int = 120, window_seconds: float = 60) -> None:
        self.maximum_requests = maximum_requests
        self.window_seconds = window_seconds
        self._requests: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()
        self._last_cleanup = 0.0

    def allow(self, client: str) -> bool:
        now = time.monotonic()
        threshold = now - self.window_seconds
        with self._lock:
            if now - self._last_cleanup >= self.window_seconds:
                for key, history in list(self._requests.items()):
                    while history and history[0] <= threshold:
                        history.popleft()
                    if not history:
                        self._requests.pop(key, None)
                self._last_cleanup = now
            requests = self._requests[client]
            while requests and requests[0] <= threshold:
                requests.popleft()
            if len(requests) >= self.maximum_requests:
                return False
            requests.append(now)
            return True


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
        sync_token: str | None = None,
        allowed_origins: set[str] | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self.interval_seconds = interval_seconds
        self.config = config
        self.storage = storage
        self.pipeline = pipeline
        self.sync_token = sync_token
        self.allowed_origins = allowed_origins or set()
        self._rate_limiter = _ClientRateLimiter()
        self._sync_lock = threading.Lock()
        self._stop = threading.Event()
        self._last_sync_report: dict[str, object] | None = None

    def serve_forever(self) -> None:
        self._sync_async()
        scheduler = threading.Thread(target=self._schedule, daemon=True)
        scheduler.start()
        handler = self._handler_type()
        server = BoundedThreadingHTTPServer((self.host, self.port), handler)
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
                if not self._request_is_allowed():
                    return
                if not self._origin_is_allowed():
                    self._json(HTTPStatus.FORBIDDEN, {"error": "origin not allowed"})
                    return
                self.send_response(HTTPStatus.NO_CONTENT)
                self._security_headers()
                self._cors_headers()
                self.end_headers()

            def do_GET(self) -> None:  # noqa: N802
                if not self._request_is_allowed():
                    return
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
                if not self._request_is_allowed():
                    return
                if urlparse(self.path).path != "/sync":
                    self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                    return
                if api.sync_token is None:
                    self._json(HTTPStatus.FORBIDDEN, {"error": "sync disabled"})
                    return
                authorization = self.headers.get("Authorization", "")
                expected = f"Bearer {api.sync_token}"
                if not hmac.compare_digest(authorization, expected):
                    self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
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
                self._security_headers()
                self._cors_headers()
                self.end_headers()
                self.wfile.write(encoded)

            def _cors_headers(self) -> None:
                origin = self.headers.get("Origin")
                if origin is None or not self._origin_is_allowed():
                    return
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header(
                    "Access-Control-Allow-Headers",
                    "Authorization, Content-Type",
                )

            def _origin_is_allowed(self) -> bool:
                origin = self.headers.get("Origin")
                if origin is None:
                    return True
                if origin in api.allowed_origins:
                    return True
                parsed = urlparse(origin)
                return (
                    parsed.scheme in {"http", "https"}
                    and parsed.hostname in {"localhost", "127.0.0.1", "::1"}
                )

            def _request_is_allowed(self) -> bool:
                client = self.client_address[0] if self.client_address else "unknown"
                if api._rate_limiter.allow(client):
                    return True
                self._json(HTTPStatus.TOO_MANY_REQUESTS, {"error": "rate limited"})
                return False

            def _security_headers(self) -> None:
                self.send_header("Cache-Control", "no-store")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.send_header("Referrer-Policy", "no-referrer")

        return Handler
