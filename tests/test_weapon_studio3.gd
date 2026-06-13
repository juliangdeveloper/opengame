extends SceneTree

# Studio renderer that uses RenderingServer.frame_post_draw signal to ensure
# a real render frame happens before grabbing the image.
# Trick: instead of a custom World3D, reuse the play scene's render tree but
# replace the visible content with a single weapon.

func _initialize() -> void:
	print("=== Weapon studio (signal-based) ===")
	var weapons := [
		"short_sword", "long_sword", "great_sword", "dagger",
		"scimitar", "war_axe", "mace", "spear",
		"great_scythe", "long_bow", "arcane_staff", "cursed_blade_001",
	]
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	for i in 3:
		await process_frame

	var ps: Node = root.find_child("ProgressionState", true, false)
	for w in weapons:
		if not (w in ps.owned_weapons):
			ps.owned_weapons.append(w)

	# Hide the player + saibaman + altar so the screenshot is clean
	for n in root.find_children("*", "Node3D", true, false):
		if n.name in ["Player", "Saibaman", "AltarOfPractice", "Ground", "DirectionalLight3D", "CameraPivot", "Environment", "WorldEnvironment"]:
			n.visible = false

	# Add a preview anchor in front of the camera
	var preview := Node3D.new()
	preview.name = "PreviewAnchor"
	root.add_child(preview)
	preview.global_position = Vector3(0, 1.4, 0)
	# Add a strong directional light so the weapon is well-lit
	var dl := DirectionalLight3D.new()
	dl.rotation_degrees = Vector3(-30, -45, 0)
	dl.light_energy = 2.0
	preview.add_child(dl)

	for wid in weapons:
		var glb_id: String = wid.replace("_001", "")
		var path := "res://assets/models/weapons/wpn_%s.glb" % glb_id
		var packed: PackedScene = load(path)
		if packed == null:
			print("  [FAIL] %s: load fail" % wid)
			continue

		# Clean previous weapon
		for c in preview.get_children():
			if c is MeshInstance3D or c is Node3D and c.name != "PreviewAnchor" and c is not DirectionalLight3D:
				c.queue_free()
		await process_frame

		var model: Node3D = packed.instantiate()
		model.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
		model.rotate_y(deg_to_rad(15))
		model.position = Vector3(0, -_center_offset_for(wid), 0)
		preview.add_child(model)

		# Move camera further back for full-weapon framing
		var cam: Camera3D = root.get_viewport().get_camera_3d()
		if cam:
			# Use a per-weapon distance so bigger weapons don't overflow
			var cam_dist: float = _camera_dist_for(wid)
			cam.global_position = preview.global_position + Vector3(cam_dist * 0.6, cam_dist * 0.3, cam_dist * 0.8)
			cam.look_at(preview.global_position, Vector3.UP)
			cam.fov = 25.0

		# Wait for actual frame_post_draw (a real render signal)
		for i in 4:
			await RenderingServer.frame_post_draw

		var img: Image = root.get_viewport().get_texture().get_image()
		if img == null:
			print("  [FAIL] %s: null image" % wid)
			continue
		var out := "/tmp/weapon_%s.png" % wid
		img.save_png(out)
		# Hash check
		var data := img.get_data()
		var h: int = hash(data)
		print("  [ok] %s -> %s hash=%d" % [wid, out, h])

	quit()


func _center_offset_for(wid: String) -> float:
	var map: Dictionary = {
		"short_sword": 0.40, "long_sword": 0.50, "great_sword": 0.75,
		"dagger": 0.20, "scimitar": 0.50, "war_axe": 0.40,
		"mace": 0.40, "spear": 1.00, "great_scythe": 1.10,
		"long_bow": 0.65, "arcane_staff": 0.75, "cursed_blade_001": 0.40,
	}
	return float(map.get(wid, 0.5))


func _camera_dist_for(wid: String) -> float:
	var map: Dictionary = {
		"short_sword": 1.4, "long_sword": 1.6, "great_sword": 2.0,
		"dagger": 0.9, "scimitar": 1.6, "war_axe": 1.5,
		"mace": 1.4, "spear": 2.5, "great_scythe": 2.8,
		"long_bow": 2.0, "arcane_staff": 2.2, "cursed_blade_001": 1.4,
	}
	return float(map.get(wid, 1.5))
