from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.request import Request, urlopen


OSV_BATCH_URL = "https://api.osv.dev/v1/querybatch"
MAX_OSV_RESPONSE_BYTES = 5 * 1024 * 1024


def main() -> int:
    parser = argparse.ArgumentParser(description="Check Dart/Flutter packages in OSV")
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    project = args.project.resolve()

    dart = shutil.which("dart")
    if dart is None:
        raise RuntimeError("dart executable was not found")
    dart_command = [dart, "pub", "deps", "--json"]
    if os.name == "nt" and Path(dart).suffix.casefold() in {".bat", ".cmd"}:
        dart_command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", *dart_command]

    dependencies = json.loads(
        subprocess.run(
            dart_command,
            cwd=project,
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        ).stdout
    )
    packages = [
        (item["name"], item["version"])
        for item in dependencies["packages"]
        if item.get("source") == "hosted"
    ]
    payload = json.dumps(
        {
            "queries": [
                {
                    "package": {"ecosystem": "Pub", "name": name},
                    "version": version,
                }
                for name, version in packages
            ]
        }
    ).encode("utf-8")
    request = Request(
        OSV_BATCH_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "Qesto-security-check/1.0",
        },
        method="POST",
    )
    with urlopen(request, timeout=30) as response:
        raw = response.read(MAX_OSV_RESPONSE_BYTES + 1)
    if len(raw) > MAX_OSV_RESPONSE_BYTES:
        raise RuntimeError("OSV response exceeded the safety limit")
    results = json.loads(raw.decode("utf-8")).get("results", [])
    if len(results) != len(packages):
        raise RuntimeError("OSV returned an incomplete batch response")

    findings: list[tuple[str, str, str]] = []
    for (name, version), result in zip(packages, results, strict=True):
        for vulnerability in result.get("vulns", []):
            findings.append((name, version, vulnerability.get("id", "unknown")))
    if findings:
        print("Known vulnerable Pub dependencies detected:", file=sys.stderr)
        for name, version, identifier in findings:
            print(f"- {name} {version}: {identifier}", file=sys.stderr)
        return 1
    print(f"OSV reported no known vulnerabilities for {len(packages)} Pub packages.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        print(f"Dependency advisory check failed closed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
