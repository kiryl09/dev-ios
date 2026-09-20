#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <xcodebuildmcp-package-root>" >&2
  exit 1
fi

target="$1/build/utils/test-common.js"
if [[ ! -f "$target" ]]; then
  echo "error: missing $target" >&2
  exit 1
fi

if grep -q 'pinnedDd = process.env.XCODEBUILDMCP_DERIVED_DATA_PATH' "$target"; then
  exit 0
fi

python3 - "$target" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
needle = """    "test-without-building"
  ];
  const sourceWorkingDirectory = resolveSourceWorkingDirectory(params);"""
if needle not in source:
    raise SystemExit("patch target not found")
insert = """    "test-without-building"
  ];
  const pinnedDd = process.env.XCODEBUILDMCP_DERIVED_DATA_PATH;
  if (pinnedDd && pinnedDd.trim() && !command.includes("-derivedDataPath")) {
    const actionIdx = command.indexOf("test-without-building");
    command.splice(actionIdx, 0, "-derivedDataPath", pinnedDd.trim());
  }
  const sourceWorkingDirectory = resolveSourceWorkingDirectory(params);"""
path.write_text(source.replace(needle, insert, 1))
PY
