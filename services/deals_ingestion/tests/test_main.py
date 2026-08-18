from __future__ import annotations

import unittest
from unittest.mock import patch

from qesto_deals.__main__ import _is_loopback_host, _sync_token_for_host


class MainSafetyTest(unittest.TestCase):
    def test_loopback_detection_is_fail_closed(self) -> None:
        for host in ["localhost", "127.0.0.1", "::1"]:
            with self.subTest(host=host):
                self.assertTrue(_is_loopback_host(host))
        for host in ["0.0.0.0", "192.168.1.20", "api.example.test", "invalid"]:
            with self.subTest(host=host):
                self.assertFalse(_is_loopback_host(host))

    def test_sync_token_is_rejected_for_non_loopback_server(self) -> None:
        with patch.dict("os.environ", {"QESTO_DEALS_SYNC_TOKEN": "secret"}):
            self.assertEqual("secret", _sync_token_for_host("127.0.0.1"))
            with self.assertRaisesRegex(SystemExit, "non-loopback"):
                _sync_token_for_host("0.0.0.0")


if __name__ == "__main__":
    unittest.main()
