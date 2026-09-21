export async function load(url, context, defaultLoad) {
  const pinned = process.env.XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH;
  const href =
    typeof url === "string" ? url : url && typeof url.href === "string" ? url.href : "";
  if (!pinned || !href.includes("test-products-path.js")) {
    return defaultLoad(url, context, defaultLoad);
  }

  const result = await defaultLoad(url, context, defaultLoad);
  if (result.format !== "module" || result.source === undefined) {
    return result;
  }

  const source =
    typeof result.source === "string"
      ? result.source
      : Buffer.from(result.source).toString("utf8");

  if (!source.includes("function createDefaultTestProductsPath")) {
    return result;
  }

  const patched = source.replace(
    "function createDefaultTestProductsPath(toolName) {",
    `function createDefaultTestProductsPath(toolName) {
  const pinned = process.env.XCODEBUILDMCP_PINNED_TEST_PRODUCTS_PATH;
  if (pinned) {
    return pinned;
  }`
  );

  return {
    format: "module",
    source: patched,
    shortCircuit: true,
  };
}
