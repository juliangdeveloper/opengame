# MCP Server (FastMCP) — `mcp_server.py`

An MCP (Model Context Protocol) server that exposes 11 tools to an LLM,
letting it author, modify, and grant skills to the player at runtime.

## Architecture

```
LLM (Claude Desktop, OpenCode, etc.)
    │
    │  MCP protocol (stdio)
    ▼
mcp_server.py (FastMCP, this file)
    │
    │  HTTP POST /tools/call
    ▼
bridge.py (FastAPI on 127.0.0.1:8000)
    │
    │  TCP JSON-RPC 2.0
    ▼
MCPReceiver (Godot autoload, 127.0.0.1:9876)
    │
    ▼
Game state (player, enemies, skills, .tres files)
```

## Tools (11)

| Tool | Purpose |
|---|---|
| `ping` | Health check |
| `get_player_state` | skill_points, proficiency, owned_skills, tier, allocations |
| `list_skills` | Enumerate all skill templates in `data/skills/` |
| `grant_skill_points` | Award N points (updates proficiency & tier) |
| `grant_skill` | Award a skill template by id |
| `spawn_challenge` | Design a quest: enemies + objective + reward |
| `spawn_enemy` | Spawn a single enemy |
| `set_objective` | Set HUD objective text |
| `allocate_skill_points` | LLM allocates player points to a skill stat |
| `create_skill` | Author a new skill .tres from closed atom library |
| `modify_skill` | Modify fields of an existing skill |

## Resources (4, read-only)

| URI | Content |
|---|---|
| `contracts://skill-atoms` | The 14-atom closed library |
| `contracts://stat-caps` | Hard clamps for stats |
| `contracts://balance-config` | Tier curves & cost scaling |
| `contracts://mcp-tools` | The full tools spec (markdown) |

## Prompts (2 recipes)

| Prompt | Purpose |
|---|---|
| `author_skill(theme, tier)` | Recipe for LLM to author a skill on a theme |
| `tune_player_skill(skill_id)` | Recipe to tune an existing skill safely |

## Configuration

- `BRIDGE_URL` env var (default `http://127.0.0.1:8000`)
- `BRIDGE_TIMEOUT` env var (default `5.0` seconds)

## Run with stdio (default MCP transport)

```bash
# Terminal 1: Godot with idle scene (keeps MCPReceiver alive)
godot --headless scenes/mcp_idle.tscn

# Terminal 2: FastAPI bridge
python3 mcp_bridge/bridge.py

# Terminal 3: MCP server (stdio) — invoked by MCP client
python3 mcp_bridge/mcp_server.py
```

The MCP client (e.g. Claude Desktop, OpenCode) starts the server as a
subprocess and communicates via stdio. Configure your client with:

```json
{
  "mcpServers": {
    "mcp-souls-game": {
      "command": "python3",
      "args": ["/absolute/path/to/mcp-souls-game/mcp_bridge/mcp_server.py"],
      "env": { "BRIDGE_URL": "http://127.0.0.1:8000" }
    }
  }
}
```

## E2E Test

```bash
# Start Godot + bridge first (as above), then:
python3 mcp_bridge/test_mcp_server.py
# Expected: === MCP E2E: 8 PASS / 0 FAIL ===
```

## Safety

- All `create_skill` / `modify_skill` calls run through `SkillValidator` in
  Godot. Out-of-library atoms, too-many-atoms, invalid target_resolver, etc.
  are rejected server-side AND in Godot (defense in depth).
- Hard clamps from `data/contracts/stat_caps.json` apply during allocation.
- The LLM can never bypass tier requirements or proficiency thresholds.
