from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parent.parent
APP_DIRECTORY = ROOT / "apps" / "qesto_app"
SERVICE_DIRECTORY = ROOT / "services" / "deals_ingestion"
SERVICE_HEALTH_URL = "http://127.0.0.1:8787/health"
SERVICE_LOG = SERVICE_DIRECTORY / "data" / "service.log"


def _service_is_ready() -> bool:
    try:
        with urlopen(SERVICE_HEALTH_URL, timeout=0.75) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return response.status == 200 and payload.get("status") == "ok"
    except (OSError, URLError, ValueError, json.JSONDecodeError):
        return False


def _start_service() -> subprocess.Popen[bytes] | None:
    if _service_is_ready():
        print("Qesto: сервис акций уже запущен.")
        return None

    SERVICE_LOG.parent.mkdir(parents=True, exist_ok=True)
    creation_flags = 0
    if os.name == "nt":
        creation_flags = (
            subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        )
    with SERVICE_LOG.open("ab") as log:
        process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "qesto_deals",
                "serve",
                "--host",
                "0.0.0.0",
                "--port",
                "8787",
                "--interval",
                "2700",
            ],
            cwd=SERVICE_DIRECTORY,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            creationflags=creation_flags,
        )

    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if _service_is_ready():
            print("Qesto: сервис акций готов.")
            return process
        return_code = process.poll()
        if return_code is not None:
            raise RuntimeError(
                f"Сервис акций завершился с кодом {return_code}. "
                f"Лог: {SERVICE_LOG}"
            )
        time.sleep(0.25)

    process.terminate()
    raise RuntimeError(f"Сервис акций не запустился. Лог: {SERVICE_LOG}")


def _local_ip() -> str:
    connection = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        connection.connect(("8.8.8.8", 80))
        return str(connection.getsockname()[0])
    except OSError:
        return "127.0.0.1"
    finally:
        connection.close()


def _flutter_device_platform(flutter: str, device: str) -> str | None:
    try:
        result = subprocess.run(
            [flutter, "devices", "--machine"],
            capture_output=True,
            check=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
        )
        devices = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None
    for item in devices:
        if str(item.get("id", "")).casefold() == device.casefold():
            return str(item.get("targetPlatform", ""))
    return None


def _find_adb() -> str | None:
    from_path = shutil.which("adb")
    if from_path:
        return from_path
    roots = [
        os.environ.get("ANDROID_HOME"),
        os.environ.get("ANDROID_SDK_ROOT"),
        str(Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk"),
    ]
    for root in roots:
        if not root:
            continue
        candidate = Path(root) / "platform-tools" / "adb.exe"
        if candidate.is_file():
            return str(candidate)
    return None


def _android_api_url(device: str) -> str:
    adb = _find_adb()
    if adb:
        try:
            result = subprocess.run(
                [adb, "-s", device, "reverse", "tcp:8787", "tcp:8787"],
                capture_output=True,
                check=False,
                encoding="utf-8",
                errors="replace",
                timeout=15,
            )
            if result.returncode == 0:
                print("Qesto: Android подключён к сервису через USB.")
                return "http://127.0.0.1:8787"
            detail = result.stderr.strip() or result.stdout.strip()
            print(f"Qesto: adb reverse недоступен ({detail}).")
        except (OSError, subprocess.SubprocessError) as error:
            print(f"Qesto: не удалось настроить adb reverse ({error}).")
    address = _local_ip()
    print(
        "Qesto: Android подключается по Wi-Fi. Телефон и компьютер должны "
        f"быть в одной сети; адрес сервиса: {address}:8787"
    )
    return f"http://{address}:8787"


def _reverse_connected_android_devices() -> int:
    """Expose the local API to every authorized USB Android device."""
    adb = _find_adb()
    if not adb:
        return 0
    try:
        result = subprocess.run(
            [adb, "devices"],
            capture_output=True,
            check=False,
            encoding="utf-8",
            errors="replace",
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return 0
    device_ids = []
    for line in result.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            device_ids.append(parts[0])
    configured = 0
    for device_id in device_ids:
        try:
            reverse = subprocess.run(
                [adb, "-s", device_id, "reverse", "tcp:8787", "tcp:8787"],
                capture_output=True,
                check=False,
                encoding="utf-8",
                errors="replace",
                timeout=15,
            )
        except (OSError, subprocess.SubprocessError):
            continue
        if reverse.returncode == 0:
            configured += 1
    if configured:
        print(f"Qesto: USB-доступ к сервису настроен для Android: {configured}.")
    return configured


def _flutter_command(device: str | None, extra_args: list[str]) -> list[str]:
    flutter = shutil.which("flutter")
    if not flutter:
        raise RuntimeError("Flutter не найден в PATH.")
    command = [flutter, "run"]
    if device:
        command.extend(("-d", device))
    if device:
        platform = _flutter_device_platform(flutter, device)
        if platform and platform.casefold().startswith("android"):
            api_url = _android_api_url(device)
            command.append(f"--dart-define=QESTO_DEALS_API_URL={api_url}")
        elif device.casefold() not in {"edge", "chrome", "windows"}:
            command.append(
                "--dart-define="
                f"QESTO_DEALS_API_URL=http://{_local_ip()}:8787"
            )
    command.extend(extra_args)
    return command


def _stop_owned_service(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Qesto with its local services")
    parser.add_argument("--service-only", action="store_true")
    parser.add_argument("--device", help="Flutter device id; defaults to Edge")
    parser.add_argument(
        "flutter_args",
        nargs=argparse.REMAINDER,
        help="Extra flutter run arguments after --",
    )
    args = parser.parse_args()

    owned_service = _start_service()
    if args.service_only:
        _reverse_connected_android_devices()
        return 0

    device = args.device or "edge"
    command = _flutter_command(device, args.flutter_args)
    print(f"Qesto: запуск Flutter на устройстве {device}.")
    try:
        return subprocess.call(command, cwd=APP_DIRECTORY)
    except KeyboardInterrupt:
        return 130
    finally:
        _stop_owned_service(owned_service)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"Qesto: {error}", file=sys.stderr)
        raise SystemExit(1) from error
