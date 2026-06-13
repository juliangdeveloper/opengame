## objectives_tab_content.gd — Lógica del tab "Objetivos" en el menú.
##
## Muestra los 20 bosses predefinidos en una lista scrollable. Cada entry
## tiene un botón "RETAR" que invoca ObjectivesManager.start_objective.
##
## Se attacha al menu.gd como un child del ObjectivesPanel (creado en .tscn).
## Sigue el mismo patrón que mission_tab_content.gd.
extends RefCounted

var _menu: Control = null
var _list: VBoxContainer = null
var _back_button: Button = null
var _active_objective_id: StringName = &""


func attach(menu: Control) -> void:
	_menu = menu
	_list = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel/ObjectivesMargin/ObjectivesVBox/ObjScroll/ObjList")
	_back_button = menu.get_node_or_null("Panel/Margin/VBox/ObjectivesPanel/ObjectivesMargin/ObjectivesVBox/ObjBackButton")
	# Hide back button (we use R1/L1 to cycle tabs in the menu)
	if _back_button:
		_back_button.visible = false
	_populate_list()
	# Conectar signal del ObjectivesManager para refrescar cuando se complete
	var om: Node = Engine.get_main_loop().root.get_node_or_null("ObjectivesManager")
	if om and not om.objective_completed.is_connected(_on_objective_completed):
		om.objective_completed.connect(_on_objective_completed)
	if om and not om.objective_started.is_connected(_on_objective_started):
		om.objective_started.connect(_on_objective_started)


func _populate_list() -> void:
	if _list == null:
		return
	# Limpiar
	for c in _list.get_children():
		c.queue_free()
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
		# Separator
		_list.add_child(HSeparator.new())


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
