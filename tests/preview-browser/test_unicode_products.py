from __future__ import annotations

import unittest

from _load_preview_browser import load_preview_browser
from reference_infer import reference_infer_package_product

pb = load_preview_browser()


class UnicodeProductSortTests(unittest.TestCase):
    def test_collate_order_is_locale_aware(self) -> None:
        self.assertLess(pb.collate_product_names("a", "b"), 0)
        self.assertGreater(pb.collate_product_names("b", "a"), 0)
        self.assertEqual(pb.collate_product_names("same", "same"), 0)
        left, right = "Zed", "Äpfel"
        sign = pb.collate_product_names(left, right)
        self.assertEqual(pb.collate_product_names(right, left), -sign if sign else 0)

    def test_infer_unicode_tiebreak(self) -> None:
        dump = {
            "products": [
                {"name": "Zed", "type": {"library": ["static"]}, "targets": ["Shared"]},
                {"name": "Äpfel", "type": {"library": ["static"]}, "targets": ["Shared"]},
            ]
        }
        expected = reference_infer_package_product("Shared", dump)
        self.assertEqual(pb.infer_package_product("Shared", dump), expected)

    def test_infer_unicode_combining_marks(self) -> None:
        dump = {
            "products": [
                {"name": "naive", "type": {"library": ["static"]}, "targets": ["T"]},
                {"name": "naïve", "type": {"library": ["static"]}, "targets": ["T"]},
            ]
        }
        expected = reference_infer_package_product("T", dump)
        self.assertEqual(pb.infer_package_product("T", dump), expected)

    def test_infer_prefers_exact_target_name_over_unicode_sort(self) -> None:
        dump = {
            "products": [
                {"name": "Über", "type": {"library": ["static"]}, "targets": ["Lib", "Extra"]},
                {"name": "Lib", "type": {"library": ["static"]}, "targets": ["Lib"]},
            ]
        }
        self.assertEqual(pb.infer_package_product("Lib", dump), "Lib")


if __name__ == "__main__":
    unittest.main()
