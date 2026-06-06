# DESIGN — Sistema de Skills Genérico + MCP Dungeon Master

> Documento de diseño vivo. Define la arquitectura del sistema de skills data-driven y el plan de integración con un LLM como Dungeon Master vía MCP.
>
> Estado actual: combat MVP funcional. Esta fase refactoriza skills a un sistema genérico controlado por datos, sentando las bases para que un LLM diseñe skills, challenges y progresión.

---

## 1. Visión

El jugador imagina una habilidad (Kamehameha, Tsukuyomi, Serious Punch, Uraraka Zero-G...), la pide al LLM Dungeon Master, y la IA:

1. **Diseña la skill** componiendo átomos primitivos (damage, motion, control, transform, etc.) — máximo 5 átomos por skill.
2. **Construye un challenge temático** (NPCs, enemigos, diálogo, objetivo, recompensa) que enseña la skill.
3. **Otorga la skill a nivel 1** — funcional pero muy débil, casi inútil.
4. **Da skill points** al completar el challenge.
5. **El jugador distribuye los skill points** entre los stats de todas sus skills.

El resultado es **mastery emergente**: la IA no da un Kamehameha "lvl 10". Da la semilla. El jugador la cultiva con puntos.

El MCP es el **puente HTTP** entre el LLM y el juego. El LLM no toca el juego directamente — solo envía `SkillSpec` y `ChallengeSpec` JSONs validados.

---

## 2. Taxonomía

### 2.1 Tipos de skill (alto nivel)

- **Damage skill** — diseñada para infligir daño. Atomos: hit, dot, burst_aoe, persistent_zone, projectile, npc, trigger.
- **Control skill** — diseñada para alterar el estado de un target. Atomos: move, morph, buff, status, mind, zone.

> Regla de enforcement: `move`/`morph` solo válidos en control skills. `hit`/`dot` solo en damage skills. Validado en `SkillValidator`.

### 2.2 Target resolvers

Sobre **quién** actúa la skill. Cada skill declara uno:

| Resolver | Descripción |
|---|---|
| `self` | El caster mismo (buffs, transforms) |
| `selected_npc` | El NPC bajo el retículo del jugador |
| `nearest_npc_in_range` | Auto-target del NPC más cercano dentro de X metros |
| `aoe(position, radius)` | Todos los NPCs en un área (center explícito) |
| `self_aoe(radius)` | Todos los NPCs en radio alrededor del caster |
| `projectile_carrier` | El efecto viaja con un proyectil (vía `projectile` atom) |
| `chain(max_hops, decay)` | El efecto salta entre NPCs cercanos |
| `zone_entered(zone_id)` | Activa cuando un NPC entra en una zona existente |

### 2.3 Control types

Cuando una control skill actúa sobre un target, define **cómo** lo controla:

- **motion** — telekinesis, pull, push, launch, swap, banish, dash
- **transform** — polymorph, scale, possess_body
- **mind** — charm, fear, mind_control, confuse, taunt
- **state** — stun, root, slow, silence, disarm, sleep, blind
- **spatial** — create_zone, create_wall, mark_target

### 2.4 Categorías de skills (referencia semántica para el LLM)

El LLM no necesita atarse a una categoría fija, pero el sistema tiene categorías recomendadas para que los tags del UI tengan sentido:

`ranged_projectile`, `melee_swing`, `aoe_burst`, `persistent_zone`, `buff_self`, `buff_aura`, `control_motion`, `control_mind`, `control_spatial`, `heal_self`, `heal_ally`, `dash`, `summon_npc`, `combo_trigger`, `passive`.

---

## 3. Los 14 átomos

Lista cerrada, finita, parametrizable. El LLM compone skills eligiendo átomos y seteando parámetros.

### 3.1 damage
| ID | Parámetros | Descripción |
|---|---|---|
| `hit` | `amount, damage_type, knockback, crit_chance` | Un golpe único |
| `dot` | `dpt, duration, tick_interval, status_on_tick` | Damage over time |
| `burst_aoe` | `radius, amount, damage_type, falloff` | Burst instantáneo en área |
| `persistent_zone` | `radius, duration, dpt, tick, slow_inside` | Zona de daño persistente |

