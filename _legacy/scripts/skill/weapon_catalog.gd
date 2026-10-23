
const WeaponResourceScript := preload("res://scripts/skill/weapon_resource.gd")
const ProgressionState := preload("res://scripts/skill/progression_state.gd")

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

static var _cache: Dictionary = {}

static var _mcp_generated: Dictionary = {}


static func initialize() -> void:
	_cache.clear()
	for id in BASE_CATALOG_PATHS:
		var path: String = BASE_CATALOG_PATHS[id]
		var res: Resource = load(path)
		if res != null and res is WeaponResourceScript:
			_cache[id] = res
		else:
			push_warning("[WeaponCatalog] failed to load base weapon: %s" % path)
	for id in _mcp_generated:
		var path_mcp: String = _mcp_generated[id]
		var res_mcp: Resource = load(path_mcp)
		if res_mcp != null and res_mcp is WeaponResourceScript:
			_cache[id] = res_mcp


static func list_ids() -> Array[StringName]:
	if _cache.is_empty():
		initialize()
	var ids: Array[StringName] = []
	for k in _cache.keys():
		ids.append(StringName(k))
	ids.sort()
	return ids


static func list_all() -> Array[Resource]:
	if _cache.is_empty():
		initialize()
	var all: Array[Resource] = []
	for k in _cache.keys():
		all.append(_cache[k])
	return all


static func list_by_family(family_name: String) -> Array[Resource]:
	if _cache.is_empty():
		initialize()
	var out: Array[Resource] = []
	for k in _cache.keys():
		var w: WeaponResourceScript = _cache[k]
		if w.get_family_name() == family_name:
			out.append(w)
	return out


static func get_weapon(id: StringName) -> Resource:
	if _cache.is_empty():
		initialize()
	return _cache.get(id, null)


static func register_mcp_generated(id: StringName, path: String) -> bool:
	_mcp_generated[id] = path
	var res: Resource = load(path)
	if res == null or not res is WeaponResourceScript:
		return false
	_cache[id] = res
	return true


static func debug_dump() -> void:
	if _cache.is_empty():
		initialize()
	for k in _cache.keys():
		var w: WeaponResourceScript = _cache[k]
		print("[WeaponCatalog] %s: %s (%s, %dh, dmg=%.1f)" % [
			String(k), w.display_name, w.get_family_display(), w.hands,
			float(w.designed_stats.get("dmg", 0.0))
		])
