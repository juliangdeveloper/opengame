## objectives_tab_content.gd — Lógica del tab "Objetivos" en el menú.
##
## Muestra los 20 bosses predefinidos en una lista scrollable. Cada entry
## tiene un botón "RETAR" que invoca ObjectivesManager.start_objective.
##
## Se attacha al menu.gd como un child del ObjectivesPanel (creado en .tscn).
## Sigue el mismo patrón que mission_tab_content.gd.
##
## Navegación: usa MenuNavHelper.bind_list() para wirear el focus chain
## de los 20 botones RETAR (wrap-around, scroll-follow, mismo formato que
## los otros menús). D-pad up/down navega entre bosses, X dispara RETAR.
extends RefCounted

const MenuNavHelperScript := preload("res://scripts/ui/menu_nav.gd")

var _menu: Control = null
var _list: VBoxContainer = null
var _scroll: ScrollContainer = null
var _back_button: Button = null
var _active_objective_id: StringName = &""
var _retar_buttons: Array = []  # Buttons "RETAR" en display order, para focus chain


func attach(menu: Control) -> void:
	_menu = menu
	_list = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel/ObjectivesMargin/ObjectivesVBox/ObjScroll/ObjList")
	_scroll = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel/ObjectivesMargin/ObjectivesVBox/ObjScroll")
	_back_button = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel/ObjectivesMargin/ObjectivesVBox/ObjBackButton")
	# Hide back button (we use R1/L1 to cycle tabs in the menu)
	if _back_button:
		_back_button.visible = false
	_populate_list()
	# Conectar signals del ObjectivesManager para refrescar cuando se complete
	var om: Node = Engine.get_main_loop().root.get_node_or_null("ObjectivesManager")
	if om and not om.objective_completed.is_connected(_on_objective_completed):
		om.objective_completed.connect(_on_objective_completed)
	if om and not om.objective_started.is_connected(_on_objective_started):
		om.objective_started.connect(_on_objective_started)


func _populate_list() -> void:
	if _list == null:
		return
	# Limpiar INMEDIATAMENTE (no queue_free) para que _wire_focus no vea
	# rows viejos con focus_neighbor paths stale.
	for c in _list.get_children():
		_list.remove_child(c)
		c.free()
	_retar_buttons.clear()
	# Obtener lista
	var om: Node = Engine.get_main_loop().root.get_node_or_null("ObjectivesManager")
	if om == null:
		return
	var objectives: Array = om.list_objectives()
	# Por cada objetivo, crear un row
	for entry in objectives:
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Info column
		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Title line: "01. Frieza — El Tirano del Espacio"
		var title: String = "%s — %s" % [String(entry.get("display_name", "???")), String(entry.get("title", ""))]
		var title_label: Label = Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 16)
		info.add_child(title_label)
		# Subtitle: tier + reward + status
		var status: String = "✓ COMPLETADO" if entry.get("completed", false) else ("▶ ACTIVO" if entry.get("is_active", false) else "")
		var sub: String = "Tier %d · %d SP · %s" % [
			int(entry.get("tier", 0)),
			int(entry.get("reward_skill_points", 0)),
			status
		]
		var sub_label: Label = Label.new()
		sub_label.text = sub
		sub_label.add_theme_font_size_override("font_size", 12)
		info.add_child(sub_label)
		# Description (strategy hint)
		var desc_label: Label = Label.new()
		desc_label.text = String(entry.get("description", ""))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_font_size_override("font_size", 11)
		info.add_child(desc_label)
		row.add_child(info)
		# Button: RETAR / ACTIVO / ✓
		var btn: Button = Button.new()
		btn.focus_mode = Control.FOCUS_ALL
		var id_str: StringName = StringName(String(entry.get("id", "")))
		if entry.get("completed", false):
			btn.text = "✓"
			btn.disabled = true
		elif entry.get("is_active", false):
			btn.text = "▶ ACTIVO"
			btn.disabled = true
			_active_objective_id = id_str
		else:
			btn.text = "RETAR ▶"
		if not btn.disabled:
			btn.pressed.connect(_on_start_pressed.bind(id_str))
		row.add_child(btn)
		_list.add_child(row)
		_retar_buttons.append(btn)
		# Separator
		_list.add_child(HSeparator.new())
	# Wire focus chain con MenuNavHelper (mismo patrón que arsenal/elementos)
	_wire_focus()


## Wirea el focus chain de los 20 botones RETAR + wrap-around + scroll-follow.
## Esto hace que D-pad up/down navegue entre los bosses, X dispare RETAR.
func _wire_focus() -> void:
	if _retar_buttons.is_empty():
		return
	# Filtrar solo los botones habilitados (focus nav). Pero los disabled
	# también necesitan estar en la chain para que el D-pad no "salte"
	# sobre ellos. MenuNavHelper._chain_items los incluye todos si tienen
	# focus_mode != FOCUS_NONE. Como seteamos focus_mode = FOCUS_ALL arriba,
	# quedan en la chain.
	MenuNavHelperScript.bind_list(_retar_buttons, _scroll, true)


## Llamado por el master menu cuando el tab objetivos se activa.
## Foco en el primer botón RETAR habilitado.
func focus_default() -> void:
	for b in _retar_buttons:
		if b and is_instance_valid(b) and not b.disabled:
			b.grab_focus()
			return


func _on_start_pressed(id: StringName) -> void:
	var om: Node = Engine.get_main_loop().root.get_node_or_null("ObjectivesManager")
	if om == null:
		return
	var resp: Dictionary = om.start_objective(id)
	if resp.get("ok", false) == true:
		_active_objective_id = id
		print("[ObjectivesTab] started %s" % String(id))
		# Cerrar el menú
		if _menu and _menu.has_method("close"):
			_menu.close()
	else:
		push_warning("[ObjectivesTab] start failed: %s" % str(resp))


func _on_objective_completed(id: StringName, _reward: int) -> void:
	if _active_objective_id == id:
		_active_objective_id = &""
	_populate_list()


func _on_objective_started(id: StringName, _path: String) -> void:
	_active_objective_id = id
	_populate_list()


func refresh() -> void:
	_populate_list()
