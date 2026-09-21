import { register } from "node:module";
import { pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
register(
  join(here, "xcodebuildmcp-pin-test-products-hook.mjs"),
  import.meta.url
);
