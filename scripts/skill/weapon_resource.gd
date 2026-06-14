## WeaponResource — Data layer para un arma equipable.
##
## Un arma es un Resource data-driven (.tres) que define:
##   - Identidad (id, display_name, flavor)
##   - Familia (sword, scimitar, scythe, bow, dagger, spear...) — define animación/sfx
##   - Hands (1 o 2) — limita a no permitir otra arma en off-hand
##   - Stats base (damage, speed, range, weight, reach)
##   - Multiplicadores por stat del jugador (fuerza → damage, destreza → speed)
##   - Compatibilidad de skills (qué skills pueden usarse con esta arma equipada)
##   - Visual (mesh_hint para el modelo, color tinte, longitud hoja)
##
## El SkillExecutor consulta el arma equipada al castear un skill melee para
## ajustar damage, knockback, hitbox size. El catalogue (WeaponCatalog) registra
## todos los .tres disponibles para que la IA vía MCP pueda crearlos y el
## jugador equiparlos desde el libro.
##
## Diseño de "potencia de skill con arma + stats del jugador + target":
##   final_dmg = skill.base_dmg
##             * (1.0 + weapon.dmg_mult * player.strength_points)
##             * (1.0 + weapon.spd_mult * player.dexterity_points)
##             * (1.0 - target.phys_res * weapon.ignore_res_factor)
##             * weapon.weapon_class_dmg_mult[target_class]
##
## El detalle vive en EffectLibrary._compute_skill_power() — este resource
## sólo declara los multiplicadores base.
class_name WeaponResource
extends Resource

## Familias de armas. Determinan animación/sfx y reglas de compatibilidad.
## sword: hoja recta, balanceada (1h/2h)
## scimitar: hoja curva, cortante (1h)
## dagger: hoja corta, rápida (1h)
## scythe: hoja curva larga, lenta, gran alcance (2h)
## bow: a distancia, requiere flechas (2h)
## spear: asta, alcance medio (1h/2h)
## axe: hacha, contundente, lenta (1h/2h)
## mace: maza, contundente pura (1h)
## staff: bastón, canaliza magias (2h)
## unarmed: sin arma (puño), damage bajo pero siempre disponible
enum Family { SWORD, SCIMITAR, DAGGER, SCYTHE, BOW, SPEAR, AXE, MACE, STAFF, UNARMED }

@export var id: StringName = &""
@export var display_name: String = "Unarmed"
@export_multiline var flavor_text: String = ""
@export var family: Family = Family.UNARMED
@export var hands: int = 1  # 1 = one-handed, 2 = two-handed

## Stats base (diseñados). DEPRECATED en Fase 1 — usar `attribute_modifiers`.
## Se mantiene para retrocompatibilidad con .tres existentes y para los
## helpers visuales (weapon_allocator UI, get_scaled_dmg, etc.).
## dmg:        daño base por hit (escalado por strength del caster)
## speed:      multiplicador de velocidad de swing (0.5 = lento, 1.5 = rápido)
## reach:      multiplicador de hitbox radius (0.8 = corto, 1.5 = largo)
## weight:     kg virtuales, afecta move_speed y consume de stamina
## parry_bonus: 0..1, bonus al intentar defender con esta arma
## crit_chance: 0..1, probabilidad de crítico (daño x2)
@export var designed_stats: Dictionary = {
	"dmg": 0.0,
	"speed": 1.0,
	"reach": 1.0,
	"weight": 0.0,
	"parry_bonus": 0.0,
	"crit_chance": 0.05,
}


## FASE 1 (2026-06-14): Modificadores de atributos aplicados al equiparse.
## Cada clave = StringName de un attribute_id (ver AttributeComponent.ATTRIBUTES).
## Cada valor = float que se SUMA al temp_offset del caster al equipar y se
## RESTA al desequipar.
##
## Ejemplo para una short_sword:
##   attribute_modifiers = {
##     "attack_power": 0.15,    # +15% dmg al caster
##     "attack_speed": 0.10,    # +10% attack_speed
##     "crit_chance": 0.05,    # +5% crit chance
##   }
##
## Esto cumple la directiva del user: "Las armas actúan solo modificando
## los atributos, de esta manera potencian los skills". El weapon ya no
## aporta daño directamente — solo boost a los stats del caster, y el
## skill damage formula lee esos stats.
@export var attribute_modifiers: Dictionary = {}


