## Skill Panel — UI de una skill individual dentro del allocator.
##
## Layout:
##   Skill name + description
##   Power ratio bar
##   Por cada stat en designed_max:
##     Label "stat_name: current / designed"
##     Barra horizontal (ProgressBar)
##     Botones -/+  (1 punto por click)
##     Botón -5 / +5  (bulk)
extends PanelContainer

const ProgressionStateScript := preload("res://scripts/skill/progression_state.gd")
const BalanceScript := preload("res://scripts/skill/balance.gd")

var _skill: Resource = null  # SkillResource
var _skill_id: StringName
var _title_label: Label
var _desc_label: Label
var _power_bar: ProgressBar
var _stats_container: VBoxContainer

const MAX_PTS_PER_STAT := 5


func _ready() -> void:
	_build()


func _build() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 18)
	v.add_child(_title_label)

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_desc_label)

	_power_bar = ProgressBar.new()
	_power_bar.min_value = 0.0
	_power_bar.max_value = 1.0
	_power_bar.show_percentage = false
	v.add_child(_power_bar)

	_stats_container = VBoxContainer.new()
	_stats_container.add_theme_constant_override("separation", 2)
	v.add_child(_stats_container)


## Configura el panel para una skill.
func setup(skill) -> void:
	_skill = skill
	_skill_id = StringName(skill.id)
	_title_label.text = "%s" % skill.name
	_desc_label.text = skill.description if skill.description else ""
	_refresh()


func _refresh() -> void:
	var ps: Node = Engine.get_main_loop().root.get_node_or_null("ProgressionState")
	if _skill == null or ps == null:
		return
	# Power bar
	var ratio: float = ps.get_skill_power_ratio(_skill_id)
	_power_bar.value = ratio
	# Stats
	for child in _stats_container.get_children():
		child.queue_free()
	for stat_name_v in _skill.designed_max.keys():
		var stat_name: StringName = StringName(stat_name_v)
		var designed: float = float(_skill.designed_max[stat_name_v])
		if designed <= 0.0:
			continue
		var current: float = ps.get_effective_stat_for_skill(_skill_id, stat_name, designed)
		var alloc: int = int(ps.allocations.get(String(_skill_id), {}).get(stat_name, 0))
		_stats_container.add_child(_build_stat_row(ps, stat_name, designed, current, alloc))


func _build_stat_row(ps: Node, stat_name: StringName, designed: float, current: float, alloc: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Label "stat: current/designed (alloc=N)"
	var label := Label.new()
	label.custom_minimum_size = Vector2(220, 0)
	label.text = "%s: %.1f / %.1f  [pts=%d]" % [stat_name, current, designed, alloc]
	row.add_child(label)

	# Progress bar
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = designed
	bar.value = current
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)

	# Botones -1 / +1 / -5 / +5
	row.add_child(_make_alloc_button(ps, "-1", stat_name, -1, alloc > 0))
	row.add_child(_make_alloc_button(ps, "+1", stat_name, 1, ps.skill_points > 0 and alloc < MAX_PTS_PER_STAT))
	row.add_child(_make_alloc_button(ps, "-5", stat_name, -5, alloc > 0))
	row.add_child(_make_alloc_button(ps, "+5", stat_name, 5, ps.skill_points > 0 and alloc < MAX_PTS_PER_STAT))
	return row


func _make_alloc_button(ps: Node, label: String, stat_name: StringName, delta: int, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.disabled = not enabled
	btn.pressed.connect(_on_alloc_pressed.bind(ps, stat_name, delta))
	return btn


func _on_alloc_pressed(ps: Node, stat_name: StringName, delta: int) -> void:
	if delta > 0:
		ps.allocate(_skill_id, stat_name, delta)
	else:
		ps.deallocate(_skill_id, stat_name, -delta)
	# Notifica al allocator para refrescar el header
	var parent := get_parent()
	while parent and not parent.has_method("_refresh"):
		parent = parent.get_parent()
	if parent:
		parent._refresh()
	else:
		_refresh()
