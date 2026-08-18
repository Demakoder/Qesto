from __future__ import annotations

import io
import unittest
from email.message import Message
from urllib.error import HTTPError
from urllib.request import Request

from qesto_deals.http_safety import (
    SameOriginRedirectHandler,
    read_limited_response,
    validate_https_base_url,
)


class _Response:
    def __init__(self, payload: bytes, declared_length: str | None = None) -> None:
        self._stream = io.BytesIO(payload)
        self.headers = Message()
        if declared_length is not None:
            self.headers["Content-Length"] = declared_length

    def read(self, size: int) -> bytes:
        return self._stream.read(size)


class HttpSafetyTest(unittest.TestCase):
    def test_reads_only_up_to_the_configured_response_limit(self) -> None:
        response = _Response(b"a" * 11)
        with self.assertRaisesRegex(ValueError, "byte limit"):
            read_limited_response(response, 10)

    def test_rejects_oversized_declared_content_length_before_reading(self) -> None:
        response = _Response(b"small", declared_length="100")
        with self.assertRaisesRegex(ValueError, "byte limit"):
            read_limited_response(response, 10)

    def test_requires_a_credential_free_https_base_url(self) -> None:
        self.assertEqual(
            "https://api.example.test",
            validate_https_base_url("https://api.example.test/"),
        )
        for value in [
            "http://api.example.test",
            "https://token@api.example.test",
            "https://api.example.test?redirect=evil",
            "https://api.example.test:invalid",
            "https://api.example.test/path\n",
        ]:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    validate_https_base_url(value)

    def test_cross_origin_redirect_is_blocked_before_credentials_are_forwarded(
        self,
    ) -> None:
        request = Request(
            "https://api.example.test/v1/posts",
            headers={"Authorization": "Bearer secret"},
        )
        with self.assertRaisesRegex(HTTPError, "credentials"):
            SameOriginRedirectHandler().redirect_request(
                request,
                io.BytesIO(),
                302,
                "Found",
                Message(),
                "https://evil.example.test/steal",
            )


if __name__ == "__main__":
    unittest.main()
