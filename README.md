# opengame

A 3rd-person souls-like prototype with a **data-driven skill system** and an
**MCP (Model Context Protocol) server** that lets an LLM author, balance, and
grant skills to the player in real time.

The LLM doesn't drive the player character — it drives the **Dungeon Master**:
it composes new skills from a closed atom library, validates them, persists
them as `.tres` files, and spawns challenges that reward those skills to the
player upon completion.

## Pipeline

```
LLM client (Claude Desktop, OpenCode, ...)
   │  stdio (MCP)
   ▼
mcp_server.py  ──── FastMCP, 11 tools + 4 resources + 2 prompts
   │  HTTP /tools/call (auth + rate-limited)
   ▼
bridge.py  ──── FastAPI
   │  TCP JSON-RPC 2.0
   ▼
MCPReceiver.gd  ──── Godot autoload, listens on 127.0.0.1:9876
   ▼
Game state (player, enemies, .tres skills)
```

## What's in the box

- **Godot 4.6.3** — game engine, 3rd-person character, enemies, HUD
- **Closed atom library** (~14 atoms) in `data/contracts/skill_atoms.json`
- **4-layer balance** (lvl1 hard floor 5%, soft cap diminishing returns,
  proficiency tiers, cost scaling) — see `data/contracts/balance_config.json`
- **SkillValidator** — server-side and Godot-side validation
- **ProgressionState autoload** — skill points, proficiency, tier, allocations
- **Skill UI allocator** (Tab to open)
- **5 example skills**: kamehameha, gomu_gomu_pistol, serious_punch,
  uraraka_zero_gravity, light_attack

## MCP tools exposed to the LLM

`ping`, `get_player_state`, `list_skills`, `grant_skill_points`, `grant_skill`,
`spawn_challenge`, `spawn_enemy`, `set_objective`, `allocate_skill_points`,
`create_skill`, `modify_skill`

## Quick start

```bash
# 1. Godot listens on 127.0.0.1:9876
godot --headless scenes/mcp_idle.tscn

# 2. Bridge on 127.0.0.1:8000
pip install -r mcp_bridge/requirements.txt
python3 mcp_bridge/bridge.py

# 3. MCP server (stdio, invoked by your MCP client)
python3 mcp_bridge/mcp_server.py
```

Wire it into Claude Desktop / OpenCode:

```json
{
  "mcpServers": {
    "opengame": {
      "command": "python3",
      "args": ["/abs/path/mcp_bridge/mcp_server.py"],
      "env": { "BRIDGE_URL": "http://127.0.0.1:8000" }
    }
  }
}
```

## Tests

```bash
# Godot skill system (35 tests)
godot --headless --script scripts/skill/smoke_test.gd

# Godot MCP JSON-RPC roundtrip (12 tests)
godot --headless scenes/mcp_test.tscn

# FastMCP end-to-end through the bridge (8 tests)
python3 mcp_bridge/test_mcp_server.py
```

All green at the latest commit. CI in `.github/workflows/tests.yml` runs all
three on every push.

## Safety

Every `create_skill` and `modify_skill` call runs through `SkillValidator` in
both the bridge and Godot. The LLM cannot:

- invent atoms outside the closed library
- exceed 5 atoms per skill or 3 targets per effect
- violate `data/contracts/stat_caps.json` hard clamps
- bypass tier requirements or proficiency thresholds

Hard floor at 0 points is 5% of designed max — no skill is ever useless at
level 1. Diminishing returns above soft cap. Full unlock only at Mythic tier
with all points allocated.

## License

MIT — see `LICENSE` (add if you publish).
