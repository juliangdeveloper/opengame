extends CanvasLayer
## HUD: stamina, HP, skill bar for controller-first play, and mission objective.

@onready var hp_bar: ProgressBar = $Bars/HP
@onready var stam_bar: ProgressBar = $Bars/Stamina
@onready var hp_label: Label = $Bars/HP/Value
@onready var stam_label: Label = $Bars/Stamina/Value

var player: Node3D
var skill_hud: HBoxContainer
var _skill_slots: Array = []
var _objective_label: Label = null  # Creado en _ready

func _ready() -> void:
	# Objective label (top-center of screen)
	_objective_label = Label.new()
	_objective_label.name = "ObjectiveLabel"
	_objective_label.anchor_left = 0.5
	_objective_label.anchor_right = 0.5
	_objective_label.anchor_top = 0.0
	_objective_label.anchor_bottom = 0.0
	_objective_label.offset_left = -300
	_objective_label.offset_right = 300
	_objective_label.offset_top = 20
	_objective_label.offset_bottom = 60
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.modulate = Color(1, 0.9, 0.5, 1)
	_objective_label.text = ""
	_objective_label.z_index = 100
	add_child(_objective_label)
	await get_tree().process_frame
	player = get_tree().root.find_child("Player", true, false)
	_build_skill_hud()
	_refresh_skill_hud()


## set_objective(text) — llamado por MissionManager para mostrar el objetivo
## de la misión activa en la HUD. Pasar "" para limpiar.
func set_objective(text: String) -> void:
	if _objective_label == null:
		return
	_objective_label.text = text
	_objective_label.visible = text != ""

# Por slot: [label_teclado, label_gamepad]. El HUD muestra ambos para que
# el usuario sepa qué tecla/botón activa cada skill.
#
# Slots 0-3: face buttons SIN modifier (X/□/○/△ directos).
# Slots 4-7: L1/R1 + face (modifier).
#
# Esquema de gamepad:
#   X        → slot 0
#   □        → slot 1
#   ○        → slot 2
#   △        → slot 3
#   L1+X     → slot 4
#   L1+□     → slot 5
#   L1+○     → slot 6
#   L1+△     → slot 7
#   L2 held: block legacy.
#
# Esquema de teclado:
#   1-4 → slots 0-3 (skills básicas, sin modifier)
#   L1/R1 + 1-4 → slots 4-7 (skills especiales, con modifier)
const SLOT_BINDINGS := [
	{"kb": "1", "pad": "X"},        # cast_skill_1: tecla 1 / X
	{"kb": "2", "pad": "□"},        # cast_skill_2: tecla 2 / □
	{"kb": "3", "pad": "○"},        # cast_skill_3: tecla 3 / ○
	{"kb": "4", "pad": "△"},        # cast_skill_4: tecla 4 / △
	{"kb": "1+L1", "pad": "L1+X"},  # cast_skill_5: tecla 1 + L1 / L1 + X
	{"kb": "2+L1", "pad": "L1+□"},  # cast_skill_6: tecla 2 + L1 / L1 + □
	{"kb": "3+L1", "pad": "L1+○"},  # cast_skill_7: tecla 3 + L1 / L1 + ○
	{"kb": "4+L1", "pad": "L1+△"},  # cast_skill_8: tecla 4 + L1 / L1 + △
]

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null:
			return
	if not ("hp" in player and "max_hp" in player):
		return
	_refresh_skill_hud()
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	hp_label.text = "%d / %d" % [int(max(0, player.hp)), int(player.max_hp)]
	stam_bar.max_value = player.max_stamina
	stam_bar.value = player.stamina
	stam_label.text = "%d / %d" % [int(player.stamina), int(player.max_stamina)]

