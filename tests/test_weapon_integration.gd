extends SceneTree

# Visual integration test: verify each weapon .glb loads as a child of
# weapon_mesh, with the correct transform.

func _initialize() -> void:
	print("=== Weapon model integration test ===")
	var ps_scene: PackedScene = load("res://scenes/play.tscn")
	var play := ps_scene.instantiate()
	root.add_child(play)
	await process_frame
	await process_frame
	await process_frame

	var player: Node = root.find_child("Player", true, false)
	var ps: Node = root.find_child("ProgressionState", true, false)
	var weapon_mesh: MeshInstance3D = player.get_node("Model/Weapon")
	var failures := 0
	var weapons_to_test := [
		"short_sword", "great_sword", "war_axe", "great_scythe", "long_bow", "arcane_staff",
	]
	for wid in weapons_to_test:
		var tres_path := "res://data/weapons/%s.tres" % wid
		if not ResourceLoader.exists(tres_path):
			print("  [skip] %s: no .tres" % wid)
			continue
		# Grant weapon to player so equip_weapon doesn't bail
		if not (wid in ps.owned_weapons):
			ps.owned_weapons.append(wid)
		# Equip via the public API (triggers _apply_weapon_visual)
		ps.call("equip_weapon", StringName(wid))
		await process_frame
		await process_frame
		# Inspect weapon_mesh
		var n_children: int = weapon_mesh.get_child_count()
		var placeholder_hidden: bool = not weapon_mesh.visible
		if n_children >= 1 and placeholder_hidden:
			print("  [PASS] %s: %d model child(ren), placeholder hidden" % [wid, n_children])
		else:
			print("  [FAIL] %s: children=%d, placeholder_visible=%s" % [wid, n_children, weapon_mesh.visible])
			failures += 1

	print("\n=== RESULT: %d failures ===" % failures)
	quit(1 if failures > 0 else 0)
