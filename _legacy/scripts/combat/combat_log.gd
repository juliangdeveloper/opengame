extends Node

const EVENT_TYPES := [
	"skill_cast", "skill_hit", "skill_miss",
	"dodge", "parry", "block",
	"status_apply", "status_tick",
	"damage_taken", "heal", "death",
	"ai_decision", "sim_start", "sim_end",
]

var _run_id: String = ""
var _output_path: String = ""
var _file: FileAccess = null
var _event_count: int = 0
var _t0_ms: int = 0
var _enabled: bool = true
var _buffer: Array[String] = []
const BUFFER_FLUSH_EVERY := 32


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	print("[CombatLog] ready (idle; call set_run_id to start)")


func set_run_id(run_id: String, output_path: String = "") -> void:
	close()
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
	_file.store_line("# combat_log run_id=%s" % _run_id)
	_file.flush()
	print("[CombatLog] logging to %s" % _output_path)


func get_output_path() -> String:
	return _output_path


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


func sim_start(meta: Dictionary) -> void:
	log_event("sim_start", meta)


func sim_end(meta: Dictionary) -> void:
	flush()
	log_event("sim_end", meta)


func flush() -> void:
	if _file == null or _buffer.is_empty():
		return
	for line in _buffer:
		_file.store_line(line)
	_file.flush()
	_buffer.clear()


func close() -> void:
	if _file != null:
		flush()
		_file.close()
		_file = null


func disable() -> void:
	_enabled = false


func enable() -> void:
	_enabled = true


func get_event_count() -> int:
	return _event_count


func _exit_tree() -> void:
	close()
