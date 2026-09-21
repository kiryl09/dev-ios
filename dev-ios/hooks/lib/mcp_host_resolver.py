"""Resolve XcodeBuildMCP host dir the same way as the plugin wrapper (single source: host-dir.sh)."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

_HOST_DIR_SH = (
    Path(__file__).resolve().parents[2]
    / "skills/build-ios-apps/scripts/xcodebuildmcp-host-dir.sh"
)


def resolve_host_dir_for_workspace_root(root: Path | str | None) -> Path | None:
    if root is None:
        return None
    anchor = Path(root).expanduser().resolve()
    if not anchor.is_dir():
        return None
    if not _HOST_DIR_SH.is_file():
        return None
    env = os.environ.copy()
    env["WORKSPACE_FOLDER_PATHS"] = str(anchor)
    env.pop("XCODEBUILDMCP_SEARCH_ROOT", None)
    script = f'source "{_HOST_DIR_SH}" && xcodebuildmcp_find_host_dir 0'
    proc = subprocess.run(
        ["bash", "-c", script],
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return None
    text = proc.stdout.strip()
    if not text:
        return None
    host = Path(text.splitlines()[-1].strip()).expanduser().resolve()
    return host if host.is_dir() else None


def resolve_host_dir_for_roots(roots: list[Path]) -> Path | None:
    for root in roots:
        host = resolve_host_dir_for_workspace_root(root)
        if host is not None:
            return host
    return None


def project_stem_from_host(host: Path) -> str | None:
    config = host / ".xcodebuildmcp" / "config.yaml"
    if not config.is_file():
        return None
    try:
        text = config.read_text(encoding="utf-8")
    except OSError:
        return None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("projectPath:"):
            continue
        raw = stripped.split(":", 1)[1].strip()
        path = Path(raw)
        if path.suffix == ".xcodeproj":
            return path.stem
        return path.name or None
    return None
