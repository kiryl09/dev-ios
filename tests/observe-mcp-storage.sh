#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: observe-mcp-storage.sh <before|after|check> [state_file]

Snapshots MCP forbidden trees and df Avail on $HOME volume.
State file defaults to /tmp/dev-ios-observe.state.

  before   Record baseline (exit 0)
  after    Compare to baseline; exit 1 on new MCP copies or bad df delta
  check    Print current metrics only (exit 0)
EOF
}

mode="${1:-}"
state_file="${2:-/tmp/dev-ios-observe.state}"
home_volume="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
mcp_root="${HOME}/Library/Developer/XcodeBuildMCP"

list_mcp_forbidden() {
  python3 - "$mcp_root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
if not root.is_dir():
    print("")
    raise SystemExit(0)
entries: list[str] = []
for ws in sorted(root.glob("workspaces/*")):
    for name in ("DerivedData", "test-products", "result-bundles"):
        p = ws / name
        if p.is_dir():
            entries.append(str(p.resolve()))
print("\n".join(entries))
PY
}

snapshot() {
  printf 'avail_kb=%s\n' "$home_volume"
  printf 'mcp_forbidden_dirs=%s\n' "$(list_mcp_forbidden | paste -sd, -)"
}

case "$mode" in
  -h|--help) usage; exit 0 ;;
  check)
    echo "avail_kb=$home_volume"
    echo "mcp_forbidden_dirs:"
    list_mcp_forbidden
    exit 0
    ;;
  before)
    snapshot >"$state_file"
    echo "observe: baseline saved to $state_file"
    cat "$state_file"
    exit 0
    ;;
  after)
    [[ -f "$state_file" ]] || {
      echo "error: missing baseline; run before first" >&2
      exit 1
    }
    before_avail="$(grep '^avail_kb=' "$state_file" | cut -d= -f2-)"
    before_mcp="$(grep '^mcp_forbidden_dirs=' "$state_file" | cut -d= -f2-)"
    after_avail="$home_volume"
    after_mcp="$(list_mcp_forbidden | paste -sd, -)"

    delta_avail=$((before_avail - after_avail))
    if [[ -f "$state_file" ]] && grep -q '^cold_delta=' "$state_file" 2>/dev/null; then
      cold_delta="$(grep '^cold_delta=' "$state_file" | cut -d= -f2-)"
    else
      cold_delta="$delta_avail"
      echo "cold_delta=$cold_delta" >>"$state_file"
    fi

    threshold=$((cold_delta / 2))
    if (( threshold < 204800 )); then
      threshold=204800
    fi

    fail=0
    IFS=',' read -r -a before_arr <<<"${before_mcp}"
    IFS=',' read -r -a after_arr <<<"${after_mcp}"
    for entry in "${after_arr[@]}"; do
      [[ -z "$entry" ]] && continue
      found=0
      for b in "${before_arr[@]}"; do
        [[ "$entry" == "$b" ]] && found=1 && break
      done
      if (( found == 0 )); then
        echo "FAIL: new MCP forbidden dir $entry" >&2
        fail=1
      fi
    done

    if (( delta_avail >= threshold )) && (( cold_delta > 0 )); then
      echo "FAIL: df Avail dropped ${delta_avail}KB (threshold ${threshold}KB, cold_delta ${cold_delta}KB)" >&2
      fail=1
    fi

    echo "observe after: avail_kb=$after_avail delta_avail_kb=$delta_avail"
    if (( fail != 0 )); then
      exit 1
    fi
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
