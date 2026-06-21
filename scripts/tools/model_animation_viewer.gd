extends Node3D

# Model/Animation Viewer — auto-discovers imported characters, animations and weapons,
# lets you select each, play animations (with optional loop), and equip weapons to the
# right-hand bone (auto-detected per rig).
#
# Designed to be a sandbox/test scene for opengame: try any imported asset here
# before wiring it into the game logic.

const CHAR_DIR := "res://assets/imports/characters/realpg"
const ANIM_DIR := "res://assets/imports/animations/realpg"
const WPN_DIR := "res://assets/models/weapons"
const WPN_TRES_DIR := "res://data/weapons"

# Per-weapon grip config loaded from data/weapons/*.tres.
# Each entry: { "rotation_deg": Vector3, "grip_offset": float, "scale": float }
# Keyed by weapon stem (e.g. "wpn_short_sword"). Weapons without a matching
# .tres fall back to a sensible default (grip_offset=0.2, no extra rotation).
var weapon_grips: Dictionary = {}

# Auto-discovered
var characters: Array[String] = []        # res:// paths
var character_labels: Array[String] = []   # display names
var animations: Array[String] = []        # res:// paths
var animation_labels: Array[String] = []   # display names (with category prefix)
var weapons: Array[String] = []           # res:// paths
var weapon_labels: Array[String] = []     # display names

# State
var current_character: Node3D = null      # instanced character root
var current_weapon: Node3D = null         # instanced weapon root
var animation_player: AnimationPlayer = null
var current_animation: String = ""

# UI references
@onready var char_option: OptionButton = $UI/Panel/VBox/TopRow/CharBox/CharOption
@onready var anim_option: OptionButton = $UI/Panel/VBox/TopRow/AnimBox/AnimOption
@onready var loop_check: CheckButton = $UI/Panel/VBox/TopRow/LoopBox/LoopCheck
@onready var weapon_option: OptionButton = $UI/Panel/VBox/TopRow/WeaponBox/WeaponOption
@onready var equip_btn: Button = $UI/Panel/VBox/TopRow/EquipBox/HBox/EquipBtn
@onready var unequip_btn: Button = $UI/Panel/VBox/TopRow/EquipBox/HBox/UnequipBtn
@onready var info_label: Label = $UI/Panel/VBox/InfoRow/InfoLabel
@onready var character_pivot: Node3D = $CharacterPivot
@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_scan_characters()
	_scan_animations()
	_scan_weapons()
	_load_weapon_grips()
	_populate_options()
	_connect_signals()
	_load_character(0)
	# Apply initial weapon option (after character loads so we can equip on demand)
	_update_info()
	print("[Viewer] ready — chars=%d anims=%d weapons=%d (grips=%d)" % [characters.size(), animations.size(), weapons.size(), weapon_grips.size()])


func _scan_characters() -> void:
	var dir := DirAccess.open(CHAR_DIR)
	if not dir:
		push_warning("No character dir: %s" % CHAR_DIR)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".fbx.import"):
			var stem := f.replace(".import", "")
			characters.append(CHAR_DIR + "/" + stem)
			# Pretty label: viking_rig_v1 → "Viking Rig V1"
			character_labels.append(_humanize(stem.get_basename()))
		f = dir.get_next()
	dir.list_dir_end()


func _scan_animations() -> void:
	var subdirs := ["basic_motions", "martial_arts", "skills", "steamvr_humanoid", "tests"]
	for sub in subdirs:
		var dir := DirAccess.open(ANIM_DIR + "/" + sub)
		if not dir:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.ends_with(".fbx.import"):
				var stem := f.replace(".import", "")
				animations.append(ANIM_DIR + "/" + sub + "/" + stem)
				animation_labels.append("[%s] %s" % [sub, _humanize(stem.get_basename())])
			f = dir.get_next()
		dir.list_dir_end()


