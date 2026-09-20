#!/bin/sh
meta=$(dd bs=65536 count=1 2>/dev/null)
hook_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

if ! printf '%s' "$meta" | python3 "$hook_dir/lib/ios_scope.py" --quiet 2>/dev/null; then
  printf '%s\n' '{"permission":"allow"}'
  exit 0
fi

allow() {
  printf '%s\n' '{"permission":"allow"}'
  exit 0
}

deny() {
  printf '%s\n' '{"permission":"deny","agent_message":"Use XcodeBuildMCP or xcode-tools for build, test, launch, boot, and shutdown. Do not run xcodebuild, xcrun, or simctl via Shell.","user_message":"Blocked Xcode/simulator Shell access outside MCP."}'
  exit 0
}

deny_write() {
  printf '%s\n' '{"permission":"deny","agent_message":"Do not write or delete under DerivedData, SourcePackages, CoreSimulator, or Xcode.app. Interrupted SPM resolve must be left for the user; wiping checkouts makes it worse.","user_message":"Blocked write to Xcode/simulator cache paths."}'
  exit 0
}

deny_kill() {
  printf '%s\n' '{"permission":"deny","agent_message":"Do not send signals to xcodebuild or kill PIDs from hygiene status. Stopping mid package-resolve corrupts SourcePackages (submodules/artifacts). Wait until it exits, or ask the user.","user_message":"Blocked kill of Xcode/xcodebuild."}'
  exit 0
}

extract() {
  _key=$1
  printf '%s' "$meta" | grep -o "\"${_key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/'
}

command=$(extract command)
file_path=$(extract file_path)
path=$(extract path)
target_directory=$(extract target_directory)
glob_pattern=$(extract glob_pattern)
event=$(extract hook_event_name)
tool=$(extract tool_name)

is_shell=0
[ "$event" = "beforeShellExecution" ] && is_shell=1
[ "$tool" = "Shell" ] && is_shell=1

aux_path_re='/(DerivedData)(/|$)|SourcePackages|(^|/)CoreSimulator(/|$)|/Library/Developer/Xcode(/|$)|/Library/Developer/CoreSimulator|/Applications/Xcode\.app'
cli_names='xcodebuild|xcrun|simctl|xcode-select|instruments|xed|agvtool|ibtool|actool'
shell_cmd_re='(^|[;&|`$()]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)*((nohup|command|time|nice|env)[[:space:]]+)*((\.|\.\.)/)*('"$cli_names"')([[:space:];&|`$()]|$)'
shell_c_re='(^|[;&|`$()]|&&|\|\|)[[:space:]]*(/bin/)?(bash|sh|zsh)[[:space:]]+(-[A-Za-z]*c[A-Za-z]*[[:space:]]+)(["'"'"'][[:space:]]*)?(sudo[[:space:]]+)*('"$cli_names"')([[:space:];&|`$()'"'"'"]|$)'
unix_kill_re='(^|[;&|`$()]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)*(/bin/)?kill[[:space:]]'
pkill_re='(^|[;&|`$()]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)*(pkill|killall)[[:space:]]'
skill_re='^[[:space:]]*(sudo[[:space:]]+)*((/bin/)?(sh|bash)[[:space:]]+)?([^[:space:]]*/)?skills/[^/]+/scripts/'
rm_cache_re='(^|[;&|`$()]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)*rm(dir)?[[:space:]].*(DerivedData|SourcePackages|CoreSimulator|/Library/Developer/Xcode)'

if [ "$is_shell" -eq 1 ]; then
  printf '%s' "$command" | grep -Fq 'kill-xcodebuild' && deny_kill
  printf '%s' "$command" | grep -Eq "$unix_kill_re" && deny_kill
  printf '%s' "$command" | grep -Eq "$pkill_re" && deny_kill
  printf '%s' "$command" | grep -Eqi "$rm_cache_re" && deny_write
  printf '%s' "$command" | grep -Eq "$skill_re" && allow
  printf '%s' "$command" | grep -Eqi "$shell_cmd_re" && deny
  printf '%s' "$command" | grep -Eqi "$shell_c_re" && deny
  allow
fi

case "$tool" in
  Write|Delete|StrReplace)
    haystack=$(printf '%s\n%s\n%s\n%s' "$file_path" "$path" "$target_directory" "$glob_pattern")
    printf '%s' "$haystack" | grep -Eq "$aux_path_re" && deny_write
    ;;
esac

allow
