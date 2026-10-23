extends EntityCharacter




func _state_windup() -> void:
	super._state_windup()
	if model:
		model.scale = Vector3(1.0, 1.0 + 0.15 * (1.0 - state_timer / maxf(windup_duration, 0.01)), 1.0)


func _state_recover() -> void:
	super._state_recover()
	if model:
		model.scale = Vector3.ONE


func _enter_stagger(duration: float = 1.30) -> void:
	super._enter_stagger(duration)
	if model:
		model.scale = Vector3(1.0, 0.7, 1.0)
	_flash()


func _die() -> void:
	if is_dying:
		return
	if model:
		model.scale = Vector3.ONE
		model.visible = false
	super._die()


func _respawn() -> void:
	if model:
		model.visible = true
	collision_layer = 4
	collision_mask = 1 | 2
	super._respawn()
	global_position = spawn_position if spawn_position != Vector3.ZERO else global_position
	velocity = Vector3.ZERO
	_enter_idle()


func on_parried(source: Node) -> void:
	if is_dying or state == State.DEAD:
		return
	_show_parry_label()
	_parry_punch()
	_enter_stagger()


func is_attack_active() -> bool:
	return state == State.ACTIVE


func is_attack_winding_up() -> bool:
	return state == State.WINDUP


func take_damage_legacy(amount: float, source: Node = null) -> void:
	take_damage(amount, source, &"physical")


func _on_attack_body(body: Node) -> void:
	if state != State.ACTIVE:
		return
	if body == self:
		return
	if not body.has_method("take_damage"):
		return
	var dmg: float = float(data.attack_damage) if data != null and "attack_damage" in data else 0.0
	if dmg <= 0.0:
		return
	if body.has_method("take_damage"):
		body.call("take_damage", dmg, self, &"physical")
		print("[enemy] %s hit %s dmg=%.1f" % [name, body.name, dmg])



func _flash() -> void:
	if not _base_mat:
		return
	_base_mat.albedo_color = flash_color
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and _base_mat:
		_base_mat.albedo_color = base_color


func _parry_punch() -> void:
	if not _base_mat:
		return
	_base_mat.albedo_color = Color(1.0, 0.95, 0.2)
	await get_tree().create_timer(0.3).timeout
	if is_instance_valid(self) and _base_mat and state == State.STAGGER:
		_base_mat.albedo_color = base_color


func _show_parry_label() -> void:
	if not label_parry:
		return
	label_parry.visible = true
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(self):
		label_parry.visible = false