### 3.2 heal
| ID | Parámetros | Descripción |
|---|---|---|
| `heal` | `amount, target` | Curación instantánea |
| `hot` | `amount_per_tick, duration, tick, target` | Curación over time |
| `shield` | `amount, duration, absorbs, target` | Escudo que absorbe daño |

### 3.3 motion
| ID | Parámetros | Descripción |
|---|---|---|
| `move` | `kind: dash|teleport|knockback|pull|launch, distance, duration, target` | Mueve al caster o target |

### 3.4 transform
| ID | Parámetros | Descripción |
|---|---|---|
| `morph` | `kind: polymorph|scale|possess, into, duration, stat_overrides` | Transforma al target |
| `buff` | `stat, value, kind: add|multiply, duration, target` | Buff/debuff de stat |

### 3.5 control
| ID | Parámetros | Descripción |
|---|---|---|
| `status` | `kind: stun|root|slow|silence|disarm|sleep|blind|charm|fear|taunt|confuse, duration, magnitude, target` | Aplica un estado |
| `mind` | `kind: mind_control|charm|taunt, duration, post_effect, target` | Control mental |

### 3.6 summon
| ID | Parámetros | Descripción |
|---|---|---|
| `projectile` | `speed, hitbox_radius, lifetime, on_hit_effect, friendly, owner` | Spawnea proyectil |
| `npc` | `template, count, duration, friendly, on_spawn_effect, on_death_effect, position` | Spawnea NPC |
| `zone` | `kind, radius, duration, tick, friendly, position, enter_effect` | Spawnea zona persistente |

### 3.7 trigger
| ID | Parámetros | Descripción |
|---|---|---|
| `trigger` | `when: on_hit|on_kill|on_take_damage|on_health_below|on_skill_used|on_status_applied|delay, condition, then_effect, then_skill_id` | Efecto retardado o condicional |

---

## 4. Sistema de balanceo (4 capas)

El balanceo es **el corazón de "muy muy muy débil"**. Cuatro capas que se acumulan:

### 4.1 Capa 1 — Lvl1 forzado al 5%

Cualquier stat arranca al **5% del `designed_max`** que el LLM declare, sin importar lo que pida. Enforcement en el ejecutor de Godot (`Balance.compute_effective`), no en el LLM. El LLM puede escribir `designed_max.damage: 100` y el sistema lo clampea a `5` para el primer uso.

### 4.2 Capa 2 — Soft cap con diminishing returns

Cada stat acepta hasta **5 skill points**. Curva sublineal:
```
value = lvl1 + (soft_target - lvl1) * (points / 5) ^ 0.7
soft_target = designed_max * 0.5
```
Los primeros 2 puntos dan la mayor parte del beneficio. Anti-min-max.

### 4.3 Capa 3 — Hard cap por Proficiency (mastery tiers)

El **proficiency** sube con cada reto completado (universal, no por skill). Gatea qué tan cerca del 100% se puede llegar aunque se inviertan todos los puntos:

| Tier | Puntos acumulados | Soft cap efectivo |
|---|---|---|
| Novice | 0 | 10% |
| Apprentice | 5 | 20% |
| Adept | 15 | 35% |
| Expert | 30 | 50% |
| Master | 50 | 65% |
| Grandmaster | 75 | 80% |
| Legend | 100 | 92% |
| Mythic | 150 | 100% |

A Novice, aunque se gasten 5 puntos en una skill, queda cappeado a 10% del max. Esto fuerza a diversificar.

### 4.4 Capa 4 — Cost scaling (spam-friendly al inicio)

Stats invertidas (cooldown, stamina, charge_time) escalan al revés, pero se correlacionan con el poder actual. A lvl1 spameas barato y débil; subir = más poder, más costo.

### 4.5 Ejemplo: Kamehameha

LLM diseña con `designed_max: {damage:100, radius:5, cooldown:8, stamina:50, charge:2}`.

| Stage | damage | radius | cd | stam | sensación |
|---|---|---|---|---|---|
| Lvl1 Novice (0 pts) | 5 | 0.25m | 12s | 15 | tickle ray |
| +2 pts damage | 16 | 0.25m | 12s | 15 | cosquillas eléctricas |
| +5 pts damage (soft) | 50 | 0.25m | 12s | 15 | golpe serio |
| Adept (15 pts total) | 65 | 0.5m | 10s | 20 | wow |
| Expert (30 pts, full soft) | 80 | 1m | 8s | 30 | dominante |
| Master + max pts | 87 | 1.4m | 7s | 35 | devastador |
| Mythic (150 pts total) | 100 | 5m | 4s | 50 | arma definitiva |

