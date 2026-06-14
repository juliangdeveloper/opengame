extends BookTabBase
## AttributeAllocator — UI de asignación de puntos a Atributos.
##
## Estilo "compendio": muestra TODOS los atributos definidos en
## AttributeComponent.ATTRIBUTES con sus botones -1/+1/-5/+5.
##
## El mismo punto sube:
##   - el stat correspondiente (HP, Stamina, atk%, res%, etc.)
##   - y (para status_res) la resistencia al status homónimo
## (regla del "doble efecto" tipo Pokémon/Path of Exile).
##
## Puntos: consume del MISMO pool unificado que Skills/Elementos/Armas
## (ProgressionState.skill_points, alias de attribute_points). Ver
## MenuNavHelper.format_points() para el formato del display.
##
## Navegación: misma que el menu.gd (Skills), vía MenuNavHelper.bind_row.
## Bugfix 2026-06-14: el selector desaparecía porque `rows_container`
## no estaba declarado como @onready (el .tscn tiene `Rows`). Ahora se
## cablea correctamente. Wrap-around, auto-repeat D-pad, focus chain
## unificado con el resto de menús.

const AttributeCompScript := preload("res://scripts/attribute_component.gd")
const MenuNavHelperScript := preload("res://scripts/ui/menu_nav.gd")
const MenuFocusableScript := preload("res://scripts/ui/menu_focusable.gd")

@onready var back_button: Button = $Panel/Margin/VBox/TopBar/BackButton
@onready var reset_button: Button = $Panel/Margin/VBox/TopBar/ResetButton
@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var points_label: Label = $Panel/Margin/VBox/TopBar/PointsLabel
## BUGFIX: el .tscn define `Rows` (no `rows_container`). Antes el código
## referenciaba `rows_container` sin declararlo → null → "selector
## desaparece" en el menú de atributos.
@onready var rows_container: VBoxContainer = $Panel/Margin/VBox/Scroll/Rows

var _autorepeat: MenuFocusableScript = null  # D-pad auto-repeat driver
var _attr_row_panels: Array = []  # HBoxContainers in display order, for MenuNavHelper.bind_row


func _do_initialize() -> void:
	tab_id = &"atributos"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not back_button.pressed.is_connected(close):
		back_button.pressed.connect(close)
	if not reset_button.pressed.is_connected(_on_reset):
		reset_button.pressed.connect(_on_reset)
	# D-pad nav + Esc/Backspace/joy Back/Share cierra
	set_process_unhandled_input(true)
	_refresh()


## Override del _input: tab nav con R1/L1 + autorepeat D-pad.
## D-pad NO se intercepta (dejamos que Godot navegue focus).
## El base ya maneja L1/R1 si el slave es master_tab; acá llamamos
## super para mantener el comportamiento consistente.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	# El base maneja L1/R1 (delegando al master_menu) — siempre lo llamamos
	super._input(event)
	# Alimentar el driver de auto-repeat
	if _autorepeat:
		_autorepeat.feed_event(event)


## No-op: el primer step ya lo entrega Godot (focus moves);
## los repeat steps no necesitan acción extra.
func _on_repeat_step(_direction: String) -> void:
	pass


func open() -> void:
	super.open()
	_refresh()
	# Auto-grab focus en el primer botón útil, con retries (como el arsenal)
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
	if total > 0:
		print("[attribute_allocator] reset %d points" % total)
	_refresh()


func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Unified points display — misma fuente, mismo formato en todos los menús
	# (pool unificado: skill_points == attribute_points via property alias)
	points_label.text = MenuNavHelperScript.format_points(
		ps,
		int(ps.call("get_total_allocated_attribute_points")),
		-1,
		"Atributos"
	)
	# Limpiar rows INMEDIATAMENTE (no queue_free) para que _wire_focus no
	# vea rows viejos. queue_free corre al final del frame y deja
	# focus_neighbor paths apuntando a nodos stale → "selector desaparece".
	for c in rows_container.get_children():
		rows_container.remove_child(c)
		c.free()
	_attr_row_panels.clear()
	# Crear un row por cada atributo
	var attrs: Array = AttributeCompScript.ATTRIBUTES
	for attr in attrs:
		var row := _build_row(ps, attr)
		rows_container.add_child(row)
		_attr_row_panels.append(row)
	# Re-wire focus chain con MenuNavHelper (uniform con arsenal/elementos)
	_wire_focus()


