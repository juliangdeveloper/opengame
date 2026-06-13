## Elemental & Status Effect Catalog
##
## Define los 8 elementos y los efectos de status del sistema de
## fortalezas/resistencias. Usado por:
##   - SkillResource atoms (campo "element", "applies_status", "status_chance")
##   - ProgressionState.element_allocations (puntos por elemento)
##   - ResistanceComponent (multiplicadores temporales y permanentes)
##   - StatusComponent.Kind enum (statuses elementales)
##
## Diseño "todo en uno": el mismo punto sube tu ataque del elemento Y tu
## resistencia al mismo elemento. Inspirado en Pokémon (mismo tipo = más
## fuerte al atacar Y más resistente al recibir).
extends RefCounted

## === ELEMENTOS (8) ===
## Cada elemento:
##   - "id":      StringName para usar en .tres
##   - "name":    nombre legible en español
##   - "color":   Color del tema (para UI y visuals)
##   - "icon":    emoji/texto corto (para UI sin imágenes)
##   - "desc":    descripción corta
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

## Lookup rápido por ID
static func get_element(id: StringName) -> Dictionary:
	for e in ELEMENTS:
		if e["id"] == id:
			return e
	return {}

static func get_element_color(id: StringName) -> Color:
	return Color(get_element(id).get("color", Color.WHITE))

static func get_element_name(id: StringName) -> String:
	return String(get_element(id).get("name", "???"))

## === ELEMENTAL MATRIX (ventajas/desventajas tipo Pokémon) ===
## Multiplicador de daño cuando ATACANTE de [attacker_elem] ataca a DEFENSOR
## de [defender_elem]. Default 1.0 (neutral).
## 2.0 = super efectivo, 0.5 = poco efectivo, 0.0 = inmune
const ELEMENTAL_MATRIX: Dictionary = {
	&"fire": {
		&"earth": 2.0,  # fuego arrasa la tierra/naturaleza
		&"air": 0.5,    # el aire apaga el fuego
		&"water": 0.5,  # agua apaga fuego
		&"fire": 0.5,   # mismo elemento: solo mitad
		&"arcane": 1.0,
	},
	&"water": {
		&"fire": 2.0,
		&"lightning": 0.5,  # agua conduce electricidad (malo para ti)
		&"water": 0.5,
		&"arcane": 1.0,
	},
	&"earth": {
		&"lightning": 2.0,  # tierra absorbe rayos
		&"air": 0.5,
		&"earth": 0.5,
		&"arcane": 1.0,
	},
	&"air": {
		&"earth": 2.0,
		&"fire": 2.0,       # aire aviva fuego
		&"air": 0.5,
		&"arcane": 1.0,
	},
	&"lightning": {
		&"water": 2.0,
		&"air": 2.0,        # el rayo viaja por el aire
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
		# Arcano no tiene ventaja elemental. Solo es fuerte por mastery.
	},
	&"physical": {
		# Físico es neutral contra todo. Sin modificador elemental.
	},
}

## Multiplicador elemental cuando un ataquero de [atk_elem] ataca a [def_elem].
## Devuelve 1.0 si no hay regla (neutral).
static func get_elemental_multiplier(atk_elem: StringName, def_elem: StringName) -> float:
	if atk_elem == &"" or atk_elem == &"physical":
		return 1.0
	if def_elem == &"" or def_elem == &"physical":
		return 1.0
	var atk_table: Dictionary = ELEMENTAL_MATRIX.get(atk_elem, {})
	return float(atk_table.get(def_elem, 1.0))


## === STATUS EFFECTS (efectos elementales + clásicos) ===
## Estos son los kinds que el StatusComponent reconoce.
## Ya existían (compatibilidad con código previo): STUN, ROOT, SLOW, etc.
## Nuevos elementales: BURN, FREEZE, SHOCK, BLEED, POISON.
const STATUS_EFFECTS: Array = [
	{
		"id": &"burn",
		"name": "Quemadura",
		"element": &"fire",
		"color": Color(1.0, 0.4, 0.1),
		"icon": "🔥",
		"dpt": 3.0,           # damage per tick (típico)
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
	# Efectos clásicos (sin DoT propio, se manejan en StatusComponent)
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


## Devuelve la definición de un status por id.
static func get_status(id: StringName) -> Dictionary:
	for s in STATUS_EFFECTS:
		if s["id"] == id:
			return s
	return {}


## === POINTS → MULTIPLIER CONVERSION ===
##
## Cada punto asignado a un elemento sube TANTO el attack multiplier
## COMO el resistance multiplier. Fórmula:
##   points 0 → 1.0 (neutral)
##   points 1 → 1.10 (10% boost)
##   points 2 → 1.20
##   points 3 → 1.30
##   points 4 → 1.40
##   points 5 → 1.50 (max)
##
## Así, en level 5 de "fire", tus hechizos de fuego hacen 50% más daño
## Y recibes 50% menos daño de fuego. La resistencia se calcula como
## 2.0 - multiplier (cap 1.0 de reducción). Ver get_resistance_multiplier.
const MAX_ELEMENT_POINTS := 5

static func get_attack_multiplier(points: int) -> float:
	# Linear: 0 puntos = 1.0, 5 puntos = 1.5
	return 1.0 + 0.1 * clampi(points, 0, MAX_ELEMENT_POINTS)


## Resistance: a más puntos, más reducción de daño recibido.
## points 0 → multiplier 1.0 (sin resistencia)
## points 5 → multiplier 0.5 (50% menos daño)
static func get_resistance_multiplier(points: int) -> float:
	# Inverse linear: 0 = 1.0, 5 = 0.5
	return clampf(1.0 - 0.1 * clampi(points, 0, MAX_ELEMENT_POINTS), 0.0, 1.0)
