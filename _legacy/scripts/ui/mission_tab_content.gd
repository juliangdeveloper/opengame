extends RefCounted
## MissionTabContent — lógica de la pestaña "Misión" del menú.
##
## Conecta los nodos UI del MissionPanel (built-in en menu.tscn) a los
## métodos del MissionManager. NO es un nodo instanciado — se adosa
## al MissionPanel via bind_nodes(panel) y maneja la lógica via
## connect_manager().
##
## Layout esperado del MissionPanel:
##   MissionPanel (PanelContainer)
##   └─ VBox
##       ├─ TitleLabel
##       ├─ PurposeLabel
##       ├─ TypeLabel
##       ├─ StateLabel
##       ├─ DifficultyRow (HBox)
##       │   ├─ DiffLabel
##       │   └─ [Btn1, Btn2, Btn3, Btn4, Btn5]   (5 buttons)
##       ├─ ConfigLabel (multiline, shows enemy count, HP, rewards, modifiers)
##       ├─ Separator
##       └─ ActionButton (Start / Abandon / Retry / Edit)

class_name MissionTabContent

var _panel: Control = null
var _title_label: Label = null
var _purpose_label: Label = null
var _type_label: Label = null
var _state_label: Label = null
var _diff_label: Label = null
var _diff_buttons: Array = []  # [Button, Button, ...] 5 items
var _config_label: Label = null
var _action_button: Button = null
var _mission_list_button: Button = null  # opcional: ver lista de misiones

var _mm: Node = null
var _current_mission_id: StringName = &""
var _selected_difficulty: int = 0


func bind_nodes(panel: Control) -> void:
	_panel = panel
	if _panel == null:
		return
	# Walk the panel to find UI nodes by name
	_title_label = _find_label(panel, "TitleLabel")
	_purpose_label = _find_label(panel, "PurposeLabel")
	_type_label = _find_label(panel, "TypeLabel")
	_state_label = _find_label(panel, "StateLabel")
	_diff_label = _find_label(panel, "DiffLabel")
	_config_label = _find_label(panel, "ConfigLabel")
	_action_button = _find_button(panel, "ActionButton")
	_mission_list_button = _find_button(panel, "MissionListButton")
	_diff_buttons.clear()
	for i in range(1, 6):
		var btn := _find_button(panel, "DiffBtn%d" % i)
		if btn != null:
			_diff_buttons.append(btn)


func connect_manager() -> void:
	_mm = Engine.get_main_loop().root.get_node_or_null("MissionManager")
	if _mm == null:
		push_warning("[MissionTabContent] MissionManager not found")
		return
	# Connect difficulty buttons
	for i in range(_diff_buttons.size()):
		var btn: Button = _diff_buttons[i]
		var d: int = i + 1
		btn.pressed.connect(_on_difficulty_pressed.bind(d))
	# Action button
	if _action_button != null:
		_action_button.pressed.connect(_on_action_pressed)
	# List button (next mission)
	if _mission_list_button != null:
		_mission_list_button.pressed.connect(_on_next_mission)
	# MissionManager signals
	if _mm.has_signal("mission_created"):
		_mm.mission_created.connect(_on_any_mission_change)
	if _mm.has_signal("mission_state_changed"):
		_mm.mission_state_changed.connect(_on_state_changed)
	if _mm.has_signal("mission_progress"):
		_mm.mission_progress.connect(_on_progress)
	# Initial pick: first AVAILABLE mission (or current ACTIVE)
	_pick_default_mission()


func refresh() -> void:
	if _mm == null:
		connect_manager()
	if _mm == null:
		return
	# If no current mission, pick one
	if _current_mission_id == &"" or _mm.get_mission(_current_mission_id) == null:
		_pick_default_mission()
	_render()


func focus_default() -> void:
	# Focus the action button or first diff button
	if _diff_buttons.size() > 0 and _diff_buttons[0] != null:
		_diff_buttons[0].grab_focus()


# === Internals ===

func _find_label(node: Node, name: String) -> Label:
	var n: Node = node.find_child(name, true, false)
	if n is Label:
		return n
	return null


func _find_button(node: Node, name: String) -> Button:
	var n: Node = node.find_child(name, true, false)
	if n is Button:
		return n
	return null


func _pick_default_mission() -> void:
	if _mm == null:
		return
	# Priority: ACTIVE > READY > first AVAILABLE
	var active: Resource = _mm.get_active_mission()
	if active != null:
		_current_mission_id = StringName(String(active.id))
		return
	# First READY
	for m in _mm.list_missions():
		if String(m.state) == "READY":
			_current_mission_id = StringName(String(m.id))
			return
	# First AVAILABLE
	for m in _mm.list_missions():
		if String(m.state) == "AVAILABLE":
			_current_mission_id = StringName(String(m.id))
			return
	# Last terminal
	for m in _mm.list_missions():
		_current_mission_id = StringName(String(m.id))
		return
	_current_mission_id = &""


func _on_next_mission() -> void:
	var missions: Array = _mm.list_missions()
	if missions.is_empty():
		return
	# Find current index, pick next
	var idx := -1
	for i in missions.size():
		if String(missions[i].id) == String(_current_mission_id):
			idx = i
			break
	idx = (idx + 1) % missions.size()
	_current_mission_id = StringName(String(missions[idx].id))
	_selected_difficulty = 0
	_render()


func _on_difficulty_pressed(d: int) -> void:
	if _current_mission_id == &"" or _mm == null:
		return
	var m: Resource = _mm.get_mission(_current_mission_id)
	if m == null:
		return
	if String(m.state) != "AVAILABLE":
		push_warning("[MissionTab] can only set difficulty on AVAILABLE missions")
		return
	_selected_difficulty = d
	_mm.set_difficulty(_current_mission_id, d)
	_render()


