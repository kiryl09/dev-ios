#!/usr/bin/env bash
set -euo pipefail

MONOREPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
ROOT="$MONOREPO_ROOT/ios-dev"
SCRIPT_DIR="$ROOT/skills/build-ios-apps/scripts"
DD="/tmp/ios-dev-gate-pinned-derived-data"
PRODUCTS="/tmp/ios-dev-gate-pinned-products.xctestproducts"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir"
npm init -y >/dev/null 2>&1
npm install xcodebuildmcp@2.7.0 --silent >/dev/null 2>&1

"$SCRIPT_DIR/patch-xcodebuildmcp-prepared-test-derived-data.sh" "$tmpdir/node_modules/xcodebuildmcp"
export XCODEBUILDMCP_DERIVED_DATA_PATH="$DD"
export GATE_PRODUCTS="$PRODUCTS"
unset NODE_OPTIONS

node --input-type=module <<'NODE'
import { configureRuntimeWorkspaceKey } from "./node_modules/xcodebuildmcp/build/utils/runtime-instance.js";
import { createTestExecutor } from "./node_modules/xcodebuildmcp/build/utils/test-common.js";

configureRuntimeWorkspaceKey("ios-dev-gate-pin-derived-data");

const captured = [];
const fakeExecutor = async (command) => {
  captured.push(command);
  return { success: true };
};

const run = createTestExecutor(fakeExecutor, {
  toolName: "test_sim",
  target: "simulator",
  request: {},
});

await run(
  {
    testProductsPath: process.env.GATE_PRODUCTS,
    simulatorId: "00000000-0000-0000-0000-000000000001",
    platform: "iOS Simulator",
    extraArgs: [],
  },
  {
    emit: () => {},
    emitFragment: () => {},
  }
);

const cmd = captured[0];
if (!cmd) {
  console.error("gate-pin-derived-data FAIL: no xcodebuild command captured");
  process.exit(1);
}
const dd = process.env.XCODEBUILDMCP_DERIVED_DATA_PATH;
const ddIdx = cmd.indexOf("-derivedDataPath");
if (ddIdx === -1 || cmd[ddIdx + 1] !== dd) {
  console.error("gate-pin-derived-data FAIL: missing -derivedDataPath", cmd.join(" "));
  process.exit(1);
}
const ddCount = cmd.filter((t) => t === "-derivedDataPath").length;
if (ddCount !== 1) {
  console.error("gate-pin-derived-data FAIL: duplicate -derivedDataPath", ddCount);
  process.exit(1);
}
console.log("gate-pin-derived-data PASS");
NODE
