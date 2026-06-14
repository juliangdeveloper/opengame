extends BookTabBase
## Element Allocator UI — Distribuye skill points entre 8 elementos.
##
## El mismo punto sube TANTO el attack multiplier (1.0 + 0.1*pts)
## como el resistance multiplier (1.0 - 0.1*pts) — diseño "Pokémon"
## donde la misma afinidad te hace más fuerte atacando Y más
## resistente al recibir.
##
## Layout:
##   - Header: skill points, total points allocated
##   - Por cada elemento: card con icon + nombre + barras ATK/DEF
##     + botones -1/+1/-5/+5 (focus-friendly para D-pad)
##   - Botón "Reset All" para devolver todos los puntos
##   - Botón Close
##
## Navegación: misma que el menu.gd (Skills), vía MenuNavHelper.

const ElementsScript := preload("res://scripts/skill/elements.gd")
const SkillBookScene := preload("res://scenes/ui/menu.tscn")  # ahora "Menú"
const SKILL_BOOK_NODE_NAME := "Menu"  # backwards compat: SkillBook
const MenuNavHelperScript := preload("res://scripts/ui/menu_nav.gd")
const MenuFocusableScript := preload("res://scripts/ui/menu_focusable.gd")

@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var points_label: Label = $Panel/Margin/VBox/PointsLabel
@onready var elements_container: VBoxContainer = $Panel/Margin/VBox/Scroll/ElementsContainer
@onready var close_button: Button = $Panel/Margin/VBox/TopBar/CloseButton
@onready var open_skill_book_button: Button = $Panel/Margin/VBox/TopBar/OpenSkillBookButton
@onready var reset_button: Button = $Panel/Margin/VBox/BottomBar/ResetButton

var _element_rows: Dictionary = {}  # element_id -> {atk_label, def_label, btn_plus1, ...}
var _element_row_panels: Array = []  # PanelContainer in display order
var _autorepeat: MenuFocusableScript = null  # D-pad auto-repeat driver


func _ready() -> void:
	pass  # La inicialización real ocurre en _do_initialize (después del primer
	# process_frame, evitando race conditions con autoloads).


## Inicialización (llamada por el base en `ready`, antes de que el master
## pueda llamar `open()`). NO tocamos `visible` aquí: el .tscn ya tiene
## `visible = false` por default, y si `open()` fue llamado antes
## (vía el master), debemos respetar ese estado.
func _do_initialize() -> void:
	tab_id = &"elementos"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if not open_skill_book_button.pressed.is_connected(_open_skill_book):
		open_skill_book_button.pressed.connect(_open_skill_book)
	if not reset_button.pressed.is_connected(_reset_all):
		reset_button.pressed.connect(_reset_all)
	# Esc/Backspace para cerrar (vía _unhandled_input)
	set_process_unhandled_input(true)
	_build_element_rows()


## Construye una fila UI por cada elemento (8 + physical = 9).
## Cada fila: [icon][name] | ATK bar | DEF bar | +/- buttons
func _build_element_rows() -> void:
	# Free INMEDIATO (no queue_free) para que _wire_focus no vea rows viejos
	for child in elements_container.get_children():
		elements_container.remove_child(child)
		child.free()
	_element_rows.clear()
	_element_row_panels.clear()
	for e in ElementsScript.ELEMENTS:
		var row := _build_row(e)
		elements_container.add_child(row)
		_element_row_panels.append(row)
	# Wire focus chain (también se re-wirea en _refresh, pero aquí cubrimos el primer render)
	_wire_focus()


