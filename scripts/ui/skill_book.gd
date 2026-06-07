extends Control
## SkillBook — UI "compendio" de skills con detalles por skill + asignación de bindings.
##
## Estilo "libro abierto": panel central 1000x600 con dos páginas:
##   - Página izquierda: lista de skills owned (ItemList)
##   - Página derecha: detalle de la skill seleccionada (name/desc/level/power)
##     + filas de atom/stat con botones +/-
##     + dropdown para asignar binding (T/G/H/1/2/3/R1+1/etc)
##
## Lifecycle:
##   - open() / close() con get_tree().paused toggle
##   - process_mode = Node.PROCESS_MODE_ALWAYS (para que los botones respondan
##     cuando el tree está pausado)
##   - Inicialización lazy via process_frame (evita race con autoloads)
##
## No usa class_name para no chocar con el autoload ProgressionState.

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")
const BalanceScript := preload("res://scripts/skill/balance.gd")

# Bindings disponibles: (display_name, action_key_in_player_skill_bar)
const BINDINGS: Array = [
	{"name": "— none —",     "idx": -1},
	{"name": "T (slot 1)",   "idx": 0},
	{"name": "G (slot 2)",   "idx": 1},
	{"name": "H (slot 3)",   "idx": 2},
	{"name": "1 (alt 1)",    "idx": 10},
	{"name": "2 (alt 2)",    "idx": 11},
	{"name": "3 (alt 3)",    "idx": 12},
]

# --- Nodos (configurados en .tscn) ---
@onready var skill_list: ItemList = $Panel/HBoxBody/LeftPanel/ItemList
@onready var name_label: Label = $Panel/HBoxBody/RightPanel/DetailVBox/NameLabel
@onready var desc_label: Label = $Panel/HBoxBody/RightPanel/DetailVBox/DescLabel
@onready var level_label: Label = $Panel/HBoxBody/RightPanel/DetailVBox/LevelLabel
@onready var power_label: Label = $Panel/HBoxBody/RightPanel/DetailVBox/PowerLabel
@onready var binding_option: OptionButton = $Panel/HBoxBody/RightPanel/DetailVBox/BindingRow/BindingOption
@onready var atom_rows: VBoxContainer = $Panel/HBoxBody/RightPanel/DetailVBox/AtomRows
@onready var points_label: Label = $Panel/HBoxBody/RightPanel/DetailVBox/PointsLabel
@onready var close_button: Button = $Panel/HBoxTop/CloseButton
@onready var header_label: Label = $Panel/HBoxTop/HeaderLabel

var _was_paused: bool = false
var _current_skill_id: StringName = &""
var _initialized: bool = false


# En lugar de _ready, inicializamos lazy en process_frame para evitar
# race condition con los autoloads.
func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Conectar one-shot al primer process_frame para inicializar UI
	get_tree().process_frame.connect(_initialize, CONNECT_ONE_SHOT)


func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	# Conectar signals de los nodos
	if not close_button.pressed.is_connected(_close):
		close_button.pressed.connect(_close)
	if not skill_list.item_selected.is_connected(_on_skill_selected):
		skill_list.item_selected.connect(_on_skill_selected)
	if not binding_option.item_selected.is_connected(_on_binding_changed):
		binding_option.item_selected.connect(_on_binding_changed)
	# Llenar dropdown de bindings
	binding_option.clear()
	for i in BINDINGS.size():
		binding_option.add_item(BINDINGS[i]["name"])
	# Cerrar con Esc/Backspace también (compatible con player.gd)
	print("[skill_book] initialized")


# --- Public API ---

func open() -> void:
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	# Liberar mouse para que el UI sea usable
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_close()


func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	# Devolver el mouse al modo captura (player lo necesita)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Refresh ---

func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Header
	header_label.text = "Skill Compendium — Proficiency: %d (%s)" % [
		ps.proficiency, ps.get_tier_name()
	]
	points_label.text = "Points: %d" % ps.skill_points
	# Llenar lista de skills
	skill_list.clear()
	for sid in ps.owned_skills:
		var skill = ps.get_skill(sid)
		if skill == null:
			continue
		var idx := skill_list.add_item(String(skill.name))
		skill_list.set_item_metadata(idx, String(skill.id))
	# Si tenemos skills y nada seleccionado, seleccionar la primera
	if skill_list.item_count > 0 and skill_list.get_selected_items().is_empty():
		skill_list.select(0)
		_on_skill_selected(0)
	elif skill_list.item_count > 0 and not skill_list.get_selected_items().is_empty():
		# Mantener selección actual
		var sel := skill_list.get_selected_items()[0]
		_on_skill_selected(sel)


func _on_skill_selected(idx: int) -> void:
	if idx < 0:
		return
	var meta = skill_list.get_item_metadata(idx)
	if meta == null:
		return
	_current_skill_id = StringName(meta)
	_show_skill_detail(_current_skill_id)


