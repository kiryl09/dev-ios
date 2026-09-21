#!/bin/sh
meta=$(dd bs=65536 count=1 2>/dev/null)
hook_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

if ! printf '%s' "$meta" | python3 "$hook_dir/lib/ios_scope.py" --quiet 2>/dev/null; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

event=$(printf '%s' "$meta" | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p.get("hook_event_name",""))')

if [ "$event" = "beforeMCPExecution" ]; then
  printf '%s' "$meta" | python3 "$hook_dir/lib/mcp_dd_policy.py" witness-before
  exit 0
fi

printf '%s' "$meta" | python3 "$hook_dir/lib/mcp_dd_policy.py" witness-after
