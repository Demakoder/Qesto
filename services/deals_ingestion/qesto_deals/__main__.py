from __future__ import annotations

import argparse
import ipaddress
import json
import logging
import os

from .api import DealsApiServer
from .config import load_config
from .max_source import MaxSourceProvider
from .pipeline import DealsSyncPipeline
from .storage import DealsStorage
from .telegram_source import TelegramWebPreviewProvider


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Qesto deals ingestion")
    parser.add_argument("--config", help="Path to sources.json")
    parser.add_argument("--verbose", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("sync", help="Run one synchronization")
    serve = subparsers.add_parser("serve", help="Run JSON API and scheduler")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8787)
    serve.add_argument("--interval", type=int, default=2700)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    sync_token = (
        _sync_token_for_host(args.host) if args.command == "serve" else None
    )
    config = load_config(args.config)
    storage = DealsStorage(config.database_path)
    pipeline = DealsSyncPipeline(
        config=config,
        providers=(
            MaxSourceProvider(
                config.max_provider,
                timeout_seconds=config.request_timeout_seconds,
                max_response_bytes=config.max_response_bytes,
            ),
            TelegramWebPreviewProvider(
                config.request_timeout_seconds,
                max_response_bytes=config.max_response_bytes,
            ),
        ),
        storage=storage,
    )
    if args.command == "sync":
        print(json.dumps(pipeline.sync().to_dict(), ensure_ascii=False, indent=2))
        return
    DealsApiServer(
        host=args.host,
        port=args.port,
        interval_seconds=max(60, args.interval),
        config=config,
        storage=storage,
        pipeline=pipeline,
        sync_token=sync_token,
        allowed_origins={
            value.strip()
            for value in os.environ.get("QESTO_DEALS_ALLOWED_ORIGINS", "").split(",")
            if value.strip()
        },
    ).serve_forever()


def _is_loopback_host(host: str) -> bool:
    if host.casefold() == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _sync_token_for_host(host: str) -> str | None:
    token = os.environ.get("QESTO_DEALS_SYNC_TOKEN") or None
    if token is not None and not _is_loopback_host(host):
        raise SystemExit(
            "Refusing to expose QESTO_DEALS_SYNC_TOKEN over non-loopback HTTP"
        )
    return token


if __name__ == "__main__":
    main()
