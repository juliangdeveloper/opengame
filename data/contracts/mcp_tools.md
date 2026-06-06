# MCP Tools

> Lista de tools que el LLM Dungeon Master tiene a su disposición. Cada tool se traduce a un HTTP request al FastAPI bridge, que lo dispatcha a Godot.

---

## Tools del LLM

### `consult_player_state`

Lee el estado actual del jugador. El LLM usa esto para tomar decisiones informadas.

**Input:** `{}`

**Output:**
```json
{
  "player_id": "string",
  "hp": 80,
  "hp_max": 100,
  "stamina": 100,
  "position": [0, 0, 0],
  "level": 5,
  "proficiency": 12,
  "proficiency_tier": "Adept",
  "skill_points_available": 3,
  "owned_skills": [
    { "id": "kamehameha_001", "name": "Kamehameha", "level": 1, "effective_damage": 65 }
  ],
  "active_challenge": null,
  "recent_history": ["defeated 3 saibamen", "learned Kamehameha"]
}
```

### `list_owned_skills`

Lista las skills del jugador con sus stats efectivos actuales.

**Input:** `{}`

**Output:**
```json
{
  "skills": [
    {
      "id": "kamehameha_001",
      "name": "Kamehameha",
      "type": "damage",
      "allocations": { "damage": 2, "radius": 0, "cooldown": 0 },
      "effective_stats": { "damage": 16, "radius": 0.25, "cooldown": 12, "stamina": 15 }
    }
  ]
}
```

### `create_skill`

El LLM diseña una skill y la registra. Validada antes de crear.

**Input:**
```json
{
  "skill_spec": { ...SkillSpec completo (ver skill_instance_schema.md)... }
}
```

**Output:**
```json
{
  "skill_id": "kamehameha_001",
  "validation_warnings": [],
  "created_at": "iso8601"
}
```

**Errores:**
- `422 invalid_spec`: el SkillSpec no pasa validación
- `409 already_exists`: ya hay una skill con ese id

### `modify_skill`

Modifica una skill existente owned por el jugador. Mismas reglas de validación.

**Input:**
```json
{
  "skill_id": "kamehameha_001",
  "patch": {
    "name": "Kamehameha Mejorado",
    "atoms_to_add": [{ "type": "dot", "params": { "dpt": 5, "duration": 3, "tick_interval": 1 } }],
    "designed_max_overrides": { "amount": 120 }
  }
}
```

**Output:**
```json
{ "skill_id": "kamehameha_001", "updated_at": "iso8601" }
```

### `delete_skill`

Borra una skill. Las combo skills que la referencian deben borrarse primero o se dangling.

**Input:** `{ "skill_id": "kamehameha_001" }`

**Output:** `{}`

### `allocate_skill_points`

Distribuye skill points a un stat de una skill owned.

**Input:**
```json
{
  "skill_id": "kamehameha_001",
  "stat": "damage",
  "points_to_add": 2
}
```

**Output:**
```json
{
  "new_value": { "damage": 16 },
  "skill_points_remaining": 1
}
```

**Errores:**
- `422 invalid_stat`: stat no está en `designed_max` de la skill
- `422 too_many_points`: excede `max_points_per_stat` (5)
- `422 not_enough_points`: `points_to_add > skill_points_available`

### `deallocate_skill_points`

Devuelve skill points al bank.

**Input:**
```json
{
  "skill_id": "kamehameha_001",
  "stat": "damage",
  "points_to_remove": 1
}
```

**Output:**
```json
{ "skill_points_remaining": 2 }
```

### `design_challenge`

El LLM diseña un challenge (quest) para enseñar/fortalecer una skill o probar al jugador.

**Input:**
```json
{
  "challenge_spec": { ...ChallengeSpec completo (ver challenge_schema.md)... }
}
```

**Output:**
```json
{ "challenge_id": "challenge_001", "spawned_at": "iso8601" }
```

### `accept_challenge`

