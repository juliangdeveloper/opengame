extends BookTabBase
## Menu (antes "SkillBook") — UI "libro abierto" con tabs.
##
## Pestañas (5, navegación cíclica con L1/R1):
##   - Skills     (master, este nodo)         — skills owned + bindings
##   - Misión     (master, MissionPanel)      — quest actual
##   - Elementos  (slave, scene instanced)    — element_allocator
##   - Atributos  (slave)                     — attribute_allocator
##   - Armas      (slave)                     — weapon_allocator
##
## El LLM crea misiones vía MCP (create_mission). El jugador escoge
## dificultad 1-5 desde esta pestaña, ve el config (enemigos, rewards,
## damage_modifiers), y hace click START. Dentro de la misión, puede
## ABANDONAR, RETRY, o EDIT (cambiar dificultad) cuantas veces quiera.
##
## Lifecycle: open()/close() con get_tree().paused toggle.
## process_mode = Node.PROCESS_MODE_ALWAYS (botones responden en pausa).
##
## No usa class_name (choca con autoload ProgressionState).

const BalanceScript := preload("res://scripts/skill/balance.gd")

const BINDINGS: Array = [
	{"name": "— none —",     "slot": -1, "keycode": 0,  "button": -1, "modifier_btn": -1},
	{"name": "1  ·  L1+X",   "slot": 0,  "keycode": 49, "button": 0,  "modifier_btn": 9},
	{"name": "2  ·  L1+□",   "slot": 1,  "keycode": 50, "button": 2,  "modifier_btn": 9},
	{"name": "3  ·  L1+○",   "slot": 2,  "keycode": 51, "button": 1,  "modifier_btn": 9},
	{"name": "4  ·  L1+△",   "slot": 3,  "keycode": 52, "button": 3,  "modifier_btn": 9},
	{"name": "5  ·  R1+X",   "slot": 4,  "keycode": 53, "button": 0,  "modifier_btn": 10},
	{"name": "6  ·  R1+□",   "slot": 5,  "keycode": 54, "button": 2,  "modifier_btn": 10},
	{"name": "7  ·  R1+○",   "slot": 6,  "keycode": 55, "button": 1,  "modifier_btn": 10},
	{"name": "8  ·  R1+△",   "slot": 7,  "keycode": 56, "button": 3,  "modifier_btn": 10},
]

const SWALLOW_WINDOW := 0.2

# Tab order. 0=Skills, 1=Misión, 2=Objetivos, 3=Elementos, 4=Atributos, 5=Armas
const TABS: Array = [&"skills", &"mision", &"objetivos", &"elementos", &"atributos", &"armas"]

# --- Nodos (configurados en .tscn) ---
@onready var skill_list: ItemList = $Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll/ItemList
@onready var name_label: Label = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/NameLabel
@onready var desc_label: Label = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/DescLabel
@onready var level_label: Label = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/LevelLabel
@onready var power_label: Label = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/PowerLabel
@onready var binding_button: Button = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/BindingRow/BindingButton
@onready var atom_rows: VBoxContainer = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/AtomRows
@onready var points_label: Label = $Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll/DetailVBox/PointsLabel
@onready var close_button: Button = $Panel/Margin/VBox/TopBar/CloseButton
@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var prev_tab_button: Button = $Panel/Margin/VBox/TopBar/PrevTabButton
@onready var next_tab_button: Button = $Panel/Margin/VBox/TopBar/NextTabButton
# MissionPanel — sibling de HBoxBody, solo visible cuando TABS[_current_tab] == &"mision"
@onready var mission_panel: Control = $Panel/Margin/VBox/MissionPanel

const MISSION_TAB_SCENE := preload("res://scripts/ui/mission_tab_content.gd")
const OBJECTIVES_TAB_SCENE := preload("res://scripts/ui/objectives_tab_content.gd")
var _mission_tab: RefCounted = null  # control node that implements mission tab logic
var _objectives_tab: RefCounted = null  # control node that implements objectives tab logic

var _scroll_left: ScrollContainer = null
var _scroll_right: ScrollContainer = null
const ELEMENT_ALLOCATOR_SCENE := preload("res://scenes/ui/element_allocator.tscn")
const ATTRIBUTE_ALLOCATOR_SCENE := preload("res://scenes/ui/attribute_allocator.tscn")
const WEAPON_ALLOCATOR_SCENE := preload("res://scenes/ui/weapon_allocator.tscn")

var _current_skill_id: StringName = &""
var _binding_capture_mode: bool = false
var _original_binding_text: String = ""
var _last_close_time: float = 0.0
var _pending_focus_rows: Array = []
var _current_tab: int = 0
var _last_l1: bool = false
var _last_r1: bool = false


