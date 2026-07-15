# Skill Instance Schema

> JSON que el LLM envía al MCP para crear o modificar una skill. Validado por `SkillValidator` antes de crear la `SkillResource` en Godot.

---

## Estructura

```json
{
  "id": "string (auto-generated si es create)",
  "name": "string",
  "description": "string",
  "flavor_text": "string",
  "category": "enum[string]",
  "type": "damage | control",
  "target_resolver": { ... },
  "designed_max": { ... },
  "atoms": [ ... ],
  "combo_triggers": [ ... ],
  "costs": { ... },
  "vfx": { ... },
  "icon_hint": "string"
}
```

---

## Campos

### `id` (string, optional en create)

Identificador único. Auto-generado como `<name>_<hash4>` si no se provee. Requerido en `modify_skill`.

### `name` (string, required)

Nombre visible al jugador. Sin restricciones de longitud pero recomendado < 30 chars.

### `description` (string, required)

Descripción mecánica. Aparece en el tooltip. < 200 chars.

### `flavor_text` (string, optional)

Texto de ambientación. Aparece al castear. < 100 chars. Ej: "¡Kame... Hame... HA!"

### `category` (enum, optional)

Tag semántico para UI. Cualquier string es válido, pero se sugieren:
- `ranged_projectile`, `melee_swing`, `aoe_burst`, `persistent_zone`
- `buff_self`, `buff_aura`
- `control_motion`, `control_mind`, `control_spatial`
- `heal_self`, `heal_ally`
- `dash`, `summon_npc`
- `combo_trigger`
- `passive`

### `type` (enum, required)

`"damage"` o `"control"`. Determina qué átomos son válidos (ver validación).

### `target_resolver` (dict, required)

Declara sobre quién actúa la skill. Formato:
```json
{
  "kind": "self | selected_npc | nearest_npc_in_range | aoe | self_aoe | projectile_carrier | chain | zone_entered",
  "params": { ... }
}
```

Ejemplos:
```json
{ "kind": "self" }
{ "kind": "selected_npc" }
{ "kind": "nearest_npc_in_range", "params": { "max_distance": 15 } }
{ "kind": "aoe", "params": { "position": "selected_npc", "radius": 5 } }
{ "kind": "self_aoe", "params": { "radius": 8 } }
{ "kind": "chain", "params": { "max_hops": 4, "decay": 0.3 } }
```

### `designed_max` (dict, required)

Los valores "máximos pensados por el LLM" para cada stat. El sistema clampea y los usa como techo. Claves válidas (todas opcionales, las que falten = 0):

```json
{
  "amount": 100,
  "dpt": 20,
  "radius": 5,
  "duration": 5,
  "cooldown": 8,
  "stamina": 50,
  "charge_time": 2,
  "knockback": 8,
  "crit_chance": 0.1,
  "speed": 30,
  "hitbox_radius": 0.5,
  "lifetime": 5,
  "count": 1,
  "shield_amount": 200,
  "heal_amount": 100,
  "hot_per_tick": 10,
  "magnitude": 1.0
}
```

Los valores se clampean a `data/contracts/stat_caps.json`.

### `atoms` (array, required)

Lista de átomos que componen la skill. Cada átomo:
```json
{
  "type": "hit | dot | burst_aoe | persistent_zone | heal | hot | shield | move | morph | buff | status | mind | projectile | npc | zone | trigger",
  "params": { ... },
  "applies_to_target": "primary | all_in_aoe | chain_target | carrier"
}
```

`applies_to_target`:
- `primary` (default): el target principal del target_resolver
- `all_in_aoe`: cada NPC en el AOE (requiere target_resolver kind=ao|self_aoe)
- `chain_target`: cada NPC en el chain (requiere target_resolver kind=chain)
- `carrier`: el proyectil (requiere projectile atom previo)

### `combo_triggers` (array, optional)

Max 2. Cada uno:
```json
{
  "when": "on_skill_used | on_hit | on_kill | on_health_below | on_status_applied",
  "condition": "string (opcional, expresión simple)",
  "trigger_skill_id": "string (ID de skill owned por caster)"
}
```

