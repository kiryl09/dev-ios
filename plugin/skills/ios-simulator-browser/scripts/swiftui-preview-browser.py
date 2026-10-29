#!/usr/bin/env python3
"""Swift Package preview host launcher with hot reload on Simulator."""

from __future__ import annotations

import hashlib
import json
import locale
import os
import re
import unicodedata
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass
from datetime import datetime
from functools import cmp_to_key
from pathlib import Path
from typing import Any, Callable

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR / "lib"))
from xcode_project import (  # noqa: E402
    create_package_project_file,
    generated_package_configuration_swift_source,
)

TARGET_NAME = "PreviewHost"
PACKAGE_PLUGIN_TARGET_NAME = "PreviewReloadPlugin"
BUNDLE_ID = "dev.swiftui-preview-browser.host"
HOT_RELOAD_NOTIFICATION = "dev.swiftui-preview-browser.reload"
TEMPLATE_ROOT = SCRIPT_DIR / "templates"
TEMPLATE_FILE_NAMES = (
    "FocusedPreviewApp.swift",
    "FocusedPreviewHotReloadRuntime.swift",
    "PreviewBrowserEntries.swift",
)
CONFIGURATION_FILE_NAME = "PreviewBrowserConfiguration.swift"
SKIP_WATCH_DIRS = frozenset({".build", ".git", ".swiftpm"})
_COLLATE_LOCALE_READY = False


def _ensure_collate_locale() -> None:
    global _COLLATE_LOCALE_READY
    if _COLLATE_LOCALE_READY:
        return
    for candidate in ("", "C.UTF-8", "C"):
        try:
            locale.setlocale(locale.LC_COLLATE, candidate)
            break
        except locale.Error:
            continue
    _COLLATE_LOCALE_READY = True


def normalize_product_name(name: str) -> str:
    return unicodedata.normalize("NFC", name or "")


def collate_product_names(left: str, right: str) -> int:
    _ensure_collate_locale()
    left_name = normalize_product_name(left)
    right_name = normalize_product_name(right)
    try:
        return locale.strcoll(left_name, right_name)
    except (ValueError, TypeError):
        if left_name.casefold() < right_name.casefold():
            return -1
        if left_name.casefold() > right_name.casefold():
            return 1
        return 0


@dataclass
class ParseOptions:
    packageSwiftPath: str | None = None
    device: str | None = None
    packageTarget: str | None = None
    previewFilters: list[str] | None = None
    help: bool = False


@dataclass
class LauncherState:
    project_root: Path
    build_root: Path
    package_preview_configuration: dict[str, Any]
    udid: str
    data_container: Path | None = None
    app_pid: int | None = None
    preview_name: str = ""
    hot_reloading: bool = False
    hot_reload_queued: bool = False


def parse_preview_filters(value: str) -> list[str]:
    filters = [part.strip() for part in value.split(",") if part.strip()]
    if not filters:
        raise ValueError("Pass at least one non-empty value to --preview-filter.")
    return filters


def parse_args(argv: list[str]) -> ParseOptions:
    options = ParseOptions()
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg in ("--help", "-h"):
            options.help = True
        elif arg in ("--device", "-d"):
            index += 1
            options.device = argv[index]
        elif arg == "--package-target":
            index += 1
            options.packageTarget = argv[index]
        elif arg == "--preview-filter":
            index += 1
            options.previewFilters = parse_preview_filters(argv[index])
        elif not options.packageSwiftPath:
            options.packageSwiftPath = arg
        else:
            raise ValueError(f"Unexpected argument: {arg}")
        index += 1

    if not options.help and not options.packageSwiftPath:
        raise ValueError("Pass the path to Package.swift.")
    if not options.help and not options.packageTarget:
        raise ValueError(
            "Pass --package-target <target> to choose which Swift Package target to preview."
        )
    if not options.help and not options.device:
        raise ValueError("Pass --device <simulator-udid> to choose the Simulator explicitly.")
    return options


def print_help() -> None:
    print(
        """swiftui-preview-browser

Render SwiftUI previews from one Swift Package target in an iOS Simulator.

Usage:
  swiftui-preview-browser <Package.swift> --package-target <target> --device <simulator-udid>

Options:
  --package-target  Swift Package target to scan. Required.
  --preview-filter  Comma-separated regex filters matched against preview names and identifiers.
  --device, -d      Simulator UDID. Required.
"""
    )


def resolve_package_swift_path(file_arg: str) -> Path:
    resolved = Path(file_arg).resolve()
    if not resolved.is_file() or resolved.name != "Package.swift":
        raise ValueError(f"Package.swift not found: {resolved}")
    return resolved


