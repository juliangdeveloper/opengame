## floating_hp.gd — HUD bar showing hit object's HP for 5 seconds.
## Only one instance at a time — new hits replace the previous bar instantly.
extends CanvasLayer

static var _current: CanvasLayer = null

var _bar: ProgressBar = null
var _label: Label = null
var _timer: float = 0.0
var _duration: float = 5.0


func _ready() -> void:
	# Destroy previous instance if still alive
	if _current != null and is_instance_valid(_current):
		_current.queue_free()
	_current = self
	layer = 10
	# Label — add first, then configure
	_label = Label.new()
	add_child(_label)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_label.position = Vector2(374, 20)
	_label.size = Vector2(532, 20)
	# HP bar
	_bar = ProgressBar.new()
	add_child(_bar)
	_bar.position = Vector2(374, 44)
	_bar.size = Vector2(532, 16)
	_bar.show_percentage = false


func setup(obj_name: String, current_hp: float, max_hp_val: float) -> void:
	if _bar == null or _label == null:
		return
	_bar.max_value = maxf(max_hp_val, 1.0)
	_bar.value = current_hp
	_label.text = "%s  %.0f / %.0f" % [obj_name, current_hp, max_hp_val]
	var pct: float = current_hp / maxf(max_hp_val, 1.0)
	if pct > 0.6:
		_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	elif pct > 0.3:
		_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _duration:
		queue_free()