func _on_action_pressed() -> void:
	if _mm == null or _current_mission_id == &"":
		return
	var m: Resource = _mm.get_mission(_current_mission_id)
	if m == null:
		return
	match String(m.state):
		"READY":
			_mm.start_mission(_current_mission_id)
		"ACTIVE":
			_mm.abandon_mission(_current_mission_id)
		"COMPLETED", "FAILED", "ABANDONED":
			# Show Edit dialog inline (simplified: cycle to next difficulty)
			var new_diff: int = (_selected_difficulty % 5) + 1
			_mm.edit_mission(_current_mission_id, new_diff)
			_selected_difficulty = new_diff
	_render()


func _on_state_changed(_mission_id: StringName, _new_state: StringName) -> void:
	_render()


func _on_progress(_mission_id: StringName, _progress: Dictionary) -> void:
	# Don't re-render on every progress tick (would steal focus); just update progress label
	if _state_label != null and _current_mission_id != &"" and String(_mission_id) == String(_current_mission_id):
		var m: Resource = _mm.get_mission(_current_mission_id)
		if m != null and String(m.state) == "ACTIVE":
			_state_label.text = _state_text_with_progress(m)


func _on_any_mission_change(_mission_id: StringName) -> void:
	# Pick a mission if we don't have one
	if _current_mission_id == &"":
		_pick_default_mission()
	_render()


func _render() -> void:
	if _panel == null or _mm == null:
		return
	var m: Resource = null
	if _current_mission_id != &"":
		m = _mm.get_mission(_current_mission_id)
	if m == null:
		_title_label.text = "Sin misión activa"
		_purpose_label.text = "Pide al Dungeon Master que cree una con create_mission()"
		_type_label.text = ""
		_state_label.text = ""
		_diff_label.text = "Dificultad:"
		for b in _diff_buttons:
			b.disabled = true
			b.modulate = Color(0.5, 0.5, 0.5, 1)
		_config_label.text = ""
		_action_button.text = "Sin misión"
		_action_button.disabled = true
		return
	_title_label.text = m.title
	_purpose_label.text = m.get_purpose_label()
	_type_label.text = "Tipo: %s" % m.mission_type
	_state_label.text = m.get_state_label()
	_diff_label.text = "Dificultad:"
	# Difficulty buttons: enable only for AVAILABLE
	var allow_diff: bool = (String(m.state) == "AVAILABLE")
	for i in range(_diff_buttons.size()):
		var btn: Button = _diff_buttons[i]
		btn.disabled = not allow_diff
		var d: int = i + 1
		if m.difficulty == d:
			btn.modulate = Color(0.4, 1.0, 0.4, 1)  # green = selected
			btn.text = "[%d]" % d
		elif allow_diff:
			btn.modulate = Color.WHITE
			btn.text = "%d" % d
		else:
			btn.modulate = Color(0.5, 0.5, 0.5, 1)
			btn.text = "%d" % d
	# Config: show enemy count, HP mult, rewards, modifiers (only if has difficulty)
	if m.difficulty > 0:
		var cfg_text := "Dificultad: %d\n" % m.difficulty
		cfg_text += "Enemigos: %d %s (HP x%.1f)\n" % [m.enemy_count, m.enemy_type, m.enemy_hp_mult]
		if m.time_limit_sec > 0.0:
			cfg_text += "Tiempo: %ds\n" % int(m.time_limit_sec)
		var sp: int = int(m.rewards.get("skill_points", 0))
		var prof: int = int(m.rewards.get("proficiency", 0))
		cfg_text += "Recompensa: +%d skill points, +%d proficiency\n" % [sp, prof]
		cfg_text += "Modifiers:\n"
		for elem in m.damage_modifiers:
			var mult: float = float(m.damage_modifiers[elem])
			var arrow: String = "↑" if mult > 1.0 else "↓" if mult < 1.0 else "="
			cfg_text += "  %s %s: x%.2f\n" % [elem, arrow, mult]
		_config_label.text = cfg_text
	else:
		_config_label.text = "(elige una dificultad para ver el config)"
	# Action button state-aware
	match String(m.state):
		"AVAILABLE":
			_action_button.text = "(elige dificultad primero)"
			_action_button.disabled = true
		"READY":
			_action_button.text = "▶ START MISSION"
			_action_button.disabled = false
		"ACTIVE":
			_action_button.text = "✕ ABANDON"
			_action_button.disabled = false
		"COMPLETED":
			_action_button.text = "↻ RETRY  (o EDIT para cambiar dificultad)"
			_action_button.disabled = false
		"FAILED":
			_action_button.text = "↻ RETRY  (o EDIT)"
			_action_button.disabled = false
		"ABANDONED":
			_action_button.text = "↻ RETRY  (o EDIT)"
			_action_button.disabled = false
	# List button
	if _mission_list_button != null:
		var count: int = _mm.list_missions().size()
		_mission_list_button.text = "↻ Siguiente (%d misiones)" % count


func _state_text_with_progress(m: Resource) -> String:
	if String(m.mission_type) == "cast_skill_n":
		return "Estado: %s — Casts: %d/%d" % [m.get_state_label(), m.casts, m.enemy_count]
	elif String(m.mission_type) == "survive":
		return "Estado: %s — %.0fs / %.0fs" % [m.get_state_label(), m.elapsed_sec, m.time_limit_sec]
	else:
		return "Estado: %s — Kills: %d/%d" % [m.get_state_label(), m.kills, m.enemy_count]