func _do_initialize() -> void:
	is_master_tab = true
	tab_id = &"skills"
	_scroll_left = get_node_or_null("Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll")
	_scroll_right = get_node_or_null("Panel/Margin/VBox/HBoxBody/RightPanel/RightMargin/Scroll")
	scroll = _scroll_right
	# Init mission tab
	if mission_panel != null:
		_mission_tab = MISSION_TAB_SCENE.new()
		# Apply the script to the MissionPanel by attaching manually
		# (mission_panel is built in .tscn with UI nodes; we connect to its children by name)
		_mission_tab.bind_nodes(mission_panel)
		_mission_tab.connect_manager()
	# Signals
	if not close_button.pressed.is_connected(_close):
		close_button.pressed.connect(_close)
	if not prev_tab_button.pressed.is_connected(_on_prev_tab):
		prev_tab_button.pressed.connect(_on_prev_tab)
	if not next_tab_button.pressed.is_connected(_on_next_tab):
		next_tab_button.pressed.connect(_on_next_tab)
	if not skill_list.item_selected.is_connected(_on_skill_selected):
		skill_list.item_selected.connect(_on_skill_selected)
	if not binding_button.pressed.is_connected(_on_binding_button_pressed):
		binding_button.pressed.connect(_on_binding_button_pressed)
	_update_top_bar_tabs()
	# Initially hide mission panel
	if mission_panel != null:
		mission_panel.visible = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _binding_capture_mode:
		return
	if event is InputEventJoypadButton and event.pressed:
		var btn: int = event.button_index
		if btn == 9:  # L1
			_on_prev_tab()
			get_viewport().set_input_as_handled()
			return
		elif btn == 10:  # R1
			_on_next_tab()
			get_viewport().set_input_as_handled()
			return


func _on_prev_tab() -> void:
	_current_tab = (_current_tab - 1 + TABS.size()) % TABS.size()
	_switch_to_tab(_current_tab)


func _on_next_tab() -> void:
	_current_tab = (_current_tab + 1) % TABS.size()
	_switch_to_tab(_current_tab)


func _switch_to_tab(idx: int) -> void:
	_current_tab = idx
	_update_top_bar_tabs()
	_close_internal_no_release_pause()
	_close_all_slave_tabs()
	# Hide all panel-style tabs by default
	if mission_panel != null:
		mission_panel.visible = false
	var obj_panel: Control = get_node_or_null("Panel/Margin/VBox/ObjectivesPanel")
	if obj_panel != null:
		obj_panel.visible = false
	var tab_id_str: StringName = TABS[idx]
	var parent_layer: Node = get_tree().root.find_child("MenuContainer", true, false)
	if parent_layer == null:
		parent_layer = get_tree().root.find_child("MenuLayer", true, false)
	if parent_layer == null:
		parent_layer = get_tree().root.find_child("SkillBookContainer", true, false)  # backwards compat
	if parent_layer == null:
		parent_layer = get_tree().root
	if tab_id_str == &"skills":
		visible = true
		if mission_panel != null:
			mission_panel.visible = false
		$Panel/Margin/VBox/HBoxBody.visible = true
		_refresh()
		if skill_list and skill_list.item_count > 0:
			focus_skill_list()
		return
	if tab_id_str == &"mision":
		visible = true
		$Panel/Margin/VBox/HBoxBody.visible = false
		if mission_panel != null:
			mission_panel.visible = true
			if _mission_tab != null:
				_mission_tab.refresh()
				_mission_tab.focus_default()
		return
	if tab_id_str == &"objetivos":
		visible = true
		$Panel/Margin/VBox/HBoxBody.visible = false
		if mission_panel != null:
			mission_panel.visible = false
		var objectives_panel_node: Control = get_node_or_null("Panel/Margin/VBox/ObjectivesPanel")
		if objectives_panel_node != null:
			objectives_panel_node.visible = true
			# Attach the objectives tab content if not yet
			if _objectives_tab == null:
				_objectives_tab = OBJECTIVES_TAB_SCENE.new()
			(_objectives_tab as Object).call("attach", self)
			(_objectives_tab as Object).call("refresh")
		return
	if tab_id_str == &"elementos":
		var ea: Control = parent_layer.get_node_or_null("ElementAllocator") if parent_layer else null
		if ea == null:
			ea = ELEMENT_ALLOCATOR_SCENE.instantiate()
			ea.name = "ElementAllocator"
			parent_layer.add_child(ea)
		if ea.has_method("open"):
			ea.open()
	elif tab_id_str == &"atributos":
		var aa: Control = parent_layer.get_node_or_null("AttributeAllocator") if parent_layer else null
		if aa == null:
			aa = ATTRIBUTE_ALLOCATOR_SCENE.instantiate()
			aa.name = "AttributeAllocator"
			parent_layer.add_child(aa)
		if aa.has_method("open"):
			aa.open()
	elif tab_id_str == &"armas":
		var wa: Control = parent_layer.get_node_or_null("WeaponAllocator") if parent_layer else null
		if wa == null:
			wa = WEAPON_ALLOCATOR_SCENE.instantiate()
			wa.name = "WeaponAllocator"
			parent_layer.add_child(wa)
		if wa.has_method("open"):
			wa.open()


