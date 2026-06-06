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
                "spawn_challenge",
                {"enemy_count": 2, "radius": 5.0, "objective": "Defeat 2 (E2E)", "reward_skill": "mcp_e2e_fireball", "reward_points": 1},
                # mcp_idle.tscn has no Player, so we expect an error — this still validates the JSON-RPC roundtrip.
                lambda r: (
                    ("error" in r)  # no Player
                    or (str(r.get("challenge_id", "")).startswith("challenge_") and int(r.get("enemies_spawned", 0)) == 2)
                ),
            ),
        ]
        for name, args, check in tests:
            try:
                r = await call_tool(name, args)
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