func _build_row(ps: Node, attr: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# Etiqueta con icono/grupo + display + descripción
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(280, 0)
	var id_s: String = String(attr["id"])
	var group_emoji_map: Dictionary = {
		"vital": "❤",
		"offense": "⚔",
		"defense": "🛡",
		"status_res": "✨",
	}
	var group_emoji: String = String(group_emoji_map.get(String(attr["group"]), ""))
	lbl.text = "%s %s — %s" % [group_emoji, String(attr["display"]), String(attr["description"])]
	row.add_child(lbl)
	# Valor actual
	var current_val: float = float(ps.get_attribute_points(attr["id"]))
	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(70, 0)
	value_lbl.text = "pts: %d" % int(current_val)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_lbl)
	# Botones -5, -1, +1, +5
	var btn_minus5 := _make_btn("-5", -5, ps, attr, current_val)
	var btn_minus1 := _make_btn("-1", -1, ps, attr, current_val)
	var btn_plus1 := _make_btn("+1", 1, ps, attr, current_val)
	var btn_plus5 := _make_btn("+5", 5, ps, attr, current_val)
	row.add_child(btn_minus5)
	row.add_child(btn_minus1)
	row.add_child(btn_plus1)
	row.add_child(btn_plus5)
	# Pequeño separator visual
	var sep := VSeparator.new()
	row.add_child(sep)
	# Indicador de efecto derivado: para status_res muestra la duration reduction
	if String(attr["linked_status"]) != "":
		var status_lbl := Label.new()
		status_lbl.custom_minimum_size = Vector2(150, 0)
		var pts: int = int(current_val)
		var dur_red := int(pts * 10)  # 10% por punto
		var pot_inc := int(pts * 10)  # 10% por punto
		status_lbl.text = "→ %s: -%d%% recv / +%d%% apply" % [
			String(attr["linked_status"]), dur_red, pot_inc
		]
		status_lbl.modulate = Color(0.9, 0.9, 0.6)
		row.add_child(status_lbl)
	return row


func _make_btn(text: String, delta: int, ps: Node, attr: Dictionary, current_pts: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	# Habilitar/deshabilitar según disponibilidad (pool unificado: ps.skill_points
	# es el MISMO número que ps.attribute_points gracias al property alias)
	var attr_id: StringName = attr["id"]
	if delta > 0:
		btn.disabled = int(ps.skill_points) < delta or (int(current_pts) + delta) > 5
	else:
		btn.disabled = int(current_pts) + delta < 0
	# Capturar delta y attr_id en el callback
	var _attr_id: StringName = attr_id
	var _delta: int = delta
	btn.pressed.connect(_on_alloc_pressed.bind(_attr_id, _delta))
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


## Re-wire focus chain usando MenuNavHelper (mismo sistema que menu.gd).
## TopBar: BackButton ↔ ResetButton. Attribute rows: chain + wrap
## + first row ↑ → ResetButton. Auto-repeat driver.
func _wire_focus() -> void:
	# TopBar: BackButton ↔ ResetButton
	if back_button and reset_button:
		back_button.focus_neighbor_right = reset_button.get_path()
		reset_button.focus_neighbor_left = back_button.get_path()
	# Rows: usa bind_row chain con wrap-around
	for i in _attr_row_panels.size():
		var row: HBoxContainer = _attr_row_panels[i]
		if not is_instance_valid(row):
			continue
		MenuNavHelperScript.bind_row(
			row, _attr_row_panels, i,
			reset_button if i == 0 else null,
			true  # wrap
		)
	# Scroll-follow safety net (por si headless test no renderiza follow)
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


## Esc / Backspace / joy Back/Share cierra este slave y vuelve al master.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") \
			or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.pressed \
					and (event.button_index == 4 or event.button_index == 6)):
		close()
		get_viewport().set_input_as_handled()


func _get_progression_state() -> Node:
	var root: Window = Engine.get_main_loop().root
	var node := root.get_node_or_null("ProgressionState")
	if node == null:
		node = root.find_child("ProgressionState", true, false)
	return node
