extends BookTabBase
## AttributeAllocator (unificado: Atributos + Elementos) — UI única
## para distribuir skill_points entre:
##   - Atributos (HP, Stamina, atk%, def%, status_res, ...) — efecto
##     "doble" (mismo punto sube stat Y resistencia al status homónimo)
##   - Elementos (8 elementos + physical) — efecto "Pokémon" (mismo
##     punto sube ATK mult Y baja DEF mult)
##
## Ambos consumen del MISMO pool unificado (ProgressionState.skill_points,
## alias de attribute_points). Ver MenuNavHelper.format_points() para el
## formato del display.
##
## Navegación: misma que el menu.gd (Skills), vía MenuNavHelper.bind_row.
## Bugfixes acumulados:
##   2026-06-14: rows_container no estaba declarado (selector desaparecía)
##   2026-06-14: reset_button.focus_neighbor_bottom faltaba (focus loss)
##   2026-06-14: el menú Elementos se fusiona aquí (5 tabs en vez de 6)
##
## Layout (todo dentro de un solo Scroll → Rows VBox):
##   [HEADER: Atributos]
##     row[0] vital:   HP Max, Stamina Max
##     row[1] offense: atk%, ...
##     row[2] defense: def%, ...
##     row[3] status_res: con link a status homónimo
##   [HSeparator]
##   [HEADER: Elementos]
##     row[N] physical: ATK/DEF bars + -1/+1/-5/+5
##     row[N+1] fire:    ATK/DEF bars + ...
##     ... (8 elementos)

const AttributeCompScript := preload("res://scripts/attribute_component.gd")
const ElementsScript := preload("res://scripts/skill/elements.gd")
const MenuNavHelperScript := preload("res://scripts/ui/menu_nav.gd")
const MenuFocusableScript := preload("res://scripts/ui/menu_focusable.gd")

@onready var back_button: Button = $Panel/Margin/VBox/TopBar/BackButton
@onready var reset_button: Button = $Panel/Margin/VBox/TopBar/ResetButton
@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var points_label: Label = $Panel/Margin/VBox/TopBar/PointsLabel
@onready var rows_container: VBoxContainer = $Panel/Margin/VBox/Scroll/Rows

var _autorepeat: MenuFocusableScript = null
var _attr_row_panels: Array = []  # HBoxContainers in display order (atributos + elementos)
var _element_rows: Dictionary = {}  # elem_id -> {atk_bar, def_bar, btn_plus1, ...}


func _do_initialize() -> void:
	tab_id = &"atributos"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# BUGFIX 2026-06-14: el BackButton debe volver al master (reabrirlo),
	# no solo cerrarse a sí mismo (que dejaba la pantalla en pausa sin UI).
	# Mismo patrón que element_allocator._on_close_pressed → _open_skill_book.
	if not back_button.pressed.is_connected(_on_back_pressed):
		back_button.pressed.connect(_on_back_pressed)
	if not reset_button.pressed.is_connected(_on_reset):
		reset_button.pressed.connect(_on_reset)
	set_process_unhandled_input(true)
	_refresh()


## Cierra esta UI y REABRE el menú master. Si solo cerramos, el juego
## queda en pausa con la pantalla vacía (porque el master ya estaba
## pausado). Reabrir el master restaura la UX consistente.
func _on_back_pressed() -> void:
	_close()
	var master := get_tree().root.find_child("Menu", true, false)
	if master == null:
		master = get_tree().root.find_child("SkillBook", true, false)  # backwards compat
	if master and master.has_method("open"):
		master.open()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	super._input(event)
	if _autorepeat:
		_autorepeat.feed_event(event)


func _on_repeat_step(_direction: String) -> void:
	pass


func open() -> void:
	super.open()
	_refresh()
	for _i in 3:
		call_deferred("_grab_initial_focus_attempt", _i)
	get_tree().create_timer(0.1).timeout.connect(_re_grab_if_lost)


func _grab_initial_focus_attempt(_attempt: int) -> void:
	if _attr_row_panels.is_empty():
		return
	var first_row: HBoxContainer = _attr_row_panels[0]
	if first_row and is_instance_valid(first_row):
		for c in first_row.get_children():
			if c is Button and not (c as Button).disabled:
				(c as Button).grab_focus()
				return


func _re_grab_if_lost() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	_grab_initial_focus_attempt(-1)


func _on_reset() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	var total := int(ps.call("reset_attribute_allocations"))
	# Reset elements too (same unified pool)
	var el_total := _reset_all_elements(ps)
	total += el_total
	if total > 0:
		print("[attribute_allocator] reset %d points (attr + elements)" % total)
	_refresh()


func _reset_all_elements(ps: Node) -> int:
	var to_return: int = 0
	for element in ps.element_allocations.keys().duplicate():
		var pts: int = int(ps.element_allocations[element])
		ps.deallocate_element(element, pts)
		to_return += pts
	return to_return


