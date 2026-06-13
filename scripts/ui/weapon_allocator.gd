extends BookTabBase
## Weapon Allocator UI — Tab "Armas" del Skill Book.
##
## Muestra el catálogo de armas (owned + disponibles), permite equipar/
## desequipar, y asignar puntos a stats de cada arma.
##
## Layout (mismo diseño que los otros 3 tabs):
##   - Top bar: header + botón "← Skills" + close
##   - Points label
##   - HSeparator
##   - Scroll horizontal split: lista de armas | detalle + stat rows
##
## Datos desde ProgressionState:
##   - owned_weapons: Array[StringName]
##   - equipped_weapon: Resource (WeaponResource)
##   - weapon_allocations: {weapon_id: {stat: points}}

@onready var header_label: Label = $Panel/Margin/VBox/TopBar/HeaderLabel
@onready var close_button: Button = $Panel/Margin/VBox/TopBar/CloseButton
@onready var open_skill_book_button: Button = $Panel/Margin/VBox/TopBar/OpenSkillBookButton
@onready var points_label: Label = $Panel/Margin/VBox/PointsLabel
@onready var weapons_container: VBoxContainer = $Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll/WeaponsContainer
@onready var name_label: Label = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/NameLabel
@onready var family_label: Label = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/FamilyLabel
@onready var stats_label: Label = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/StatsLabel
@onready var compat_label: Label = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/CompatLabel
@onready var flavor_label: Label = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/FlavorLabel
@onready var equip_button: Button = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/EquipButton
@onready var stat_rows: VBoxContainer = $Panel/Margin/VBox/HBoxBody/DetailPanel/DetailMargin/DetailScroll/DetailVBox/StatRows

var _current_weapon_id: StringName = &""
var _weapon_row_buttons: Dictionary = {}  # weapon_id -> {btn, name_label, status_label}
var _stat_row_buttons: Dictionary = {}  # stat_name -> {plus, minus, val_label}


func _do_initialize() -> void:
	tab_id = &"armas"
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if not open_skill_book_button.pressed.is_connected(_on_open_skill_book_pressed):
		open_skill_book_button.pressed.connect(_on_open_skill_book_pressed)
	if not equip_button.pressed.is_connected(_on_equip_pressed):
		equip_button.pressed.connect(_on_equip_pressed)
	header_label.text = "Arsenal — Equipa y mejora tus armas"


func open() -> void:
	super.open()
	_refresh()


func close() -> void:
	_close()


func _on_close_pressed() -> void:
	_close()


func _on_open_skill_book_pressed() -> void:
	_close()
	# Pedir al master que se reabra
	var book: Control = get_tree().root.find_child("SkillBook", true, false)
	if book and book.has_method("open"):
		book.open()


func _on_equip_pressed() -> void:
	if _current_weapon_id == &"":
		return
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Toggle equip/unequip
	if str(ps.equipped_weapon.id) == str(_current_weapon_id):
		ps.call("unequip_weapon")
	else:
		ps.call("equip_weapon", _current_weapon_id)
	_refresh()


func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Reconstruir lista de armas (catálogo: owned primero, luego resto)
	_weapon_row_buttons.clear()
	for child in weapons_container.get_children():
		child.queue_free()
	var catalog: Array = ps.call("get_weapon_catalog", "all")
	var equipped_id: String = str(ps.equipped_weapon.id) if ps.equipped_weapon != null else ""
	# Separar owned vs no-owned
	var owned: Array = []
	var other: Array = []
	for wid in catalog:
		if wid in ps.owned_weapons:
			owned.append(wid)
		else:
			other.append(wid)
	for wid in owned:
		var row := _build_weapon_row(ps, wid, equipped_id)
		weapons_container.add_child(row)
	# Separator
	if not other.is_empty():
		var sep := HSeparator.new()
		weapons_container.add_child(sep)
		var label := Label.new()
		label.text = "  (catálogo — no en inventario)"
		label.modulate = Color(0.7, 0.7, 0.7)
		label.add_theme_font_size_override("font_size", 11)
		weapons_container.add_child(label)
		for wid in other:
			var row := _build_weapon_row(ps, wid, equipped_id)
			weapons_container.add_child(row)
	# Header points
	points_label.text = "Armas en inventario: %d   |   Puntos de arma: %d" % [
		ps.owned_weapons.size(),
		int(ps.call("get_weapon_points"))
	]
	# Detail: si hay current_weapon_id válido, refrescar; si no, seleccionar la equipada
	if _current_weapon_id == &"" or str(_current_weapon_id) not in catalog:
		if equipped_id != "":
			_current_weapon_id = StringName(equipped_id)
		elif not owned.is_empty():
			_current_weapon_id = owned[0]
	_show_weapon_detail(ps, _current_weapon_id, equipped_id)


