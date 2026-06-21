# Plan: Migración a Primitivas 3D (No Models / No Animations)

**Estado:** Pendiente de aprobación
**Fecha:** 2026-06-21
**Contexto:** Las sesiones de modelos 3D han sido un desastre — Blender MCP no funcionó, importar assets de otros proyectos fue bloqueante, y la escena no se puede ver bien durante el desarrollo (a ciegas). Se decide eliminar la dependencia de modelos 3D externos y animaciones.

---

## 1. Decisión de diseño

**Todos los personajes y objetos del juego serán primitivas 3D básicas** (`Cube`, `Sphere`, `Capsule`, `Cylinder`) instanciadas vía GDScript.

**Las armas NO tendrán forma física** — son "abstract effects emitters": un node invisible que aplica stats y dispara efectos al activarse (hitbox invisible, partículas, damage).

**Animaciones = transformaciones procedurales** (lerp, tweens, código). Sin `AnimationPlayer`, sin `FBX`, sin `Skeleton3D`, sin retargeting.

---

## 2. Lo que se elimina

| Categoría | Acción |
|-----------|--------|
| `assets/imports/characters/realpg/*.fbx` | Eliminar todos los .fbx y .import |
| `assets/imports/animations/realpg/**/*.fbx` | Eliminar todos los .fbx y .import |
| `assets/imports/animations/realpg/**/*.fbx.import` | Eliminar |
| `assets/models/weapons/*.fbx` y `.tres` de meshes | Eliminar (mantener solo .tres de data) |
| `data/bonemap_*.tres`, `data/humanoid_profile.tres` | Eliminar (innecesarios sin retarget) |
| `scripts/tools/model_animation_viewer.gd` | Eliminar |
| `scripts/tools/camera_orbit.gd` | Eliminar (sin modelos, sin necesidad) |
| `scenes/tools/model_animation_viewer.tscn` | Eliminar |
| `scenes/tools/` (si solo contiene el viewer) | Eliminar carpeta |
| `nodes/import_as_skeleton_bones=true` en cualquier .import | N/A (no hay .import) |

---

## 3. Lo que se conserva

| Categoría | Estado |
|-----------|--------|
| `data/contracts/*.json` | **Conservar** — bosses, balance, schemas |
| `data/skills/*.tres` | **Conservar** — definiciones de skills (ya son data-driven) |
| `data/weapons/*.tres` | **Conservar** — solo las stats, NO meshes |
| `data/characters/*.tres` | **Conservar** |
| `scripts/character.gd` | **Conservar** — ya usa primitivas |
| `scripts/player.gd`, `scripts/enemy.gd`, `scripts/dummy.gd` | **Conservar** |
| `scripts/combat/*.gd` | **Conservar** |
| `scripts/skill/*.gd` | **Conservar** — usar procedural effects (sin AnimationPlayer) |
| `scripts/missions/*.gd`, `scripts/objectives/*.gd` | **Conservar** |
| `scripts/mcp/*.gd` | **Conservar** — el MCP ya funciona sin 3D assets |
| `scenes/play.tscn`, `player.tscn`, `enemy.tscn`, `npc*.tscn`, `dummy.tscn` | **Conservar/modificar** |
| `scripts/altar.gd`, `scripts/hud.gd`, `scripts/ui/*` | **Conservar** |

---

## 4. Lo que se modifica

### 4.1 `WeaponResource` (data/weapons/*.tres + scripts/skill/weapon_resource.gd)

**Quitar** cualquier referencia a mesh/grip/visual.

**Mantener** solo stats y metadata:
```gdscript
class_name WeaponResource extends Resource

@export var id: StringName
@export var display_name: String
@export var family: int          # sword, axe, bow, staff, etc.
@export var hands: int           # 1 or 2
@export var designed_stats: Dictionary
@export var stat_scaling: Dictionary
@export var attribute_modifiers: Dictionary
@export var class_dmg_mult: Dictionary
@export var effect_tags: PackedStringArray  # ["fire", "ice", etc.]
@export var skill_ids: Array[StringName]    # skills que este arma habilita
# NO mesh_path, NO grip_offset, NO visual_rotation
```

### 4.2 Personaje procedural (player, enemy, NPC, boss)

Cada `EntityCharacter` se construye en `_ready()` desde su `CharacterResource`:

```gdscript
func _build_visual() -> void:
    # 1. Body = CapsuleMesh (altura/escala desde data)
    var body := MeshInstance3D.new()
    body.mesh = CapsuleMesh.new()
    body.mesh.height = data.body_height  # ej 1.8
    body.mesh.radius = data.body_radius  # ej 0.3
    var mat := StandardMaterial3D.new()
    mat.albedo_color = data.body_color   # Color desde data
    body.material_override = mat
    add_child(body)

    # 2. Head = Sphere pequeña encima
    var head := MeshInstance3D.new()
    head.mesh = SphereMesh.new()
    head.mesh.radius = 0.15
    head.position.y = data.body_height * 0.5
    var head_mat := StandardMaterial3D.new()
    head_mat.albedo_color = data.head_color
    head.material_override = head_mat
    add_child(head)

    # 3. Weapon proxy = un box invisible en la mano (solo para hitbox debug)
    var weapon_proxy := Node3D.new()
    weapon_proxy.name = "WeaponProxy"
    weapon_proxy.position = Vector3(0.5, 1.2, 0)  # posición mano derecha
    add_child(weapon_proxy)
```