func _scan_weapons() -> void:
	var dir := DirAccess.open(WPN_DIR)
	if not dir:
		push_warning("No weapon dir: %s" % WPN_DIR)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb.import"):
			var stem := f.replace(".import", "")
			weapons.append(WPN_DIR + "/" + stem)
			weapon_labels.append(_humanize(stem.get_basename()))
		f = dir.get_next()
	dir.list_dir_end()


func _humanize(s: String) -> String:
	# viking_rig_v1 → Viking Rig V1, wpn_short_sword → Short Sword
	s = s.replace("_", " ")
	# Strip common prefixes
	for prefix in ["wpn ", "basicmotions ", "humanoid"]:
		if s.to_lower().begins_with(prefix):
			s = s.substr(prefix.length())
	return s.capitalize()


func _load_weapon_grips() -> void:
	# Load every WeaponResource .tres in data/weapons/ and index by stem.
	# Stems are normalized to the wpn_ prefix (e.g. "short_sword.tres" becomes
	# "wpn_short_sword") so the lookup matches the GLB file stems.
	var dir := DirAccess.open(WPN_TRES_DIR)
	if not dir:
		push_warning("No weapon .tres dir: %s" % WPN_TRES_DIR)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres"):
			var res_path: String = WPN_TRES_DIR + "/" + f
			var res: Resource = load(res_path)
			if res == null:
				f = dir.get_next()
				continue
			var stem: String = f.get_basename()
			var key: String = stem if stem.begins_with("wpn_") else "wpn_" + stem
			weapon_grips[key] = {
				"rotation_deg": res.model_rotation,
				"grip_offset": res.grip_offset,
				"scale": res.model_scale,
				"hands": res.hands,
				"category": res.category,
				"display_name": res.display_name,
			}
			print("[Viewer] grip loaded: %s → offset=%.2f rot=%s" % [key, res.grip_offset, res.model_rotation])
		f = dir.get_next()
	dir.list_dir_end()


func _populate_options() -> void:
	char_option.clear()
	for i in range(character_labels.size()):
		char_option.add_item(character_labels[i], i)
	anim_option.clear()
	# Index 0 = "(none)" — explicit no animation
	anim_option.add_item("(none)", -1)
	for i in range(animation_labels.size()):
		anim_option.add_item(animation_labels[i], i)
	weapon_option.clear()
	weapon_option.add_item("(none)", -1)
	for i in range(weapon_labels.size()):
		weapon_option.add_item(weapon_labels[i], i)


func _connect_signals() -> void:
	char_option.item_selected.connect(_on_character_selected)
	anim_option.item_selected.connect(_on_animation_selected)
	loop_check.toggled.connect(_on_loop_toggled)
	weapon_option.item_selected.connect(_on_weapon_selected)
	equip_btn.pressed.connect(_on_equip_pressed)
	unequip_btn.pressed.connect(_on_unequip_pressed)


# ---------- Character handling ----------

func _on_character_selected(idx: int) -> void:
	_load_character(idx)


func _load_character(idx: int) -> void:
	# Free previous
	if is_instance_valid(current_character):
		current_character.queue_free()
		current_character = null
	animation_player = null
	current_animation = ""

	if idx < 0 or idx >= characters.size():
		_update_info()
		return

	var packed := load(characters[idx])
	if not packed:
		info_label.text = "FAIL to load character: %s" % characters[idx]
		return

	current_character = packed.instantiate() as Node3D
	if not current_character:
		info_label.text = "Character did not instantiate (not a Node3D root): %s" % characters[idx]
		return

	character_pivot.add_child(current_character)

	# Normalize scale: many FBX rigs use cm (Mixamo, Unreal exports) so the
	# model ends up ~30x too big for a Godot scene. Detect by checking the
	# skeleton's bone positions and rescale to a human-sized 1.7m tall character.
	_normalize_character_scale(current_character)

	# Re-parent any weapon that was previously equipped to the new character's hand
	if is_instance_valid(current_weapon):
		var old_weapon := current_weapon
		_try_equip_to_character(old_weapon)
		# _try_equip_to_character may have cleared current_weapon; restore it
		current_weapon = old_weapon

	# Find or create AnimationPlayer
	animation_player = _find_animation_player(current_character)
	if not animation_player:
		# Create a new AnimationPlayer so external animations can be applied.
		# Set root_node = ".." so source FBX tracks (format "Skeleton3D:bone_name")
		# resolve correctly when the destination has Skeleton3D as a sibling.
		animation_player = AnimationPlayer.new()
		animation_player.name = "ExternalAnimationPlayer"
		character_pivot.add_child(animation_player)
		# Reparent to current_character so root_node = ".." means current_character
		animation_player.reparent(current_character, false)
		animation_player.root_node = NodePath("..")
		# Find Skeleton3D so tracks can look up bones by name
		var skel := _find_skeleton(current_character)
		if not skel:
			push_warning("[Viewer] character has no Skeleton3D — animations may not play")

	_update_info()
	print("[Viewer] loaded character: %s" % character_labels[idx])


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found:
			return found
	return null