150 skill points = muchas quests. Aún en Mythic, la skill tiene techo (100) y no rompe el juego.

---

## 5. Límites de validación (lo que el LLM no puede romper)

| Regla | Enforcement |
|---|---|
| Stat inicial ≥ 5% del designed_max | hard floor en `Balance.compute_effective` |
| Soft cap por proficiency tier | clamp en `Balance.compute_effective` |
| Hard cap por proficiency tier | clamp en `Balance.compute_effective` |
| Max 5 átomos por skill | validator en `SkillValidator.validate_count` |
| Max 3 targets por efecto (no `aoe`+`chain`+`zone` juntos) | validator |
| Max 2 combo triggers por skill | validator |
| `designed_max` bounded por `stat_caps.json` | ceiling absoluto por stat type |
| `move`/`morph`/`status`/`mind`/`buff` solo en control skills | validator |
| `hit`/`dot`/`burst_aoe`/`persistent_zone` solo en damage skills | validator |
| `heal`/`hot`/`shield` permitidos en ambos pero max 1 | validator |
| Combo `trigger` solo con `when: on_skill_used`+`then_skill_id` existente | validator |

---

## 6. Combo skills

Una combo skill es una skill cuyo `trigger` atom tiene `when: on_skill_used` y `then_skill_id` apuntando a otra skill owned por el jugador.

Ejemplo: `Kamehameha Galick` combo que dispara 50 daño bonus cuando se usa Kamehameha contra un enemigo con HP > 50%.

```yaml
name: Kamehameha Galick
type: combo_trigger
combo_with: kamehameha_001
trigger: { when: on_skill_used, target: kamehameha_001, condition: enemy_hp > 0.5 }
effects: [ hit: { amount: 50, damage_type: energy } ]
```

Limit: 2 combo triggers por skill, validados al diseñar.

---

## 7. Modificación de skills existentes

El LLM puede `PATCH` skills del jugador:

- Cambiar nombre/flavor
- Agregar/quitar átomos (dentro del cap de 5)
- Cambiar `designed_max` (re-clampeado por el balance)
- Agregar combo triggers
- Cambiar `target_resolver`

El sistema re-valida con las mismas reglas y reaplica los caps. El LLM **no puede** renombrar átomos, cambiar la taxonomía de control, ni romper validaciones existentes.

---

## 8. Estructura de datos

```
data/
├── contracts/
│   ├── skill_atoms.json          # los 14 átomos + schemas
│   ├── stat_caps.json            # límites absolutos por stat
│   ├── balance_config.json       # curvas, tiers, soft/hard caps
│   ├── skill_instance_schema.md  # JSON que el LLM envía
│   ├── challenge_schema.md       # quest/dungeon que el LLM diseña
│   └── mcp_tools.md              # lista de tools del MCP
└── skills/
    ├── kamehameha.tres           # ejemplo completo LLM-authored
    ├── gomu_gomu_pistol.tres
    ├── sharingan_tsukuyomi.tres
    ├── serious_punch.tres
    └── uraraka_zero_gravity.tres
```

---

## 9. Arquitectura Godot

```
scripts/
├── skill/
│   ├── skill_resource.gd        # Resource: SkillSpec (datos)
│   ├── skill_effect.gd          # Interfaz SkillEffect (apply)
│   ├── balance.gd               # Curvas, caps, compute_effective
│   ├── effect_library.gd        # 14 átomos implementados
│   ├── target_resolver.gd       # Resuelve target cada frame
│   ├── skill_executor.gd        # Nodo: ejecuta un SkillResource
│   ├── skill_validator.gd       # Valida SkillSpec (count, caps, taxonomy)
│   └── progression_state.gd     # Skill points, proficiency, allocation
├── player.gd                    # Refactor: delega skills al sistema
└── ...
```

### 9.1 SkillResource (data layer)