**CharacterResource** se extiende con:
```json
{
  "id": "boss_frieza",
  "body_height": 2.0,
  "body_radius": 0.35,
  "body_color": "#8855ff",
  "head_color": "#ffffff",
  "shape": "capsule",  // capsule, cube, sphere
  "size_scale": 1.0
}
```

### 4.3 Animaciones procedurales

Reemplazar `AnimationPlayer` por un `Tween` system:

```gdscript
class_name ProceduralAnim

## Estados: IDLE, WALK, ATTACK_WINDUP, ATTACK_SWING, HIT_REACT, DEATH

func play_idle(character: Node3D) -> void:
    character.rotation.y = lerp(character.rotation.y, character.rotation.y + 0.05, 0.1)

func play_walk(character: Node3D, dir: Vector3, dt: float) -> void:
    # Bob de cabeza
    var t := Time.get_ticks_msec() / 1000.0
    var head := character.get_node_or_null("Head")
    if head:
        head.position.y = base_head_y + sin(t * 8.0) * 0.05
    # Lean del cuerpo
    character.rotation.x = lerp(character.rotation.x, -dir.length() * 0.1, 0.2)

func play_attack(character: Node3D, on_hit: Callable) -> void:
    var weapon: Node3D = character.get_node("WeaponProxy")
    var tween := character.create_tween()
    tween.tween_property(weapon, "position:y", 1.5, 0.15)  # windup raise
    tween.tween_callback(on_hit)                            # hit moment
    tween.tween_property(weapon, "position:y", 1.2, 0.25)  # recovery
    tween.tween_property(weapon, "rotation:z", 0.0, 0.1)

func play_hit_react(character: Node3D) -> void:
    var tween := character.create_tween()
    var orig := character.position
    tween.tween_property(character, "position", orig + Vector3(0.2, 0, 0), 0.05)
    tween.tween_property(character, "position", orig, 0.15)
    # Flash color
    var body := character.get_node("Body")
    var mat := body.material_override
    mat.albedo_color = Color(1, 0.3, 0.3)
    await get_tree().create_timer(0.1).timeout
    mat.albedo_color = character.data.body_color

func play_death(character: Node3D) -> void:
    var tween := character.create_tween()
    tween.tween_property(character, "rotation:z", PI / 2, 0.4)
    tween.tween_property(character, "position:y", -0.5, 0.4)
```

### 4.4 Weapon como "effect emitter"

```gdscript
class_name WeaponEffect extends Node3D

## No tiene mesh. Solo emite eventos.

func activate(attacker: EntityCharacter, target: EntityCharacter) -> void:
    # 1. Calcular damage
    var dmg := _calc_damage(attacker, target)

    # 2. Emit hitbox invisible (BoxShape3D temporal)
    var hitbox := _spawn_hitbox(target.global_position)

    # 3. Aplicar efecto visual procedural (partículas o flash color)
    _flash_target(target)

    # 4. Apply damage
    target.take_damage(dmg, attacker)

    # 5. Spawn particle procedural (emitter simple)
    _spawn_particles(target.global_position, attacker.data.weapon.effect_tags)
```

### 4.5 HUD / UI

Mantener — `scripts/hud.gd` y `scenes/hud.tscn` no cambian. La UI ya muestra texto, barras, números.

### 4.6 Visualización durante desarrollo

Para "ver bien la escena" sin assets 3D:
- **Gizmos siempre visibles** (en editor): hitboxes, attack ranges, AI vision cones
- **Camera debug overlay**: mostrar IDs, HP, state machine state sobre cada entidad
- **Color coding**: cada tipo de entidad tiene un color distinto (player=azul, enemy=rojo, NPC=verde, boss=morado, ally=amarillo)
- **Wireframe outlines**: alternar a un modo donde los meshes se ven solo en wireframe para ver claramente las formas

---

## 5. Plan de ejecución (orden)

### Fase 1 — Limpieza (1-2 horas)
1. `git rm assets/imports/characters/realpg/*.fbx*`
2. `git rm assets/imports/animations/realpg/**/*.fbx*`
3. `git rm assets/models/weapons/*.fbx*`
4. `git rm assets/models/weapons/*.glb*`
5. `git rm scripts/tools/model_animation_viewer.gd scripts/tools/camera_orbit.gd scenes/tools/model_animation_viewer.tscn`
6. `rmdir scripts/tools scenes/tools` (si vacíos)
7. `git rm data/bonemap_*.tres data/humanoid_profile.tres`

### Fase 2 — Refactor weapons (2-3 horas)
1. Editar `scripts/skill/weapon_resource.gd` — quitar campos visuales
2. Limpiar `data/weapons/*.tres` — quitar mesh_path, grip_offset, scale
3. Crear `scripts/effects/weapon_effect.gd` — nodo abstract effect emitter
4. Crear `scripts/effects/procedural_anim.gd` — sistema de tween-based anims

