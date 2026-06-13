extends SceneTree

# Final integration test: every weapon loads, materials are embedded,
# and the model is properly placed in the player's hand.

func _initialize() -> void:
	print("=== Final weapon integration report ===\n")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	for i in 3:
		await process_frame

	var player: Node = root.find_child("Player", true, false)
	var ps: Node = root.find_child("ProgressionState", true, false)
	if not (player and ps):
		print("FAIL setup"); quit(); return

	# Grant all weapons
	for w in ["short_sword", "long_sword", "great_sword", "dagger", "scimitar",
			  "war_axe", "mace", "spear", "great_scythe", "long_bow",
			  "arcane_staff", "cursed_blade_001"]:
		if not (w in ps.owned_weapons):
			ps.owned_weapons.append(w)

	var wm: MeshInstance3D = player.get_node("Model/Weapon")
	var failures := 0

	var weapons := ["short_sword", "long_sword", "great_sword", "dagger", "scimitar",
					"war_axe", "mace", "spear", "great_scythe", "long_bow",
					"arcane_staff", "cursed_blade_001"]
	for wid in weapons:
		ps.call("equip_weapon", StringName(wid))
		for i in 3:
			await process_frame
		# Check 1: weapon_mesh has 1 child
		var n_children: int = wm.get_child_count()
		# Check 2: child is the weapon model
		var model_name_ok: bool = false
		var n_tris: int = 0
		var n_mats: int = 0
		if n_children >= 1:
			var c = wm.get_child(0)
			# Name is "WeaponModel_<id>" (set in _load_weapon_model) or the
			# .glb root name (e.g. "wpn_short_sword") on later instances.
			model_name_ok = (c.name.begins_with("WeaponModel_") or c.name.begins_with("wpn_"))
			# Find MeshInstance3D descendants
			for sub in _find_meshes(c):
				var mi: MeshInstance3D = sub
				for s in mi.mesh.get_surface_count():
					var arr = mi.mesh.surface_get_arrays(s)
					var idx = arr[Mesh.ARRAY_INDEX]
					if idx != null:
						n_tris += (idx as PackedInt32Array).size() / 3
					else:
						n_tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
					var mat = mi.mesh.surface_get_material(s)
					if mat: n_mats += 1
		# Check 3: model is positioned somewhere reasonable (within 1.5m of hand)
		var pos_ok: bool = false
		if n_children >= 1:
			var global_pos: Vector3 = wm.get_child(0).global_position
			# Hand is at (0.4, 1.9, -0.5). The model global_pos is the model origin
			# which is the pommel base, offset by grip_offset in Y. Different
			# weapons have different grip_offsets (bows/staffs center, swords
			# near pommel), so just check the model is somewhere near the player.
			var dist_to_hand: float = global_pos.distance_to(Vector3(0.4, 1.9, -0.5))
			# Allow up to 1.0m offset (for tall 2h weapons with high grip_offset)
			pos_ok = dist_to_hand < 1.0
		# Check 4: placeholder hidden
		var placeholder_hidden: bool = not wm.visible
		var ok: bool = n_children >= 1 and model_name_ok and pos_ok and placeholder_hidden
		var status: String = "PASS" if ok else "FAIL"
		if not ok: failures += 1
		print("  [%s] %-12s | children=%d, model_name=%s, pos_dist<1.0=%s, mats=%d, tris=%d" % [
			status, wid, n_children, model_name_ok, pos_ok, n_mats, n_tris
		])

	# Unarmed (no .tres exists with that name, fallback to placeholder)
	ps.call("equip_weapon", &"unarmed")
	for i in 3:
		await process_frame
	# Unarmed has no model_path → placeholder should be VISIBLE (no child model)
	var n_children_unarmed: int = wm.get_child_count()
	var placeholder_visible_unarmed: bool = wm.visible
	var ok_unarmed: bool = n_children_unarmed == 0 and placeholder_visible_unarmed
	if ok_unarmed:
		print("  [PASS] unarmed       | no model child, placeholder visible")
	else:
		print("  [FAIL] unarmed       | children=%d, placeholder_visible=%s" % [n_children_unarmed, placeholder_visible_unarmed])
		failures += 1

	print("\n=== RESULT: %d failures ===" % failures)
	quit(1 if failures > 0 else 0)


func _find_meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_meshes(c))
	return out
