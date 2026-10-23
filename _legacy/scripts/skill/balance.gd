class_name Balance
extends RefCounted

const DEFAULT_STARTING_RATIO := 0.05
const DEFAULT_SOFT_CAP_RATIO := 0.5
const DEFAULT_SOFT_EXPONENT := 0.7
const DEFAULT_HARD_EXPONENT := 0.5
const DEFAULT_COST_MIN_RATIO := 0.3
const DEFAULT_COST_INVERSE_EXPONENT := 0.5
const DEFAULT_MAX_POINTS_PER_STAT := 5

const DEFAULT_TIERS: Array[Dictionary] = [
	{ "name": "Novice",      "threshold": 0,   "soft_cap_ratio": 0.10 },
	{ "name": "Apprentice",  "threshold": 5,   "soft_cap_ratio": 0.20 },
	{ "name": "Adept",       "threshold": 15,  "soft_cap_ratio": 0.35 },
	{ "name": "Expert",      "threshold": 30,  "soft_cap_ratio": 0.50 },
	{ "name": "Master",      "threshold": 50,  "soft_cap_ratio": 0.65 },
	{ "name": "Grandmaster", "threshold": 75,  "soft_cap_ratio": 0.80 },
	{ "name": "Legend",      "threshold": 100, "soft_cap_ratio": 0.92 },
	{ "name": "Mythic",      "threshold": 150, "soft_cap_ratio": 1.00 },
]

static var _config: Dictionary = {}


static func load_config(path: String = "res://data/contracts/balance_config.json") -> void:
	if _config.has("loaded"):
		return
	if not FileAccess.file_exists(path):
		push_warning("[Balance] %s not found, using defaults" % path)
		_config = { "loaded": true, "using_defaults": true }
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[Balance] cannot open %s, using defaults" % path)
		_config = { "loaded": true, "using_defaults": true }
		return
	var content := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Balance] invalid JSON in %s, using defaults" % path)
		_config = { "loaded": true, "using_defaults": true }
		return
	_config = parsed
	_config["loaded"] = true
	print("[Balance] loaded config from %s" % path)


static func get_tier(proficiency: int) -> Dictionary:
	load_config()
	var tiers: Array = DEFAULT_TIERS
	if _config.has("proficiency_tiers"):
		tiers = _config["proficiency_tiers"]
	var current: Dictionary = tiers[0]
	for t in tiers:
		if proficiency >= t.threshold:
			current = t
		else:
			break
	return current


static func get_tier_soft_cap(proficiency: int) -> float:
	return float(get_tier(proficiency).get("soft_cap_ratio", 0.10))


static func get_level_bonus(proficiency: int) -> float:
	load_config()
	var tiers: Array = DEFAULT_TIERS
	if _config.has("proficiency_tiers"):
		tiers = _config["proficiency_tiers"]
	var next_threshold: int = tiers[-1].threshold
	for t in tiers:
		if proficiency < t.threshold:
			next_threshold = t.threshold
			break
	var hard_exp: float = DEFAULT_HARD_EXPONENT
	if _config.has("balance"):
		hard_exp = float(_config["balance"].get("hard_curve_exponent", DEFAULT_HARD_EXPONENT))
	var ratio := float(proficiency) / float(max(1, next_threshold))
	ratio = clampf(ratio, 0.0, 1.0)
	var curved := pow(ratio, hard_exp)
	return curved * curved * (3.0 - 2.0 * curved)


static func compute_effective(
	designed_max_value: float,
	points: int,
	max_points: int,
	proficiency: int
) -> float:
	load_config()
	var starting_ratio := DEFAULT_STARTING_RATIO
	var soft_cap_ratio := DEFAULT_SOFT_CAP_RATIO
	var soft_exp := DEFAULT_SOFT_EXPONENT
	if _config.has("balance"):
		var b: Dictionary = _config["balance"]
		starting_ratio = float(b.get("starting_ratio", starting_ratio))
		soft_cap_ratio = float(b.get("soft_cap_ratio", soft_cap_ratio))
		soft_exp = float(b.get("soft_curve_exponent", soft_exp))

	if designed_max_value <= 0.0:
		return 0.0
	if max_points <= 0:
		max_points = DEFAULT_MAX_POINTS_PER_STAT

	var lvl1: float = designed_max_value * starting_ratio
	var soft_cap_value: float = designed_max_value * soft_cap_ratio
	var safe_points: int = clampi(points, 0, max_points)
	var soft_progress: float = 0.0
	if safe_points > 0:
		soft_progress = pow(float(safe_points) / float(max_points), soft_exp)
	var soft_value: float = lvl1 + (soft_cap_value - lvl1) * soft_progress

	var tier_max: float = designed_max_value * get_tier_soft_cap(proficiency)
	var points_unlock: float = soft_progress
	var tier_unlock: float = get_level_bonus(proficiency)
	var unlock: float = points_unlock * tier_unlock
	var value: float = soft_value + (designed_max_value - soft_value) * unlock
	value = min(value, tier_max)
	value = max(value, lvl1)
	return value


static func cost_effective(
	designed_cost: float,
	current_value: float,
	designed_max_value: float
) -> float:
	load_config()
	var cost_min_ratio := DEFAULT_COST_MIN_RATIO
	var cost_inv_exp := DEFAULT_COST_INVERSE_EXPONENT
	if _config.has("balance"):
		var b: Dictionary = _config["balance"]
		cost_min_ratio = float(b.get("cost_min_ratio", cost_min_ratio))
		cost_inv_exp = float(b.get("cost_inverse_exponent", cost_inv_exp))

	if designed_cost <= 0.0:
		return 0.0
	if designed_max_value <= 0.0:
		return designed_cost

	var power_ratio := clampf(current_value / designed_max_value, 0.0, 1.0)
	var power_component := pow(power_ratio, cost_inv_exp)
	var effective := designed_cost * lerpf(cost_min_ratio, 1.0, power_component)
	return effective


const INVERTED_STATS: Array[StringName] = [
	&"cooldown",
	&"stamina",
	&"charge_time",
]


static func is_inverted(stat_name: StringName) -> bool:
	return stat_name in INVERTED_STATS
