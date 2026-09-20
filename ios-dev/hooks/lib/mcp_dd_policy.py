"""Pin Xcode DerivedData: deny isolated MCP build paths; witness new MCP copies."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

XCODE_DD = Path.home() / "Library/Developer/Xcode/DerivedData"
MCP_ROOT = Path.home() / "Library/Developer/XcodeBuildMCP"
FORBIDDEN_MCP_MARKERS = (
    "/XcodeBuildMCP/workspaces/",
    "/workspaces/",
)
MCP_ARTIFACT_SUBDIRS = ("DerivedData", "test-products", "result-bundles")


def expand_path(raw: str | None) -> Path | None:
    if not raw or not str(raw).strip():
        return None
    return Path(os.path.expanduser(str(raw).strip())).resolve()


def under_xcode_dd(path: Path | None) -> bool:
    if path is None:
        return False
    try:
        path.relative_to(XCODE_DD.resolve())
        return True
    except ValueError:
        return False


def under_mcp_workspace_artifacts(path: Path | None) -> bool:
    if path is None:
        return False
    text = str(path)
    if "XcodeBuildMCP" not in text:
        return False
    for sub in MCP_ARTIFACT_SUBDIRS:
        needle = f"/{sub}"
        if needle in text or text.endswith(sub):
            return True
    return False


def parse_tool_input(payload: dict) -> dict:
    tool_input = payload.get("tool_input")
    if isinstance(tool_input, str) and tool_input.strip():
        try:
            parsed = json.loads(tool_input)
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}
    if isinstance(tool_input, dict):
        return tool_input
    return {}


def normalize_extra_args(extra_args: object) -> list[str]:
    if isinstance(extra_args, list):
        return [str(x) for x in extra_args]
    if isinstance(extra_args, str) and extra_args.strip():
        return [part.strip() for part in extra_args.split(",") if part.strip()]
    return []


def extra_args_paths(extra_args: object) -> list[str]:
    paths: list[str] = []
    args = normalize_extra_args(extra_args)
    i = 0
    while i < len(args):
        item = args[i]
        if item in ("-resultBundlePath", "-testProductsPath") and i + 1 < len(args):
            paths.append(str(args[i + 1]))
            i += 2
            continue
        i += 1
    return paths


def session_products_path(payload: dict, args: dict) -> Path | None:
    explicit = expand_path(args.get("testProductsPath"))
    if explicit is not None:
        return explicit
    for raw in extra_args_paths(args.get("extraArgs")):
        path = expand_path(raw)
        if path and path.suffix == ".xctestproducts":
            return path
    session_defaults = payload.get("session_defaults") or payload.get("defaults")
    if isinstance(session_defaults, dict):
        from_session = expand_path(session_defaults.get("testProductsPath"))
        if from_session is not None:
            return from_session
        for raw in extra_args_paths(session_defaults.get("extraArgs")):
            path = expand_path(raw)
            if path and ".xctestproducts" in path.name:
                return path
    return None


def workspace_roots(payload: dict) -> list[Path]:
    roots = payload.get("workspace_roots") or []
    if isinstance(roots, str):
        roots = [roots]
    out: list[Path] = []
    for raw in roots:
        if not raw:
            continue
        out.append(Path(str(raw)).expanduser().resolve())
    return out


def yaml_project_stem(root: Path) -> str | None:
    config = root / ".xcodebuildmcp" / "config.yaml"
    if not config.is_file():
        return None
    try:
        text = config.read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(r"^\s+projectPath:\s+(\S+)\s*$", text, re.MULTILINE)
    if not match:
        return None
    path = Path(match.group(1))
    if path.suffix == ".xcodeproj":
        return path.stem
    return path.name or None


def host_project_stem(payload: dict) -> str | None:
    for root in workspace_roots(payload):
        stem = yaml_project_stem(root)
        if stem:
            return stem
    return None


def derived_data_stem(path: Path | None) -> str | None:
    if path is None or not under_xcode_dd(path):
        return None
    try:
        rel = path.resolve().relative_to(XCODE_DD.resolve())
    except ValueError:
        return None
    folder = rel.parts[0] if rel.parts else ""
    if not folder:
        return None
    if "-" not in folder:
        return folder
    return folder.rsplit("-", 1)[0]


def is_foreign_checkout_artifact(path: Path | None, host_stem: str | None) -> bool:
    if path is None or not host_stem:
        return False
    stem = derived_data_stem(path)
    if stem is None:
        return False
    return stem.casefold() != host_stem.casefold()


LEAK_FIX = (
    "MCP session defaults are not this checkout. Do not ask the user to allow this hook. "
    "Follow skills/build-ios-apps/references/session-defaults.md before the next "
    "build_sim/test_sim (set_defaults from THIS yaml, show_defaults, assert). "
    "If assert still fails, stop and ask for Developer: Reload Window only."
)


def deny_build_call(payload: dict) -> tuple[bool, str | None]:
    tool = (payload.get("tool_name") or payload.get("mcp_tool_name") or "").strip()
    if tool == "clean":
        return (
            True,
            "Do not call MCP clean. It forces a full rebuild and can leave SPM checkouts inconsistent after an interrupted resolve. Wait or ask the user.",
        )
    if tool not in ("build_sim", "test_sim", "build_run_sim"):
        return False, None

    args = parse_tool_input(payload)
    derived = expand_path(args.get("derivedDataPath"))
    products = session_products_path(payload, args)
    build_for_testing = bool(args.get("buildForTesting"))
    host_stem = host_project_stem(payload)

    for candidate in (derived, products):
        if under_mcp_workspace_artifacts(candidate):
            return True, (
                "Build artifacts must not use XcodeBuildMCP workspace paths. "
                + LEAK_FIX
            )
        if is_foreign_checkout_artifact(candidate, host_stem):
            return True, (
                "Build artifacts belong to another Xcode project, not this checkout. "
                + LEAK_FIX
            )

    for raw in extra_args_paths(args.get("extraArgs")):
        path = expand_path(raw)
        if under_mcp_workspace_artifacts(path):
            return True, (
                "resultBundlePath must not use XcodeBuildMCP workspace paths. "
                + LEAK_FIX
            )

    if tool == "test_sim":
        if products is None:
            return True, (
                "test_sim requires testProductsPath under Xcode DerivedData "
                "from this checkout tests profile. " + LEAK_FIX
            )
        if not under_xcode_dd(products):
            return True, (
                "testProductsPath must live under Xcode DerivedData. " + LEAK_FIX
            )

    if build_for_testing and tool == "test_sim":
        if products is None or not under_xcode_dd(products):
            return True, (
                "buildForTesting requires testProductsPath under Xcode DerivedData. "
                + LEAK_FIX
            )
    if build_for_testing and tool == "build_sim" and products is not None and not under_xcode_dd(products):
        return True, (
            "testProductsPath must live under Xcode DerivedData. " + LEAK_FIX
        )

    if derived is not None and under_mcp_workspace_artifacts(derived):
        return True, (
            "derivedDataPath must not use XcodeBuildMCP workspace paths. " + LEAK_FIX
        )

    return False, None


def list_forbidden_mcp_dirs() -> set[str]:
    found: set[str] = set()
    workspaces = MCP_ROOT / "workspaces"
    if not workspaces.is_dir():
        return found
    for ws in workspaces.iterdir():
        if not ws.is_dir():
            continue
        for sub in MCP_ARTIFACT_SUBDIRS:
            p = ws / sub
            if p.is_dir():
                found.add(str(p.resolve()))
    return found


def witness_state_path(conversation_id: str | None) -> Path:
    safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", conversation_id or "default")
    return Path("/tmp") / f"ios-dev-mcp-witness-{safe}.json"


def load_witness_state(path: Path) -> dict:
    if not path.is_file():
        return {"forbidden_dirs": []}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            return data
    except (OSError, json.JSONDecodeError):
        pass
    return {"forbidden_dirs": []}


def save_witness_state(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


def witness_before(payload: dict) -> None:
    cid = payload.get("conversation_id") or payload.get("conversationId")
    path = witness_state_path(str(cid) if cid else None)
    current = sorted(list_forbidden_mcp_dirs())
    save_witness_state(path, {"forbidden_dirs": current})


def witness_after(payload: dict) -> tuple[bool, str | None]:
    cid = payload.get("conversation_id") or payload.get("conversationId")
    path = witness_state_path(str(cid) if cid else None)
    state = load_witness_state(path)
    before = {str(x) for x in state.get("forbidden_dirs", [])}
    after = list_forbidden_mcp_dirs()
    new_dirs = sorted(after - before)
    if new_dirs:
        return True, f"New MCP build copy dirs: {', '.join(new_dirs)}"
    return False, None


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else "deny"
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        payload = {}

    if mode == "deny":
        blocked, message = deny_build_call(payload)
        if blocked:
            print(
                json.dumps(
                    {
                        "permission": "deny",
                        "agent_message": message,
                        "user_message": "MCP is not this checkout. Close chats that used another project; do not disable this hook.",
                    }
                )
            )
            return 0
        print('{"permission":"allow"}')
        return 0

    if mode == "witness-before":
        witness_before(payload)
        print('{"permission":"allow"}')
        return 0

    if mode == "witness-after":
        blocked, message = witness_after(payload)
        if blocked:
            print(
                json.dumps(
                    {
                        "permission": "deny",
                        "agent_message": message,
                        "user_message": "MCP created isolated build storage.",
                    }
                )
            )
            return 0
        print('{"permission":"allow"}')
        return 0

    print('{"permission":"allow"}')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