```gdscript
class_name SkillResource
extends Resource

@export var id: StringName
@export var name: String
@export var description: String
@export var flavor_text: String
@export var category: StringName  # ranged_projectile, melee_swing, etc.
@export var type: StringName  # "damage" or "control"
@export var target_resolver: Dictionary
@export var designed_max: Dictionary  # {stat_name: value}
@export var atoms: Array[Dictionary]  # [{type: "hit", params: {...}}, ...]
@export var combo_triggers: Array[Dictionary]
@export var costs: Dictionary  # {stamina: 50, cooldown: 8.0, charge_time: 2.0}
@export var vfx: Dictionary  # {sound: "...", particle: "...", screen: "..."}
@export var icon: Texture2D
```

### 9.2 Balance (curvas)

```gdscript
class_name Balance
extends RefCounted

static func compute_effective(stat_name: String, designed_max: float, points: int, max_points: int, proficiency: int) -> float:
    # Capa 1: lvl1 floor
    var lvl1 = designed_max * 0.05
    # Capa 2: soft cap con diminishing
    var soft = designed_max * 0.5
    var soft_progress = pow(float(points) / float(max_points), 0.7) if points > 0 else 0.0
    var soft_value = lvl1 + (soft - lvl1) * soft_progress
    # Capa 3: hard cap por proficiency
    var tier = get_proficiency_tier(proficiency)
    var hard_cap = designed_max * tier.soft_cap_ratio
    var level_bonus = get_level_bonus(proficiency)  # 0..1
    # Capa 4: linear interp entre soft_value y hard_cap
    return soft_value + (hard_cap - soft_value) * level_bonus
```

### 9.3 EffectLibrary (átomos)

Cada átomo es una función pura:
```gdscript
class_name EffectLibrary
extends RefCounted

static func apply_hit(executor: SkillExecutor, atom: Dictionary) -> void:
    var amount = atom.amount * executor.balance_mult
    var target = executor.target_resolver.resolve()
    target.take_damage(amount, atom.damage_type)
    if atom.knockback > 0:
        target.apply_knockback(...)
```

### 9.4 ProgressionState (state layer)

```gdscript
class_name ProgressionState
extends Node

var skill_points: int = 0  # available to spend
var proficiency: int = 0  # total earned across all skills
var allocations: Dictionary = {}  # {skill_id: {stat_name: points}}
var owned_skills: Array[StringName] = []

func get_effective_stat(skill: SkillResource, stat_name: String) -> float:
    var designed = skill.designed_max.get(stat_name, 0.0)
    var points = allocations.get(skill.id, {}).get(stat_name, 0)
    return Balance.compute_effective(stat_name, designed, points, 5, proficiency)
```

### 9.5 Player.gd refactor

`player.gd` ya no tiene skills hardcoded. Tiene:
- `skill_bar: Array[StringName]` — IDs de skills asignadas a botones
- `current_skill: SkillResource` — la skill activa
- Llama a `SkillExecutor.execute(skill, self)` cuando se presiona el botón

Las skills básicas (light attack, heavy attack, parry, dodge) se cargan desde data:
- `data/skills/light_attack.tres`
- `data/skills/heavy_attack.tres`
- `data/skills/parry.tres`
- `data/skills/dodge.tres`

El player solo tiene `move()`, `cast_skill(skill_id)`, `parry()` como antes — pero `cast_skill` ahora dispatcha a `SkillExecutor` con el SkillResource.

---

## 10. MCP (fase posterior)

### 10.1 Tools del MCP

```python
# LLM-facing tools
create_skill(player_request: str) -> SkillSpec       # LLM diseña + valida
modify_skill(skill_id: str, patch: dict) -> SkillSpec
delete_skill(skill_id: str) -> None
list_player_skills() -> [SkillSpec]
get_player_state() -> PlayerState
allocate_points(skill_id, stat, points) -> bool
design_challenge(intent: str) -> ChallengeSpec        # AI diseña quest
accept_challenge(challenge_id) -> None
get_challenge_state() -> ChallengeState
```

### 10.2 Transporte

```
[Chat LLM]
   ↓ MCP tools (JSON-RPC over stdio / SSE)
[MCP server (Python, FastMCP)]
   ↓ HTTP POST
[FastAPI bridge :8765]
   ↓ HTTPS
[Godot MCPReceiver autoload :8766]
   ↓ direct method calls
[Game (Player, World, ProgressionState)]
```

### 10.3 Loop completo

