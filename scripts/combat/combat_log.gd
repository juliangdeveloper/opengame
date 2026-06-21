## combat_log.gd — Logger centralizado de combate.
##
## Singleton (autoload) que registra TODAS las acciones de combate en
## JSONL — una línea JSON por evento. Permite analizar balanceo de bosses,
## frecuencia de skills, daño por elemento, winrates, etc.
##
## Eventos soportados:
##   skill_cast    -> cuando caster empieza a castear una skill
##   skill_hit     -> cuando un átomo hit aplica daño a un target
##   skill_miss    -> cuando un átomo resuelve 0 targets
##   dodge         -> caster esquivó un ataque entrante
##   parry         -> caster parried un ataque entrante
##   block         -> caster bloqueó (recibió daño reducido)
##   status_apply  -> se aplicó un status effect
##   status_tick   -> DoT/HoT tick (status_effects)
##   damage_taken  -> un actor recibió daño (raw, sin modifiers)
##   heal          -> un actor fue curado
##   death         -> un actor murió
##   ai_decision   -> el boss AI tomó una decisión (DEFEND/DODGE/CAST...)
##
## Output:
##   Por defecto escribe a user://combat_log_<run_id>.jsonl
##   También se puede redirigir a /tmp/... o donde sea necesario.
##
## Uso:
##   CombatLog.log_event("skill_cast", {"caster":"frieza", "skill_id":"kamehameha_001"})
##   CombatLog.set_run_id("boss_duel_2025_06_13_001")
##   CombatLog.flush() / close()
extends Node
## Esta clase se monta como autoload. Acceso global: CombatLog.log_event(...)

const EVENT_TYPES := [
	"skill_cast", "skill_hit", "skill_miss",
	"dodge", "parry", "block",
	"status_apply", "status_tick",
	"damage_taken", "heal", "death",
	"ai_decision", "sim_start", "sim_end",
]

## Estado
var _run_id: String = ""
var _output_path: String = ""
var _file: FileAccess = null
var _event_count: int = 0
var _t0_ms: int = 0
var _enabled: bool = true
var _buffer: Array[String] = []
const BUFFER_FLUSH_EVERY := 32  # Flush cada N eventos para no martillar el disco


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	# Por defecto corre silencioso. Llamar set_run_id(...) para activar.
	print("[CombatLog] ready (idle; call set_run_id to start)")


## Activa logging para un run específico. Crea el archivo y guarda header.
func set_run_id(run_id: String, output_path: String = "") -> void:
	close()  # cerrar el anterior si estaba abierto
	_run_id = run_id
	if output_path.is_empty():
		output_path = "user://combat_log_%s.jsonl" % run_id
	_output_path = output_path
	_file = FileAccess.open(_output_path, FileAccess.WRITE)
	if _file == null:
		push_warning("[CombatLog] cannot open %s, logging to stdout only" % _output_path)
		_enabled = false
		return
	_enabled = true
	_t0_ms = Time.get_ticks_msec()
	_event_count = 0
	# Header comment
	_file.store_line("# combat_log run_id=%s" % _run_id)
	_file.flush()
	print("[CombatLog] logging to %s" % _output_path)


## Devuelve el path actual del archivo (vacío si no está activo).
func get_output_path() -> String:
	return _output_path


## Registra un evento. El dict data se serializa tal cual a JSON.
func log_event(event_type: String, data: Dictionary) -> void:
	if not _enabled:
		return
	if not event_type in EVENT_TYPES:
		push_warning("[CombatLog] unknown event_type=%s" % event_type)
	var ts: float = (Time.get_ticks_msec() - _t0_ms) / 1000.0
	var entry := {
		"t": ts,
		"run_id": _run_id,
		"event": event_type,
		"data": data,
	}
	var line := JSON.stringify(entry)
	if _file != null:
		_buffer.append(line)
		_event_count += 1
		if _buffer.size() >= BUFFER_FLUSH_EVERY:
			flush()
	else:
		print("[CombatLog] %s" % line)


## Convenience: emite sim_start con metadata del combate.
func sim_start(meta: Dictionary) -> void:
	log_event("sim_start", meta)


## Convenience: emite sim_end con resultados finales.
func sim_end(meta: Dictionary) -> void:
	flush()
	log_event("sim_end", meta)


## Vuelca el buffer al disco. Llamar al final de cada sim/fase.
func flush() -> void:
	if _file == null or _buffer.is_empty():
		return
	for line in _buffer:
		_file.store_line(line)
	_file.flush()
	_buffer.clear()


## Cierra el archivo. Llamar al shutdown.
func close() -> void:
	if _file != null:
		flush()
		_file.close()
		_file = null


## Desactiva logging (silencia).
func disable() -> void:
	_enabled = false


## Reactiva logging.
func enable() -> void:
	_enabled = true


## Stats — cuántas líneas llevamos en este run.
func get_event_count() -> int:
	return _event_count


func _exit_tree() -> void:
	close()