El jugador confirma que quiere empezar el challenge diseñado. Spawnea en el mundo.

**Input:** `{ "challenge_id": "challenge_001" }`

**Output:** `{}`

### `get_challenge_state`

Lee el progreso del challenge activo.

**Input:** `{ "challenge_id": "challenge_001" }`

**Output:**
```json
{
  "status": "in_progress",
  "objectives_progress": [
    { "type": "cast_skill", "completed": false, "progress": "0/1" },
    { "type": "defeat_enemies", "completed": false, "progress": "1/3" }
  ],
  "elapsed_time": 45.3,
  "estimated_remaining": 30
}
```

### `evaluate_challenge`

Fuerza evaluación (también se autoevalúa cuando todos los objetivos se completan).

**Input:** `{ "challenge_id": "challenge_001" }`

**Output:**
```json
{
  "outcome": "success | failure",
  "rewards_granted": {
    "skills": ["kamehameha_001"],
    "skill_points": 3,
    "proficiency": 1
  }
}
```

### `list_active_enemies`

Para que el LLM sepa qué hay en el mundo antes de diseñar un challenge.

**Input:** `{}`

**Output:**
```json
{ "enemies": [{ "id": "saibaman_1", "type": "saibaman", "hp": 100, "position": [0, 0, 15] }] }
```

### `consult_skill_atoms`

El LLM consulta la librería de átomos disponibles (útil antes de diseñar una skill).

**Input:** `{}`

**Output:** el contenido de `data/contracts/skill_atoms.json` resumido.

### `consult_balance_config`

El LLM consulta las reglas de balance (cap tiers, ratios) para diseñar skills que escalen bien.

**Input:** `{}`

**Output:** el contenido de `data/contracts/balance_config.json`.

---

## Transporte

```
[LLM (Claude, GPT, etc.)]
   ↓ MCP protocol (stdio o HTTP/SSE)
[MCP server (Python, FastMCP)]
   ↓ HTTPS POST /tools/{name}
[FastAPI bridge :8765]
   ↓ HTTP loopback a 127.0.0.1:8766
[Godot MCPReceiver autoload]
   ↓ method calls
[Game (ProgressionState, World, Player)]
```

### Endpoints FastAPI

| Method | Path | Tool | Body |
|---|---|---|---|
| GET | `/state/player` | `consult_player_state` | — |
| GET | `/state/skills` | `list_owned_skills` | — |
| POST | `/skills` | `create_skill` | `{skill_spec}` |
| PATCH | `/skills/{id}` | `modify_skill` | `{patch}` |
| DELETE | `/skills/{id}` | `delete_skill` | — |
| POST | `/skills/{id}/allocate` | `allocate_skill_points` | `{stat, points_to_add}` |
| POST | `/skills/{id}/deallocate` | `deallocate_skill_points` | `{stat, points_to_remove}` |
| POST | `/challenges` | `design_challenge` | `{challenge_spec}` |
| POST | `/challenges/{id}/accept` | `accept_challenge` | — |
| GET | `/challenges/{id}` | `get_challenge_state` | — |
| POST | `/challenges/{id}/evaluate` | `evaluate_challenge` | — |
| GET | `/world/enemies` | `list_active_enemies` | — |
| GET | `/contracts/atoms` | `consult_skill_atoms` | — |
| GET | `/contracts/balance` | `consult_balance_config` | — |

### Respuestas

```json
// éxito
{ "ok": true, "data": { ... } }

// error
{ "ok": false, "error": "invalid_spec", "detail": "atom.type 'foo' not in library" }
```

### Rate limiting

- 10 requests/seg por sesión LLM
- Tools de lectura sin límite estricto
- Tools de escritura con cooldown de 100ms

### Audit log

Todo tool call se loggea a `~/.hermes/sim_logs/mcp_audit.log` con:
```
[2026-06-06T15:30:00] [mcp] tool=create_skill args={...} result={ok:true, skill_id:"..."} duration_ms=23
```
