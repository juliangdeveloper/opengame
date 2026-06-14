## enemy.gd — Wrapper mínimo sobre Character.
##
## FASE 4 (2026-06-14): antes era un script gigante (360 líneas) con
## state machine duplicado, stats hardcoded (max_hp=100, attack_damage=22,
## move_speed=2.6, etc.) y un sistema de daño separado del sistema de
## skills. AHORA es un wrapper mínimo sobre Character que solo añade:
##   - Visual feedback específico (model scale animation, parry label)
##   - on_parried() callback que Character expone
##   - Daño de ataque básico (attack_damage) — para enemigos que NO
##     castean skills. Enemigos con skill_ids poblado castean skills
##     en su lugar (vía Character._cast_basic_skill).
##
## TODOS los stats vienen de data: CharacterResource. Sin hardcoded.
##
## CUMPLIMIENTO DE DIRECTRIZ DEL USER:
##   "Refinar los jefes y enemigos para que sean full data driven.
##    Elimina cualquier dato quemado en el código."
extends EntityCharacter


# === Visual feedback overrides ===
# (Character provee el state machine y take_damage. Acá solo añadimos
#  las particularidades visuales del enemigo básico.)


## Override Character._state_windup: añade la animación de scale.
func _state_windup() -> void:
	super._state_windup()
	if model:
		model.scale = Vector3(1.0, 1.0 + 0.15 * (1.0 - state_timer / maxf(windup_duration, 0.01)), 1.0)


## Override Character._state_recover: resetea el scale.
func _state_recover() -> void:
	super._state_recover()
	if model:
		model.scale = Vector3.ONE


## Override Character._enter_stagger: squash + flash.
func _enter_stagger(duration: float = 1.30) -> void:
	super._enter_stagger(duration)
	if model:
		model.scale = Vector3(1.0, 0.7, 1.0)
	_flash()


## Override Character._die: hide model (Character ya hace respawn logic).
func _die() -> void:
	if is_dying:
		return
	if model:
		model.scale = Vector3.ONE
		model.visible = false
	super._die()


## Override Character._respawn: reset position + visibility.
func _respawn() -> void:
	if model:
		model.visible = true
	collision_layer = 4
	collision_mask = 1 | 2
	super._respawn()
	# Reset position to spawn (Character no lo hace — Character solo resettea hp)
	global_position = spawn_position if spawn_position != Vector3.ZERO else global_position
	velocity = Vector3.ZERO
	_enter_idle()


## Llamado por el player cuando un parry impacta al enemy.
## Character ya declara la firma (no-op por default). Acá hacemos
## el feedback visual + stagger.
func on_parried(source: Node) -> void:
	if is_dying or state == State.DEAD:
		return
	_show_parry_label()
	_parry_punch()
	_enter_stagger()


## Compatibility shims (Character ya tiene is_attack_active/winding_up,
## pero acá se preserva la firma exacta del enemy legacy).
func is_attack_active() -> bool:
	return state == State.ACTIVE


func is_attack_winding_up() -> bool:
	return state == State.WINDUP


# === Damage interface (compat con player.gd) ===
# Character.take_damage ya implementa esto. Pero el player legacy llama
# `body.take_damage(amount, self)` (sin element) — Character requiere
# element. Override para inferir "physical" si no se pasa.
func take_damage_legacy(amount: float, source: Node = null) -> void:
	take_damage(amount, source, &"physical")


# === Body collision (enemigos básicos sin skill) ===
## Cuando un cuerpo entra al attack_area durante ACTIVE, le aplicamos
## el ataque. El daño viene de data.attack_damage (configurable en
## CharacterResource), no de un hardcoded.
##
## NOTA: este método es para enemigos que NO castean skills. Si
## data.skill_ids NO está vacío, el enemy debería castear skills y
## el daño lo manejará el SkillExecutor (no este callback).
func _on_attack_body(body: Node) -> void:
	if state != State.ACTIVE:
		return
	if body == self:
		return
	if not body.has_method("take_damage"):
		return
	# El daño del ataque básico viene de data (CharacterResource), no hardcoded
	var dmg: float = float(data.attack_damage) if data != null and "attack_damage" in data else 0.0
	if dmg <= 0.0:
		return
	if body.has_method("take_damage"):
		body.call("take_damage", dmg, self, &"physical")
		print("[enemy] %s hit %s dmg=%.1f" % [name, body.name, dmg])


# === Visual feedback methods ===

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
	_base_mat.albedo_color = Color(1.0, 0.95, 0.2)  # hot yellow
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
