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
##
## Datos desde ProgressionState:
##   - owned_weapons: Array[StringName]
##   - equipped_weapon: Resource (WeaponResource)
##   - weapon_allocations: {weapon_id: {stat: points}}
##
## Navegación: misma que el menu.gd (Skills), gracias a MenuNavHelper
## (focus chain, wrap-around, scroll-follow, auto-repeat con MenuFocusable).

const MenuNavHelperScript := preload("res://scripts/ui/menu_nav.gd")
const MenuFocusableScript := preload("res://scripts/ui/menu_focusable.gd")
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
var _autorepeat: MenuFocusableScript = null  # D-pad auto-repeat driver
var _stat_rows_list: Array = []  # HBoxContainers in display order, for MenuNavHelper.bind_row


func _do_initialize() -> void:
	tab_id = &"armas"
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)
	if not open_skill_book_button.pressed.is_connected(_on_open_skill_book_pressed):
		open_skill_book_button.pressed.connect(_on_open_skill_book_pressed)
	if not equip_button.pressed.is_connected(_on_equip_pressed):
		equip_button.pressed.connect(_on_equip_pressed)
	header_label.text = "Arsenal — Equipa y mejora tus armas"


func _input(event: InputEvent) -> void:
	# Llamar al base primero (maneja L1/R1 para tab nav, cierre con Esc/Back)
	super._input(event)
	# Alimentar el driver de auto-repeat
	if _autorepeat:
		_autorepeat.feed_event(event)


## Llamado por MenuFocusable cuando se detecta D-pad mantenido.
func _on_repeat_step(_direction: String) -> void:
	# No-op: el primer step ya lo entrega Godot (focus moves);
	# los repeat steps no necesitan acción extra.
	pass


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
	# Toggle equip/unequip. BUGFIX 2026-06-14: ps.equipped_weapon puede ser
	# null (al iniciar el juego no hay arma equipada), así que comprobamos
	# antes de leer `.id`. Antes hacía "null instance" en el primer equip.
	var currently_equipped: String = ""
	if ps.equipped_weapon != null and "id" in ps.equipped_weapon:
		currently_equipped = str(ps.equipped_weapon.id)
	if currently_equipped == str(_current_weapon_id):
		ps.call("unequip_weapon")
	else:
		ps.call("equip_weapon", _current_weapon_id)
	_refresh()


func _refresh() -> void:
	var ps: Node = _get_progression_state()
	if ps == null:
		return
	# Reconstruir lista de armas: SOLO owned (como Skills muestra solo
	# owned_skills). El catálogo se quita — el arsenal debe funcionar
	# igual que el menú de skills: solo lo que tienes.
	_weapon_row_buttons.clear()
	# Free INMEDIATO (no queue_free) para que _wire_focus_paths no vea
	# rows viejos con focus_neighbor paths stale.
	for child in weapons_container.get_children():
		weapons_container.remove_child(child)
		child.free()
	var equipped_id: String = str(ps.equipped_weapon.id) if ps.equipped_weapon != null else ""
	# Iterar owned_weapons (mismo patrón que skill_list con owned_skills)
	for wid in ps.owned_weapons:
		var row := _build_weapon_row(ps, wid, equipped_id)
		weapons_container.add_child(row)
	# Header points
	points_label.text = MenuNavHelperScript.format_points(
		ps,
		int(ps.call("get_weapon_points")),
		-1,
		"Armas"
	)
	# Detail: si hay current_weapon_id válido, refrescar; si no, seleccionar la equipada
	var owned_ids: Array = []
	for wid in ps.owned_weapons:
		owned_ids.append(str(wid))
	if _current_weapon_id == &"" or str(_current_weapon_id) not in owned_ids:
		if equipped_id != "" and equipped_id in owned_ids:
			_current_weapon_id = StringName(equipped_id)
		elif not ps.owned_weapons.is_empty():
			_current_weapon_id = ps.owned_weapons[0]
	_show_weapon_detail(ps, _current_weapon_id, equipped_id)
	_wire_focus_paths()
	# Auto-grab focus. Need multiple attempts because Godot's GUI
	# sometimes clears focus again on the same frame the slave becomes
	# visible (the master's hidden focusable nodes can still steal it).
	# call_deferred fires at end of current frame, and a timer catches
	# any race we missed.
	for _i in 3:
		call_deferred("_grab_initial_focus_attempt", _i)
	get_tree().create_timer(0.1).timeout.connect(_re_grab_if_lost)


func _grab_initial_focus_attempt(_attempt: int) -> void:
	print("[WA-DBG] _grab_initial_focus_attempt fire, weapons_container=%d, owner_before=%s" % [weapons_container.get_child_count(), str(get_viewport().gui_get_focus_owner())])
	for child in weapons_container.get_children():
		var b: Button = _first_button_in_node(child)
		if b:
			b.grab_focus()
			print("[WA-DBG] grab ok, owner_after=%s" % str(get_viewport().gui_get_focus_owner()))
			return
	if open_skill_book_button:
		open_skill_book_button.grab_focus()
		print("[WA-DBG] grab ok on TopBar, owner_after=%s" % str(get_viewport().gui_get_focus_owner()))


