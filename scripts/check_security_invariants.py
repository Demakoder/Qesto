from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    failures: list[str] = []

    required_text = {
        "apps/qesto_app/android/app/src/main/AndroidManifest.xml": (
            'android:allowBackup="false"',
            'android:usesCleartextTraffic="false"',
        ),
        "apps/qesto_app/android/app/build.gradle.kts": (
            "QESTO_ALLOW_DEBUG_RELEASE_SIGNING",
            "Release signing is not configured",
        ),
        "apps/qesto_app/windows/installer/qesto.iss": (
            "SignTool=qesto",
            "SignedUninstaller=yes",
        ),
        "apps/qesto_app/web/_headers": (
            "frame-ancestors 'none'",
            "Strict-Transport-Security:",
            "X-Content-Type-Options: nosniff",
        ),
        "services/deals_ingestion/qesto_deals/api.py": (
            "hmac.compare_digest",
            "BoundedThreadingHTTPServer",
            "_ClientRateLimiter",
        ),
        "services/deals_ingestion/qesto_deals/http_safety.py": (
            "read_limited_response",
            "SameOriginRedirectHandler",
            'parsed.scheme != "https"',
        ),
        "services/deals_ingestion/qesto_deals/models.py": (
            "MAX_MESSAGE_TEXT_CHARS",
            "MAX_LINKS_PER_MESSAGE",
        ),
        "services/deals_ingestion/qesto_deals/storage.py": (
            "MAX_SOURCES_PER_OFFER",
        ),
        "apps/qesto_app/lib/features/benefits/data/bounded_http_response.dart": (
            "readBoundedHttpBody",
            "maximumBytes",
        ),
        "apps/qesto_app/lib/features/benefits/data/telegram_deals_ingestion.dart": (
            "maximumPageBytes",
            "_maximumTelegramMessageChars",
        ),
        "scripts/run_deals_service.cmd": ("--host 127.0.0.1",),
        "scripts/run_qesto.py": ("MAX_HEALTH_RESPONSE_BYTES",),
        "apps/qesto_app/config/open_banking.yaml": ("enabled: false",),
        "apps/qesto_app/windows/whisper/setup_runtime.ps1": (
            "$archiveSha256 =",
            "$modelSha256 =",
            "Get-FileHash",
        ),
        ".github/workflows/ci.yml": (
            "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
            "actions/setup-python@a26af69be951a213d495a4c3e4e4022e16d87065",
            "subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2",
        ),
        ".github/workflows/release-windows.yml": (
            "actions/checkout@11d5960a326750d5838078e36cf38b85af677262",
            "subosito/flutter-action@1a449444c387b1966244ae4d4f8c696479add0b2",
            "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02",
        ),
    }
    for relative, needles in required_text.items():
        path = ROOT / relative
        if not path.is_file():
            failures.append(f"Missing security-critical file: {relative}")
            continue
        source = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in source:
                failures.append(f"{relative} is missing required invariant: {needle}")

    repository_files = _repository_files()
    forbidden_names = []
    for relative in repository_files:
        path = Path(relative)
        lower_name = path.name.casefold()
        if lower_name in {".env", "key.properties"} or path.suffix.casefold() in {
            ".jks",
            ".keystore",
            ".p12",
            ".pfx",
            ".key",
        }:
            forbidden_names.append(relative)
    if forbidden_names:
        failures.append(
            "Repository secret/key files are forbidden: " + ", ".join(forbidden_names)
        )

    secret_patterns = {
        "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
        "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
        "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    }
    for relative in repository_files:
        path = ROOT / relative
        if not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for label, pattern in secret_patterns.items():
            if pattern.search(source):
                failures.append(f"Possible {label} in repository file: {relative}")

    whisper = (ROOT / "apps/qesto_app/windows/whisper/setup_runtime.ps1").read_text(
        encoding="utf-8"
    )
    for variable in ("archiveSha256", "modelSha256"):
        if re.search(rf"\${variable}\s*=\s*'[0-9A-Fa-f]{{64}}'", whisper) is None:
            failures.append(f"Whisper {variable} must be a pinned SHA-256 value")

    if failures:
        print("Security invariant check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"Security invariants passed for {len(repository_files)} repository files.")
    return 0


def _repository_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [
        value.decode("utf-8")
        for value in result.stdout.split(b"\0")
        if value
    ]


if __name__ == "__main__":
    raise SystemExit(main())
