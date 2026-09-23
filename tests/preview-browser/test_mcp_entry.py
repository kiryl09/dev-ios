from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_REPO = Path(__file__).resolve().parents[2]
_ENTRY = _REPO / "plugin/skills/build-ios-apps/scripts/xcodebuildmcp-mcp-entry.py"


def _load_entry():
    spec = importlib.util.spec_from_file_location("xcodebuildmcp_mcp_entry", _ENTRY)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


entry = _load_entry()


class McpEntryTests(unittest.TestCase):
    def test_missing_cli_exits(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"XCODEBUILDMCP_NPM_CACHE": tmp}, clear=False):
                with self.assertRaises(SystemExit) as ctx:
                    entry.main(["mcp"])
                self.assertEqual(ctx.exception.code, 1)

    def test_exec_invokes_node_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cli = Path(tmp) / "node_modules/xcodebuildmcp/build/cli.js"
            cli.parent.mkdir(parents=True)
            cli.write_text("// stub\n")
            with patch.dict(os.environ, {"XCODEBUILDMCP_NPM_CACHE": tmp}, clear=False):
                with patch.object(os, "execvp") as execvp:
                    try:
                        entry.main(["mcp"])
                    except SystemExit:
                        pass
                    execvp.assert_called_once_with(
                        "node", ["node", str(cli), "mcp"]
                    )


if __name__ == "__main__":
    unittest.main()
