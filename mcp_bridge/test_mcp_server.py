"""
E2E test for the MCP server.

Requires:
  - Godot running with scenes/mcp_idle.tscn (MCPReceiver listening on 127.0.0.1:9876)
  - FastAPI bridge (mcp_bridge/bridge.py) running on http://127.0.0.1:8000

Then this script:
  1. Calls each MCP tool via FastMCP's in-process client
  2. Verifies the response shape and that Godot state changed

Run with: python3 mcp_bridge/test_mcp_server.py
"""

import asyncio
import os
import subprocess
import sys
import time
import urllib.request
import json
from pathlib import Path
from typing import Dict

PROJECT_ROOT = Path("/mnt/c/Users/Rog/Workspace/01_PROYECTOS/mcp-souls-game")
BRIDGE_URL = "http://127.0.0.1:8000"

sys.path.insert(0, str(PROJECT_ROOT / "mcp_bridge"))
import mcp_server  # noqa: E402


def _bridge_health() -> bool:
    try:
        with urllib.request.urlopen(f"{BRIDGE_URL}/health", timeout=2) as r:
            data = json.loads(r.read().decode("utf-8"))
            return data.get("godot_connected", False) is True
    except Exception:
        return False


async def call_tool(name: str, args: dict) -> dict:
    """Call an MCP tool via FastMCP's in-memory client.

    FastMCP 3.x wraps tool return dicts in a 'result' key (structured_content).
    We unwrap that here so the test asserts against the actual payload.
    """
    from fastmcp import Client

    client = Client(mcp_server.mcp)
    async with client:
        result = await client.call_tool(name, args)
        # Prefer parsing text content (always JSON of the tool return)
        if hasattr(result, "content") and result.content:
            for c in result.content:
                if hasattr(c, "text") and c.text:
                    try:
                        return json.loads(c.text)
                    except Exception:
                        return {"text": c.text}
        # Fallback: structured_content
        sc = getattr(result, "structured_content", None)
        if isinstance(sc, dict) and "result" in sc and isinstance(sc["result"], dict):
            return sc["result"]
        return sc or {}


def main():
    print("=== MCP Server E2E Test ===")
    if not _bridge_health():
        print("SKIP: bridge not running or Godot not connected")
        print("Start with:")
        print("  godot --headless scenes/mcp_idle.tscn &")
        print("  python3 mcp_bridge/bridge.py &")
        return 1
    print("OK bridge+Godot up")
    results = []
    cached: Dict[str, dict] = {}  # cache tool results for chain resolution
    async def run():
        tests = [
            ("ping", {}, lambda r: r.get("pong") is True),
            ("get_player_state", {}, lambda r: "skill_points" in r),
            ("list_skills", {}, lambda r: r.get("count", 0) >= 5),
            ("grant_skill_points", {"amount": 3}, lambda r: int(r.get("granted", 0)) == 3),
            (
                "create_skill",
                {
                    "id": "mcp_e2e_fireball",
                    "name": "MCP E2E Fireball",
                    "type": "damage",
                    "target_resolver_kind": "projectile_carrier",
                    "atoms": [{"type": "hit", "params": {"amount": 50.0}, "applies_to_target": True}],
                    "designed_max": {"amount": 60.0, "cooldown": 4.0},
                    "costs": {"stamina": 20.0, "cooldown": 4.0},
                },
                lambda r: r.get("id") == "mcp_e2e_fireball" and int(r.get("atoms_count", 0)) == 1,
            ),
            (
                "modify_skill",
                {"id": "mcp_e2e_fireball", "name": "MCP E2E Fireball v2"},
                lambda r: r.get("id") == "mcp_e2e_fireball",
            ),
            (
                "grant_skill",
                {"skill_id": "kamehameha_001"},
                lambda r: r.get("granted_skill") == "kamehameha_001",
            ),
            (
                "create_mission",
                {
                    "purpose": "teach_skill",
                    "target_id": "kamehameha_001",
                    "mission_type": "1v1",
                    "title": "E2E Test Mission",
                },
                lambda r: str(r.get("mission_id", "")).startswith("mission_") and r.get("state") == "AVAILABLE",
            ),
            (
                "set_mission_difficulty",
                # Note: requires a mission_id from create_mission; we resolve at runtime
                # by parsing the previous result. This is a chain.
                {"_chain_from": "create_mission", "difficulty": 1},
                lambda r: r.get("difficulty") == 1 and r.get("state") == "READY",
            ),
            (
                "start_mission",
                {"_chain_from": "set_mission_difficulty"},
                lambda r: str(r.get("started", "")).startswith("mission_") and r.get("objective", "") != "",
            ),
            (
                "get_mission_state",
                {"_chain_from": "start_mission"},
                lambda r: str(r.get("id", "")).startswith("mission_") and r.get("state") in ["ACTIVE", "READY", "COMPLETED", "FAILED"],
            ),
            (
                "list_missions",
                {},
                lambda r: r.get("count", 0) >= 3 and r.get("missions") is not None,
            ),
        ]
        for name, args, check in tests:
            # Resolve chain (use cached result of a previous tool)
            resolved_args: dict = {}
            for k, v in args.items():
                if isinstance(v, str) and v.startswith("_chain_from:"):
                    parent_name = v.split(":", 1)[1]
                    parent = cached.get(parent_name, {})
                    resolved_args[k] = parent.get("mission_id", "")
                elif k == "_chain_from" and isinstance(v, str):
                    parent = cached.get(v, {})
                    # The "set_mission_difficulty" / "start_mission" / "get_mission_state" need mission_id
                    if name == "set_mission_difficulty":
                        resolved_args["mission_id"] = parent.get("mission_id", "")
                        resolved_args["difficulty"] = args.get("difficulty", 1)
                    elif name == "start_mission":
                        resolved_args["mission_id"] = parent.get("mission_id", "")
                    elif name == "get_mission_state":
                        # start_mission returns {"started": "<id>"}, not {"mission_id": "..."}
                        # create_mission returns {"mission_id": "..."}
                        mid = parent.get("mission_id", "") or parent.get("started", "")
                        resolved_args["mission_id"] = mid
                    else:
                        resolved_args = dict(args)
                        del resolved_args["_chain_from"]
                else:
                    resolved_args[k] = v
            try:
                r = await call_tool(name, resolved_args)
                cached[name] = r
                ok = check(r)
                print(f"  [{'PASS' if ok else 'FAIL'}] {name} -> {r}")
                results.append(ok)
            except Exception as e:
                print(f"  [ERR] {name} -> {type(e).__name__}: {e}")
                results.append(False)
    asyncio.run(run())
    passed = sum(results)
    total = len(results)
    print(f"=== MCP E2E: {passed} PASS / {total - passed} FAIL ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