func _build_weapon_row(ps: Node, weapon_id: StringName, equipped_id: String) -> Control:
	var w: Resource = ps.call("get_weapon", weapon_id)
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var is_owned: bool = weapon_id in ps.owned_weapons
	var is_equipped: bool = str(weapon_id) == equipped_id
	# Color de fondo según estado
	if is_equipped:
		style.bg_color = Color(0.20, 0.30, 0.20, 0.85)
		style.border_color = Color(0.4, 0.9, 0.4)
	elif is_owned:
		style.bg_color = Color(0.20, 0.20, 0.20, 0.7)
		style.border_color = Color(0.6, 0.6, 0.6)
	else:
		style.bg_color = Color(0.12, 0.12, 0.12, 0.5)
		style.border_color = Color(0.3, 0.3, 0.3)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_right = 3
	style.corner_radius_bottom_left = 3
	row.add_theme_stylebox_override("panel", style)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	row.add_child(hb)
	# Botón para seleccionar
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.alignment = 0  # HORIZONTAL_ALIGNMENT_LEFT (= 0). El enum no se
	# acepta como int en Godot 4.6 strict mode.
	var name_text: String = String(w.display_name) if w and "display_name" in w else str(weapon_id)
	if is_equipped:
		name_text = "▶ " + name_text
	btn.text = name_text
	btn.pressed.connect(_on_weapon_row_pressed.bind(weapon_id))
	hb.add_child(btn)
	# Status label
	var status := Label.new()
	status.custom_minimum_size = Vector2(80, 0)
	if is_equipped:
		status.text = "EQUIPADA"
		status.modulate = Color(0.4, 1.0, 0.4)
	elif is_owned:
		status.text = "inventario"
		status.modulate = Color(0.7, 0.7, 0.7)
	else:
		status.text = "—"
		status.modulate = Color(0.4, 0.4, 0.4)
	hb.add_child(status)
	_weapon_row_buttons[weapon_id] = {"btn": btn, "status": status}
	return row


func _on_weapon_row_pressed(weapon_id: StringName) -> void:
	_current_weapon_id = weapon_id
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	var equipped_id: String = str(ps.equipped_weapon.id) if ps.equipped_weapon != null else ""
	_show_weapon_detail(ps, _current_weapon_id, equipped_id)