func _close_all_slave_tabs() -> void:
	var parent_layer: Node = get_tree().root.find_child("MenuContainer", true, false)
	if parent_layer == null:
		parent_layer = get_tree().root.find_child("MenuLayer", true, false)
	if parent_layer == null:
		parent_layer = get_tree().root.find_child("SkillBookContainer", true, false)  # backwards compat
	if parent_layer == null:
		return
	for slave_name in ["ElementAllocator", "AttributeAllocator", "WeaponAllocator"]:
		var slave: Node = parent_layer.get_node_or_null(slave_name)
		if slave and slave.visible and slave.has_method("_close"):
			slave._close()


func _update_top_bar_tabs() -> void:
	var prev_idx: int = (_current_tab - 1 + TABS.size()) % TABS.size()
	var next_idx: int = (_current_tab + 1) % TABS.size()
	var prev_name: String = _tab_display_name(TABS[prev_idx])
	var next_name: String = _tab_display_name(TABS[next_idx])
	prev_tab_button.text = "← %s" % prev_name
	next_tab_button.text = "%s →" % next_name
	header_label.text = "Menú — %s" % _tab_display_name(TABS[_current_tab])


func _tab_display_name(id: StringName) -> String:
	match id:
		&"skills":    return "Skills"
		&"mision":    return "Misión"
		&"objetivos": return "Objetivos"
		&"elementos": return "Elementos"
		&"atributos": return "Atributos"
		&"armas":     return "Armas"
	return "?"


# --- Public API ---

func open() -> void:
	_current_tab = 0
	_update_top_bar_tabs()
	super.open()
	_refresh()
	if skill_list and skill_list.item_count > 0:
		focus_skill_list()


func close() -> void:
	_close()


func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _binding_capture_mode:
		_exit_capture_mode()
	_last_close_time = Time.get_ticks_msec() / 1000.0
	_release_all_skill_actions()


func _close_internal_no_release_pause() -> void:
	visible = false
	if _binding_capture_mode:
		_exit_capture_mode()
	_last_close_time = Time.get_ticks_msec() / 1000.0
	_release_all_skill_actions()


func focus_skill_list() -> void:
	if skill_list and skill_list.item_count > 0:
		skill_list.grab_focus()


func was_recently_open() -> bool:
	if visible:
		return true
	return (Time.get_ticks_msec() / 1000.0 - _last_close_time) < SWALLOW_WINDOW


# --- Skills refresh ---

func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	_update_top_bar_tabs()
	points_label.text = "Points: %d" % int(ps.skill_points)
	skill_list.clear()
	for sid in ps.owned_skills:
		var skill = ps.get_skill(sid)
		if skill == null:
			continue
		var idx := skill_list.add_item(String(skill.name))
		skill_list.set_item_metadata(idx, String(skill.id))
	if skill_list.item_count > 0 and skill_list.get_selected_items().is_empty():
		skill_list.select(0)
		_on_skill_selected(0)
	elif skill_list.item_count > 0 and not skill_list.get_selected_items().is_empty():
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
	name_label.text = String(skill.name)
	desc_label.text = String(skill.description) if skill.description else ""
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ratio: float = ps.get_skill_power_ratio(skill_id)
	power_label.text = "Power: %.0f%%" % (ratio * 100.0)
	level_label.text = "Tier: %s" % ps.get_tier_name()
	points_label.text = "Points: %d" % int(ps.skill_points)
	for child in atom_rows.get_children():
		child.queue_free()
	_pending_focus_rows.clear()
	atom_rows.add_child(_build_points_label_row(ps, skill_id, skill))
	for stat_name_v in skill.designed_max.keys():
		var stat_name: StringName = StringName(stat_name_v)
		var designed: float = float(skill.designed_max[stat_name_v])
		if designed <= 0.0:
			continue
		atom_rows.add_child(_build_stat_row(ps, skill_id, stat_name, designed))
	_set_binding_button(ps, skill_id)


