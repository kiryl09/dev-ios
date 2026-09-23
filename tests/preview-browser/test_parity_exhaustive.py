from __future__ import annotations

import importlib.util
import itertools
import json
import random
import sys
import unittest
from pathlib import Path

from _load_preview_browser import load_preview_browser
from reference_infer import reference_infer_package_product

pb = load_preview_browser()

_REPO = Path(__file__).resolve().parents[2]
_XCODE = _REPO / "plugin/skills/ios-simulator-browser/scripts/lib/xcode_project.py"


def _load_xcode_project():
    spec = importlib.util.spec_from_file_location("xcode_project", _XCODE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["xcode_project"] = module
    spec.loader.exec_module(module)
    return module


xp = _load_xcode_project()


class ParityExhaustiveTests(unittest.TestCase):
    def test_parse_args_error_messages(self) -> None:
        cases = [
            (["extra", "a", "b"], "Unexpected argument: a"),
            ([], "Pass the path to Package.swift."),
            (
                ["/tmp/Package.swift"],
                "Pass --package-target <target> to choose which Swift Package target to preview.",
            ),
            (
                ["/tmp/Package.swift", "--package-target", "Lib"],
                "Pass --device <simulator-udid> to choose the Simulator explicitly.",
            ),
        ]
        for argv, message in cases:
            with self.assertRaises(ValueError) as ctx:
                pb.parse_args(argv)
            self.assertEqual(str(ctx.exception), message)

    def test_infer_deployment_numeric_version(self) -> None:
        dump = {"platforms": [{"platformName": "ios", "version": 18}]}
        self.assertEqual(pb.infer_package_deployment_target(dump), 18)

    def test_infer_product_randomized(self) -> None:
        random.seed(0)
        names = ["Lib", "Core", "App", "Zed", "beta", "Feature", "Kit", "Äpfel", "Über", "naïve"]
        for _ in range(120):
            target = random.choice(names)
            products = []
            for name in random.sample(names, k=random.randint(1, len(names))):
                products.append(
                    {
                        "name": name,
                        "type": {"library": ["static"]},
                        "targets": random.sample(names, k=random.randint(1, len(names))),
                    }
                )
            dump = {"products": products}
            try:
                py_out = pb.infer_package_product(target, dump)
            except ValueError as error:
                py_out = f"ERR:{error}"
            try:
                ref_out = reference_infer_package_product(target, dump)
            except ValueError as error:
                ref_out = f"ERR:{error}"
            self.assertEqual(py_out, ref_out)

    def test_create_package_project_grid(self) -> None:
        targets = ["PreviewHost"]
        bundle_ids = ["dev.example.host", "dev.swiftui-preview-browser.host"]
        paths = ["../Pkg", ".", "../../MyPackage"]
        products = ["MyProduct", "AppFeature"]
        deployments = ["17.0", "18.2"]
        for target, bundle, rel, product, deployment in itertools.product(
            targets, bundle_ids, paths, products, deployments
        ):
            py_out = xp.create_package_project_file(
                target_name=target,
                bundle_id=bundle,
                package_relative_path=rel,
                package_product=product,
                plugin_target_name="PreviewReloadPlugin",
                deployment_target=deployment,
            )
            self.assertIn(product, py_out)
            self.assertIn(f"IPHONEOS_DEPLOYMENT_TARGET = {deployment}", py_out)
            self.assertIn(bundle, py_out)


if __name__ == "__main__":
    unittest.main()
