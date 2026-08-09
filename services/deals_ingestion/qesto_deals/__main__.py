from __future__ import annotations

import argparse
import json
import logging

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
    config = load_config(args.config)
    storage = DealsStorage(config.database_path)
    pipeline = DealsSyncPipeline(
        config=config,
        providers=(
            MaxSourceProvider(
                config.max_provider,
                timeout_seconds=config.request_timeout_seconds,
            ),
            TelegramWebPreviewProvider(config.request_timeout_seconds),
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
    ).serve_forever()


if __name__ == "__main__":
    main()
