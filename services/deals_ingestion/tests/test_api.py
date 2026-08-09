from __future__ import annotations

import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import urlopen

from qesto_deals.api import DealsApiServer
from qesto_deals.config import load_config
from qesto_deals.storage import DealsStorage


class _NoopPipeline:
    def sync(self) -> None:
        return None


class DealsApiTest(unittest.TestCase):
    def test_health_and_offers_endpoints(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            storage = DealsStorage(Path(directory) / "test.sqlite3")
            api = DealsApiServer(
                host="127.0.0.1",
                port=0,
                interval_seconds=2700,
                config=load_config(),
                storage=storage,
                pipeline=_NoopPipeline(),  # type: ignore[arg-type]
            )
            server = ThreadingHTTPServer(("127.0.0.1", 0), api._handler_type())
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                port = server.server_address[1]
                with urlopen(f"http://127.0.0.1:{port}/health") as response:
                    health = json.loads(response.read().decode("utf-8"))
                with urlopen(f"http://127.0.0.1:{port}/offers") as response:
                    offers = json.loads(response.read().decode("utf-8"))
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)

        self.assertEqual("ok", health["status"])
        self.assertEqual(0, health["messages"])
        self.assertEqual([], offers["offers"])


if __name__ == "__main__":
    unittest.main()
