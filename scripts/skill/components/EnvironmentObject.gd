## EnvironmentObject — Nodo para objetos del entorno que las skills pueden
## afectar (mover, romper, encender, etc.).
##
## Es un "target_resolver.kind = env_object" que tiene propiedades relevantes
## para el cálculo de potencia de skill:
##   - weight (kg virtuales): un skill "move" consume más energía si el
##     objeto es pesado. La potencia del caster se enfrenta al peso.
##   - durability (0..1): los skills de daño lo desgastan. Al llegar a 0,
##     el objeto se "rompe" (queue_free + emit signal).
##   - material: piedra/metal/madera/cristal/vegetal → afecta a dmg
##     (madera se rompe con poco dmg, metal resiste más).
##   - flammable, conductive, fragile, magical: flags que interactúan con
##     elementos (fire daña flammable, shock daña conductive, etc.)
##   - is_pickup: si es true, el objeto puede ser "recogido" por una skill
##     y transportado. Los weights < 5kg son picked up; > 5kg solo moved.
##
## El cálculo de potencia en EffectLibrary._compute_skill_power():
##   effective_weight = weight * (1.0 - caster.strength * 0.05)
##   move_speed = skill.power / max(1.0, effective_weight)
##   break_chance = clampf(skill.dmg / (durability * material_resistance), 0, 1)
##
## Las skills se ejecutan a través de env_object en lugar de enemy cuando el
## caster las apunta a uno de estos nodos (con un raycast o proximidad).
class_name EnvironmentObject
extends StaticBody3D

## Materiales reconocidos. Cada uno tiene una resistencia base al daño.
## Los valores son dmg_needed_to_break (dmg acumulada para destruir).
enum Material { STONE, METAL, WOOD, CRYSTAL, VEGETAL, GLASS, BONE, FLESH }

## Constantes públicas (kg virtuales y resistencia base).
const WEIGHT_PICKUP_MAX := 5.0  # objetos <= 5kg pueden recogerse

## Resistencia base por material (cuánto dmg necesita para "romperse").
const MATERIAL_RESISTANCE: Dictionary = {
	Material.STONE: 200.0,
	Material.METAL: 350.0,
	Material.WOOD: 80.0,
	Material.CRYSTAL: 60.0,
	Material.VEGETAL: 30.0,
	Material.GLASS: 25.0,
	Material.BONE: 70.0,
	Material.FLESH: 20.0,
}

## Flags y propiedades del objeto.
@export var object_name: String = "Object"
@export var weight: float = 1.0           # kg virtuales
@export var durability: float = 1.0      # 0..1, baja con cada hit
@export var max_durability: float = 100.0  # hp interno del objeto
@export var material: Material = Material.WOOD
@export var flammable: bool = false
@export var conductive: bool = false
@export var fragile: bool = false        # si true, al primer hit fuerte se rompe
@export var is_pickup: bool = false      # puede ser recogido (weight <= WEIGHT_PICKUP_MAX)
@export var breakable: bool = true       # puede ser destruido

## Estado interno.
var _current_durability: float
var _broken: bool = false

## Señales para que otras cosas (UI, IA) reaccionen.
signal broken(obj: Node)
signal damaged(obj: Node, amount: float, remaining: float)
signal picked_up(by: Node)
signal moved(by: Node, distance: float)


func _ready() -> void:
	_current_durability = max_durability
	# Auto-añadir al grupo "env_objects" para que el target_resolver lo encuentre.
	if not is_in_group("env_objects"):
		add_to_group("env_objects")
	# Si no tiene collision_layer asignada, ponemos una razonable (5 = env)
	# El proyecto usa: 1=World, 2=Player, 3=Enemy, 4=AttackArea → 5 = Env
	if collision_layer == 0:
		collision_layer = 1 << 4  # layer 5
	if collision_mask == 1:
		collision_mask = 1  # default


## Devuelve la resistencia al dmg del material.
func get_material_resistance() -> float:
	return float(MATERIAL_RESISTANCE.get(material, 100.0))


## Aplica daño al objeto. Devuelve el dmg REAL que inflingió (post-armadura).
## Si el objeto se rompe, emite `broken` y queue_free.
func take_damage(amount: float, source: Node = null) -> float:
	if _broken:
		return 0.0
	# Los "objetivos" del entorno no usan hp, sino durability.
	# Reducimos la durability interna y emitimos damaged.
	_current_durability -= amount
	# Reducir también durability ratio (0..1)
	durability = clampf(_current_durability / max_durability, 0.0, 1.0)
	damaged.emit(self, amount, _current_durability)
	if breakable and _current_durability <= 0.0:
		_break(source)
	return amount


## Calcula la "resistencia" efectiva que este objeto opone a un skill.power.
## Se usa en EffectLibrary._compute_skill_power para resolver si el skill
## lo afecta o no, y con qué intensidad.
## skill_power: la "potencia" del skill (suma de stats del caster + arma + skill level)
## Devuelve: { "can_affect": bool, "resisted_by": float (0..1), "effective": float }
func resist(skill_power: float) -> Dictionary:
	if _broken:
		return { "can_affect": false, "resisted_by": 1.0, "effective": 0.0 }
	var mat_res: float = get_material_resistance()
	var resisted: float = clampf(mat_res / max(1.0, mat_res + skill_power), 0.0, 0.95)
	# Si es frágil, ignora un 50% de la resistencia
	if fragile:
		resisted *= 0.5
	return {
		"can_affect": skill_power > 0.0 and resisted < 0.95,
		"resisted_by": resisted,
		"effective": skill_power * (1.0 - resisted),
	}


## Rompe el objeto (lo libera de la escena).
func _break(source: Node = null) -> void:
	_broken = true
	broken.emit(self)
	# En MVP, simplemente lo eliminamos. En futuro, spawnear debris/particles.
	queue_free()


## ¿Puede este objeto ser recogido por una skill de pickup?
func can_be_picked_up() -> bool:
	return is_pickup and not _broken and weight <= WEIGHT_PICKUP_MAX


## ¿Es muy pesado para moverlo por una skill "move"?
func is_too_heavy_to_move(skill_move_power: float) -> bool:
	# Regla: necesita al menos 1.0 de power por cada 2kg (ajustable).
	return weight > max(1.0, skill_move_power * 2.0)
