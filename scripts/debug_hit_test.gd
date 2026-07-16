extends SceneTree

func _init():
	print("[TEST] === Hit + CanvasLayer test ===")
	var world_scene = load("res://scenes/test_world.tscn")
	var world = world_scene.instantiate()
	root.add_child(world)
	await create_timer(1.0).timeout
	
	var player = world.get_node("Player")
	var crate = world.get_node("Crate1")
	print("[TEST] Player: %s Crate: %s" % [player.global_position, crate.global_position])
	
	# Simulate _execute_hit manually
	var hitbox_scene = load("res://assets/hitbox_cube.tscn")
	var hitbox = hitbox_scene.instantiate()
	
	# Add to tree first
	world.add_child(hitbox)
	
	# Position near crate
	hitbox.global_position = crate.global_position
	hitbox.scale = Vector3(0.5, 0.5, 0.5)
	hitbox.push_force = 1.0
	hitbox.push_effect = 2.0
	hitbox.caster_vitality = 1.0
	hitbox.base_damage = 2.0
	hitbox.push_direction = Vector3(1, 0, 0)
	hitbox.lifetime = 5.0
	
	print("[TEST] Hitbox spawned at: %s" % hitbox.global_position)
	
	# Wait for overlap detection
	await create_timer(1.0).timeout
	
	print("[TEST] Crate hp: %s/%s" % [crate.hp, crate.max_hp])
	print("[TEST] === Done ===")
	quit(0)
