#!/usr/bin/env bash
set -euo pipefail

xcodebuildmcp_find_git_root_from() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.git" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

xcodebuildmcp_find_git_root() {
  xcodebuildmcp_find_git_root_from "$PWD"
}

xcodebuildmcp_search_anchor() {
  local candidate=""
  local resolved=""

  if [[ -n "${WORKSPACE_FOLDER_PATHS:-}" ]]; then
    candidate="${WORKSPACE_FOLDER_PATHS%%:*}"
    if [[ -n "$candidate" ]] && resolved="$(cd "$candidate" 2>/dev/null && pwd -P)"; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  if [[ -n "${XCODEBUILDMCP_SEARCH_ROOT:-}" ]]; then
    candidate="${XCODEBUILDMCP_SEARCH_ROOT}"
    if [[ "$candidate" == *'${'* ]]; then
      candidate=""
    fi
    if [[ -n "$candidate" ]] && resolved="$(cd "$candidate" 2>/dev/null && pwd -P)"; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi

  return 1
}

xcodebuildmcp_host_search_root() {
  local anchor=""

  if anchor="$(xcodebuildmcp_search_anchor)"; then
    printf '%s\n' "$anchor"
    return 0
  fi

  printf '%s\n' "$(pwd -P)"
}

xcodebuildmcp_project_root() {
  xcodebuildmcp_host_search_root
}

xcodebuildmcp_pick_host_xcodeproj() {
  local search_root="$1"
  local require_config="${2:-0}"
  XCODEBUILDMCP_PICK_REQUIRE_CONFIG="$require_config" python3 - "$search_root" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    raise SystemExit(f"error: project root is not a directory: {root}")

require_config = os.environ.get("XCODEBUILDMCP_PICK_REQUIRE_CONFIG") == "1"
skip_names = {"Pods", "SourcePackages", ".git"}
candidates: list[tuple[int, str, Path]] = []

for dirpath, dirnames, _filenames in os.walk(root, topdown=True):
    base = Path(dirpath)
    for name in dirnames:
        if not name.endswith(".xcodeproj"):
            continue
        proj = base / name
        if not proj.is_dir():
            continue
        host_dir = proj.parent
        if require_config and not (host_dir / ".xcodebuildmcp" / "config.yaml").is_file():
            continue
        rel = proj.relative_to(root)
        depth = len(rel.parts) - 1
        candidates.append((depth, str(proj), proj))
    dirnames[:] = [
        d
        for d in dirnames
        if d not in skip_names
        and not d.startswith(".git")
        and not d.endswith(".xcodeproj")
    ]

if not candidates:
    if require_config:
        print(
            f"error: no .xcodeproj with .xcodebuildmcp/config.yaml under {root}",
            file=sys.stderr,
        )
    else:
        print(f"error: no .xcodeproj under {root}", file=sys.stderr)
    raise SystemExit(1)

candidates.sort(key=lambda item: (item[0], item[1]))
min_depth = candidates[0][0]
best = [item for item in candidates if item[0] == min_depth]
if len(best) > 1:
    paths = "\n".join(f"  - {item[2]}" for item in best)
    print(
        "error: multiple .xcodeproj at the same depth; pass --xcodeproj to bootstrap:\n"
        f"{paths}",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(best[0][2].resolve())
PY
}

xcodebuildmcp_find_host_dir() {
  local bootstrap="${1:-0}"
  local search_root=""
  local xcodeproj=""
  local host_dir=""

  search_root="$(xcodebuildmcp_host_search_root)"
  if ! xcodeproj="$(xcodebuildmcp_pick_host_xcodeproj "$search_root" 1)"; then
    if [[ "$bootstrap" -eq 0 ]]; then
      return 1
    fi
    if ! xcodeproj="$(xcodebuildmcp_pick_host_xcodeproj "$search_root" 0)"; then
      return 1
    fi
  fi
  host_dir="$(cd "$(dirname "$xcodeproj")" && pwd -P)"

  if [[ -f "$host_dir/.xcodebuildmcp/config.yaml" ]]; then
    printf '%s\n' "$host_dir"
    return 0
  fi

  if [[ "$bootstrap" -eq 1 ]]; then
    if [[ -z "${XCODEBUILDMCP_BOOTSTRAP_SCRIPT:-}" ]]; then
      echo "error: XCODEBUILDMCP_BOOTSTRAP_SCRIPT is not set" >&2
      return 1
    fi
    "$XCODEBUILDMCP_BOOTSTRAP_SCRIPT" --xcodeproj "$xcodeproj" >/dev/null
    printf '%s\n' "$host_dir"
    return 0
  fi

  echo "error: .xcodebuildmcp/config.yaml must live beside the .xcodeproj (in $host_dir)" >&2
  return 1
}