func _show_skill_detail(skill_id: StringName) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	var skill = ps.get_skill(skill_id)
	if skill == null:
		name_label.text = "<missing>"
		return
	# Header
	name_label.text = String(skill.name)
	desc_label.text = String(skill.description) if skill.description else ""
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Power / ratio
	var ratio: float = ps.get_skill_power_ratio(skill_id)
	power_label.text = "Power: %.0f%%" % (ratio * 100.0)
	# Level (tier-based label)
	level_label.text = "Tier: %s" % ps.get_tier_name()
	# Points disponibles
	points_label.text = "Points: %d" % ps.skill_points
	# Limpiar y crear atom rows
	for child in atom_rows.get_children():
		child.queue_free()
	atom_rows.add_child(_build_points_label_row(ps, skill_id, skill))
	for stat_name_v in skill.designed_max.keys():
		var stat_name: StringName = StringName(stat_name_v)
		var designed: float = float(skill.designed_max[stat_name_v])
		if designed <= 0.0:
			continue
		atom_rows.add_child(_build_stat_row(ps, skill_id, stat_name, designed))
	# Binding: qué slot está asignado a esta skill
	_set_binding_dropdown(ps, skill_id)


func _set_binding_dropdown(ps: Node, skill_id: StringName) -> void:
	# Buscar en skill_bar del player
	var player := get_tree().root.find_child("Player", true, false)
	var current_idx := -1
	if player and "skill_bar" in player:
		var bar: Array = player.skill_bar
		for i in bar.size():
			if String(bar[i]) == String(skill_id):
				current_idx = i
				break
	# Mapear idx de skill_bar -> idx de BINDINGS
	var match_b: int = 0  # default "— none —"
	for i in BINDINGS.size():
		if int(BINDINGS[i]["idx"]) == current_idx:
			match_b = i
			break
	binding_option.select(match_b)


func _on_binding_changed(b_idx: int) -> void:
	if _current_skill_id == &"":
		return
	var target_slot: int = int(BINDINGS[b_idx]["idx"])
	# Obtener player y modificar skill_bar
	var player := get_tree().root.find_child("Player", true, false)
	if player == null or not ("skill_bar" in player):
		print("[skill_book] player not found, cannot bind")
		return
	var bar: Array = player.skill_bar
	# Quitar esta skill de cualquier slot previo
	for i in bar.size():
		if String(bar[i]) == String(_current_skill_id):
			bar[i] = &""
	# Asignar al nuevo slot (si target_slot >= 0)
	if target_slot >= 0:
		# Asegurar tamaño del bar
		while bar.size() <= target_slot:
			bar.append(&"")
		bar[target_slot] = _current_skill_id
	player.skill_bar = bar
	print("[skill_book] bound %s -> slot %d" % [_current_skill_id, target_slot])


# --- Atom/stat rows ---

func _build_points_label_row(ps: Node, _skill_id: StringName, skill) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s — %d atoms, %d stats" % [String(skill.name), skill.atoms.size(), skill.designed_max.size()]
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	return row


func _build_stat_row(ps: Node, skill_id: StringName, stat_name: StringName, designed: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Label "stat: current/designed (alloc=N)"
	var current: float = ps.get_effective_stat_for_skill(skill_id, stat_name, designed)
	var alloc: int = int(ps.allocations.get(String(skill_id), {}).get(String(stat_name), 0))
	var label := Label.new()
	label.custom_minimum_size = Vector2(180, 0)
	label.text = "%s: %.1f/%.1f [pts=%d]" % [stat_name, current, designed, alloc]
	row.add_child(label)
	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = designed
	bar.value = current
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	# Botones +/- (1 punto por click)
	row.add_child(_make_alloc_button(ps, skill_id, stat_name, "+1", 1, ps.skill_points > 0 and alloc < 5))
	row.add_child(_make_alloc_button(ps, skill_id, stat_name, "-1", -1, alloc > 0))
	row.add_child(_make_alloc_button(ps, skill_id, stat_name, "+5", 5, ps.skill_points > 0 and alloc < 5))
	row.add_child(_make_alloc_button(ps, skill_id, stat_name, "-5", -5, alloc > 0))
	return row


func _make_alloc_button(ps: Node, skill_id: StringName, stat_name: StringName, label: String, delta: int, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.disabled = not enabled
	btn.pressed.connect(_on_alloc_pressed.bind(ps, skill_id, stat_name, delta))
	return btn


func _on_alloc_pressed(ps: Node, skill_id: StringName, stat_name: StringName, delta: int) -> void:
	if delta > 0:
		ps.allocate(skill_id, stat_name, delta)
	else:
		ps.deallocate(skill_id, stat_name, -delta)
	# Re-seleccionar la misma skill para refrescar
	if skill_list.item_count > 0 and not skill_list.get_selected_items().is_empty():
		_on_skill_selected(skill_list.get_selected_items()[0])
	points_label.text = "Points: %d" % ps.skill_points


# --- Helpers ---

func _get_progression_state() -> Node:
	# Buscar el autoload por nombre
	return Engine.get_main_loop().root.get_node_or_null("ProgressionState")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_close()
		get_viewport().set_input_as_handled()
