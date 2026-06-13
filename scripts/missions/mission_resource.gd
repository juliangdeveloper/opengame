## MissionResource — data layer para misiones.
##
## Una misión tiene:
##   - Spec mínima del LLM (purpose, target_id, mission_type)
##   - State machine (AVAILABLE → READY → ACTIVE → COMPLETED/FAILED/ABANDONED)
##   - Config computada por el juego al setear dificultad
##     (enemigos, HP, rewards, damage_modifiers, time_limit)
##   - Tracking del progreso (kills, casts, elapsed)
##
## El LLM solo crea la spec; el juego calcula el resto.
class_name MissionResource
extends Resource

## === Spec del LLM ===
@export var id: StringName = &""
@export var title: String = ""
@export var purpose: StringName = &""  # "teach_skill" | "teach_weapon"
@export var target_id: StringName = &""  # skill_id o weapon_id
@export var target_kind: StringName = &""  # "skill" | "weapon" (derivado del purpose)
@export var mission_type: StringName = &"defeat_enemies"

## === Dificultad + config computada ===
@export var difficulty: int = 0  # 0 = no asignada, 1..5 = asignada
@export var enemy_type: StringName = &"saibaman"
@export var enemy_count: int = 0
@export var enemy_hp_mult: float = 1.0
@export var time_limit_sec: float = 0.0
@export var damage_modifiers: Dictionary = {}  # {element_id: mult} — multiplicador de daño RECIBIDO por el enemigo
@export var rewards: Dictionary = {}  # {skill_points, proficiency}

## === State machine ===
@export var state: StringName = &"AVAILABLE"  # AVAILABLE | READY | ACTIVE | COMPLETED | FAILED | ABANDONED

## === Tracking (ACTIVO) ===
@export var kills: int = 0
@export var casts: int = 0
@export var elapsed_sec: float = 0.0
@export var reached_destination: bool = false
@export var survived: bool = false

## === Timestamps (msec) ===
@export var created_at: int = 0
@export var started_at: int = 0
@export var completed_at: int = 0

## === Estado terminal? ===
func is_terminal() -> bool:
	return state == &"COMPLETED" or state == &"FAILED" or state == &"ABANDONED"

## === Puede iniciar? ===
func can_start() -> bool:
	return state == &"READY"

## === Está activa? ===
func is_active() -> bool:
	return state == &"ACTIVE"

## === Necesita dificultad? ===
func needs_difficulty() -> bool:
	return state == &"AVAILABLE" and difficulty == 0

## === Descripción del estado para UI ===
func get_state_label() -> String:
	match state:
		&"AVAILABLE": return "Sin dificultad — elige 1-5"
		&"READY": return "Lista — click START"
		&"ACTIVE": return "En progreso"
		&"COMPLETED": return "✓ Completada"
		&"FAILED": return "✗ Fallida"
		&"ABANDONED": return "↶ Abandonada"
		_: return "?"

## === Descripción de la misión para UI ===
func get_purpose_label() -> String:
	if purpose == &"teach_skill":
		return "Enseñar skill: " + String(target_id)
	elif purpose == &"teach_weapon":
		return "Enseñar arma: " + String(target_id)
	return String(purpose)

## === Objetivo textual para HUD ===
func get_objective_text() -> String:
	var count_str := ""
	match mission_type:
		&"defeat_enemies", &"timed", &"reach_destination":
			count_str = "%d %s" % [enemy_count, enemy_type]
		&"1v1":
			count_str = "1 %s (1v1)" % enemy_type
		&"survive":
			count_str = "Sobrevive %ds" % int(time_limit_sec)
		&"cast_skill_n":
			count_str = "Usa %s %d veces" % [target_id, enemy_count]  # usamos enemy_count como "veces"
	var base := ""
	match mission_type:
		&"defeat_enemies": base = "Derrota %s" % count_str
		&"1v1": base = "Derrota en duelo a %s" % count_str
		&"timed": base = "Derrota %s en %ds" % [count_str, int(time_limit_sec)]
		&"reach_destination": base = "Llega al destino y derrota %s" % count_str
		&"survive": base = "Sobrevive %ds" % int(time_limit_sec)
		&"cast_skill_n": base = "Castea la skill %d veces" % enemy_count
	if time_limit_sec > 0 and mission_type != &"timed" and mission_type != &"survive":
		base += " (límite %ds)" % int(time_limit_sec)
	return base