# Detect rig scale by checking bone distances. Many FBX rigs from Mixamo,
# Unreal, and similar tools export in cm. We want a human-sized character
# (~1.7m tall). If the bone positions indicate the rig is at a different
# scale, rescale the character to 1.7m height.
#
# Approach: find the height of the skeleton by looking at the highest bone
# (head) and the lowest (feet). If the height suggests > 5m or < 0.5m,
# rescale to 1.7m.
func _normalize_character_scale(node: Node) -> void:
	var skel := _find_skeleton(node)
	if not skel:
		return
	if skel.get_bone_count() == 0:
		return

	# Find the bounding height of all bone positions in world space.
	var min_y: float = INF
	var max_y: float = -INF
	for i in range(skel.get_bone_count()):
		var p := skel.get_bone_global_pose(i).origin
		if p.y < min_y: min_y = p.y
		if p.y > max_y: max_y = p.y
	var height: float = max_y - min_y
	if height <= 0.0:
		return

	# Target human height ~1.7m. If the rig is already in that ballpark
	# (0.5m .. 5m), don't touch it.
	var target_height := 1.7
	if height >= 0.5 and height <= 5.0:
		return

	var scale_factor := target_height / height
	node.scale = Vector3.ONE * scale_factor
	print("[Viewer] normalized rig scale: height=%.2fm → scale=%.4f" % [height, scale_factor])


# ---------- Animation handling ----------

func _on_animation_selected(idx: int) -> void:
	if not animation_player:
		info_label.text = "No AnimationPlayer on current character"
		return
	if idx < 0 or idx >= animations.size():
		# "(none)" or out-of-range → stop
		animation_player.stop()
		current_animation = ""
		_update_info()
		return
	_play_animation(animations[idx])