func _re_grab_if_lost() -> void:
	if not visible:
		return
	var o = get_viewport().gui_get_focus_owner()
	print("[WA-DBG] _re_grab_if_lost timer fire, owner=%s" % str(o))
	if o == null:
		_grab_initial_focus_attempt(-1)


## Conecta focus_neighbor_* usando MenuNavHelper (mismo sistema que
## menu.gd / Skills). Esto unifica:
##   - Weapon list rows (chain + wrap + first row ↑ → OpenSkillBookButton)
##   - EquipButton (left → first weapon row, down → first stat row)
##   - Stat rows (chain + wrap + first stat row's first button ↑ → EquipButton)
##   - Scroll-follow safety net
##   - D-pad auto-repeat
func _wire_focus_paths() -> void:
	# === TopBar: OpenSkillBookButton ↔ CloseButton ===
	if open_skill_book_button and close_button:
		open_skill_book_button.focus_neighbor_right = close_button.get_path()
		close_button.focus_neighbor_left = open_skill_book_button.get_path()
	# === Weapon rows (left list) — same nav as the skills ItemList ===
	var weapon_focusables: Array = []
	for child in weapons_container.get_children():
		var btn: Button = _first_button_in_node(child)
		if btn:
			weapon_focusables.append(btn)
	MenuNavHelperScript.bind_list(
		weapon_focusables,
		get_node_or_null("Panel/Margin/VBox/HBoxBody/LeftPanel/LeftMargin/Scroll"),
		true  # wrap
	)
	# First weapon row ↑ → OpenSkillBookButton (overrides wrap)
	if weapon_focusables.size() > 0 and open_skill_book_button:
		weapon_focusables[0].focus_neighbor_top = open_skill_book_button.get_path()
		open_skill_book_button.focus_neighbor_bottom = weapon_focusables[0].get_path()
	# D-right from each weapon row → equip button (move into detail panel).
	# Esto es lo mismo que hace skills: desde ItemList → DetailPanel.
	if equip_button and not equip_button.disabled and weapon_focusables.size() > 0:
		var equip_path: NodePath = equip_button.get_path()
		for b: Button in weapon_focusables:
			b.focus_neighbor_right = equip_path
	# Last weapon row ↓ → wrap to first (if no override) or first stat row
	# (we set this explicitly: ↓ from last weapon row → first stat row)
	# === EquipButton: left → first weapon row, right/down → first stat row ===
	if equip_button and not equip_button.disabled:
		if weapon_focusables.size() > 0:
			equip_button.focus_neighbor_left = weapon_focusables[0].get_path()
			# Up from equip → also first weapon row (so D-up from stat rows
			# goes equip → first weapon row → OpenSkillBookButton)
			equip_button.focus_neighbor_top = weapon_focusables[0].get_path()
		# Right/Down from equip → first stat row (D-pad moves into the
		# detail panel). Si no hay stat rows, el path queda vacío y
		# Godot usa búsqueda geométrica.
		# BUGFIX 2026-06-14: rebuild _stat_rows_list ANTES de usarlo. Antes
		# la lista tenía refs stale (los stat rows anteriores fueron freed en
		# un _refresh() previo) y leer `_stat_rows_list[0]` lanzaba
		# "Trying to assign invalid previously freed instance" en el cast
		# a HBoxContainer. Ahora: clear + rebuild PRIMERO, después usar.
		_stat_rows_list.clear()
		for child in stat_rows.get_children():
			if child is HBoxContainer and is_instance_valid(child):
				_stat_rows_list.append(child)
		if equip_button and not equip_button.disabled and _stat_rows_list.size() > 0:
			var first_stat_row: HBoxContainer = _stat_rows_list[0]
			if is_instance_valid(first_stat_row):
				# Primer button focusable del primer stat row
				for c in first_stat_row.get_children():
					if c is Button and not (c as Button).disabled:
						equip_button.focus_neighbor_right = c.get_path()
						equip_button.focus_neighbor_bottom = c.get_path()
						break
	# === Stat rows — same nav as menu.gd's atom_rows ===
	# (Ya tenemos _stat_rows_list poblada arriba con stat rows frescos)
	for i in _stat_rows_list.size():
		MenuNavHelperScript.bind_row(
			_stat_rows_list[i], _stat_rows_list, i,
			equip_button if i == 0 else null,
			true  # wrap
		)
	# === Scroll-follow safety net (already done by bind_list / bind_row) ===
	# === D-pad auto-repeat driver ===
	if _autorepeat == null:
		_autorepeat = MenuFocusableScript.new()
		add_child(_autorepeat)
		_autorepeat.repeat_step.connect(_on_repeat_step)


## Encuentra el primer Button focusable dentro de un nodo (recursivo en Containers).
func _first_button_in_node(n: Node) -> Button:
	if n is Button and not (n as Button).disabled:
		return n
	if n is Container:
		for c in n.get_children():
			var b: Button = _first_button_in_node(c)
			if b:
				return b
	return null


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
	# Limpiar stat rows (free INMEDIATO para que _wire_focus_paths no
	# vea los rows viejos mezclados con los nuevos)
	for child in stat_rows.get_children():
		stat_rows.remove_child(child)
		child.free()
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
