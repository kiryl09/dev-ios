from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from types import ModuleType

_REPO = Path(__file__).resolve().parents[2]
_PREVIEW_BROWSER_PATH = (
    _REPO
    / "plugin/skills/ios-simulator-browser/scripts/swiftui-preview-browser.py"
)


def load_preview_browser() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "swiftui_preview_browser", _PREVIEW_BROWSER_PATH
    )
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {_PREVIEW_BROWSER_PATH}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module
