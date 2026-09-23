from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

from _load_preview_browser import load_preview_browser

pb = load_preview_browser()


class PreviewBrowserTests(unittest.TestCase):
    def test_parse_args_requires_device(self) -> None:
        with self.assertRaises(ValueError):
            pb.parse_args(["/tmp/Package.swift", "--package-target", "Lib"])

    def test_parse_preview_filter(self) -> None:
        options = pb.parse_args(
            [
                "/tmp/Package.swift",
                "--package-target",
                "Lib",
                "--device",
                "SIM-UDID",
                "--preview-filter",
                " Foo , Bar ",
            ]
        )
        self.assertEqual(options.previewFilters, ["Foo", "Bar"])

    def test_infer_package_product_prefers_matching_name(self) -> None:
        dump = {
            "products": [
                {
                    "name": "Big",
                    "type": {"library": ["static"]},
                    "targets": ["Lib", "Extra"],
                },
                {
                    "name": "Lib",
                    "type": {"library": ["static"]},
                    "targets": ["Lib"],
                },
            ]
        }
        self.assertEqual(pb.infer_package_product("Lib", dump), "Lib")

    def test_infer_package_product_rejects_dynamic_only(self) -> None:
        dump = {
            "products": [
                {
                    "name": "Lib",
                    "type": {"library": ["dynamic"]},
                    "targets": ["Lib"],
                }
            ]
        }
        with self.assertRaises(ValueError):
            pb.infer_package_product("Lib", dump)

    def test_infer_deployment_target_minimum_17(self) -> None:
        self.assertEqual(
            pb.infer_package_deployment_target({"platforms": [{"platformName": "ios", "version": "15.0"}]}),
            "17.0",
        )
        self.assertEqual(
            pb.infer_package_deployment_target({"platforms": [{"platformName": "ios", "version": "18.0"}]}),
            "18.0",
        )

    def test_should_skip_watched_paths(self) -> None:
        self.assertTrue(pb.should_skip_watched_package_path(".build/foo.swift"))
        self.assertFalse(pb.should_skip_watched_package_path("Sources/foo.swift"))

    def test_launch_pid(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout=f"{pb.BUNDLE_ID}: 4242\n",
            stderr="",
        )
        self.assertEqual(pb.launch_pid(result), 4242)

    def test_default_scratch_root_stable(self) -> None:
        path = Path("/tmp/Package.swift")
        cfg = {
            "packageModule": "Mod",
            "previewFilters": ["A"],
        }
        a = pb.default_scratch_root(path, cfg)
        b = pb.default_scratch_root(path, cfg)
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
