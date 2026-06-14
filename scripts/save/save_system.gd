extends Node
## SaveSystem — Autoload que persiste el estado del "game master" en disco.
##
## El menú ES el game master: ProgressionState, MissionManager, ObjectivesManager.
## Cada manager expone `to_dict() / from_dict()` y emite `data_changed` en cada
## mutación. SaveSystem escucha el signal, hace debounce, y escribe atómicamente
## a `user://menu_state.json`.
##
## En el boot: lee el archivo si existe, entrega cada sección al manager
## correspondiente vía `consume(section_name)`. El manager llama a esto en
## su propio `_ready()`.
##
## Auto-load (estilo Dark Souls): al abrir el juego, el estado se restaura
## automáticamente. No hay UI de save/load.
##
## Atomicidad: write a `*.tmp` → `DirAccess.rename_absolute` para evitar
## corrupción si el juego crashea mid-write. Sin backup, sin slots, sin UI.
##
## No persistimos: HP, stamina, posición, damage en curso, telemetry,
## settings, achievements. Solo el estado del game master.

const SAVE_PATH := "user://menu_state.json"
const SCHEMA_VERSION := 1
const DEBOUNCE_SEC := 0.25

# Manageres registrados. SaveSystem llama `to_dict()` en cada uno al save,
# y entrega el dict al manager correspondiente en `consume()` al load.
const _MANAGERS: Array[StringName] = [
	&"progression",
	&"missions",
	&"objectives",
]

# Datos cargados del disco, pendientes de entregar a los managers. Se
# consume (y se borra) cuando el manager llama `consume(section)`.
var _pending: Dictionary = {}

# Timer para debounce. Reinicia en cada `mark_dirty`, save al expirar.
var _debounce_timer: Timer

# True si SaveSystem ya cargó del disco (los managers pueden llamar consume).
var _ready_called: bool = false


func _ready() -> void:
	_debounce_timer = Timer.new()
	_debounce_timer.wait_time = DEBOUNCE_SEC
	_debounce_timer.one_shot = true
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)
	_load()
	_ready_called = true
	# Defer: los otros autoloads (ProgressionState, MissionManager,
	# ObjectivesManager) aún no existen cuando SaveSystem._ready corre
	# (SaveSystem es el PRIMER autoload). Conectamos después de que
	# todos estén en el tree.
	call_deferred("_connect_managers")
	print("[SaveSystem] ready (path=%s, pending_sections=%s)" % [SAVE_PATH, str(_pending.keys())])


## Conecta el signal data_changed de cada manager a mark_dirty.
## Usamos call_deferred para que los managers ya estén en el tree
## (sus _ready ya corrieron) cuando intentemos conectarlos.
func _connect_managers() -> void:
	for section in _MANAGERS:
		var manager: Node = _get_manager(section)
		if manager == null:
			continue
		if manager.has_signal("data_changed"):
			if not manager.data_changed.is_connected(mark_dirty):
				manager.data_changed.connect(mark_dirty)


# ============================================================
# Public API
# ============================================================

## Llamado por los managers en su `_ready()` para obtener su sección.
## Devuelve el dict y lo borra del pending. Si no hay datos guardados
## (o no hay sección para este manager), devuelve {}.
func consume(section: StringName) -> Dictionary:
	var d: Dictionary = _pending.get(section, {})
	_pending.erase(section)
	return d


## Llamado por los managers (o internamente) cuando su estado cambia.
## Dispara un save con debounce. Si llegan más cambios durante el debounce,
## se reinicia el timer (solo se escribe una vez al final del burst).
func mark_dirty(_section: StringName = &"") -> void:
	if _debounce_timer.is_stopped():
		_debounce_timer.start()
	else:
		# Reiniciar para agrupar ráfagas (allocate + element_allocate + ... en un frame)
		_debounce_timer.start()


## Force save ahora (sin debounce). Usado por tests.
func save_now() -> bool:
	return _save()


## Devuelve si hay datos guardados en disco.
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# ============================================================
# Internals
# ============================================================

func _on_debounce_timeout() -> void:
	_save()


func _save() -> bool:
	var data: Dictionary = {"schema_version": SCHEMA_VERSION}
	# Llamar to_dict() en cada manager registrado.
	for section in _MANAGERS:
		var manager: Node = _get_manager(section)
		if manager != null and manager.has_method("to_dict"):
			data[String(section)] = manager.to_dict()
	# Atomic write: tmp file → rename
	var tmp_path := SAVE_PATH + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[SaveSystem] cannot open %s for write" % tmp_path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir: DirAccess = DirAccess.open(SAVE_PATH.get_base_dir())
	if dir == null:
		dir = DirAccess.open("user://")
	if dir == null:
		push_error("[SaveSystem] cannot open user:// for rename")
		return false
	var err := dir.rename(tmp_path.get_file(), SAVE_PATH.get_file())
	if err != OK:
		# Fallback: copy contents then remove tmp
		var src: FileAccess = FileAccess.open(tmp_path, FileAccess.READ)
		if src != null:
			var dst: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if dst != null:
				dst.store_string(src.get_as_text())
				dst.close()
			src.close()
		DirAccess.remove_absolute(tmp_path)
		print("[SaveSystem] used copy-fallback for atomic rename")
	return true


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		print("[SaveSystem] no save file at %s" % SAVE_PATH)
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("[SaveSystem] cannot open %s for read" % SAVE_PATH)
		return
	var json_text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveSystem] save file is not a JSON object — ignoring")
		return
	var data: Dictionary = parsed
	var v: int = int(data.get("schema_version", 0))
	if v != SCHEMA_VERSION:
		push_warning("[SaveSystem] schema_version %d != %d — ignoring (delete %s to reset)" % [v, SCHEMA_VERSION, SAVE_PATH])
		return
	# Entregar cada sección al pending; los managers la reclamarán en su _ready.
	for section in _MANAGERS:
		if data.has(String(section)):
			_pending[section] = data[String(section)]
	print("[SaveSystem] loaded %d sections: %s" % [_pending.size(), str(_pending.keys())])


func _get_manager(section: StringName) -> Node:
	match section:
		&"progression": return Engine.get_main_loop().root.get_node_or_null("ProgressionState")
		&"missions": return Engine.get_main_loop().root.get_node_or_null("MissionManager")
		&"objectives": return Engine.get_main_loop().root.get_node_or_null("ObjectivesManager")
	return null
