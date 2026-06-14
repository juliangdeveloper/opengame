## ai_controller.gd — AIController que pilota un Character.
##
## FASE 4 (2026-06-14): este Controller es el "cerebro" de cualquier
## Character con `data.ai_controlled = true` (enemigos, villanos, NPCs).
##
## Lee `data.skill_weights` para pickear skills, `data.behavior` para
## el estilo de combate, y `data.aggression` para la frecuencia de
## acciones. NO tiene stats propios — solo DECIDE; el Character
## ejecuta.
##
## El controller es genérico para todos los AI. Los villanos con
## reward_skill_points > 0 son solo un Character con data.ai_controlled=true
## y ese campo poblado. No hay código especial de villano aquí.
extends Node
class_name AIController

var character: Node = null  # Character (set externally or by Character._install_default_controller)

# === Anti-streak: tracks últimas skills para evitar spam ===
const ANTI_STREAK_DEPTH: int = 3

# === Cooldowns defensivos (delegated to character) ===
# (character ya tiene parry_cooldown, dodge_cooldown, defend_cooldown)


func _physics_process(_delta: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	# 1) Si character está en DEAD, este controller no hace nada
	if character.state == character.State.DEAD:
		return
	# 2) Si el character está en IDLE/CHASE, evaluar si castear
	#    La decisión final (qué skill) la hace _decide_next_skill
	#    cuando el character esté listo (CHASE→CHOOSE_SKILL).
	if character.state == character.State.IDLE:
		_evaluate_transitions()
	# 3) En CHASE, verificar si el target está en rango de skill
	# (Character._state_chase ya lo hace con attack_range, pero podríamos
	#  agregar behaviors especiales aquí si hace falta.)


## Decide si el character debe pasar de IDLE→CHASE o si debe castear.
## La lógica de "qué skill" la delega al Character (que usa
## data.skill_weights con anti-streak).
func _evaluate_transitions() -> void:
	if character.target == null or not is_instance_valid(character.target):
		return
	var d: float = character._dist_to_target()
	if d < character.detection_range:
		character._enter_chase()


## Override este método para lógica AI especializada por behavior.
## Default: delegar al Character (que ya hace weighted random con
## anti-streak en _pick_weighted_skill()).
func decide_skill() -> StringName:
	return character._pick_weighted_skill()
