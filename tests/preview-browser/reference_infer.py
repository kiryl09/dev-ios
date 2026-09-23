from __future__ import annotations

from functools import cmp_to_key
from typing import Any

from _load_preview_browser import load_preview_browser

pb = load_preview_browser()


def _compare_supported_products(left: dict[str, Any], right: dict[str, Any]) -> int:
    left_len = len(left.get("targets") or [])
    right_len = len(right.get("targets") or [])
    if left_len != right_len:
        return left_len - right_len
    return pb.collate_product_names(left.get("name") or "", right.get("name") or "")


def reference_infer_package_product(package_target: str, package_dump: dict[str, Any]) -> str:
    products = [
        product
        for product in package_dump.get("products") or []
        if (product.get("type") or {}).get("library") is not None
        and package_target in (product.get("targets") or [])
    ]
    supported: list[dict[str, Any]] = []
    for product in products:
        library = product["type"]["library"]
        if "dynamic" not in library:
            supported.append(product)
    product = next((item for item in supported if item.get("name") == package_target), None)
    if product is None and supported:
        product = sorted(supported, key=cmp_to_key(_compare_supported_products))[0]
    if product:
        return product["name"]
    if products:
        raise ValueError(
            f'Swift package target "{package_target}" is only exported by dynamic library products. '
            "Dynamic library products are not supported because hot reload only replaces "
            "the generated preview plugin dylib."
        )
    raise ValueError(
        f'Swift package target "{package_target}" is not exported by a library product.'
    )