def default_scratch_root(package_swift_path: Path, package_preview_configuration: dict[str, Any]) -> Path:
    identity = json.dumps(
        {
            "packageSwiftPath": str(package_swift_path),
            "packageModule": package_preview_configuration["packageModule"],
            "previewFilters": package_preview_configuration.get("previewFilters"),
        },
        separators=(",", ":"),
    )
    scratch_id = hashlib.sha256(identity.encode()).hexdigest()[:12]
    return Path(tempfile.gettempdir()) / "swiftui-preview-browser" / scratch_id


def log(message: str) -> None:
    try:
        timestamp = datetime.now().strftime("%-I:%M:%S %p")
    except ValueError:
        timestamp = datetime.now().strftime("%I:%M:%S %p").lstrip("0")
    print(f"[{timestamp}] {message}")


def run_json(command: str, args: list[str]) -> Any:
    try:
        result = subprocess.run(
            [command, *args],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as error:
        detail = error.stderr or error.stdout or str(error)
        raise ValueError(f"{command} {' '.join(args)} failed: {detail}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"{command} {' '.join(args)} returned invalid JSON") from error


def resolve_package_target(requested_target: str, package_dump: dict[str, Any]) -> str:
    for candidate in package_dump.get("targets") or []:
        if candidate.get("name") == requested_target and candidate.get("type") == "regular":
            return candidate["name"]
    raise ValueError(
        f'Swift package does not contain a regular target named "{requested_target}".'
    )


def resolve_package_module(package_target: str, package_description: dict[str, Any]) -> str:
    for candidate in package_description.get("targets") or []:
        if candidate.get("name") == package_target and candidate.get("c99name"):
            return candidate["c99name"]
    raise ValueError(
        f'Swift package target "{package_target}" does not expose an importable module name.'
    )


def _compare_supported_products(left: dict[str, Any], right: dict[str, Any]) -> int:
    left_len = len(left.get("targets") or [])
    right_len = len(right.get("targets") or [])
    if left_len != right_len:
        return left_len - right_len
    return collate_product_names(left.get("name") or "", right.get("name") or "")


def infer_package_product(package_target: str, package_dump: dict[str, Any]) -> str:
    products = [
        product
        for product in package_dump.get("products") or []
        if (product.get("type") or {}).get("library") is not None
        and package_target in (product.get("targets") or [])
    ]
    supported: list[dict[str, Any]] = []
    for product in products:
        library = product["type"]["library"]
        if "dynamic" not in library:
            supported.append(product)
    product = next((item for item in supported if item.get("name") == package_target), None)
    if product is None and supported:
        product = sorted(supported, key=cmp_to_key(_compare_supported_products))[0]
    if product:
        return product["name"]
    if products:
        raise ValueError(
            f'Swift package target "{package_target}" is only exported by dynamic library products. '
            "Dynamic library products are not supported because hot reload only replaces "
            "the generated preview plugin dylib."
        )
    raise ValueError(
        f'Swift package target "{package_target}" is not exported by a library product.'
    )


def infer_package_deployment_target(package_dump: dict[str, Any]) -> Any:
    ios_platform = next(
        (p for p in package_dump.get("platforms") or [] if p.get("platformName") == "ios"),
        None,
    )
    package_deployment_target = (ios_platform or {}).get("version") or "17.0"
    if float(package_deployment_target) < 17:
        return "17.0"
    return package_deployment_target


def resolve_package_preview_configuration(
    package_swift_path: Path, options: ParseOptions
) -> dict[str, Any]:
    package_root = package_swift_path.parent
    package_dump = run_json(
        "swift", ["package", "dump-package", "--package-path", str(package_root)]
    )
    package_target = resolve_package_target(options.packageTarget, package_dump)
    package_product = infer_package_product(package_target, package_dump)
    package_description = run_json(
        "swift",
        ["package", "--package-path", str(package_root), "describe", "--type", "json"],
    )
    package_module = resolve_package_module(package_target, package_description)
    return {
        "packageRoot": package_root,
        "packageProduct": package_product,
        "packageModule": package_module,
        "previewFilters": options.previewFilters,
        "deploymentTarget": infer_package_deployment_target(package_dump),
    }


def run(
    command: str,
    args: list[str],
    *,
    cwd: Path | None = None,
    timeout_ms: int = 30_000,
    allow_failure: bool = False,
    log_output: bool = False,
    output_file: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    if output_file is not None:
        return run_with_output_file(
            command,
            args,
            cwd=cwd,
            timeout_ms=timeout_ms,
            allow_failure=allow_failure,
            output_file=output_file,
        )
    try:
        result = subprocess.run(
            [command, *args],
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            text=True,
            timeout=timeout_ms / 1000,
            check=True,
        )
        if log_output and result.stdout.strip():
            log(result.stdout.strip())
        if log_output and result.stderr.strip():
            log(result.stderr.strip())
        return result
    except subprocess.CalledProcessError as error:
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if log_output and stdout.strip():
            log(stdout.strip())
        if log_output and stderr.strip():
            log(stderr.strip())
        if allow_failure:
            return subprocess.CompletedProcess(
                args=[command, *args], returncode=error.returncode, stdout=stdout, stderr=stderr
            )
        detail = stderr or stdout or str(error)
        raise ValueError(f"{command} {' '.join(args)} failed: {detail}") from error
    except subprocess.TimeoutExpired as error:
        raise ValueError(f"{command} {' '.join(args)} timed out") from error


def run_with_output_file(
    command: str,
    args: list[str],
    *,
    cwd: Path | None,
    timeout_ms: int,
    allow_failure: bool,
    output_file: Path,
) -> subprocess.CompletedProcess[str]:
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with output_file.open("w") as handle:
        try:
            result = subprocess.run(
                [command, *args],
                cwd=str(cwd) if cwd else None,
                stdout=handle,
                stderr=subprocess.STDOUT,
                timeout=timeout_ms / 1000,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            if allow_failure:
                return subprocess.CompletedProcess(
                    args=[command, *args], returncode=-1, stdout="", stderr=""
                )
            raise ValueError(
                f"{command} {' '.join(args)} failed; full output: {output_file}: {error}"
            ) from error
    if result.returncode == 0:
        return subprocess.CompletedProcess(
            args=[command, *args], returncode=0, stdout="", stderr=""
        )
    if allow_failure:
        return subprocess.CompletedProcess(
            args=[command, *args], returncode=result.returncode, stdout="", stderr=""
        )
    raise ValueError(
        f"{command} {' '.join(args)} failed (exited with code {result.returncode}); "
        f"full output: {output_file}"
    )


def ensure_booted_sync(udid: str) -> None:
    json_data = run_json("xcrun", ["simctl", "list", "devices", "available", "-j"])
    device = None
    for entries in (json_data.get("devices") or {}).values():
        for entry in entries:
            if entry.get("udid") == udid:
                device = entry
                break
    if device is None:
        raise ValueError(f"Simulator not found: {udid}")
    if device.get("state") != "Booted":
        log(f"booting {device.get('name')}")
        run("xcrun", ["simctl", "boot", udid], allow_failure=True, log_output=True)
    run(
        "xcrun",
        ["simctl", "bootstatus", udid, "-b"],
        timeout_ms=120_000,
        log_output=True,
    )


def launch_pid(result: subprocess.CompletedProcess[str]) -> int | None:
    output = f"{result.stdout}\n{result.stderr}"
    escaped = re.escape(BUNDLE_ID)
    match = re.search(rf"{escaped}:\s*(\d+)", output)
    return int(match.group(1)) if match else None


def copy_swift_templates(project_root: Path) -> None:
    target_dir = project_root / TARGET_NAME
    for file_name in TEMPLATE_FILE_NAMES:
        shutil.copy2(TEMPLATE_ROOT / file_name, target_dir / file_name)


def build_and_launch_package(state: LauncherState) -> None:
    cfg = state.package_preview_configuration
    shutil.rmtree(state.project_root, ignore_errors=True)
    (state.project_root / f"{TARGET_NAME}.xcodeproj").mkdir(parents=True)
    (state.project_root / TARGET_NAME).mkdir(parents=True)

    copy_swift_templates(state.project_root)
    (state.project_root / TARGET_NAME / CONFIGURATION_FILE_NAME).write_text(
        generated_package_configuration_swift_source(
            cfg["packageModule"],
            cfg.get("previewFilters"),
        )
    )
    package_relative = _relative_or_dot(state.project_root, cfg["packageRoot"])
    (state.project_root / f"{TARGET_NAME}.xcodeproj" / "project.pbxproj").write_text(
        create_package_project_file(
            target_name=TARGET_NAME,
            bundle_id=BUNDLE_ID,
            package_relative_path=package_relative,
            package_product=cfg["packageProduct"],
            plugin_target_name=PACKAGE_PLUGIN_TARGET_NAME,
            deployment_target=str(cfg["deploymentTarget"]),
        )
    )

    build_log_path = state.build_root / "logs" / "preview-host.log"
    run(
        "xcodebuild",
        [
            "-project",
            str(state.project_root / f"{TARGET_NAME}.xcodeproj"),
            "-scheme",
            TARGET_NAME,
            "-configuration",
            "Debug",
            "-destination",
            f"id={state.udid}",
            "-sdk",
            "iphonesimulator",
            "-derivedDataPath",
            str(state.build_root),
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ],
        cwd=state.project_root,
        timeout_ms=900_000,
        output_file=build_log_path,
    )
    log(f"built preview host; build log: {build_log_path}")

    app_path = (
        state.build_root
        / "Build/Products/Debug-iphonesimulator"
        / f"{TARGET_NAME}.app"
    )
    if not app_path.is_dir():
        raise ValueError(f"Build succeeded but app bundle was not found: {app_path}")

    run("xcrun", ["simctl", "install", state.udid, str(app_path)], log_output=True)
    state.data_container = Path(
        run(
            "xcrun",
            ["simctl", "get_app_container", state.udid, BUNDLE_ID, "data"],
            timeout_ms=15_000,
        ).stdout.strip()
    )
    reload_docs = state.data_container / "Documents" / "swiftui-preview-browser"
    shutil.rmtree(reload_docs, ignore_errors=True)
    launch_result = run(
        "xcrun",
        ["simctl", "launch", state.udid, BUNDLE_ID],
        log_output=True,
    )
    state.app_pid = launch_pid(launch_result)
    wait_for_host_ready(state)
    log(f"launched package preview host for {state.preview_name}")


def _relative_or_dot(from_dir: Path, to_path: Path) -> str:
    rel = os.path.relpath(to_path.resolve(), from_dir.resolve())
    return rel if rel != "." else "."


def read_host_status(state: LauncherState) -> dict[str, Any] | None:
    if state.data_container is None:
        return None
    status_path = (
        state.data_container / "Documents" / "swiftui-preview-browser" / "status.json"
    )
    try:
        return json.loads(status_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def wait_for_host_status(
    state: LauncherState,
    *,
    attempts: int,
    is_ready: Callable[[dict[str, Any]], bool],
    status_error: Callable[[dict[str, Any]], ValueError | None] | None = None,
    timeout_message: str,
) -> dict[str, Any]:
    for _ in range(attempts):
        time.sleep(0.1)
        status = read_host_status(state)
        if not status:
            continue
        if status_error:
            err = status_error(status)
            if err:
                raise err
        if is_ready(status):
            return status
    raise ValueError(timeout_message)


def wait_for_host_ready(state: LauncherState) -> dict[str, Any]:
    return wait_for_host_status(
        state,
        attempts=50,
        is_ready=lambda status: status.get("pid") == state.app_pid
        and status.get("phase") == "running",
        timeout_message=(
            "Preview host launched but did not render. The selected preview may not be "
            "self-contained; inspect Simulator logs."
        ),
    )


def wait_for_host_reload(state: LauncherState, token: str) -> dict[str, Any]:
    def status_error(status: dict[str, Any]) -> ValueError | None:
        if status.get("lastToken") == token and status.get("phase") == "error":
            return ValueError(
                f"Hot reload failed inside host: {status.get('lastError') or 'unknown error'}"
            )
        return None

    return wait_for_host_status(
        state,
        attempts=80,
        is_ready=lambda status: status.get("lastToken") == token
        and status.get("phase") == "reloaded",
        status_error=status_error,
        timeout_message="Timed out waiting for the running host app to apply the hot reload",
    )


def hot_reload_package(state: LauncherState) -> None:
    host_before = read_host_status(state)
    expected_pid = (host_before or {}).get("pid") or state.app_pid
    token = str(uuid.uuid4())
    build_log_path = state.build_root / "logs" / "hot-reload.log"
    run(
        "xcodebuild",
        [
            "-project",
            str(state.project_root / f"{TARGET_NAME}.xcodeproj"),
            "-scheme",
            PACKAGE_PLUGIN_TARGET_NAME,
            "-configuration",
            "Debug",
            "-destination",
            f"id={state.udid}",
            "-sdk",
            "iphonesimulator",
            "-derivedDataPath",
            str(state.build_root),
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        ],
        cwd=state.project_root,
        timeout_ms=900_000,
        output_file=build_log_path,
    )
    log(f"built hot reload plugin; build log: {build_log_path}")

    dylib_path = (
        state.build_root
        / "Build/Products/Debug-iphonesimulator"
        / f"lib{PACKAGE_PLUGIN_TARGET_NAME}.dylib"
    )
    if not dylib_path.is_file():
        raise ValueError(
            f"Package hot reload build succeeded but dylib was not found: {dylib_path}"
        )

    if state.data_container is None:
        raise ValueError("Missing simulator data container for hot reload")

    reload_dir = state.data_container / "Documents" / "swiftui-preview-browser"
    reload_dir.mkdir(parents=True, exist_ok=True)
    container_dylib = reload_dir / f"lib{PACKAGE_PLUGIN_TARGET_NAME}-{token}.dylib"
    shutil.copy2(dylib_path, container_dylib)
    manifest_path = reload_dir / "reload.json"
    manifest_path.write_text(
        json.dumps(
            {"token": token, "dylibPath": str(container_dylib)},
            separators=(",", ":"),
        )
    )
    run(
        "xcrun",
        ["simctl", "spawn", state.udid, "notifyutil", "-p", HOT_RELOAD_NOTIFICATION],
        log_output=True,
    )
    host_after = wait_for_host_reload(state, token)
    if expected_pid and host_after.get("pid") != expected_pid:
        raise ValueError(
            f"Hot reload changed PID from {expected_pid} to {host_after.get('pid')}"
        )
    state.app_pid = host_after.get("pid")
    log(f"hot reloaded package preview {state.preview_name} in pid {state.app_pid}")


def hot_reload(state: LauncherState) -> None:
    if state.hot_reloading:
        state.hot_reload_queued = True
        return
    state.hot_reloading = True
    try:
        hot_reload_package(state)
    finally:
        state.hot_reloading = False
        if state.hot_reload_queued:
            state.hot_reload_queued = False
            enqueue_hot_reload(state)


def enqueue_hot_reload(state: LauncherState) -> None:
    try:
        hot_reload(state)
    except ValueError:
        pass


def should_skip_watched_package_path(file_name: str) -> bool:
    parts = re.split(r"[\\/]", file_name)
    return any(part in SKIP_WATCH_DIRS for part in parts)


def package_tree_snapshot(package_root: Path) -> dict[Path, float]:
    snapshot: dict[Path, float] = {}
    for path in package_root.rglob("*"):
        if should_skip_watched_package_path(str(path.relative_to(package_root))):
            continue
        if path.is_file():
            try:
                snapshot[path] = path.stat().st_mtime_ns
            except OSError:
                continue
    return snapshot


def watch_package_tree(package_root: Path, on_change: Callable[[], None]) -> None:
    last_snapshot = package_tree_snapshot(package_root)
    debounce_timer: threading.Timer | None = None
    lock = threading.Lock()

    def schedule() -> None:
        nonlocal debounce_timer
        with lock:
            if debounce_timer is not None:
                debounce_timer.cancel()
            debounce_timer = threading.Timer(0.25, fire)
            debounce_timer.daemon = True
            debounce_timer.start()

    def fire() -> None:
        on_change()

    def poll() -> None:
        nonlocal last_snapshot
        while True:
            time.sleep(0.25)
            current = package_tree_snapshot(package_root)
            if current != last_snapshot:
                last_snapshot = current
                schedule()

    thread = threading.Thread(target=poll, daemon=True)
    thread.start()


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    try:
        options = parse_args(argv)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    if options.help:
        print_help()
        return 0

    package_swift_path = resolve_package_swift_path(options.packageSwiftPath)
    package_preview_configuration = resolve_package_preview_configuration(
        package_swift_path, options
    )
    scratch_root = default_scratch_root(package_swift_path, package_preview_configuration)
    build_root = scratch_root / "build"
    project_root = scratch_root / "GeneratedPreviewHost"
    udid = options.device

    preview_name = (
        ", ".join(package_preview_configuration["previewFilters"])
        if package_preview_configuration.get("previewFilters")
        else f"{package_preview_configuration['packageModule']} previews"
    )

    state = LauncherState(
        project_root=project_root,
        build_root=build_root,
        package_preview_configuration=package_preview_configuration,
        udid=udid,
        preview_name=preview_name,
    )

    log(f"Package.swift: {package_swift_path}")
    log(f"package: {package_preview_configuration['packageRoot']}")
    log(f"product: {package_preview_configuration['packageProduct']}")
    log(f"module: {package_preview_configuration['packageModule']}")
    if package_preview_configuration.get("previewFilters"):
        log(
            "preview filters: "
            + ", ".join(package_preview_configuration["previewFilters"])
        )
    log(f"simulator: {udid}")

    try:
        ensure_booted_sync(udid)
        build_and_launch_package(state)
    except ValueError as error:
        log(str(error))
        return 1

    print(f"swiftui-preview-browser ready on simulator {udid}")

    def handle_change() -> None:
        log("change detected; hot reloading")
        enqueue_hot_reload(state)

    watch_package_tree(package_preview_configuration["packageRoot"], handle_change)

    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
