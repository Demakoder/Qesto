from __future__ import annotations

from typing import Any
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import HTTPRedirectHandler, OpenerDirector, build_opener


DEFAULT_MAX_RESPONSE_BYTES = 5 * 1024 * 1024


def validate_https_base_url(value: str) -> str:
    if any(ord(character) <= 32 for character in value):
        raise ValueError("External API base URL must not contain whitespace")
    normalized = value.rstrip("/")
    parsed = urlparse(normalized)
    try:
        parsed.port
    except ValueError as error:
        raise ValueError("External API base URL contains an invalid port") from error
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("External API base URL must be a credential-free HTTPS URL")
    return normalized


def read_limited_response(response: Any, maximum_bytes: int) -> bytes:
    if maximum_bytes <= 0:
        raise ValueError("Response byte limit must be positive")

    declared_length = response.headers.get("Content-Length")
    if declared_length:
        try:
            parsed_length = int(declared_length)
        except (TypeError, ValueError):
            parsed_length = None
        if parsed_length is not None and (
            parsed_length < 0 or parsed_length > maximum_bytes
        ):
            raise ValueError("Remote response exceeds the configured byte limit")

    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = response.read(min(64 * 1024, maximum_bytes - total + 1))
        if not chunk:
            break
        total += len(chunk)
        if total > maximum_bytes:
            raise ValueError("Remote response exceeds the configured byte limit")
        chunks.append(chunk)
    return b"".join(chunks)


class SameOriginRedirectHandler(HTTPRedirectHandler):
    def redirect_request(
        self,
        request: Any,
        file_pointer: Any,
        code: int,
        message: str,
        headers: Any,
        new_url: str,
    ) -> Any:
        resolved = urljoin(request.full_url, new_url)
        if _origin(request.full_url) != _origin(resolved):
            raise HTTPError(
                request.full_url,
                code,
                "Cross-origin redirect blocked to protect API credentials",
                headers,
                file_pointer,
            )
        return super().redirect_request(
            request,
            file_pointer,
            code,
            message,
            headers,
            resolved,
        )


def same_origin_opener() -> OpenerDirector:
    return build_opener(SameOriginRedirectHandler())


def _origin(value: str) -> tuple[str, str, int | None]:
    parsed = urlparse(value)
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80 if parsed.scheme == "http" else None
    return parsed.scheme.casefold(), (parsed.hostname or "").casefold(), port