func _build_row(e: Dictionary) -> Control:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(e["color"]) * Color(0.3, 0.3, 0.3, 0.6)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(e["color"])
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	row.add_theme_stylebox_override("panel", style)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	row.add_child(hb)

	# Icon (emoji/short text)
	var icon_label := Label.new()
	icon_label.custom_minimum_size = Vector2(40, 0)
	icon_label.text = e["icon"]
	icon_label.add_theme_font_size_override("font_size", 28)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(icon_label)

	# Name + desc
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var name_label := Label.new()
	name_label.text = "%s" % e["name"]
	name_label.add_theme_font_size_override("font_size", 16)
	vb.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = "%s" % e["desc"]
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.modulate = Color(0.7, 0.7, 0.7)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc_label)

	# ATK / DEF bars (vertical)
	var stats_vb := VBoxContainer.new()
	stats_vb.custom_minimum_size = Vector2(200, 0)
	hb.add_child(stats_vb)
	var atk_hb := HBoxContainer.new()
	stats_vb.add_child(atk_hb)
	var atk_label := Label.new()
	atk_label.custom_minimum_size = Vector2(36, 0)
	atk_label.text = "ATK"
	atk_label.add_theme_font_size_override("font_size", 12)
	atk_hb.add_child(atk_label)
	var atk_bar := ProgressBar.new()
	atk_bar.min_value = 1.0
	atk_bar.max_value = 1.5
	atk_bar.value = 1.0
	atk_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atk_bar.show_percentage = false
	atk_hb.add_child(atk_bar)
	var atk_value := Label.new()
	atk_value.custom_minimum_size = Vector2(48, 0)
	atk_value.text = "100%"
	atk_value.add_theme_font_size_override("font_size", 12)
	atk_hb.add_child(atk_value)
	var def_hb := HBoxContainer.new()
	stats_vb.add_child(def_hb)
	var def_label := Label.new()
	def_label.custom_minimum_size = Vector2(36, 0)
	def_label.text = "DEF"
	def_label.add_theme_font_size_override("font_size", 12)
	def_hb.add_child(def_label)
	var def_bar := ProgressBar.new()
	def_bar.min_value = 0.5
	def_bar.max_value = 1.0
	def_bar.value = 1.0
	def_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	def_bar.show_percentage = false
	def_hb.add_child(def_bar)
	var def_value := Label.new()
	def_value.custom_minimum_size = Vector2(48, 0)
	def_value.text = "100%"
	def_value.add_theme_font_size_override("font_size", 12)
	def_hb.add_child(def_value)

	# Buttons (-1 / +1 / -5 / +5)
	var btns_vb := VBoxContainer.new()
	btns_vb.add_theme_constant_override("separation", 2)
	hb.add_child(btns_vb)
	var btn_row1 := HBoxContainer.new()
	btn_row1.add_theme_constant_override("separation", 2)
	btns_vb.add_child(btn_row1)
	var btn_minus1 := Button.new()
	btn_minus1.text = "-1"
	btn_minus1.custom_minimum_size = Vector2(40, 24)
	btn_row1.add_child(btn_minus1)
	var btn_plus1 := Button.new()
	btn_plus1.text = "+1"
	btn_plus1.custom_minimum_size = Vector2(40, 24)
	btn_row1.add_child(btn_plus1)
	var btn_row2 := HBoxContainer.new()
	btn_row2.add_theme_constant_override("separation", 2)
	btns_vb.add_child(btn_row2)
	var btn_minus5 := Button.new()
	btn_minus5.text = "-5"
	btn_minus5.custom_minimum_size = Vector2(40, 24)
	btn_row2.add_child(btn_minus5)
	var btn_plus5 := Button.new()
	btn_plus5.text = "+5"
	btn_plus5.custom_minimum_size = Vector2(40, 24)
	btn_row2.add_child(btn_plus5)

	# Connect buttons
	var elem_id: StringName = e["id"]
	btn_minus1.pressed.connect(_on_minus_pressed.bind(elem_id, 1))
	btn_plus1.pressed.connect(_on_plus_pressed.bind(elem_id, 1))
	btn_minus5.pressed.connect(_on_minus_pressed.bind(elem_id, 5))
	btn_plus5.pressed.connect(_on_plus_pressed.bind(elem_id, 5))

	# Store references for refresh
	_element_rows[elem_id] = {
		"atk_bar": atk_bar,
		"atk_value": atk_value,
		"def_bar": def_bar,
		"def_value": def_value,
		"btn_minus1": btn_minus1,
		"btn_plus1": btn_plus1,
		"btn_minus5": btn_minus5,
		"btn_plus5": btn_plus5,
	}
	return row


func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Unified points display — misma fuente, mismo formato en todos los menús
	points_label.text = MenuNavHelperScript.format_points(
		ps, _total_allocated(ps),
		ElementsScript.MAX_ELEMENT_POINTS * (ElementsScript.ELEMENTS.size() - 1),
		"Elementos"
	)
	for elem_id in _element_rows.keys():
		var pts: int = int(ps.element_allocations.get(elem_id, 0))
		var atk_mult := ElementsScript.get_attack_multiplier(pts)
		var def_mult := ElementsScript.get_resistance_multiplier(pts)
		var r: Dictionary = _element_rows[elem_id]
		r["atk_bar"].value = atk_mult
		r["def_bar"].value = def_mult
		r["atk_value"].text = "%d%%" % int(atk_mult * 100)
		r["def_value"].text = "%d%%" % int(def_mult * 100)
		# Enable/disable buttons según skill points y max
		var can_plus_1: bool = ps.can_allocate_element_more(elem_id, 1)
		var can_plus_5: bool = ps.can_allocate_element_more(elem_id, 5)
		var can_minus: bool = pts > 0
		r["btn_plus1"].disabled = not can_plus_1
		r["btn_plus5"].disabled = not can_plus_5
		r["btn_minus1"].disabled = not can_minus
		var can_minus5: bool = pts >= 5
		r["btn_minus5"].disabled = not can_minus5
	# Re-wire focus chain con MenuNavHelper
	_wire_focus()


func _total_allocated(ps: Node) -> int:
	var total := 0
	for k in ps.element_allocations.keys():
		total += int(ps.element_allocations[k])
	return total


func _on_plus_pressed(element: StringName, amount: int) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	ps.allocate_element(element, amount)
	_refresh()


