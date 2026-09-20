#!/bin/sh
meta=$(dd bs=65536 count=1 2>/dev/null)
hook_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
export PYTHONPATH="$hook_dir/lib${PYTHONPATH:+:$PYTHONPATH}"
printf '%s' "$meta" | python3 "$hook_dir/lib/ios_dev_gate.py"
exit 0
