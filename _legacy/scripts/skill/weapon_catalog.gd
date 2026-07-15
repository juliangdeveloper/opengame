## WeaponCatalog — Registro de armas disponibles en el juego.
##
## A diferencia de los skills (que se autoran dinámicamente vía MCP y viven
## en data/skills/), las armas tienen un **catálogo curado** inicial que
## define las "clases" base del juego. La IA puede crear armas NUEVAS
## (vía MCP create_weapon) que se añaden al catálogo en runtime.
##
## Diseño:
##   - Catálogo base: 9 armas predefinidas (1 unarmed + 8 armas curadas)
##   - Cada WeaponResource define family, stats, scaling, compatibilidades
##   - El jugador equipa UNA a la vez (no dual-wield en MVP)
##   - El catalogue se persiste en ProgressionState (no en disco en MVP,
##     las armas se re-crean desde .tres al iniciar)
##
## Acceso desde MCP:
##   - list_weapons() → todas las del catálogo (base + grants del MCP)
##   - get_weapon(id) → una específica
##   - grant_weapon(id) → añadir a la "colección" del jugador (owned_weapons)
##   - equip_weapon(id) → marcarla como equipped en PS
##
## Acceso desde UI:
##   - WeaponAllocator (tab en skill book) lista owned + equipped

const WeaponResourceScript := preload("res://scripts/skill/weapon_resource.gd")
const ProgressionState := preload("res://scripts/skill/progression_state.gd")

## Catálogo base: id → path del .tres
const BASE_CATALOG_PATHS: Dictionary = {
	&"unarmed": "res://data/weapons/unarmed.tres",
	&"short_sword": "res://data/weapons/short_sword.tres",
	&"long_sword": "res://data/weapons/long_sword.tres",
	&"great_sword": "res://data/weapons/great_sword.tres",
	&"scimitar": "res://data/weapons/scimitar.tres",
	&"dagger": "res://data/weapons/dagger.tres",
	&"great_scythe": "res://data/weapons/great_scythe.tres",
	&"long_bow": "res://data/weapons/long_bow.tres",
	&"spear": "res://data/weapons/spear.tres",
	&"war_axe": "res://data/weapons/war_axe.tres",
	&"mace": "res://data/weapons/mace.tres",
	&"arcane_staff": "res://data/weapons/arcane_staff.tres",
}

## Catálogo runtime (se llena al _ready): id → WeaponResource
static var _cache: Dictionary = {}

## Weapons creados por la IA vía MCP (id → path del .tres generado)
static var _mcp_generated: Dictionary = {}


## Inicializa el cache cargando todos los .tres del catálogo base.
## Llamar desde el autoload ProgressionState o desde la play scene _ready.
static func initialize() -> void:
	_cache.clear()
	for id in BASE_CATALOG_PATHS:
		var path: String = BASE_CATALOG_PATHS[id]
		var res: Resource = load(path)
		if res != null and res is WeaponResourceScript:
			_cache[id] = res
		else:
			push_warning("[WeaponCatalog] failed to load base weapon: %s" % path)
	# Cargar también los generados por MCP (si los hay)
	for id in _mcp_generated:
		var path_mcp: String = _mcp_generated[id]
		var res_mcp: Resource = load(path_mcp)
		if res_mcp != null and res_mcp is WeaponResourceScript:
			_cache[id] = res_mcp


## Devuelve todos los ids del catálogo.
static func list_ids() -> Array[StringName]:
	if _cache.is_empty():
		initialize()
	var ids: Array[StringName] = []
	for k in _cache.keys():
		ids.append(StringName(k))
	ids.sort()
	return ids


## Devuelve todos los WeaponResource del catálogo (para la UI).
static func list_all() -> Array[Resource]:
	if _cache.is_empty():
		initialize()
	var all: Array[Resource] = []
	for k in _cache.keys():
		all.append(_cache[k])
	return all


## Devuelve armas filtradas por familia.
static func list_by_family(family_name: String) -> Array[Resource]:
	if _cache.is_empty():
		initialize()
	var out: Array[Resource] = []
	for k in _cache.keys():
		var w: WeaponResourceScript = _cache[k]
		if w.get_family_name() == family_name:
			out.append(w)
	return out


## Devuelve un WeaponResource por id, o null.
static func get_weapon(id: StringName) -> Resource:
	if _cache.is_empty():
		initialize()
	return _cache.get(id, null)


## Registra un arma nueva (creada por MCP). Devuelve true si ok.
## path: ruta absoluta al .tres recién escrito.
static func register_mcp_generated(id: StringName, path: String) -> bool:
	_mcp_generated[id] = path
	var res: Resource = load(path)
	if res == null or not res is WeaponResourceScript:
		return false
	_cache[id] = res
	return true


## Helper de diagnóstico.
static func debug_dump() -> void:
	if _cache.is_empty():
		initialize()
	for k in _cache.keys():
		var w: WeaponResourceScript = _cache[k]
		print("[WeaponCatalog] %s: %s (%s, %dh, dmg=%.1f)" % [
			String(k), w.display_name, w.get_family_display(), w.hands,
			float(w.designed_stats.get("dmg", 0.0))
		])