## FASE 1: Aplica los `attribute_modifiers` como temp_offsets al caster.
## Llamar desde ps.equip_weapon(id) cuando el arma se equipa.
## caster: un Node3D (player o NPC) con un AttributeComponent hijo.
func apply_to_caster(caster: Node) -> bool:
	if caster == null or attribute_modifiers.is_empty():
		return false
	if not caster.has_node("AttributeComponent"):
		return false
	var ac: Node = caster.get_node("AttributeComponent")
	if not ac.has_method("apply_temp_offset"):
		return false
	for attr_id in attribute_modifiers:
		var amt: float = float(attribute_modifiers[attr_id])
		ac.call("apply_temp_offset", StringName(attr_id), amt)
	return true


## FASE 1: Remueve los `attribute_modifiers` del caster (inverso de apply).
## Llamar desde ps.unequip_weapon() cuando se desequipa.
func remove_from_caster(caster: Node) -> bool:
	if caster == null or attribute_modifiers.is_empty():
		return false
	if not caster.has_node("AttributeComponent"):
		return false
	var ac: Node = caster.get_node("AttributeComponent")
	if not ac.has_method("remove_temp_offset"):
		return false
	for attr_id in attribute_modifiers:
		var amt: float = float(attribute_modifiers[attr_id])
		ac.call("remove_temp_offset", StringName(attr_id), amt)
	return true

## Multiplicadores por stat del jugador (cuánto suma cada punto del stat).
## skill_point en el stat → +dmg_mult * dmg_base por punto (cap 5).
@export var stat_scaling: Dictionary = {
	"strength_to_dmg": 0.10,    # +10% dmg por punto de fuerza
	"dexterity_to_speed": 0.05, # +5% speed por punto de destreza
	"dexterity_to_crit": 0.02,  # +2% crit por punto de destreza
	"faith_to_parry": 0.05,     # +5% parry_bonus por punto de fe
}

## Multiplicadores de daño según la clase/familia del target.
## Sirve para implementar "esta arma es efectiva contra X".
## Ej: hacha contra armored (+30%), dagger contra light (+25%),
##     spear contra cavalry (+50%), bow contra flying (+40%).
## Claves = family name del target (lowercase); valores = multiplicador.
@export var class_dmg_mult: Dictionary = {}

## Skills compatibles. Si está vacío, todos los melee_skills son compatibles.
## Lista de skill_id (StringName) que pueden castearse con esta arma equipada.
## Skills fuera de esta lista NO se pueden usar con el arma equipada.
@export var compatible_skill_ids: Array[StringName] = []

## Skills bloqueados explícitamente (override). Algunos skills requieren
## "unarmed" o un tipo específico de arma.
@export var blocked_skill_ids: Array[StringName] = []

## Visual. mesh_hint lo lee Player para swapear el modelo.
@export var mesh_hint: String = ""        # "sword_1h", "scythe_2h", "bow_long", etc.
@export var tint_color: Color = Color(0.8, 0.8, 0.85)
@export var blade_length: float = 0.0     # longitud visual (metros)
@export var trail_color: Color = Color(1.0, 0.9, 0.6, 0.7)
@export var hit_sound: String = "sword_hit"  # nombre lógico del sfx

## Visual attachment config. Lo lee Player._load_weapon_model para colocar
## el modelo 3D en la mano del jugador.
##   model_path:     res:// path al .glb (e.g. "res://assets/models/weapons/wpn_short_sword.glb").
##                  Si está vacío, se usa el BoxMesh placeholder (e.g. unarmed).
##   model_rotation: rotación adicional aplicada al modelo (en grados, Euler XYZ)
##                  después de la rotación base que convierte Blender Z-up a Godot Y-up.
##                  Útil para armas que se sostienen horizontalmente (bow) o invertidas.
##   grip_offset:    distancia en metros desde el origen del modelo hasta el punto
##                  donde la mano agarra (eje Y del modelo, después de la rotación base).
##                  El modelo se baja en Y por este valor para que el grip quede en
##                  (0,0,0) del Weapon node (la mano).
##   model_scale:    escala uniforme aplicada al modelo (default 1.0).
@export_group("Visual Attachment")
@export var model_path: String = ""
@export var model_rotation: Vector3 = Vector3.ZERO   # Euler XYZ en grados
@export var grip_offset: float = 0.20                # default sensato para espadas 1h
@export var model_scale: float = 1.0

## Categoría para UI / filtros en el catálogo.
@export var category: StringName = &"melee"


