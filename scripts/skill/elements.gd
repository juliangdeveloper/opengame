extends RefCounted

const ELEMENTS: Array = [
	{
		"id": &"physical",
		"name": "Físico",
		"color": Color(0.85, 0.85, 0.9),
		"icon": "⚔",
		"desc": "Daño cuerpo a cuerpo, sin elemento. Neutral contra todo.",
	},
	{
		"id": &"fire",
		"name": "Fuego",
		"color": Color(1.0, 0.4, 0.1),
		"icon": "🔥",
		"desc": "Quema al enemigo. Fuerte contra nature/earth, débil contra water.",
	},
	{
		"id": &"water",
		"name": "Agua",
		"color": Color(0.2, 0.5, 1.0),
		"icon": "💧",
		"desc": "Congela y ralentiza. Fuerte contra fire, débil contra lightning.",
	},
	{
		"id": &"earth",
		"name": "Tierra",
		"color": Color(0.55, 0.4, 0.2),
		"icon": "🌿",
		"desc": "Veneno y root. Fuerte contra lightning, débil contra air.",
	},
	{
		"id": &"air",
		"name": "Aire",
		"color": Color(0.8, 0.9, 1.0),
		"icon": "💨",
		"desc": "Velocidad y knockback. Fuerte contra earth, débil contra fire.",
	},
	{
		"id": &"lightning",
		"name": "Rayo",
		"color": Color(1.0, 1.0, 0.3),
		"icon": "⚡",
		"desc": "Stun y chain. Fuerte contra water/air, débil contra earth.",
	},
	{
		"id": &"light",
		"name": "Luz",
		"color": Color(1.0, 0.95, 0.7),
		"icon": "✨",
		"desc": "Cura y purge. Fuerte contra dark, neutral contra light.",
	},
	{
		"id": &"dark",
		"name": "Oscuridad",
		"color": Color(0.45, 0.2, 0.6),
		"icon": "🌑",
		"desc": "DoT y debuffs. Fuerte contra light, débil contra light.",
	},
	{
		"id": &"arcane",
		"name": "Arcano",
		"color": Color(0.75, 0.35, 0.95),
		"icon": "🔮",
		"desc": "Magia pura. Sin ventaja/desventaja elemental (solo por mastery).",
	},
]

static func get_element(id: StringName) -> Dictionary:
	for e in ELEMENTS:
		if e["id"] == id:
			return e
	return {}

static func get_element_color(id: StringName) -> Color:
	return Color(get_element(id).get("color", Color.WHITE))

static func get_element_name(id: StringName) -> String:
	return String(get_element(id).get("name", "???"))

const ELEMENTAL_MATRIX: Dictionary = {
	&"fire": {
		&"earth": 2.0,
		&"air": 0.5,
		&"water": 0.5,
		&"fire": 0.5,
		&"arcane": 1.0,
	},
	&"water": {
		&"fire": 2.0,
		&"lightning": 0.5,
		&"water": 0.5,
		&"arcane": 1.0,
	},
	&"earth": {
		&"lightning": 2.0,
		&"air": 0.5,
		&"earth": 0.5,
		&"arcane": 1.0,
	},
	&"air": {
		&"earth": 2.0,
		&"fire": 2.0,
		&"air": 0.5,
		&"arcane": 1.0,
	},
	&"lightning": {
		&"water": 2.0,
		&"air": 2.0,
		&"earth": 0.5,
		&"lightning": 0.5,
		&"arcane": 1.0,
	},
	&"light": {
		&"dark": 2.0,
		&"light": 0.5,
		&"arcane": 1.0,
	},
	&"dark": {
		&"light": 2.0,
		&"dark": 0.5,
		&"arcane": 1.0,
	},
	&"arcane": {
	},
	&"physical": {
	},
}

static func get_elemental_multiplier(atk_elem: StringName, def_elem: StringName) -> float:
	if atk_elem == &"" or atk_elem == &"physical":
		return 1.0
	if def_elem == &"" or def_elem == &"physical":
		return 1.0
	var atk_table: Dictionary = ELEMENTAL_MATRIX.get(atk_elem, {})
	return float(atk_table.get(def_elem, 1.0))