func _build_skill_hud() -> void:
	if skill_hud != null:
		return
	skill_hud = HBoxContainer.new()
	skill_hud.name = "SkillHUD"
	# Centrado en la parte inferior, ancho 720 (reducido), alto 56 (reducido).
	skill_hud.anchor_left = 0.5
	skill_hud.anchor_right = 0.5
	skill_hud.anchor_top = 1.0
	skill_hud.anchor_bottom = 1.0
	skill_hud.offset_left = -360.0
	skill_hud.offset_right = 360.0
	skill_hud.offset_top = -68.0
	skill_hud.offset_bottom = -12.0
	skill_hud.add_theme_constant_override("separation", 3)
	add_child(skill_hud)
	# 8 slots: L1+X/□/○/△ (0-3) + R1+X/□/○/△ (4-7).
	# Cada card reducida: 80x52. Separador entre L1 y R1.
	for i in range(8):
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(80, 52)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		card.add_child(vb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vb.add_child(row)
		# Icon más pequeño (10x10).
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(10, 10)
		row.add_child(icon)
		# Title corto, sin truncar.
		var title := Label.new()
		title.text = "Slot %d" % (i + 1)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		title.add_theme_font_size_override("font_size", 10)
		row.add_child(title)
		# Binding: solo el pad label, sin kb (eso va en tooltip).
		var bind := Label.new()
		bind.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bind.text = _pad_label_for_slot(i)
		bind.add_theme_font_size_override("font_size", 9)
		bind.modulate = Color(0.7, 0.7, 0.7)
		vb.add_child(bind)
		# Cooldown label pequeño.
		var cd := Label.new()
		cd.name = "CooldownLabel"
		cd.text = "READY"
		cd.add_theme_font_size_override("font_size", 9)
		vb.add_child(cd)
		# Separador visual entre grupo L1 (slots 0-3) y R1 (slots 4-7).
		skill_hud.add_child(card)
		if i == 3:
			var sep := VSeparator.new()
			skill_hud.add_child(sep)
		_skill_slots.append({"card": card, "icon": icon, "title": title, "bind": bind, "cd": cd, "slot": i})


## Devuelve solo el pad label (sin la parte de teclado) para que el card
## se vea compacto.
func _pad_label_for_slot(slot_idx: int) -> String:
	if slot_idx >= 0 and slot_idx < SLOT_BINDINGS.size():
		return String(SLOT_BINDINGS[slot_idx]["pad"])
	return "Slot %d" % (slot_idx + 1)

func _refresh_skill_hud() -> void:
	if skill_hud == null:
		return
	var ps: Node = get_tree().root.get_node_or_null("ProgressionState")
	if ps == null:
		return
	var bar: Array = []
	if player != null and is_instance_valid(player) and ("skill_bar" in player):
		bar = player.skill_bar
	var cooldowns: Dictionary = {}
	if player != null and is_instance_valid(player) and ("_skill_cooldowns" in player):
		cooldowns = player._skill_cooldowns
	for s in _skill_slots:
		var i := int(s.slot)
		var skill_id: StringName = &""
		if i < bar.size():
			skill_id = bar[i]
		var skill = ps.get_skill(skill_id) if skill_id != &"" else null
		var icon: ColorRect = s.icon
		var title: Label = s.title
		var bind: Label = s.bind
		var cd_label: Label = s.cd
		var card: PanelContainer = s.card
		if skill == null:
			icon.color = Color(0.28, 0.28, 0.28)
			title.text = "—"
			bind.text = _pad_label_for_slot(i)
			cd_label.text = ""
			card.modulate = Color(0.7, 0.7, 0.7, 0.85)
		else:
			icon.color = _skill_color_for(skill_id)
			title.text = String(skill.name)
			bind.text = _pad_label_for_slot(i)
			var cooldown_left := float(cooldowns.get(String(skill_id), 0.0))
			cd_label.text = "READY" if cooldown_left <= 0.0 else "%.1fs" % cooldown_left
			card.modulate = Color(1, 1, 1, 1) if cooldown_left <= 0.0 else Color(1.0, 0.9, 0.6, 1.0)

func _controller_label_for_slot(slot_idx: int) -> String:
	if slot_idx >= 0 and slot_idx < SLOT_BINDINGS.size():
		var b: Dictionary = SLOT_BINDINGS[slot_idx]
		return "%s  ·  %s" % [b["kb"], b["pad"]]
	return "Slot %d" % (slot_idx + 1)

func _controller_hint_from_icon(icon_hint: String) -> String:
	return icon_hint.replace("KEY_", "")

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