func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Pool unificado: total disponible + total ya asignado (atributos + elementos)
	var available: int = int(ps.skill_points)
	var allocated_attrs: int = int(ps.call("get_total_allocated_attribute_points"))
	var allocated_elements: int = 0
	for v in ps.element_allocations.values():
		allocated_elements += int(v)
	var allocated: int = allocated_attrs + allocated_elements
	points_label.text = MenuNavHelperScript.format_points(ps, allocated, -1, "Atributos")
	# Free INMEDIATAMENTE (no queue_free) para que _wire_focus no vea rows viejos
	for c in rows_container.get_children():
		rows_container.remove_child(c)
		c.free()
	_attr_row_panels.clear()
	_element_rows.clear()
	# === Section 1: Atributos ===
	_add_section_label("— ATRIBUTOS —")
	var attrs: Array = AttributeCompScript.ATTRIBUTES
	for attr in attrs:
		var row := _build_attribute_row(ps, attr)
		rows_container.add_child(row)
		_attr_row_panels.append(row)
	# === Section 2: Elementos ===
	_add_section_label("— ELEMENTOS —")
	for e in ElementsScript.ELEMENTS:
		var row := _build_element_row(ps, e)
		rows_container.add_child(row)
		_attr_row_panels.append(row)
	# Re-wire focus chain
	_wire_focus()


func _add_section_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.8, 0.7, 0.5)
	rows_container.add_child(label)


func _build_attribute_row(ps: Node, attr: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(220, 0)
	var group_emoji_map: Dictionary = {
		"vital": "❤",
		"offense": "⚔",
		"defense": "🛡",
		"status_res": "✨",
	}
	var group_emoji: String = String(group_emoji_map.get(String(attr["group"]), ""))
	lbl.text = "%s %s — %s" % [group_emoji, String(attr["display"]), String(attr["description"])]
	row.add_child(lbl)
	var current_val: float = float(ps.get_attribute_points(attr["id"]))
	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(50, 0)
	value_lbl.text = "pts: %d" % int(current_val)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_lbl)
	var attr_id: StringName = attr["id"]
	row.add_child(_make_attr_btn("-5", -5, ps, attr_id, current_val))
	row.add_child(_make_attr_btn("-1", -1, ps, attr_id, current_val))
	row.add_child(_make_attr_btn("+1", 1, ps, attr_id, current_val))
	row.add_child(_make_attr_btn("+5", 5, ps, attr_id, current_val))
	if String(attr["linked_status"]) != "":
		var status_lbl := Label.new()
		status_lbl.custom_minimum_size = Vector2(180, 0)
		var pts: int = int(current_val)
		var dur_red := int(pts * 10)
		var pot_inc := int(pts * 10)
		status_lbl.text = "→ %s: -%d%% recv / +%d%% apply" % [
			String(attr["linked_status"]), dur_red, pot_inc
		]
		status_lbl.modulate = Color(0.9, 0.9, 0.6)
		row.add_child(status_lbl)
	return row


func _make_attr_btn(text: String, delta: int, ps: Node, attr_id: StringName, current_pts: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	if delta > 0:
		btn.disabled = int(ps.skill_points) < delta or (int(current_pts) + delta) > 5
	else:
		btn.disabled = int(current_pts) + delta < 0
	btn.pressed.connect(_on_alloc_pressed.bind(attr_id, delta))
	return btn


func _on_alloc_pressed(attr_id: StringName, delta: int) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	if delta > 0:
		ps.call("allocate_attribute", attr_id, delta)
	else:
		ps.call("deallocate_attribute", attr_id, -delta)
	_refresh()


## Construye un row para un elemento (8 elementos + physical).
## Layout: [icon][name+desc] [ATK bar+val] [DEF bar+val] [-1/+1/-5/+5]
## Mismo HBoxContainer que los attribute rows para que bind_row
## funcione uniforme en TODO el menú unificado.
func _build_element_row(ps: Node, e: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Icon
	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(28, 0)
	icon_label.text = String(e["icon"])
	icon_label.add_theme_font_size_override("font_size", 18)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(icon_label)
	# Name + desc
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vb)
	var name_label := Label.new()
	name_label.text = String(e["name"])
	name_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = String(e["desc"])
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc_label)
	# ATK bar
	var atk_bar := ProgressBar.new()
	atk_bar.custom_minimum_size = Vector2(60, 0)
	atk_bar.min_value = 1.0
	atk_bar.max_value = 1.5
	atk_bar.value = 1.0
	atk_bar.show_percentage = false
	row.add_child(atk_bar)
	# DEF bar
	var def_bar := ProgressBar.new()
	def_bar.custom_minimum_size = Vector2(60, 0)
	def_bar.min_value = 0.5
	def_bar.max_value = 1.0
	def_bar.value = 1.0
	def_bar.show_percentage = false
	row.add_child(def_bar)
	# Value label (% ATK / % DEF combined)
	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(60, 0)
	value_lbl.add_theme_font_size_override("font_size", 11)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_lbl)
	# Buttons
	var elem_id: StringName = StringName(String(e["id"]))
	var cur_pts: int = int(ps.element_allocations.get(elem_id, 0))
	row.add_child(_make_elem_btn("-1", elem_id, cur_pts, ps, -1))
	row.add_child(_make_elem_btn("+1", elem_id, cur_pts, ps, 1))
	row.add_child(_make_elem_btn("-5", elem_id, cur_pts, ps, -5))
	row.add_child(_make_elem_btn("+5", elem_id, cur_pts, ps, 5))
	# Store refs para _refresh updates
	_element_rows[elem_id] = {
		"atk_bar": atk_bar,
		"def_bar": def_bar,
		"value_lbl": value_lbl,
		"btn_minus1": row.get_child(row.get_child_count() - 4),
		"btn_plus1": row.get_child(row.get_child_count() - 3),
		"btn_minus5": row.get_child(row.get_child_count() - 2),
		"btn_plus5": row.get_child(row.get_child_count() - 1),
	}
	# Initial values
	_update_element_row_display(ps, elem_id)
	return row


