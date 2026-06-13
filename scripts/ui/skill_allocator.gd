## Skill Allocator UI — UI data-driven para distribuir skill points.
##
## Muestra todas las skills que el jugador posee. Por cada skill:
##   - Nombre y descripción
##   - Lista de designed_max stats con barra visual (current/designed)
##   - Botones +/- para asignar/deasignar puntos al stat
##   - Muestra el ratio de power actual (0-1)
##
## Header:
##   - Skill points disponibles
##   - Proficiency + tier
##
## Controles:
##   - Esc o Tab: cerrar
##   - Click en +/- o flechas
##
## Pausa el juego con get_tree().paused = true al abrirse.
extends Control

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")
const BalanceScript := preload("res://scripts/skill/balance.gd")

const SKILL_PANEL := preload("res://scenes/ui/skill_panel.tscn")

var _root_vbox: VBoxContainer
var _header_label: Label
var _skills_container: VBoxContainer
var _close_button: Button

var _skill_panels: Dictionary = {}  # StringName -> SkillPanel instance
var _skill_icon_hud: VBoxContainer
var _skill_icon_rows: Dictionary = {}

var _was_paused: bool = false


func _ready() -> void:
	# Escondido por defecto; el player lo abre con Tab
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	# Fondo semitransparente
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	# Color de fondo
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.85)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_root_vbox = VBoxContainer.new()
	_root_vbox.anchor_left = 0.05
	_root_vbox.anchor_top = 0.05
	_root_vbox.anchor_right = 0.95
	_root_vbox.anchor_bottom = 0.95
	_root_vbox.add_theme_constant_override("separation", 12)
	add_child(_root_vbox)

	# Header
	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 24)
	_header_label.text = "Skill Allocator"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(_header_label)

	# Skill bar HUD
	var hud_title := Label.new()
	hud_title.text = "Skill Bar"
	hud_title.add_theme_font_size_override("font_size", 16)
	_root_vbox.add_child(hud_title)
	_skill_icon_hud = VBoxContainer.new()
	_skill_icon_hud.add_theme_constant_override("separation", 6)
	_root_vbox.add_child(_skill_icon_hud)

	# Close button
	_close_button = Button.new()
	_close_button.text = "Close (Tab/Esc)"
	_close_button.pressed.connect(_close)
	_root_vbox.add_child(_close_button)

	# Scroll container para skills
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(scroll)

	_skills_container = VBoxContainer.new()
	_skills_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_skills_container)


## Abre la UI. Pausa el juego.
func open() -> void:
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_refresh()


## Cierra la UI. Reanuda el juego.
func _close() -> void:
	visible = false
	get_tree().paused = _was_paused


## Refresca el contenido: header + skills.
func _refresh() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	_header_label.text = "Skill Allocator — Points: %d  |  Proficiency: %d  |  Tier: %s" % [
		ps.skill_points,
		ps.proficiency,
		ps.get_tier_name()
	]
	_refresh_skill_bar_hud(ps)
	# Limpia paneles viejos
	for child in _skills_container.get_children():
		child.queue_free()
	_skill_panels.clear()
	# Crea un panel por skill owned
	for skill_id in ps.owned_skills:
		var skill = ps.get_skill(skill_id)
		if skill == null:
			continue
		var panel = SKILL_PANEL.instantiate()
		_skills_container.add_child(panel)
		panel.setup(skill)
		_skill_panels[skill_id] = panel


func _refresh_skill_bar_hud(ps: Node) -> void:
	if _skill_icon_hud == null:
		return
	for child in _skill_icon_hud.get_children():
		child.queue_free()
	_skill_icon_rows.clear()
	var player := get_tree().root.find_child("Player", true, false)
	var bar: Array = []
	if player and "skill_bar" in player:
		bar = player.skill_bar
	for slot_idx in range(3):
		var skill_id: StringName = &""
		if slot_idx < bar.size():
			skill_id = bar[slot_idx]
		var skill = ps.get_skill(skill_id) if skill_id != &"" else null
		_skill_icon_hud.add_child(_make_skill_slot_row(ps, skill, skill_id, slot_idx, player))


func _make_skill_slot_row(ps: Node, skill, skill_id: StringName, slot_idx: int, player: Node) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.color = _skill_color_for(skill_id)
	row.add_child(icon)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var binding_text := _binding_text_for_slot(slot_idx)
	var cd_text := "READY"
	var cooldown_left := 0.0
	if player and "_skill_cooldowns" in player:
		cooldown_left = float(player._skill_cooldowns.get(String(skill_id), 0.0))
	if cooldown_left > 0.0:
		cd_text = "CD %.1fs" % cooldown_left
	if skill == null:
		label.text = "Slot %d — vacío" % (slot_idx + 1)
	else:
		label.text = "%s | %s | %s" % [String(skill.name), binding_text, cd_text]
		if skill.has("icon_hint") and String(skill.icon_hint) != "":
			label.text += " | %s" % String(skill.icon_hint)
	row.add_child(label)
	return row


func _binding_text_for_slot(slot_idx: int) -> String:
	match slot_idx:
		0:
			return "T"
		1:
			return "G"
		2:
			return "H"
		_:
			return "?"


func _skill_color_for(skill_id: StringName) -> Color:
	if skill_id == &"":
		return Color(0.35, 0.35, 0.35)
	var sid := String(skill_id)
	if sid.find("kamehameha") != -1:
		return Color(0.2, 0.6, 1.0)
	if sid.find("pistol") != -1 or sid.find("gomu") != -1:
		return Color(1.0, 0.65, 0.2)
	if sid.find("punch") != -1:
		return Color(1.0, 0.2, 0.2)
	return Color(0.8, 0.8, 0.8)