### Fase 3 — Refactor personajes (2-3 horas)
1. Editar `scripts/character.gd`:
   - Eliminar cualquier `@onready var skel: Skeleton3D`
   - Eliminar `animation_player`
   - Añadir `_build_visual()` procedural (cube/capsule/sphere desde data)
2. Editar `scripts/player.gd`, `scripts/enemy.gd`, `scripts/dummy.gd`:
   - Eliminar referencias a AnimationPlayer
   - Reemplazar con `ProceduralAnim` calls
3. Editar `scenes/player.tscn`, `scenes/enemy.tscn`, etc.:
   - Quitar nodos Skeleton3D / AnimationPlayer
   - Añadir solo CollisionShape3D + MeshInstance3D construidos en script

### Fase 4 — CharacterResource extension (1-2 horas)
1. Editar `scripts/character_resource.gd`:
   - Añadir `body_height`, `body_radius`, `body_color`, `head_color`, `shape`, `size_scale`
2. Migrar `data/characters/*.tres` y `data/contracts/bosses.json`:
   - Añadir visual params a cada entry
3. Verificar que el spawn factory en `scripts/missions/mission_manager.gd` use los nuevos campos

### Fase 5 — Combat & Skills (2-3 horas)
1. Editar `scripts/combat/*.gd`:
   - Reemplazar AnimationPlayer calls con ProceduralAnim
2. Editar `scripts/skill/*.gd`:
   - Reemplazar visualizaciones de mesh con particles procedurales
3. Verificar que el attack hitbox sigue funcionando (es invisible pero funcional)

### Fase 6 — Testing (1-2 horas)
1. `godot --headless --script /tmp/test_basic_scene.gd` — verificar scene graph
2. Iniciar `play.tscn` y verificar que player, enemies, dummy se ven
3. Combat test: verificar que attacks funcionan, hitboxes aplican damage, death animation se reproduce
4. Performance: verificar framerate con 50+ entidades primitivas

### Fase 7 — Documentación (1 hora)
1. Añadir sección "Visual System (Primitives)" al README
2. Documentar `ProceduralAnim` API
3. Documentar `CharacterResource` nuevos campos visuales

---

## 6. Total estimado

**11-16 horas** de trabajo concentrado. Spread over 2-3 sesiones.

---

## 7. Trade-offs

| Pro | Con |
|-----|-----|
| ✅ No más sesiones de modelos 3D | ❌ Pierdes "carácter visual" de los modelos |
| ✅ Ver la escena siempre funciona (primitivas simples) | ❌ El juego se ve "abstracto/cubista" |
| ✅ Animaciones procedurales son editables instantáneamente | ❌ Menos "polish" sin animaciones baked |
| ✅ Tamaño de repo se reduce ~80% (sin .fbx ni .import) | ❌ Si después quieres models, hay que migrar de vuelta |
| ✅ Debugging visual más fácil (todo es código) | ❌ Marketing/screenshots menos atractivos |
| ✅ MCP-driven content generation funciona 100% sin assets | ❌ No hay diferenciación visual entre armas |

---

## 8. Alternativas consideradas (descartadas)

- **A) Solo filtrar dropdown viewer + seguir con basic_motions_dummy**: Rechazada — basic_motions_dummy también es un modelo .fbx, tiene los mismos problemas
- **B) Comprar/descargar nuevos modelos ya rigged para Mixamo**: Rechazada — dinero + tiempo + sigue dependiendo de retargeting
- **C) Usar solo sprites 2D en lugar de primitivas 3D**: Considerada — viable pero más trabajo de UI/UX. Se mantiene 3D primitivas por consistencia con el motor
- **D) Implementar el retargeting via editor GUI manual**: Descartada — 1 hora de trabajo manual repetitivo por 31 archivos

---

## 9. Preguntas abiertas

1. ¿Las primitivas deben tener **textura/color sólido** o **wireframe/outlined**? (sólido recomendado para mejor lectura visual)
2. ¿Quieres que las **armas tengan un placeholder visible** (un cubo pequeño en la mano) o que sean **100% invisibles**? (recomiendo invisible para forzar la idea de "abstract effect")
3. ¿Los **bosses** deben tener un mesh custom (más complejo) o también primitivas? (recomiendo primitivas con scale + color distintivo)
4. ¿La **animación de muerte** debe ser: a) caer de lado (rotation.z), b) shrink (scale → 0), c) fade-out (modulate.a → 0)?

---

## 10. Criterio de éxito

- ✅ `git status` muestra 0 archivos `.fbx` ni `.import` en `assets/`
- ✅ `play.tscn` corre y muestra player + enemy primitivos
- ✅ Combat funciona end-to-end: atacar → hit → damage → muerte procedural
- ✅ HUD sigue mostrando HP, stamina, cooldowns correctamente
- ✅ MCP funciona y puede spawnear entities sin errores de assets
- ✅ Build size < 50MB (vs ~500MB con FBX)
- ✅ Tiempo de import: < 5s (vs minutos con FBX + retarget)

---

**Próximo paso:** aprobar este plan o iterarlo, luego ejecutar Fase 1.