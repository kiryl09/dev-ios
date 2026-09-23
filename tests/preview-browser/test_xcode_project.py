from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

_REPO = Path(__file__).resolve().parents[2]
_LIB = _REPO / "plugin/skills/ios-simulator-browser/scripts/lib/xcode_project.py"


def _load_xcode_project():
    spec = importlib.util.spec_from_file_location("xcode_project", _LIB)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["xcode_project"] = module
    spec.loader.exec_module(module)
    return module


xp = _load_xcode_project()


class XcodeProjectTests(unittest.TestCase):
    def test_swift_filters_nil(self) -> None:
        source = xp.generated_package_configuration_swift_source("MyModule", None)
        self.assertIn("let previewBrowserFilters: [String]? = nil", source)
        self.assertIn('import MyModule', source)

    def test_swift_filters_escaped(self) -> None:
        source = xp.generated_package_configuration_swift_source(
            "MyModule", ['say "hi"', "a\\b"]
        )
        self.assertIn('"say \\"hi\\""', source)

    def test_pbxproj_contains_product_and_deployment(self) -> None:
        project = xp.create_package_project_file(
            target_name="PreviewHost",
            bundle_id="dev.example.host",
            package_relative_path="../MyPackage",
            package_product="MyProduct",
            plugin_target_name="PreviewReloadPlugin",
            deployment_target="18.2",
        )
        self.assertIn("MyProduct in Frameworks", project)
        self.assertIn('../MyPackage', project)
        self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 18.2", project)
        self.assertIn('productName = "MyProduct"', project)


if __name__ == "__main__":
    unittest.main()
