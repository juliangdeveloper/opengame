class_name BookTabBase
extends Control
## BookTabBase — Helpers compartidos para todos los tabs del Skill Book
## (Skills, Elementos, Atributos, Armas).
##
## Provee:
##   - Tab nav con R1/L1 (no D-pad left/right)
##   - Scroll vertical sintetizado: D-pad up/down + left-stick up/down +
##     D-pad up button + L3 mueven el ScrollContainer aunque el foco esté
##     en una row/button
##   - Apertura/cierre uniforme: pausa, mouse mode, signal "tab_opened/closed"
##
## Cada tab concreto (skill_book, element_allocator, etc.) hereda de este
## nodo y simplemente implementa open()/close() y referencia su contenido.
##
## Identificación: el nodo raíz debe tener `tab_id` (StringName) que
## coincida con un valor de TABS en skill_book.gd.

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")

## Identificador de este tab (debe matchear TABS en skill_book.gd).
@export var tab_id: StringName = &""

## Si es true, este tab es el "master" (skill_book) y maneja la apertura
## de otros tabs. Los demás tabs son "slaves" y delegan a él.
@export var is_master_tab: bool = false

## ScrollContainer principal de este tab (se asigna en el .tscn o
## dinámicamente en _ready).
@export var scroll: ScrollContainer = null

## Step en pixels para cada "tick" de scroll.
@export var scroll_step: int = 48

## Was-paused state al abrir este tab.
var _was_paused: bool = false
## True si ya capturamos _was_paused en una apertura previa. Evita que
## `open()` lo sobreescriba cuando un slave tab reabre el master (en ese
## caso el mundo YA está paused por el master original, y queremos
## restaurar al estado del mundo ANTES de que el master se abriera).
var _was_paused_initialized: bool = false
var _initialized: bool = false
var _scroll_accum: float = 0.0
var _scroll_threshold: float = 0.4  # segundos entre scrolls


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _initialized:
		# Conectamos a `ready` (NO a `process_frame`) para evitar la race
		# con `open()`: el base debe estar inicializado ANTES de que el
		# master (skill_book) llame `open()` inmediatamente después de
		# `add_child`. `ready` se emite dentro de `add_child`, antes de
		# que retorne, así que cuando el master hace `add_child(ea); ea.open()`
		# el `_do_initialize` ya corrió y `_element_rows` está poblado.
		ready.connect(_initialize, CONNECT_ONE_SHOT)


## Punto de entrada de inicialización para subclases. El base hace cosas
## genéricas (auto-find scroll) y luego llama a _do_initialize() para que
## el subclase haga su trabajo (conectar signals, asignar nodos hijos, etc).
## Este patrón evita el bug donde el base marca _initialized=true y el
## subclase retorna early antes de conectar signals.
func _initialize() -> void:
	if _initialized:
		return
	_initialized = true
	# Auto-find scroll si no se asignó manualmente
	if scroll == null:
		scroll = _find_first_scroll(self)
	_do_initialize()


## Override este método en lugar de `_initialize` para inicializar tu tab.
## El base ya marcó _initialized=true y auto-encontró el scroll.
func _do_initialize() -> void:
	pass


## Abre este tab.
func open() -> void:
	visible = true
	# Solo capturamos _was_paused en la PRIMERA apertura de un ciclo
	# de apertura/cierre. Esto preserva el estado original del mundo
	# cuando un slave tab reabre el master (en ese caso, el mundo ya
	# está paused por el master original, y queremos restaurar al
	# estado del mundo ANTES de que el master se abriera).
	if not _was_paused_initialized:
		_was_paused = get_tree().paused
		_was_paused_initialized = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_scroll_accum = 0.0


## Cierra este tab.
func close() -> void:
	_close()


## Cierra este tab (sin notificar a otros). Usado al cambiar de tab.
func _close() -> void:
	visible = false
	get_tree().paused = _was_paused
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Reset para que la próxima apertura capture el estado actual del mundo.
	_was_paused_initialized = false


## Cicla al tab anterior/posterior delegando al master skill_book.
func _navigate_to_master_tab(delta: int) -> void:
	if is_master_tab:
		# Master: ciclar directamente
		if delta > 0:
			call("_on_next_tab")
		else:
			call("_on_prev_tab")
		return
	# Slave: cerrar y pedir al master que navegue
	var book: Control = get_tree().root.find_child("SkillBook", true, false)
	_close()
	if book == null:
		return
	if delta > 0:
		if book.has_method("_on_next_tab"):
			book._on_next_tab()
	else:
		if book.has_method("_on_prev_tab"):
			book._on_prev_tab()
## REGLAS de navegación en sub-tabs (slaves):
##   - R1 (10) / L1 (9): cambiar tab (delegando al master)
##   - D-pad (up/down/left/right): navega focus NATIVO de Godot
##   - NO interceptamos D-pad: si lo hacemos, `set_input_as_handled()`
##     bloquea la focus navigation nativa.
##
## El scroll es manejado automáticamente por Godot 4 cuando el foco
## se mueve (ScrollContainer hace auto-scroll del control con foco).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Solo slaves manejamos tab nav aquí. El master (skill_book) tiene
	# su propio _input que maneja R1/L1.
	if not is_master_tab and event is InputEventJoypadButton and event.pressed:
		var btn: int = event.button_index
		if btn == 9:  # L1
			_navigate_to_master_tab(-1)
			get_viewport().set_input_as_handled()
			return
		elif btn == 10:  # R1
			_navigate_to_master_tab(+1)
			get_viewport().set_input_as_handled()
			return
	# D-pad NO se intercepta — Godot hace focus navigation nativa.


## Buscar el primer ScrollContainer en el árbol del nodo (preferentemente
## uno llamado "Scroll").
func _find_first_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n.name == "Scroll" or n.name == "DetailScroll"):
		return n
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_first_scroll(c)
		if r != null:
			return r
	return null
