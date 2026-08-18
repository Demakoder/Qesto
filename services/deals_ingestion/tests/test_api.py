from __future__ import annotations

import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from qesto_deals.api import DealsApiServer
from qesto_deals.config import load_config
from qesto_deals.storage import DealsStorage


class _NoopPipeline:
    def sync(self) -> None:
        return None


class DealsApiTest(unittest.TestCase):
    def test_health_and_offers_endpoints(self) -> None:
        with self._running_server() as base_url:
            with urlopen(f"{base_url}/health") as response:
                health = json.loads(response.read().decode("utf-8"))
            with urlopen(f"{base_url}/offers") as response:
                offers = json.loads(response.read().decode("utf-8"))

        self.assertEqual("ok", health["status"])
        self.assertEqual(0, health["messages"])
        self.assertEqual([], offers["offers"])

    def test_sync_is_disabled_without_a_token(self) -> None:
        with self._running_server() as base_url:
            request = Request(f"{base_url}/sync", method="POST")
            with self.assertRaises(HTTPError) as caught:
                urlopen(request)
        self.assertEqual(403, caught.exception.code)

    def test_sync_requires_the_configured_bearer_token(self) -> None:
        with self._running_server(sync_token="test-token") as base_url:
            rejected = Request(f"{base_url}/sync", method="POST")
            with self.assertRaises(HTTPError) as caught:
                urlopen(rejected)
            accepted = Request(
                f"{base_url}/sync",
                method="POST",
                headers={"Authorization": "Bearer test-token"},
            )
            with urlopen(accepted) as response:
                payload = json.loads(response.read().decode("utf-8"))
        self.assertEqual(401, caught.exception.code)
        self.assertTrue(payload["started"])

    def test_cors_rejects_unknown_browser_origin(self) -> None:
        with self._running_server() as base_url:
            request = Request(
                f"{base_url}/health",
                headers={"Origin": "https://attacker.example"},
            )
            with urlopen(request) as response:
                self.assertIsNone(response.headers.get("Access-Control-Allow-Origin"))

    def _running_server(
        self,
        *,
        sync_token: str | None = None,
    ) -> _RunningDealsServer:
        return _RunningDealsServer(sync_token=sync_token)


class _RunningDealsServer:
    def __init__(self, *, sync_token: str | None) -> None:
        self.sync_token = sync_token
        self.directory = tempfile.TemporaryDirectory()

    def __enter__(self) -> str:
        storage = DealsStorage(Path(self.directory.name) / "test.sqlite3")
        api = DealsApiServer(
            host="127.0.0.1",
            port=0,
            interval_seconds=2700,
            config=load_config(),
            storage=storage,
            pipeline=_NoopPipeline(),  # type: ignore[arg-type]
            sync_token=self.sync_token,
        )
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), api._handler_type())
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def __exit__(self, *_: object) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.directory.cleanup()


if __name__ == "__main__":
    unittest.main()