func _play_animation(anim_path: String) -> void:
	# Load the animation FBX as a temporary scene to extract its AnimationLibrary
	var packed := load(anim_path)
	if not packed:
		info_label.text = "FAIL to load animation: %s" % anim_path
		return
	var temp_inst: Node = packed.instantiate()
	if not temp_inst:
		info_label.text = "Animation did not instantiate: %s" % anim_path
		return

	# Find source AnimationPlayer
	var src_ap := _find_animation_player(temp_inst)
	if not src_ap:
		info_label.text = "Animation FBX has no AnimationPlayer: %s" % anim_path
		temp_inst.queue_free()
		return

	# Copy each animation library/animation from source to our character
	var src_root := animation_player.root_node
	var src_anims: PackedStringArray = src_ap.get_animation_list()
	if src_anims.is_empty():
		info_label.text = "Animation FBX has no animations"
		temp_inst.queue_free()
		return

	# Remove previous imported animations we added (those with prefix "ext_")
	for lib in animation_player.get_animation_library_list():
		animation_player.remove_animation_library("")

	# Use the first animation; the source's AnimationPlayer uses its own root_node
	# We need to remap tracks to use the character's Skeleton3D as root.
	var src_animation_name: String = src_anims[0]
	var src_anim: Animation = src_ap.get_animation(src_animation_name)
	if not src_anim:
		info_label.text = "No animation named %s in source" % src_animation_name
		temp_inst.queue_free()
		return

	# Build a duplicate animation (so we don't mutate cached FBX data)
	var dup: Animation = src_anim.duplicate(true)
	var anim_name := "ext_" + anim_path.get_file().get_basename()

	# Godot 4: animations must live inside an AnimationLibrary.
	# Create (or reuse) a library named "imported" and add the animation there.
	var lib_name := "imported"
	if not animation_player.has_animation_library(lib_name):
		var lib := AnimationLibrary.new()
		animation_player.add_animation_library(lib_name, lib)
	var lib2: AnimationLibrary = animation_player.get_animation_library(lib_name)
	lib2.add_animation(anim_name, dup)

	# Normalize track paths: different FBX sources use different prefixes
	# before "Skeleton3D:bone_name" — e.g. "Root/Skeleton3D:Shoulder_R"
	# (when source AP.root_node is "Root") or just "Skeleton3D:B-hips"
	# (when source AP.root_node is ".."). We strip everything before
	# "Skeleton3D:" so tracks resolve to our local Skeleton3D.
	_normalize_track_paths(dup)

	# Apply loop setting
	dup.loop_mode = Animation.LOOP_LINEAR if loop_check.button_pressed else Animation.LOOP_NONE

	# In Godot 4, animations in a non-default library are addressed as "lib_name/anim_name"
	var play_name := lib_name + "/" + anim_name
	animation_player.play(play_name)
	current_animation = anim_name
	temp_inst.queue_free()
	_update_info()
	print("[Viewer] playing animation: %s" % anim_name)


func _remap_animation_paths(anim: Animation, old_root: NodePath, new_root: NodePath) -> void:
	# Old root is something like ^"Character1_Hips" or ^"viking_ROOTJ"
	# New root is the AnimationPlayer's root_node (relative to itself)
	# We need to replace the old_root prefix with new_root on every track path
	var tracks := anim.get_track_count()
	for i in range(tracks):
		var path: NodePath = anim.track_get_path(i)
		var path_str := str(path)
		var old_str := str(old_root)
		if old_str != "" and path_str.begins_with(old_str):
			var new_path := path_str.replace(old_str, str(new_root))
			anim.track_set_path(i, NodePath(new_path))


func _on_loop_toggled(pressed: bool) -> void:
	if not animation_player or current_animation == "":
		return
	var anim := animation_player.get_animation(current_animation)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR if pressed else Animation.LOOP_NONE
	_update_info()


func _normalize_track_paths(anim: Animation) -> void:
	# Strip any prefix before "Skeleton3D:" in track paths so they resolve to
	# our local Skeleton3D regardless of the source FBX's path conventions.
	var tracks := anim.get_track_count()
	for i in range(tracks):
		var path: NodePath = anim.track_get_path(i)
		var path_str := str(path)
		var idx := path_str.find("Skeleton3D:")
		if idx > 0:
			var new_path := path_str.substr(idx)
			anim.track_set_path(i, NodePath(new_path))


# ---------- Weapon handling ----------

func _on_weapon_selected(_idx: int) -> void:
	_update_info()


func _on_equip_pressed() -> void:
	# Load selected weapon and attach to character's right-hand bone
	var idx := weapon_option.selected
	if idx <= 0:
		info_label.text = "Pick a weapon first"
		return
	if idx - 1 >= weapons.size():
		return
	_unequip()
	var packed := load(weapons[idx - 1])
	if not packed:
		info_label.text = "FAIL to load weapon: %s" % weapons[idx - 1]
		return
	var wpn := packed.instantiate() as Node3D
	if not wpn:
		info_label.text = "Weapon did not instantiate: %s" % weapons[idx - 1]
		return
	character_pivot.add_child(wpn)
	_try_equip_to_character(wpn)
	current_weapon = wpn
	_update_info()
	print("[Viewer] equipped: %s" % weapon_labels[idx - 1])


func _on_unequip_pressed() -> void:
	_unequip()
	_update_info()


func _unequip() -> void:
	if is_instance_valid(current_weapon):
		current_weapon.queue_free()
		current_weapon = null