func _show_weapon_detail(ps: Node, weapon_id: StringName, equipped_id: String) -> void:
	# Limpiar stat rows
	for child in stat_rows.get_children():
		child.queue_free()
	_stat_row_buttons.clear()
	var w: Resource = null
	if weapon_id != &"":
		w = ps.call("get_weapon", weapon_id)
	if w == null:
		name_label.text = "Selecciona un arma"
		family_label.text = ""
		stats_label.text = ""
		compat_label.text = ""
		flavor_label.text = ""
		equip_button.disabled = true
		return
	name_label.text = String(w.display_name)
	# Family
	if "family" in w:
		family_label.text = "Familia: %s   |   Manos: %d" % [w.get_family_display(), w.hands]
	else:
		family_label.text = ""
	# Stats
	var stats: Dictionary = w.designed_stats if "designed_stats" in w else {}
	var lines: Array = []
	for k in stats.keys():
		lines.append("  %s: %.1f" % [k, float(stats[k])])
	stats_label.text = "Stats: " + ", ".join(lines) if not lines.is_empty() else ""
	# Compat
	var compat: Array = w.compatible_skill_ids if "compatible_skill_ids" in w else []
	var blocked: Array = w.blocked_skill_ids if "blocked_skill_ids" in w else []
	var compat_txt := ""
	if not compat.is_empty():
		compat_txt = "Compatible con: " + ", ".join(compat)
	if not blocked.is_empty():
		if compat_txt != "":
			compat_txt += "   |   "
		compat_txt += "Bloqueado por: " + ", ".join(blocked)
	compat_label.text = compat_txt
	# Flavor
	flavor_label.text = String(w.flavor_text) if "flavor_text" in w and w.flavor_text else ""
	# Equip button
	var is_owned: bool = weapon_id in ps.owned_weapons
	var is_equipped: bool = str(weapon_id) == equipped_id
	if not is_owned:
		equip_button.disabled = true
		equip_button.text = "No en inventario"
	elif is_equipped:
		equip_button.disabled = false
		equip_button.text = "Desequipar"
	else:
		equip_button.disabled = false
		equip_button.text = "Equipar"
	# Stat rows
	var upgrades: Array = []
	if "upgradeable_stats" in w and w.upgradeable_stats:
		upgrades = w.upgradeable_stats
	else:
		# Default: los stat keys que sean numéricos positivos
		for k in stats.keys():
			upgrades.append(k)
	var alloc: Dictionary = ps.weapon_allocations.get(str(weapon_id), {})
	var pts_avail: int = int(ps.call("get_weapon_points"))
	for stat in upgrades:
		var stat_name: StringName = StringName(stat)
		var designed_val: float = float(stats.get(stat, 0.0))
		var current_alloc: int = int(alloc.get(stat, 0))
		var max_alloc: int = 5
		stat_rows.add_child(_build_stat_row(ps, weapon_id, stat_name, designed_val, current_alloc, max_alloc, pts_avail))


func _build_stat_row(ps: Node, weapon_id: StringName, stat_name: StringName, base: float, current: int, max_alloc: int, pts_avail: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.text = "%s" % stat_name
	row.add_child(lbl)
	var base_lbl := Label.new()
	base_lbl.custom_minimum_size = Vector2(60, 0)
	base_lbl.text = "base: %.1f" % base
	base_lbl.modulate = Color(0.7, 0.7, 0.7)
	row.add_child(base_lbl)
	var minus := Button.new()
	minus.text = "-1"
	minus.custom_minimum_size = Vector2(40, 0)
	minus.focus_mode = Control.FOCUS_ALL
	minus.disabled = current <= 0
	row.add_child(minus)
	var val := Label.new()
	val.custom_minimum_size = Vector2(50, 0)
	val.text = "+%d" % current
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(val)
	var plus := Button.new()
	plus.text = "+1"
	plus.custom_minimum_size = Vector2(40, 0)
	plus.focus_mode = Control.FOCUS_ALL
	plus.disabled = pts_avail < 1 or current >= max_alloc
	row.add_child(plus)
	# Connect
	plus.pressed.connect(_on_stat_plus.bind(weapon_id, stat_name))
	minus.pressed.connect(_on_stat_minus.bind(weapon_id, stat_name))
	_stat_row_buttons[stat_name] = {"plus": plus, "minus": minus, "val": val, "base_lbl": base_lbl, "max": max_alloc}
	return row


func _on_stat_plus(weapon_id: StringName, stat: StringName) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	ps.call("allocate_weapon", weapon_id, stat, 1)
	_refresh()


func _on_stat_minus(weapon_id: StringName, stat: StringName) -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	ps.call("deallocate_weapon", weapon_id, stat, 1)
	_refresh()


func _get_progression_state() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("ProgressionState")