func _set_binding_button(ps: Node, skill_id: StringName) -> void:
	var player := get_tree().root.find_child("Player", true, false)
	var current_slot: int = -1
	if player and "skill_bar" in player:
		var bar: Array = player.skill_bar
		for i in bar.size():
			if String(bar[i]) == String(skill_id):
				current_slot = i
				break
	for b in BINDINGS:
		if int(b["slot"]) == current_slot:
			binding_button.text = String(b["name"])
			return
	binding_button.text = String(BINDINGS[0]["name"])


# --- Binding capture ---

func _on_binding_button_pressed() -> void:
	if _current_skill_id == &"":
		return
	if not _binding_capture_mode:
		_enter_capture_mode()


func _enter_capture_mode() -> void:
	_binding_capture_mode = true
	_original_binding_text = binding_button.text
	binding_button.text = "Press a key/button…"
	binding_button.modulate = Color(1.0, 1.0, 0.4)
	if binding_button.has_focus():
		binding_button.release_focus()


func _exit_capture_mode() -> void:
	_binding_capture_mode = false
	binding_button.modulate = Color.WHITE
	var ps := _get_progression_state()
	if ps and _current_skill_id != &"":
		_set_binding_button(ps, _current_skill_id)
	binding_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _binding_capture_mode:
		return
	var pressed := false
	var keycode := 0
	var button := -1
	if event is InputEventKey and event.pressed and not event.echo:
		pressed = true
		keycode = event.keycode
	elif event is InputEventJoypadButton and event.pressed:
		pressed = true
		button = event.button_index
	if not pressed:
		return
	_handle_capture_event(event, keycode, button)


func _handle_capture_event(event: InputEvent, keycode: int, button: int) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE)):
		binding_button.text = _original_binding_text
		_exit_capture_mode()
		get_viewport().set_input_as_handled()
		return
	var current_modifier: int = -1
	if button >= 0:
		if Input.is_action_pressed("modifier_l1"):
			current_modifier = 9
		elif Input.is_action_pressed("modifier_r1"):
			current_modifier = 10
	for b in BINDINGS:
		var b_key: int = int(b.get("keycode", 0))
		var b_btn: int = int(b.get("button", -1))
		var b_mod: int = int(b.get("modifier_btn", -1))
		if keycode != 0 and b_key != 0 and b_key == keycode:
			_assign_binding(int(b["slot"]))
			get_viewport().set_input_as_handled()
			return
		if button != -1 and b_btn != -1 and b_btn == button and b_mod == current_modifier:
			_assign_binding(int(b["slot"]))
			get_viewport().set_input_as_handled()
			return
	var hint: String = ""
	if button != -1 and current_modifier < 0:
		hint = " (hold L1 or R1 first!)"
	binding_button.text = "— not mappable —" + hint
	await get_tree().create_timer(0.6).timeout
	if _binding_capture_mode:
		_exit_capture_mode()


func _assign_binding(slot: int) -> void:
	var player := get_tree().root.find_child("Player", true, false)
	if player == null or not ("skill_bar" in player):
		_exit_capture_mode()
		return
	var bar: Array = player.skill_bar
	for i in bar.size():
		if String(bar[i]) == String(_current_skill_id):
			bar[i] = &""
	if slot >= 0:
		while bar.size() <= slot:
			bar.append(&"")
		bar[slot] = _current_skill_id
	player.skill_bar = bar
	if slot >= 0:
		_release_skill_action(slot)
	_exit_capture_mode()


func _release_skill_action(slot: int) -> void:
	if slot < 0:
		return
	var action: String = "cast_skill_%d" % (slot + 1)
	if InputMap.has_action(action):
		Input.action_release(action)


func _release_all_skill_actions() -> void:
	for slot in range(8):
		_release_skill_action(slot)


# --- Helpers (rows for skill detail) ---

func _get_progression_state() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("ProgressionState")


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
	var current: float = ps.get_effective_stat_for_skill(skill_id, stat_name, designed)
	var alloc: int = int(ps.allocations.get(String(skill_id), {}).get(String(stat_name), 0))
	var label := Label.new()
	label.custom_minimum_size = Vector2(180, 0)
	label.text = "%s: %.1f/%.1f [pts=%d]" % [stat_name, current, designed, alloc]
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = designed
	bar.value = current
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
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
	if skill_list.item_count > 0 and not skill_list.get_selected_items().is_empty():
		_on_skill_selected(skill_list.get_selected_items()[0])
	points_label.text = "Points: %d" % ps.skill_points