func _try_equip_to_character(wpn: Node3D) -> void:
	if not is_instance_valid(current_character):
		return
	var hand := _find_right_hand_bone(current_character)
	if not hand:
		print("[Viewer] no right-hand bone found; weapon stays at character origin")
		return

	# Look up grip config for this weapon by file stem
	var wpn_stem: String = wpn.name.get_basename()  # "wpn_short_sword"
	var grip: Dictionary = _lookup_grip(wpn_stem)

	# Reparent under the hand bone (BoneAttachment3D or hand bone itself)
	wpn.reparent(hand, false)

	# Build the local transform:
	# 1. Base rotation: Blender Z-up → Godot Y-up (X by -90°)
	# 2. model_rotation from .tres (Euler XYZ degrees)
	# 3. Lower the model in Y by grip_offset so the grip point sits at the hand origin
	var base_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0))
	var extra_basis := Basis.from_euler(Vector3(
		deg_to_rad(grip.rotation_deg.x),
		deg_to_rad(grip.rotation_deg.y),
		deg_to_rad(grip.rotation_deg.z),
	))
	var total_basis := base_basis * extra_basis
	var scale_val: float = grip.scale
	wpn.transform = Transform3D(total_basis, Vector3(0.0, -grip.grip_offset, 0.0)).scaled_local(Vector3.ONE * scale_val)
	# Note: scaled_local doesn't change position; we want uniform scale on rotation only
	wpn.scale = Vector3.ONE * scale_val

	print("[Viewer] equipped '%s' to bone '%s' (grip_offset=%.2fm, rot=%s, scale=%.2f)" % [
		wpn_stem, hand.name, grip.grip_offset, grip.rotation_deg, scale_val
	])


func _lookup_grip(wpn_stem: String) -> Dictionary:
	# Direct match
	if weapon_grips.has(wpn_stem):
		return weapon_grips[wpn_stem]
	# Try stripping "wpn_" prefix
	var without_prefix := wpn_stem.replace("wpn_", "")
	if weapon_grips.has(without_prefix):
		return weapon_grips[without_prefix]
	# Try adding "wpn_" prefix
	var with_prefix := "wpn_" + wpn_stem
	if weapon_grips.has(with_prefix):
		return weapon_grips[with_prefix]
	# Default fallback
	return {
		"rotation_deg": Vector3.ZERO,
		"grip_offset": 0.20,
		"scale": 1.0,
		"hands": 1,
		"category": &"unknown",
		"display_name": wpn_stem,
	}


