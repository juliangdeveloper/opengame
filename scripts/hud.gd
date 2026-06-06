extends CanvasLayer
## HUD: stamina and HP bars for the player. Updates every frame from the player node.

@onready var hp_bar: ProgressBar = $Bars/HP
@onready var stam_bar: ProgressBar = $Bars/Stamina
@onready var hp_label: Label = $Bars/HP/Value
@onready var stam_label: Label = $Bars/Stamina/Value

var player: Node3D

func _ready() -> void:
	# Find player after a frame so the scene is loaded
	await get_tree().process_frame
	player = get_tree().root.find_child("Player", true, false)

func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().root.find_child("Player", true, false)
		if player == null: return
	if not "hp" in player or not "max_hp" in player: return
	hp_bar.max_value = player.max_hp
	hp_bar.value = player.hp
	hp_label.text = "%d / %d" % [int(max(0, player.hp)), int(player.max_hp)]
	stam_bar.max_value = player.max_stamina
	stam_bar.value = player.stamina
	stam_label.text = "%d / %d" % [int(player.stamina), int(player.max_stamina)]


## Setea el texto de objetivo (llamado por MCP). Si no hay label, lo crea.
func set_objective(text: String) -> void:
	var label: Label = get_node_or_null("Objective")
	if label == null:
		label = Label.new()
		label.name = "Objective"
		label.add_theme_font_size_override("font_size", 18)
		label.anchor_left = 0.5
		label.anchor_right = 0.5
		label.anchor_top = 0.0
		label.anchor_bottom = 0.0
		label.offset_left = -200.0
		label.offset_right = 200.0
		label.offset_top = 12.0
		label.offset_bottom = 36.0
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
		add_child(label)
	label.text = "Objective: %s" % text
