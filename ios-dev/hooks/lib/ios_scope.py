"""Decide whether ios-dev plugin hooks and agent rules apply to a workspace."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PBXPROJ_GLOB = ("*.xcodeproj", "project.pbxproj")
IOS_PLATFORM_RE = re.compile(
    r"iphoneos|iphonesimulator|SDKROOT\s*=\s*iphoneos|TARGETED_DEVICE_FAMILY",
    re.IGNORECASE,
)
MACOS_ONLY_APP_RE = re.compile(
    r"SDKROOT\s*=\s*macosx|SUPPORTED_PLATFORMS\s*=\s*macosx",
    re.IGNORECASE,
)


def workspace_roots(payload: dict) -> list[Path]:
    roots = payload.get("workspace_roots") or []
    if isinstance(roots, str):
        roots = [roots]
    result: list[Path] = []
    for raw in roots:
        if not raw:
            continue
        path = Path(str(raw)).expanduser().resolve()
        if path.is_dir():
            result.append(path)
    return result


def _pbxproj_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for xcodeproj in root.rglob("*.xcodeproj"):
        if any(part.startswith(".") for part in xcodeproj.parts):
            continue
        pbx = xcodeproj / "project.pbxproj"
        if pbx.is_file():
            files.append(pbx)
    return files


def _root_has_ios_xcode_target(root: Path) -> bool:
    for pbx in _pbxproj_files(root):
        try:
            text = pbx.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if not IOS_PLATFORM_RE.search(text):
            continue
        if MACOS_ONLY_APP_RE.search(text) and not re.search(
            r"iphoneos|iphonesimulator", text, re.IGNORECASE
        ):
            continue
        return True
    return False


def root_opted_in(root: Path) -> bool:
    if (root / ".cursor" / "ios-dev-off").is_file():
        return False
    if (root / ".cursor" / "ios-dev").is_file():
        return True
    if (root / ".xcodebuildmcp" / "config.yaml").is_file():
        return True
    return _root_has_ios_xcode_target(root)


def plugin_applies(payload: dict) -> bool:
    roots = workspace_roots(payload)
    if not roots:
        return False
    return any(root_opted_in(root) for root in roots)


def main() -> int:
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    active = plugin_applies(payload)
    if "--quiet" in sys.argv:
        return 0 if active else 1
    print(json.dumps({"ios_dev_plugin_active": active}))
    return 0 if active else 1


if __name__ == "__main__":
    raise SystemExit(main())