## Helper: nombre legible de la familia.
func get_family_name() -> String:
	match family:
		Family.SWORD:    return "sword"
		Family.SCIMITAR: return "scimitar"
		Family.DAGGER:   return "dagger"
		Family.SCYTHE:   return "scythe"
		Family.BOW:      return "bow"
		Family.SPEAR:    return "spear"
		Family.AXE:      return "axe"
		Family.MACE:     return "mace"
		Family.STAFF:    return "staff"
		Family.UNARMED:  return "unarmed"
	return "unknown"


## Helper: nombre display de la familia.
func get_family_display() -> String:
	match family:
		Family.SWORD:    return "Espada"
		Family.SCIMITAR: return "Alfanje"
		Family.DAGGER:   return "Daga"
		Family.SCYTHE:   return "Guadaña"
		Family.BOW:      return "Arco"
		Family.SPEAR:    return "Lanza"
		Family.AXE:      return "Hacha"
		Family.MACE:     return "Maza"
		Family.STAFF:    return "Bastón"
		Family.UNARMED:  return "Sin arma"
	return "?"


## Helper: ¿el skill_id es compatible con este arma?
func is_skill_compatible(skill_id: StringName) -> bool:
	if skill_id in blocked_skill_ids:
		return false
	if compatible_skill_ids.is_empty():
		# Sin whitelist = todos los melee skills son compatibles.
		# Pero las skills que requieren "unarmed" explícitamente siguen bloqueadas
		# si estamos en un WeaponResource con family != UNARMED.
		return family == Family.UNARMED or true
	return skill_id in compatible_skill_ids


## Helper: damage final tras aplicar stat_scaling del jugador.
## Usado por EffectLibrary._compute_skill_power.
func get_scaled_dmg(player: Node) -> float:
	var base: float = float(designed_stats.get("dmg", 0.0))
	if player == null:
		return base
	var str_pts: float = float(_read_attr_points(player, "strength"))
	var mult: float = 1.0 + float(stat_scaling.get("strength_to_dmg", 0.0)) * str_pts
	return base * mult


## Helper: speed final tras aplicar stat_scaling.
func get_scaled_speed(player: Node) -> float:
	var base: float = float(designed_stats.get("speed", 1.0))
	if player == null:
		return base
	var dex_pts: float = float(_read_attr_points(player, "dexterity"))
	return base * (1.0 + float(stat_scaling.get("dexterity_to_speed", 0.0)) * dex_pts)


## Helper: crit_chance final.
func get_scaled_crit(player: Node) -> float:
	var base: float = float(designed_stats.get("crit_chance", 0.05))
	if player == null:
		return base
	var dex_pts: float = float(_read_attr_points(player, "dexterity"))
	return clampf(base + float(stat_scaling.get("dexterity_to_crit", 0.0)) * dex_pts, 0.0, 1.0)


## Helper: parry_bonus final.
func get_scaled_parry_bonus(player: Node) -> float:
	var base: float = float(designed_stats.get("parry_bonus", 0.0))
	if player == null:
		return base
	var fai_pts: float = float(_read_attr_points(player, "faith"))
	return clampf(base + float(stat_scaling.get("faith_to_parry", 0.0)) * fai_pts, 0.0, 1.0)


## Helper: multiplicador de dmg contra un target de cierta clase.
func get_class_mult(target_family: String) -> float:
	if target_family == "" or class_dmg_mult.is_empty():
		return 1.0
	return float(class_dmg_mult.get(target_family, 1.0))


## Lee un stat del AttributeComponent del player. Funciona tanto si el player
## tiene un AttributeComponent nativo (scripts/attribute_component.gd) como
## si lo expone como un dictionary en ps.allocations.
func _read_attr_points(player: Node, stat_id: String) -> float:
	if player == null:
		return 0.0
	# 1) AttributeComponent script (AttributeComponent.gd)
	if player.has_node("AttributeComponent"):
		var ac: Node = player.get_node("AttributeComponent")
		if ac.has_method("get_points"):
			return float(ac.call("get_points", stat_id))
	# 2) ProgressionState.allocations["attributes"][stat_id]
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps and "allocations" in ps and ps.allocations is Dictionary:
		var alloc: Dictionary = ps.allocations
		if alloc.has("attributes") and alloc["attributes"] is Dictionary:
			return float((alloc["attributes"] as Dictionary).get(stat_id, 0))
	return 0.0
