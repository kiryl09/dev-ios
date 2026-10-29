#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck source=xcodebuildmcp-host-dir.sh
source "$SCRIPT_DIR/xcodebuildmcp-host-dir.sh"

usage() {
  cat <<'EOF'
Usage: resolve-derived-data-path.sh [--write-local] [--sync-config] [--repo-root PATH]

Prints the Xcode DerivedData directory for the host project's .xcodeproj.

Reads projectPath from .xcodebuildmcp/config.yaml beside the host .xcodeproj (host discovery: repo README).

  --write-local   Write path to .xcodebuildmcp/derived-data.local (gitignored).
  --sync-config   Write derivedDataPath into all yaml profiles for THIS project only.
  --repo-root     Use this directory instead of walk-up discovery.

Exit 0 when a path is resolved. Exit 1 when config or project path is missing.
EOF
}

write_local=0
sync_config=0
explicit_repo_root=""
args=("$@")
idx=0
while [[ $idx -lt ${#args[@]} ]]; do
  arg="${args[$idx]}"
  case "$arg" in
    --write-local) write_local=1 ;;
    --sync-config) sync_config=1 ;;
    --repo-root)
      idx=$((idx + 1))
      explicit_repo_root="${args[$idx]:-}"
      if [[ -z "$explicit_repo_root" ]]; then
        echo "error: --repo-root requires a value" >&2
        exit 1
      fi
      ;;
    --repo-root=*) explicit_repo_root="${arg#--repo-root=}" ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "error: unknown argument: $arg" >&2; usage >&2; exit 1 ;;
  esac
  idx=$((idx + 1))
done

find_repo_root() {
  if [[ -n "$explicit_repo_root" ]]; then
    printf '%s\n' "$(cd "$explicit_repo_root" && pwd)"
    return 0
  fi
  xcodebuildmcp_find_host_dir 0
}

read_project_path() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

config = Path(sys.argv[1])
text = config.read_text()
match = re.search(r"^\s+projectPath:\s+(\S+)\s*$", text, re.MULTILINE)
if not match:
    raise SystemExit("error: projectPath not found in config")
print(match.group(1))
PY
}

read_tests_scheme() {
  python3 - "$1" <<'PY'
import re
import sys
from pathlib import Path

config = Path(sys.argv[1])
text = config.read_text()
block = re.search(
    r"^  tests:\s*\n(.*?)(?=^  [A-Za-z_]+:|^sessionDefaults:|\Z)",
    text,
    re.MULTILINE | re.DOTALL,
)
if not block:
    print("Tests")
    raise SystemExit(0)
match = re.search(r"^    scheme:\s+(\S+)\s*$", block.group(1), re.MULTILINE)
print(match.group(1) if match else "Tests")
PY
}

if ! repo_root="$(find_repo_root)"; then
  echo "error: .xcodebuildmcp/config.yaml not found (run from host project checkout)" >&2
  exit 1
fi

config_path="$repo_root/.xcodebuildmcp/config.yaml"
if ! project_path="$(read_project_path "$config_path")"; then
  echo "error: could not read projectPath from $config_path" >&2
  exit 1
fi

