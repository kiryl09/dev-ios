find_harness_checkout() {
  local monorepo_root="${1%/}"
  local candidate="$monorepo_root/tests/xcode-sample_project"
  if [[ -f "$candidate/.xcodebuildmcp/config.yaml" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}