func _make_elem_btn(text: String, elem_id: StringName, current_pts: int, ps: Node, delta: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	if delta > 0:
		btn.disabled = int(ps.skill_points) < delta or (current_pts + delta) > ElementsScript.MAX_ELEMENT_POINTS
	else:
		var abs_delta: int = -delta
		btn.disabled = current_pts < abs_delta
	btn.pressed.connect(_on_elem_pressed.bind(elem_id, delta))
	return btn


func _on_elem_pressed(elem_id: StringName, delta: int) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	if delta > 0:
		ps.allocate_element(elem_id, delta)
	else:
		ps.deallocate_element(elem_id, -delta)
	_refresh()


func _update_element_row_display(ps: Node, elem_id: StringName) -> void:
	if not _element_rows.has(elem_id):
		return
	var pts: int = int(ps.element_allocations.get(elem_id, 0))
	var atk_mult := ElementsScript.get_attack_multiplier(pts)
	var def_mult := ElementsScript.get_resistance_multiplier(pts)
	var r: Dictionary = _element_rows[elem_id]
	r["atk_bar"].value = atk_mult
	r["def_bar"].value = def_mult
	r["value_lbl"].text = "%d%%/%d%%" % [int(atk_mult * 100), int(def_mult * 100)]
	r["btn_plus1"].disabled = int(ps.skill_points) < 1 or (pts + 1) > ElementsScript.MAX_ELEMENT_POINTS
	r["btn_plus5"].disabled = int(ps.skill_points) < 5 or (pts + 5) > ElementsScript.MAX_ELEMENT_POINTS
	r["btn_minus1"].disabled = pts < 1
	r["btn_minus5"].disabled = pts < 5


## Re-wire focus chain usando MenuNavHelper. Wrap-around, scroll-follow,
## D-down desde reset_button → primera row, etc.
func _wire_focus() -> void:
	# TopBar: BackButton ↔ ResetButton
	if back_button and reset_button:
		back_button.focus_neighbor_right = reset_button.get_path()
		reset_button.focus_neighbor_left = back_button.get_path()
	# Bind todas las rows (atributos + elementos) como una sola lista
	# con wrap. La primera row (HP Max) es la "top"; su ↑ → reset_button.
	for i in _attr_row_panels.size():
		var row: HBoxContainer = _attr_row_panels[i]
		if not is_instance_valid(row):
			continue
		MenuNavHelperScript.bind_row(
			row, _attr_row_panels, i,
			reset_button if i == 0 else null,
			true  # wrap
		)
	# D-down desde reset_button → primer button focusable
	if reset_button and not _attr_row_panels.is_empty():
		var first_btn: Button = null
		for r in _attr_row_panels:
			if not is_instance_valid(r):
				continue
			for c in r.get_children():
				if c is Button and not (c as Button).disabled:
					first_btn = c
					break
			if first_btn != null:
				break
		if first_btn != null:
			reset_button.focus_neighbor_bottom = first_btn.get_path()
	# Scroll-follow safety net
	var scroll: ScrollContainer = get_node_or_null("Panel/Margin/VBox/Scroll")
	if scroll:
		var rows_as_controls: Array = []
		for r in _attr_row_panels:
			if is_instance_valid(r):
				rows_as_controls.append(r)
		MenuNavHelperScript.bind_list(rows_as_controls, scroll, true)
	# D-pad auto-repeat driver
	if _autorepeat == null:
		_autorepeat = MenuFocusableScript.new()
		add_child(_autorepeat)
		_autorepeat.repeat_step.connect(_on_repeat_step)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.pressed \
					and (event.button_index == 4 or event.button_index == 6)):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _get_progression_state() -> Node:
	var root: Window = Engine.get_main_loop().root
	var node := root.get_node_or_null("ProgressionState")
	if node == null:
		node = root.find_child("ProgressionState", true, false)
	return node