if [[ "$project_path" != /* ]]; then
  project_path="$repo_root/$project_path"
fi

project_name="$(basename "$project_path" .xcodeproj)"
if [[ ! -d "$project_path" ]]; then
  echo "error: project not found: $project_path" >&2
  exit 1
fi

resolved_project="$(cd "$(dirname "$project_path")" && pwd)/$(basename "$project_path")"
dd_root="${HOME}/Library/Developer/Xcode/DerivedData"

find_by_workspace_path() {
  local dir plist workspace
  [[ -d "$dd_root" ]] || return 1
  for dir in "$dd_root"/"${project_name}-"*; do
    [[ -d "$dir" ]] || continue
    plist="$dir/info.plist"
    [[ -f "$plist" ]] || continue
    workspace="$(plutil -extract WorkspacePath raw -o - "$plist" 2>/dev/null || true)"
    if [[ "$workspace" == "$resolved_project" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

compute_expected_path() {
  python3 - "$resolved_project" "$project_name" "$dd_root" <<'PY'
import hashlib
import struct
import sys
import unicodedata
from pathlib import Path

project_path, project_name, dd_root = sys.argv[1:4]

def xcode_derived_data_hash(path: str) -> str:
    normalized = unicodedata.normalize("NFD", path)
    digest = hashlib.md5(normalized.encode("utf-8")).digest()
    chars = ["a"] * 28
    for offset, end, start in ((0, 0, 13), (8, 14, 27)):
        value = struct.unpack(">Q", digest[offset : offset + 8])[0]
        for index in range(start, end - 1, -1):
            chars[index] = chr(value % 26 + ord("a"))
            value //= 26
    return "".join(chars)

folder = f"{project_name}-{xcode_derived_data_hash(project_path)}"
print(str(Path(dd_root) / folder))
PY
}

if found="$(find_by_workspace_path)"; then
  derived_data_path="$found"
else
  derived_data_path="$(compute_expected_path)"
fi

if [[ "$sync_config" -eq 1 ]]; then
  tests_scheme="$(read_tests_scheme "$config_path")"
  xcresult_path="$derived_data_path/Logs/${tests_scheme}.xcresult"
  products_path="$derived_data_path/${tests_scheme}.xctestproducts"
  python3 - "$config_path" "$derived_data_path" "$resolved_project" "$tests_scheme" "$xcresult_path" "$products_path" <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

config_path, dd_path, project_path, tests_scheme, xcresult_path, products_path = sys.argv[1:7]
text = Path(config_path).read_text(encoding="utf-8")

if project_path not in text:
    raise SystemExit("error: config projectPath does not match resolved project")

def patch_block(block: str, *, extra_args: str | None) -> str:
    lines = block.splitlines()
    out: list[str] = []
    seen_dd = False
    seen_extra = False
    for line in lines:
        if re.match(r"^\s+derivedDataPath:\s+", line):
            if not seen_dd:
                out.append(f"    derivedDataPath: {dd_path}")
                seen_dd = True
            continue
        if re.match(r"^\s+testProductsPath:\s+", line):
            continue
        if extra_args and re.match(r"^\s+extraArgs:\s+", line):
            if not seen_extra:
                out.append(f"    extraArgs: {extra_args}")
                seen_extra = True
            continue
        out.append(line)
    if not seen_dd:
        out.insert(0, f"    derivedDataPath: {dd_path}")
    if extra_args and not seen_extra:
        out.append(f"    extraArgs: {extra_args}")
    return "\n".join(out) + ("\n" if block.endswith("\n") else "")

def replace_section(name: str, extra_args: str | None = None, products_path: str | None = None) -> None:
    global text
    pat = rf"(^  {name}:\s*\n)(.*?)(?=^  [A-Za-z_]+:|^sessionDefaults:|\Z)"
    m = re.search(pat, text, re.MULTILINE | re.DOTALL)
    if not m:
        raise SystemExit(f"error: profile {name} missing")
    patched = patch_block(m.group(2), extra_args=extra_args)
    if products_path:
        lines = patched.splitlines()
        out: list[str] = []
        seen = False
        for line in lines:
            if re.match(r"^\s+testProductsPath:\s+", line):
                if not seen:
                    out.append(f"    testProductsPath: {products_path}")
                    seen = True
                continue
            out.append(line)
        if not seen:
            out.append(f"    testProductsPath: {products_path}")
        patched = "\n".join(out) + ("\n" if patched.endswith("\n") else "")
    text = text[: m.start(2)] + patched + text[m.end(2) :]

extra = (
    f'["-resultBundlePath", "{xcresult_path}", '
    f'"-parallel-testing-enabled", "NO", '
    f'"-maximum-parallel-testing-workers", "1"]'
)
replace_section("app")
replace_section("tests", extra_args=extra, products_path=products_path)

sm = re.search(r"(^sessionDefaults:\s*\n)(.*?)(?=^\S|\Z)", text, re.MULTILINE | re.DOTALL)
if sm:

    def patch_session(block: str) -> str:
        lines = block.splitlines()
        out: list[str] = []
        seen_dd = False
        for line in lines:
            if re.match(r"^  derivedDataPath:\s+", line):
                if not seen_dd:
                    out.append(f"  derivedDataPath: {dd_path}")
                    seen_dd = True
                continue
            out.append(line)
        if not seen_dd:
            out.insert(0, f"  derivedDataPath: {dd_path}")
        return "\n".join(out) + ("\n" if block.endswith("\n") else "")

    patched = patch_session(sm.group(2))
    text = text[: sm.start(2)] + patched + text[sm.end(2) :]

text = re.sub(
    r"^\s+derivedDataPath:\s+.*\n(?:\s+derivedDataPath:\s+.*\n)+",
    f"    derivedDataPath: {dd_path}\n",
    text,
    flags=re.MULTILINE,
)

text = re.sub(
    r"^(\s+projectPath:\s+).*$",
    rf"\1{project_path}",
    text,
    flags=re.MULTILINE,
)

Path(config_path).write_text(text, encoding="utf-8")
PY
fi

printf '%s\n' "$derived_data_path"

if [[ "$write_local" -eq 1 ]]; then
  local_file="$repo_root/.xcodebuildmcp/derived-data.local"
  mkdir -p "$(dirname "$local_file")"
  printf '%s\n' "$derived_data_path" >"$local_file"
fi
