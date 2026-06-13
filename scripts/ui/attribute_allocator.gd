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
## Navegación:
##   - D-pad/stick se mueve entre filas y botones
##   - Share/Back/Esc cierra
##   - Cierra también con tecla Backspace o el botón "← Volver"

const AttributeCompScript := preload("res://scripts/attribute_component.gd")

@onready var back_button: Button = $Panel/Margin/VBox/TopBar/BackButton
@onready var reset_button: Button = $Panel/Margin/VBox/TopBar/ResetButton
@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var points_label: Label = $Panel/Margin/VBox/TopBar/PointsLabel
@onready var rows_container: VBoxContainer = $Panel/Margin/VBox/Scroll/Rows



func _do_initialize() -> void:
	tab_id = &"atributos"
	if not back_button.pressed.is_connected(close):
		back_button.pressed.connect(close)
	if not reset_button.pressed.is_connected(_on_reset):
		reset_button.pressed.connect(_on_reset)


## Override del _input: cierre con Esc/Backspace/joy Back/Share + R1/L1 nav.
## D-pad NO se intercepta (dejamos que Godot navegue focus).
## El base ya hace scroll + L1/R1; aquí añadimos el cierre.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	if event is InputEventKey and not event.pressed:
		return
	if event is InputEventJoypadButton and not event.pressed:
		return
	# Cerrar con Esc/Backspace/joy Back/Share
	var is_close := false
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACKSPACE):
		is_close = true
	if event is InputEventJoypadButton and (event.button_index == 4 or event.button_index == 6):
		is_close = true
	if is_close:
		close()
		get_viewport().set_input_as_handled()
		return
	# R1/L1 → ciclar tabs (delegando al base). El base los maneja,
	# pero necesitamos re-declarar la lógica aquí si el base no corre
	# (porque attribute_allocator no es master_tab).
	if event is InputEventJoypadButton:
		var btn: int = event.button_index
		if btn == 9:  # L1
			_navigate_to_master_tab(-1)
			get_viewport().set_input_as_handled()
		elif btn == 10:  # R1
			_navigate_to_master_tab(+1)
			get_viewport().set_input_as_handled()


func _navigate_to_master_tab(delta: int) -> void:
	super._navigate_to_master_tab(delta)


func open() -> void:
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()
	# Foco en el primer botón útil
	if rows_container.get_child_count() > 0:
		var first_row := rows_container.get_child(0)
		if first_row is HBoxContainer:
			for c in first_row.get_children():
				if c is Button:
					(c as Button).grab_focus()
					return


func close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	points_label.text = "Puntos: %d   (asignados: %d)" % [
		int(ps.attribute_points), int(ps.call("get_total_allocated_attribute_points"))
	]
	# Limpiar rows
	for c in rows_container.get_children():
		c.queue_free()
	# Crear un row por cada atributo
	var attrs: Array = AttributeCompScript.ATTRIBUTES
	for attr in attrs:
		rows_container.add_child(_build_row(ps, attr))


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
	# Habilitar/deshabilitar según disponibilidad
	var attr_id: StringName = attr["id"]
	if delta > 0:
		btn.disabled = int(ps.attribute_points) < delta or (int(current_pts) + delta) > 5
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


func _get_progression_state() -> Node:
	var root: Window = Engine.get_main_loop().root
	var node := root.get_node_or_null("ProgressionState")
	if node == null:
		node = root.find_child("ProgressionState", true, false)
	return node