### `costs` (dict, optional)

```json
{
  "stamina": 50,
  "cooldown": 8.0,
  "charge_time": 2.0,
  "hp_cost": 0
}
```

Cada uno escalado por cost_effective (ver `balance_config.json`).

### `vfx` (dict, optional)

```json
{
  "cast_sound": "res://assets/sfx/kame_charge.ogg",
  "cast_particle": "res://assets/vfx/blue_glow.tscn",
  "hit_sound": "res://assets/sfx/explosion.ogg",
  "screen_text": "¡Kamehameha!"
}
```

### `icon_hint` (string, optional)

Path o keyword para el icono. UI puede resolverlo después.

---

## Ejemplo completo: Kamehameha

```json
{
  "name": "Kamehameha",
  "description": "Concentra energía en las palmas y libérala en un rayo frontal devastador.",
  "flavor_text": "¡Kame... Hame... HA!",
  "category": "ranged_projectile",
  "type": "damage",
  "target_resolver": {
    "kind": "aoe",
    "params": { "position": "in_front_of_caster", "radius": 5 }
  },
  "designed_max": {
    "amount": 100,
    "radius": 5,
    "cooldown": 8,
    "stamina": 50,
    "charge_time": 2
  },
  "atoms": [
    { "type": "buff", "params": { "stat": "damage_mult", "value": 2.0, "kind": "multiply", "duration": 3.0 } },
    { "type": "trigger", "params": { "when": "delay", "delay": 2.0, "then_effect": "burst_aoe_2" } },
    { "type": "burst_aoe", "params": { "radius": 5, "amount": 100, "damage_type": "energy", "falloff": "linear" } }
  ],
  "costs": { "stamina": 50, "cooldown": 8, "charge_time": 2 },
  "vfx": { "cast_particle": "blue_glow", "screen_text": "¡Kamehameha!" }
}
```

---

## Ejemplo: Serious Punch (One Punch Man)

```json
{
  "name": "Puño Serio",
  "description": "Un solo golpe que termina cualquier combate.",
  "flavor_text": "...",
  "category": "melee_swing",
  "type": "damage",
  "target_resolver": { "kind": "selected_npc" },
  "designed_max": { "amount": 9999, "knockback": 200, "cooldown": 86400, "stamina": 0 },
  "atoms": [
    { "type": "move", "params": { "kind": "dash", "distance": 3, "duration": 0.05, "target_relative": "selected_npc" } },
    { "type": "hit", "params": { "amount": 9999, "damage_type": "true" } },
    { "type": "move", "params": { "kind": "launch", "distance": 200, "target_relative": "selected_npc" } }
  ],
  "costs": { "stamina": 0, "cooldown": 86400 }
}
```

---

## Validación

`SkillValidator.validate(spec)` aplica:

1. `name`, `description`, `type`, `target_resolver`, `designed_max`, `atoms` no vacíos
2. `len(atoms) <= 5` (max_atoms_per_skill)
3. `len(combo_triggers) <= 2` (max_combo_triggers_per_skill)
4. Cada `atom.type` debe existir en `skill_atoms.json`
5. Cada `atom.params` debe coincidir con el schema del átomo (tipos, requeridos)
6. Átomos deben coincidir con `type`:
   - `damage` skills: no `move`, no `morph`, no `status`, no `mind` (sí `hit`, `dot`, `burst_aoe`, `persistent_zone`, `heal`, `hot`, `shield`, `buff`, `projectile`, `npc`, `zone`, `trigger`)
   - `control` skills: no `hit`, no `dot`, no `burst_aoe` (sí `move`, `morph`, `status`, `mind`, `buff`, `persistent_zone`, `heal`, `hot`, `shield`, `npc`, `zone`, `trigger`)
7. Max 1 heal/hot/shield atom por skill
8. `designed_max.*` clampeado a `stat_caps.json`
9. `target_resolver.kind` debe estar en `atom.target_resolvers` para cada átomo
10. Combo `trigger.atom` con `when=on_skill_used` requiere que `then_skill_id` apunte a una skill owned

Si pasa → se crea `SkillResource`. Si falla → 422 con detalle.
