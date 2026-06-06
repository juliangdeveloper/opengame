"""
MCP Server (FastMCP) for the mcp-souls-game project.

Exposes 11 tools to an LLM via the Model Context Protocol (stdio transport).
Each tool forwards a JSON-RPC 2.0 call to the Godot MCPReceiver via the
HTTP FastAPI bridge (mcp_bridge/bridge.py).

Pipeline:
    LLM (MCP client)  →  this server (stdio)  →  HTTP bridge  →  Godot TCP (MCPReceiver)

Run with stdio (default MCP transport):
    python3 mcp_bridge/mcp_server.py

The server reads BRIDGE_URL from env (default http://127.0.0.1:8000).
"""

import json
import os
import sys
import urllib.request
import urllib.error
from typing import Any, Dict, Optional

from mcp.server.fastmcp import FastMCP

BRIDGE_URL = os.environ.get("BRIDGE_URL", "http://127.0.0.1:8000")
BRIDGE_TIMEOUT = float(os.environ.get("BRIDGE_TIMEOUT", "5.0"))
BRIDGE_AUTH_TOKEN = os.environ.get("BRIDGE_AUTH_TOKEN", "").strip()


def _call_godot(method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Forward a JSON-RPC 2.0 call to the Godot MCPReceiver via the HTTP bridge.

    Returns:
        The "result" dict (or its embedded "error" string) — never raises.
    """
    body = json.dumps({"method": method, "params": params or {}}).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if BRIDGE_AUTH_TOKEN:
        headers["X-Auth-Token"] = BRIDGE_AUTH_TOKEN
    req = urllib.request.Request(
        f"{BRIDGE_URL}/tools/call",
        data=body,
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=BRIDGE_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if "error" in data:
                return {"error": str(data["error"])}
            result = data.get("result", data)
            # Godot may return {"error": "..."} inside result for soft errors
            if isinstance(result, dict) and "error" in result and len(result) == 1:
                return result  # bubble up the error as-is
            return result
    except urllib.error.URLError as e:
        return {"error": f"bridge unreachable at {BRIDGE_URL}: {e}"}
    except json.JSONDecodeError as e:
        return {"error": f"bridge returned invalid JSON: {e}"}
    except Exception as e:  # noqa: BLE001
        return {"error": f"bridge call failed: {type(e).__name__}: {e}"}


# --- MCP server setup --------------------------------------------------------

mcp = FastMCP("mcp-souls-game")


# --- Tools (11) --------------------------------------------------------------


@mcp.tool()
def ping() -> Dict[str, Any]:
    """Health check. Returns {pong, ts} from Godot's MCPReceiver."""
    return _call_godot("ping")


@mcp.tool()
def get_player_state() -> Dict[str, Any]:
    """Return current player state: skill_points, proficiency, owned_skills, tier, allocations."""
    return _call_godot("get_player_state")


@mcp.tool()
def list_skills() -> Dict[str, Any]:
    """List all skill templates available in data/skills/ (the LLM's library of atoms)."""
    return _call_godot("list_skills")


@mcp.tool()
def grant_skill_points(amount: int) -> Dict[str, Any]:
    """Grant N skill points to the player. Updates proficiency and tier."""
    return _call_godot("grant_skill_points", {"amount": int(amount)})


@mcp.tool()
def grant_skill(skill_id: str) -> Dict[str, Any]:
    """Award an existing skill (by id) to the player."""
    return _call_godot("grant_skill", {"skill_id": skill_id})


@mcp.tool()
def spawn_challenge(
    enemy_count: int = 3,
    radius: float = 6.0,
    objective: str = "Defeat all enemies",
    reward_skill: str = "",
    reward_points: int = 1,
) -> Dict[str, Any]:
    """
    Design a challenge: spawn N enemies around the player, set the HUD objective,
    and grant `reward_skill` + `reward_points` upon completion.

    Use this to give the player a quest that unlocks a new skill or points.
    """
    return _call_godot(
        "spawn_challenge",
        {
            "enemy_count": int(enemy_count),
            "radius": float(radius),
            "objective": objective,
            "reward_skill": reward_skill,
            "reward_points": int(reward_points),
        },
    )


@mcp.tool()
def spawn_enemy(scene: str = "res://scenes/dummy.tscn", x: float = 0.0, y: float = 1.0, z: float = 3.0) -> Dict[str, Any]:
    """Spawn a single enemy at (x,y,z). Useful for ad-hoc encounters."""
    return _call_godot(
        "spawn_enemy",
        {"scene": scene, "position": {"x": x, "y": y, "z": z}},
    )


@mcp.tool()
def set_objective(text: str) -> Dict[str, Any]:
    """Set the HUD objective text."""
    return _call_godot("set_objective", {"text": text})


@mcp.tool()
def allocate_skill_points(skill_id: str, stat: str, points: int = 1) -> Dict[str, Any]:
    """Allocate N points of a skill (owned) to a stat (e.g. 'amount', 'cooldown')."""
    return _call_godot(
        "allocate_skill_points",
        {"skill_id": skill_id, "stat": stat, "points": int(points)},
    )


@mcp.tool()
def create_skill(
    id: str,
    name: str = "",
    description: str = "",
    type: str = "damage",
    target_resolver_kind: str = "nearest_npc_in_range",
    atoms: list = None,  # type: ignore[arg-type]
    designed_max: dict = None,  # type: ignore[arg-type]
    costs: dict = None,  # type: ignore[arg-type]
) -> Dict[str, Any]:
    """
    Author a new skill template (.tres) on disk.

    The LLM composes a skill from the closed atom library (skill_atoms.json).
    Validator runs server-side and in Godot. If validation fails, the skill is
    NOT created and errors are returned.

    Args:
        id: unique skill id, e.g. "fireball_001"
        name: human-readable name
        description: short description
        type: "damage" or "control"
        target_resolver_kind: one of self, selected_npc, nearest_npc_in_range,
                              aoe, self_aoe, projectile_carrier, chain, zone_entered
        atoms: list of {type, params, applies_to_target}
        designed_max: {stat_name: max_value}
        costs: {stamina, cooldown, ...}
    """
    if atoms is None:
        return {"error": "atoms is required"}
    if designed_max is None:
        designed_max = {}
    if costs is None:
        costs = {}
    return _call_godot(
        "create_skill",
        {
            "id": id,
            "name": name or id,
            "description": description,
            "type": type,
            "category": type,  # resource stores both
            "target_resolver": {"kind": target_resolver_kind},
            "atoms": atoms,
            "designed_max": designed_max,
            "costs": costs,
        },
    )


@mcp.tool()
def modify_skill(
    id: str,
    name: str = "",
    description: str = "",
    atoms: Optional[list] = None,  # type: ignore[arg-type]
    designed_max: Optional[dict] = None,  # type: ignore[arg-type]
    costs: Optional[dict] = None,  # type: ignore[arg-type]
) -> Dict[str, Any]:
    """
    Modify fields of an existing skill. Re-validates and persists to disk.

    Only the fields you pass will be updated; pass an empty list/dict to skip them.
    Use list_skills() first to see current state.
    """
    payload: Dict[str, Any] = {"id": id}
    if name:
        payload["name"] = name
    if description:
        payload["description"] = description
    if atoms is not None:
        payload["atoms"] = atoms
    if designed_max is not None:
        payload["designed_max"] = designed_max
    if costs is not None:
        payload["costs"] = costs
    return _call_godot("modify_skill", payload)


# --- Resources: skill atom library (read-only snapshot) ----------------------


@mcp.resource("contracts://skill-atoms")
def skill_atoms() -> str:
    """The closed library of 14 atoms the LLM can compose. Read this BEFORE creating skills."""
    path = os.path.join(
        os.path.dirname(__file__), "..", "data", "contracts", "skill_atoms.json"
    )
    if not os.path.isfile(path):
        return json.dumps({"error": f"skill_atoms.json not found at {path}"})
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


@mcp.resource("contracts://stat-caps")
def stat_caps() -> str:
    """Hard clamps for skill stats (per-skill and per-stat max values)."""
    path = os.path.join(
        os.path.dirname(__file__), "..", "data", "contracts", "stat_caps.json"
    )
    if not os.path.isfile(path):
        return json.dumps({"error": f"stat_caps.json not found at {path}"})
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


@mcp.resource("contracts://balance-config")
def balance_config() -> str:
    """Balance curves, tier thresholds, and cost scaling parameters."""
    path = os.path.join(
        os.path.dirname(__file__), "..", "data", "contracts", "balance_config.json"
    )
    if not os.path.isfile(path):
        return json.dumps({"error": f"balance_config.json not found at {path}"})
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


@mcp.resource("contracts://mcp-tools")
def mcp_tools_doc() -> str:
    """Markdown spec of MCP tools (for the LLM's awareness)."""
    path = os.path.join(
        os.path.dirname(__file__), "..", "data", "contracts", "mcp_tools.md"
    )
    if not os.path.isfile(path):
        return "# mcp_tools.md not found"
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


# --- Prompts (recipes) -------------------------------------------------------


@mcp.prompt()
def author_skill(theme: str, tier: str = "Novice") -> str:
    """Generate a prompt the LLM can use to author a skill on a theme."""
    return (
        f"You are a Skill Author for a souls-like game.\n"
        f"Theme: {theme}\n"
        f"Tier: {tier}\n\n"
        f"1. Read contracts://skill-atoms to learn the 14 closed atoms.\n"
        f"2. Read contracts://stat-caps to know hard clamps.\n"
        f"3. Compose a skill with at most 5 atoms, exactly 1 type ('damage' or 'control'),\n"
        f"   and a target_resolver kind from the allowed list.\n"
        f"4. Call create_skill() with id, name, atoms, designed_max, costs.\n"
        f"5. After creation, call spawn_challenge() so the player can earn it.\n"
    )


@mcp.prompt()
def tune_player_skill(skill_id: str) -> str:
    """Generate a prompt to tune an existing skill's parameters safely."""
    return (
        f"Tune skill '{skill_id}' based on current game state.\n\n"
        f"1. Call get_player_state() to see current tier and points.\n"
        f"2. Call list_skills() to see '{skill_id}' atoms and designed_max.\n"
        f"3. Suggest up to 2 small adjustments (within stat_caps.json hard limits).\n"
        f"4. Call modify_skill() with the new atoms/designed_max/costs.\n"
        f"5. Re-read the skill via list_skills() to confirm the change.\n"
    )


def main() -> None:
    """Run the FastMCP server on stdio (default MCP transport)."""
    # FastMCP stdio transport is the default
    mcp.run()


if __name__ == "__main__":
    main()
