# Challenge Schema

> JSON que el LLM diseña cuando el jugador pide "quiero una quest que me enseñe X". El sistema lo valida, lo spawnea en el mundo, y otorga recompensas al completarlo.

---

## Estructura

```json
{
  "id": "string (auto)",
  "title": "string",
  "narrative_intro": "string",
  "objectives": [ ... ],
  "rewards": { ... },
  "spawn": { ... },
  "failure_conditions": [ ... ],
  "music": "string",
  "vfx": { ... }
}
```

---

## Campos

### `id`, `title`, `narrative_intro`

- `id`: auto-generado `challenge_<hash>`.
- `title`: ej "El entrenamiento del Maestro Roshi".
- `narrative_intro`: texto que se muestra al iniciar (cinemática o HUD). < 500 chars.

### `objectives` (array, required, 1-5 items)

Cada objetivo:
```json
{
  "type": "defeat_enemies | survive | reach_zone | interact | cast_skill | use_combo | no_damage_clear | timed",
  "params": { ... },
  "description": "string (mostrada en HUD)"
}
```

Tipos:

- `defeat_enemies`: `{ "count": 3, "enemy_type": "saibaman", "spawn_pattern": "wave" }`
- `survive`: `{ "duration": 30 }`
- `reach_zone`: `{ "zone_id": "trigger_zone_1" }`
- `interact`: `{ "npc_id": "roshi", "action": "talk" }`
- `cast_skill`: `{ "skill_id": "kamehameha_001", "min_times": 3 }` (fuerza al jugador a usar la skill que se le está enseñando)
- `use_combo`: `{ "combo_skill_id": "kamehameha_galick", "min_times": 1 }`
- `no_damage_clear`: `{}` (sub-objetivo cualitativo)
- `timed`: `{ "time_limit": 60, "must_complete": true }`

Todos los objetivos deben completarse para授予 la recompensa (a menos que alguno sea "optional: true").

### `rewards` (dict, required)

```json
{
  "grant_skills": [
    { "skill_spec": { ...SkillSpec completo... } }
  ],
  "skill_points": 3,
  "proficiency": 1,
  "items": [ { "id": "saibaman_ear", "count": 1 } ]
}
```

`grant_skills`: el LLM incluye la SkillSpec completa de la skill que se está enseñando. Se valida con `SkillValidator` y se crea como `SkillResource` owned por el jugador.

`skill_points`: currency universal para distribuir.

`proficiency`: suma al mastery tier (gating de soft caps).

### `spawn` (dict, required)

```json
{
  "npcs": [
    { "template": "master_roshi", "position": [0, 0, 10], "dialogue": "...", "role": "quest_giver" }
  ],
  "enemies": [
    { "template": "saibaman", "count": 3, "spawn_pattern": "wave", "spawn_positions": [[5,0,15], [-5,0,15], [0,0,20]] }
  ],
  "zones": [
    { "id": "arena_1", "kind": "ring", "position": [0,0,15], "radius": 15 }
  ],
  "props": [
    { "template": "barrel", "position": [3, 0, 8] }
  ]
}
```

`spawn_pattern`:
- `wave`: oleadas (se spawnean progresivamente)
- `surround`: alrededor del player al iniciar
- `sequential`: uno por uno
- `at_start`: todos al inicio

### `failure_conditions` (array, optional)

```json
[
  { "type": "player_death", "params": {} },
  { "type": "time_limit", "params": { "seconds": 300 } }
]
```

Si se cumple, challenge falla → no otorga recompensas. Opcional: retry con scaled-down enemies.

### `music` (string, optional)

Path o keyword para la música del challenge.

### `vfx` (dict, optional)

Ambiente visual: skybox, fog, lighting override.

---

## Ejemplo completo: Entrenamiento del Maestro Roshi

```json
{
  "title": "El entrenamiento del Maestro Roshi",
  "narrative_intro": "Maestro Roshi aparece frente a ti. 'Joven... si quieres aprender el Kamehameha, primero deberás sobrevivir a mis Saibamen. ¡KAME... HAME... HA!'",
  "objectives": [
    {
      "type": "cast_skill",
      "params": { "skill_id": "kamehameha_001", "min_times": 1 },
      "description": "Usa tu Kamehameha al menos una vez"
    },
    {
      "type": "defeat_enemies",
      "params": { "count": 3, "enemy_type": "saibaman" },
      "description": "Derrota a los 3 Saibamen (0/3)"
    }
  ],
  "rewards": {
    "grant_skills": [
      {
        "skill_spec": {
          "name": "Kamehameha",
          "description": "Concentra energía en las palmas y libérala en un rayo frontal devastador.",
          "flavor_text": "¡Kame... Hame... HA!",
          "category": "ranged_projectile",
          "type": "damage",
          "target_resolver": { "kind": "aoe", "params": { "position": "in_front_of_caster", "radius": 5 } },
          "designed_max": { "amount": 100, "radius": 5, "cooldown": 8, "stamina": 50, "charge_time": 2 },
          "atoms": [
            { "type": "buff", "params": { "stat": "damage_mult", "value": 2.0, "kind": "multiply", "duration": 3.0 } },
            { "type": "trigger", "params": { "when": "delay", "delay": 2.0, "then_effect": "burst_aoe_2" } },
            { "type": "burst_aoe", "params": { "radius": 5, "amount": 100, "damage_type": "energy", "falloff": "linear" } }
          ],
          "costs": { "stamina": 50, "cooldown": 8, "charge_time": 2 }
        }
      }
    ],
    "skill_points": 3,
    "proficiency": 1
  },
  "spawn": {
    "npcs": [
      { "template": "master_roshi", "position": [0, 0, -8], "dialogue": "¡Demuéstrame tu poder!", "role": "quest_giver" }
    ],
    "enemies": [
      { "template": "saibaman", "count": 3, "spawn_pattern": "wave", "spawn_positions": [[5,0,15], [-5,0,15], [0,0,20]] }
    ]
  },
  "failure_conditions": [
    { "type": "player_death", "params": {} }
  ]
}
```

---

## Validación

`ChallengeValidator.validate(spec)` aplica:

1. `title`, `objectives`, `rewards`, `spawn` no vacíos
2. `len(objectives) <= 5`
3. Cada objective.type es válido
4. `grant_skills[].skill_spec` pasa `SkillValidator.validate`
5. `skill_points <= 10` (un challenge da máximo 10 puntos)
6. `proficiency <= 3` (un challenge da máximo 3 puntos de proficiency)
7. `enemies[].count <= 20` (limita escalado)
8. NPCs/enemies referenciados tienen template que existe en la librería

Si pasa → se crea `ChallengeResource`, se enqueja en el sistema, se spawnea en el mundo.