func _find_right_hand_bone(node: Node) -> Node3D:
	# Find the Skeleton3D and create a BoneAttachment3D for the right-hand bone.
	# BoneAttachment3D automatically tracks the bone's global pose each frame.
	var skel := _find_skeleton(node)
	if not skel:
		return null

	# Priority list — match exact/contains in order from most specific to least.
	# We skip bones that contain "thumb", "index", "middle", "ring", "pinky" (fingers).
	var finger_words := ["thumb", "index", "middle", "ring", "pinky"]

	# Pre-compute the children of each bone (by index) to detect "has finger children"
	# — the wrist bone is the only hand bone whose children are finger bones.
	var child_count: PackedInt32Array = PackedInt32Array()
	child_count.resize(skel.get_bone_count())
	for i in range(skel.get_bone_count()):
		child_count[i] = 0
	for i in range(skel.get_bone_count()):
		var pi: int = skel.get_bone_parent(i)
		if pi >= 0:
			child_count[pi] += 1

	var best_name := ""
	var best_score := -1

	for i in range(skel.get_bone_count()):
		var bn: String = skel.get_bone_name(i)
		var lower := bn.to_lower()

		# Skip fingers
		var is_finger := false
		for fw in finger_words:
			if fw in lower:
				is_finger = true
				break
		if is_finger:
			continue

		# Skip root-level dummy bones (no parent in hierarchy).
		# These are usually reference dummies imported alongside the main rig.
		var parent_idx: int = skel.get_bone_parent(i)
		if parent_idx < 0:
			continue

		# Score: higher = better
		var score := 0
		var is_right := false
		var lower2 := lower
		# Right-side patterns: covers Mixamo (mixamorig_RightHand, B-hand_R),
		# Unreal (hand_r, RightHand), generic (R_hand, .R), and "_R" suffix.
		if "right" in lower2 or "_r_" in lower2 or " r " in lower2:
			is_right = true
		elif lower2.begins_with("r_") or lower2.begins_with("r.") \
			or lower2.ends_with("_r") or lower2.ends_with(".r") \
			or lower2.ends_with("_right") or lower2.ends_with("_hand_r"):
			is_right = true
		if not is_right:
			continue
		score += 100

		if "hand" in lower:
			score += 50
			if lower == "righthand" or lower == "right_hand" or lower == "b-hand_r" \
				or lower == "hand.r" or lower == "r_hand" \
				or lower == "b-hand_l" or lower == "hand_l":
				score += 30  # exact match bonus
		if "wrist" in lower:
			score += 20
		if "palm" in lower:
			# Palm is the parent of fingers but NOT the wrist. Penalize palms
			# so they don't outscore the hand bone.
			score -= 30

		# Strongest signal: count direct children that are palms or fingers.
		# The wrist bone's children are palms (>= 2); a palm's children are fingers.
		var finger_child_count := 0
		var palm_child_count := 0
		for j in range(skel.get_bone_count()):
			if skel.get_bone_parent(j) == i:
				var child_name: String = skel.get_bone_name(j).to_lower()
				for fw in finger_words:
					if fw in child_name:
						finger_child_count += 1
						break
				if "palm" in child_name:
					palm_child_count += 1
		if finger_child_count >= 2:
			# This is a PALM bone (parent of fingers) — smaller bonus than wrist.
			score += 200
		if palm_child_count >= 2:
			# This is the WRIST bone (parent of palms).
			score += 500

		if score > best_score:
			best_score = score
			best_name = bn
	if best_name == "":
		return null

	# Create (or reuse) a BoneAttachment3D
	var attach_name := "RightHandAttachment"
	var existing := skel.get_node_or_null(NodePath(attach_name))
	if existing and existing.get_class() == "BoneAttachment3D":
		return existing as Node3D

	var attach := BoneAttachment3D.new()
	attach.name = attach_name
	# Set BOTH bone_name and bone_idx — setting bone_idx explicitly is required
	# because some Godot 4 versions don't update the tracked bone if only
	# bone_name is assigned (see godot forum: boneattachment3d-not-following).
	attach.bone_name = best_name
	attach.bone_idx = skel.find_bone(best_name)
	# Default is override_pose=false (we want to COPY the bone transform, not
	# override it). Explicitly set for clarity.
	attach.override_pose = false
	# Ensure physics interpolation uses the proper mode for bone tracking.
	attach.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	skel.add_child(attach)
	print("[Viewer] created BoneAttachment3D for bone: %s idx=%d (score=%d)" % [best_name, attach.bone_idx, best_score])
	return attach


# ---------- Info display ----------

func _update_info() -> void:
	var parts: Array[String] = []
	parts.append("Char: %s" % (character_labels[char_option.selected] if char_option.selected >= 0 else "?"))
	if current_animation:
		parts.append("Anim: %s %s" % [current_animation, "(loop)" if loop_check.button_pressed else "(once)"])
	else:
		parts.append("Anim: (none)")
	var wpn_label := "(none)"
	var wpn_idx := weapon_option.selected
	if wpn_idx > 0 and wpn_idx - 1 < weapon_labels.size():
		wpn_label = weapon_labels[wpn_idx - 1]
		if is_instance_valid(current_weapon):
			wpn_label += " [EQUIPPED]"
		else:
			wpn_label += " [NOT EQUIPPED — press Equip]"
	parts.append("Weapon: %s" % wpn_label)
	parts.append("Items: chars=%d anims=%d weapons=%d" % [characters.size(), animations.size(), weapons.size()])
	info_label.text = "  |  ".join(parts)