1. Jugador: "quiero un Kamehameha"
2. LLM: `mcp.create_skill("Kamehameha estilo DBZ")` → FastAPI valida, Godot crea SkillResource con `designed_max: {damage:100, ...}` y lo registra
3. LLM: `mcp.design_challenge("Enseñarte el Kamehameha con Maestro Roshi")` → FastAPI valida, Godot spawnea NPC + enemigos
4. Jugador juega, completa el challenge
5. Sistema: `grant_skill(kamehameha)` + `grant_skill_points(3)`
6. Jugador abre skill allocator UI, distribuye puntos
7. Su Kamehameha crece

---

## 11. Fases de implementación

### Fase 1 — Sistema de skills genérico (esta fase)

- [ ] `docs/DESIGN.md` (este doc)
- [ ] `data/contracts/*.json` — los 6 contratos
- [ ] `scripts/skill/skill_resource.gd` (Resource)
- [ ] `scripts/skill/skill_effect.gd` (interfaz)
- [ ] `scripts/skill/balance.gd` (curvas)
- [ ] `scripts/skill/effect_library.gd` (átomos)
- [ ] `scripts/skill/target_resolver.gd`
- [ ] `scripts/skill/skill_executor.gd`
- [ ] `scripts/skill/skill_validator.gd`
- [ ] `scripts/skill/progression_state.gd`
- [ ] Refactor `scripts/player.gd` (skills vienen de data)
- [ ] `scripts/ui/skill_allocator.gd` + escena
- [ ] `data/skills/kamehameha.tres` (ejemplo)
- [ ] `scenes/skills_test.tscn` (validación)

### Fase 2 — FastAPI bridge + Godot MCPReceiver

- [ ] `mcp_bridge/server.py` (FastAPI)
- [ ] `scripts/mcp_receiver.gd` (autoload)
- [ ] Endpoints: `create_skill`, `modify_skill`, `delete_skill`, `spawn_npc`, `spawn_enemy`, `set_objective`, `grant_skill`, `grant_skill_points`, `get_state`, `spawn_challenge`, `evaluate_challenge`

### Fase 3 — MCP server

- [ ] `mcp_server/server.py` (FastMCP)
- [ ] Tools: `create_skill`, `modify_skill`, `design_challenge`, `accept_challenge`, `get_player_state`, `allocate_points`
- [ ] Conexión con FastAPI bridge

### Fase 4 — UI completa

- [ ] Skill wheel / hotbar
- [ ] Skill allocator screen
- [ ] Challenge HUD
- [ ] Skill log (qué skills tengo, qué stats, cuánto poder real)

### Fase 5 — Contenido

- [ ] NPC templates (saibaman, saibaman_pack, sensei, etc.)
- [ ] Enemy templates
- [ ] Challenge presets
- [ ] VFX library
- [ ] Audio library

---

## 12. Decisiones de diseño abiertas (a resolver)

- **L2/R2 sprint mapping** — ya resuelto (axis=4 / axis=5).
- **Target selection per-skill** — sí, cada skill declara su `target_resolver`. Lock-on es el default para `selected_npc` y `nearest_npc_in_range`.
- **Botón asignación** — skill wheel (radial) o hotbar (8 slots). Decisión de UI en fase 4.
- **Modificación de skills** — el LLM puede patchar skills existentes; se re-valida con las mismas reglas.
- **Combo skills** — sí, con `trigger` atom + `then_skill_id`.
- **Stats invertidos (cooldown, stamina)** — escalan al revés desde lvl1, costo correlacionado con poder actual.

---

## 13. Anti-patterns evitados

- ❌ Skill library predefinida con 100 named skills → ✅ librería abierta de 14 átomos combinables
- ❌ Balanceo hardcoded por skill → ✅ fórmulas genéricas que aplican a cualquier SkillSpec
- ❌ LLM toca el juego directamente → ✅ todo via JSON validado
- ❌ Skill crece lineal con skill points → ✅ diminishing returns
- ❌ Player puede trivial-min-maxear una skill → ✅ proficiency gating + diminishing returns
- ❌ "Kamehameha" en lvl 1 hace daño real → ✅ forzado a 5% del designed_max
- ❌ LLM inventa átomos nuevos → ✅ librería cerrada, validada

---

**Última actualización:** ver `git log docs/DESIGN.md` o revisar changelog al pie.