const STATUS_EFFECTS: Array = [
	{
		"id": &"burn",
		"name": "Quemadura",
		"element": &"fire",
		"color": Color(1.0, 0.4, 0.1),
		"icon": "🔥",
		"dpt": 3.0,
		"default_duration": 4.0,
		"tick_interval": 1.0,
		"desc": "Daño de fuego continuo. Se remueve con agua o descansando.",
	},
	{
		"id": &"freeze",
		"name": "Congelado",
		"element": &"water",
		"color": Color(0.6, 0.9, 1.0),
		"icon": "❄",
		"dpt": 0.5,
		"default_duration": 3.0,
		"tick_interval": 1.0,
		"desc": "Inmóvil + slowed. Se rompe con un golpe.",
		"is_root": true,
		"is_slow": true,
		"slow_magnitude": 0.8,
	},
	{
		"id": &"shock",
		"name": "Shock",
		"element": &"lightning",
		"color": Color(1.0, 1.0, 0.3),
		"icon": "⚡",
		"dpt": 1.0,
		"default_duration": 2.0,
		"tick_interval": 1.0,
		"desc": "Stun inicial + dpt bajo. Chance de stun adicional en cada tick.",
		"is_stun": true,
		"stun_chance": 0.3,
	},
	{
		"id": &"bleed",
		"name": "Sangrado",
		"element": &"physical",
		"color": Color(0.8, 0.1, 0.1),
		"icon": "🩸",
		"dpt": 2.0,
		"default_duration": 5.0,
		"tick_interval": 1.0,
		"desc": "Daño físico continuo. Escala con daño del hit original.",
	},
	{
		"id": &"poison",
		"name": "Veneno",
		"element": &"earth",
		"color": Color(0.4, 0.8, 0.2),
		"icon": "☠",
		"dpt": 2.5,
		"default_duration": 6.0,
		"tick_interval": 1.5,
		"desc": "Daño naturaleza continuo. Previene regeneración.",
		"prevents_regen": true,
	},
	{"id": &"stun", "name": "Stun", "element": &"lightning", "color": Color(1, 1, 0), "icon": "⚡", "default_duration": 1.5, "desc": "Incapacitado, no puede actuar."},
	{"id": &"root", "name": "Root", "element": &"earth", "color": Color(0.4, 0.3, 0.2), "icon": "🌿", "default_duration": 3.0, "desc": "No puede moverse."},
	{"id": &"slow", "name": "Slow", "element": &"water", "color": Color(0.5, 0.7, 1.0), "icon": "❄", "default_duration": 3.0, "desc": "Movimiento y ataque ralentizados."},
	{"id": &"silence", "name": "Silencio", "element": &"arcane", "color": Color(0.6, 0.4, 0.8), "icon": "🔇", "default_duration": 3.0, "desc": "No puede castear skills."},
	{"id": &"disarm", "name": "Desarme", "element": &"physical", "color": Color(0.6, 0.6, 0.6), "icon": "🚫", "default_duration": 3.0, "desc": "No puede atacar cuerpo a cuerpo."},
	{"id": &"sleep", "name": "Sueño", "element": &"arcane", "color": Color(0.5, 0.5, 0.9), "icon": "💤", "default_duration": 4.0, "desc": "Dormido. Se rompe con un golpe."},
	{"id": &"blind", "name": "Ceguera", "element": &"dark", "color": Color(0.2, 0.2, 0.2), "icon": "🙈", "default_duration": 3.0, "desc": "Precisión reducida. Fallos frecuentes."},
	{"id": &"charm", "name": "Encanto", "element": &"light", "color": Color(1.0, 0.7, 0.9), "icon": "💖", "default_duration": 4.0, "desc": "Controlado mentalmente. No puede atacar al encantador."},
	{"id": &"fear", "name": "Miedo", "element": &"dark", "color": Color(0.4, 0.2, 0.4), "icon": "😱", "default_duration": 3.0, "desc": "Huye del atacante. No puede actuar."},
	{"id": &"taunt", "name": "Taunt", "element": &"physical", "color": Color(0.8, 0.5, 0.3), "icon": "🤬", "default_duration": 4.0, "desc": "Forzado a atacar al taunter."},
]


static func get_status(id: StringName) -> Dictionary:
	for s in STATUS_EFFECTS:
		if s["id"] == id:
			return s
	return {}


const MAX_ELEMENT_POINTS := 5

static func get_attack_multiplier(points: int) -> float:
	return 1.0 + 0.1 * clampi(points, 0, MAX_ELEMENT_POINTS)


static func get_resistance_multiplier(points: int) -> float:
	return clampf(1.0 - 0.1 * clampi(points, 0, MAX_ELEMENT_POINTS), 0.0, 1.0)