func _on_minus_pressed(element: StringName, amount: int) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	ps.deallocate_element(element, amount)
	_refresh()


func _reset_all() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Devolver todos los puntos de elementos
	var to_return: int = 0
	for element in ps.element_allocations.keys().duplicate():
		var pts: int = int(ps.element_allocations[element])
		ps.deallocate_element(element, pts)
		to_return += pts
	print("[element_allocator] reset all: +%d points refunded" % to_return)
	_refresh()


# --- API ---

func open() -> void:
	super.open()
	_refresh()
	# Auto-grab focus on first row's +1 button (con retries como el arsenal)
	for _i in 3:
		call_deferred("_grab_initial_focus_attempt", _i)
	get_tree().create_timer(0.1).timeout.connect(_re_grab_if_lost)


func _grab_initial_focus_attempt(_attempt: int) -> void:
	if _element_rows.is_empty():
		return
	var first_row: Dictionary = _element_rows.values()[0]
	var btn: Button = first_row.get("btn_plus1")
	if btn and is_instance_valid(btn):
		btn.grab_focus()


func _re_grab_if_lost() -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	_grab_initial_focus_attempt(-1)


## Re-wire focus chain usando MenuNavHelper (mismo sistema que menu.gd).
## TopBar: OpenSkillBookButton ↔ CloseButton. Element rows: chain + wrap
## + first row ↑ → OpenSkillBookButton. Auto-repeat driver.
func _wire_focus() -> void:
	# TopBar
	if open_skill_book_button and close_button:
		open_skill_book_button.focus_neighbor_right = close_button.get_path()
		close_button.focus_neighbor_left = open_skill_book_button.get_path()
	# Element rows: usa el bind_row chain, con wrap-around
	var rows_to_wire: Array = []
	for panel in _element_row_panels:
		if is_instance_valid(panel):
			# El row tiene 2 HBoxContainers internos (btn_row1 con -1/+1,
			# btn_row2 con -5/+5). Wireamos ambos como un solo "row group"
			# buscando todos los HBox descendants.
			var inner_rows: Array = []
			_collect_hboxes(panel, inner_rows)
			rows_to_wire.append_array(inner_rows)
	# Bind rows
	for i in rows_to_wire.size():
		MenuNavHelperScript.bind_row(
			rows_to_wire[i], rows_to_wire, i,
			open_skill_book_button if i == 0 else null,
			true  # wrap
		)
	# Scroll-follow
	var scroll: ScrollContainer = get_node_or_null("Panel/Margin/VBox/Scroll")
	if scroll:
		MenuNavHelperScript.bind_list(rows_to_wire, scroll, true)
	# D-pad auto-repeat
	if _autorepeat == null:
		_autorepeat = MenuFocusableScript.new()
		add_child(_autorepeat)
		_autorepeat.repeat_step.connect(_on_repeat_step)


func _collect_hboxes(n: Node, out: Array) -> void:
	if n is HBoxContainer:
		out.append(n)
		return
	for c in n.get_children():
		_collect_hboxes(c, out)


func _input(event: InputEvent) -> void:
	# Llamar al base primero (maneja L1/R1 para tab nav, cierre con Esc/Back)
	super._input(event)
	# Alimentar el driver de auto-repeat
	if _autorepeat:
		_autorepeat.feed_event(event)


## No-op: el primer step ya lo entrega Godot (focus moves);
## los repeat steps no necesitan acción extra.
func _on_repeat_step(_direction: String) -> void:
	pass


func close() -> void:
	_close()


## Handler del botón X: cierra esta UI y REABRE la skill book. Esto es
## la UX consistente de "X vuelve al master" (igual que el botón "← Skills").
## NO cerramos totalmente porque eso dejaría el juego en estado paused
## sin UI (porque esta UI se abrió sobre la skill book que ya pausó).
func _on_close_pressed() -> void:
	_open_skill_book()


func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _open_skill_book() -> void:
	# Cierra este y abre el menú (antes "skill book")
	_close()
	var book := get_tree().root.find_child(SKILL_BOOK_NODE_NAME, true, false)
	if book == null:
		book = get_tree().root.find_child("SkillBook", true, false)  # backwards compat
	if book and book.has_method("open"):
		book.open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Esc / Backspace / ui_cancel → cerrar (vuelve a la skill book)
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		_open_skill_book()
		get_viewport().set_input_as_handled()
		return
	# Share/Back también cierra (vuelve a la skill book)
	if event.is_action_pressed("open_skill_book") and event.is_action_pressed:
		_open_skill_book()
		get_viewport().set_input_as_handled()
		return


## Cierra esta UI y pide al skill_book que navegue `delta` tabs.
## delta = -1 → tab anterior, +1 → tab siguiente.
func _navigate_to_master_tab(delta: int) -> void:
	super._navigate_to_master_tab(delta)


func _get_progression_state() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("ProgressionState")
