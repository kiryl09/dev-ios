import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const cacheRoot =
  process.env.XCODEBUILDMCP_NPM_CACHE ||
  join(homedir(), ".cache/ios-dev-xcodebuildmcp");
const cliPath = join(cacheRoot, "node_modules/xcodebuildmcp/build/cli.js");
if (!existsSync(cliPath)) {
  console.error(`error: xcodebuildmcp cli not found at ${cliPath}`);
  process.exit(1);
}

await import(pathToFileURL(cliPath).href);
