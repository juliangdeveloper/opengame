extends RefCounted
class_name MenuNavHelper


static func bind_list(items: Array, scroll: ScrollContainer, wrap: bool = true) -> void:
	if items.is_empty():
		return
	_chain_items(items, wrap)
	if scroll and scroll is ScrollContainer:
		_connect_scroll_follow(scroll)


static func bind_row(row: HBoxContainer, all_rows: Array, row_index: int, top_neighbor: Control = null, wrap: bool = true) -> void:
	if row == null:
		return
	var btns: Array = []
	_collect_buttons(row, btns)
	if btns.is_empty():
		return
	if row_index > 0:
		var prev_btns: Array = []
		_collect_buttons(all_rows[row_index - 1], prev_btns)
		if not prev_btns.is_empty():
			for b: Button in btns:
				b.focus_neighbor_top = prev_btns[prev_btns.size() - 1].get_path()
			prev_btns[prev_btns.size() - 1].focus_neighbor_bottom = btns[0].get_path()
	elif row_index == 0 and top_neighbor:
		for b: Button in btns:
			b.focus_neighbor_top = top_neighbor.get_path()
	if row_index < all_rows.size() - 1:
		var next_btns: Array = []
		_collect_buttons(all_rows[row_index + 1], next_btns)
		if not next_btns.is_empty():
			for b: Button in btns:
				b.focus_neighbor_bottom = next_btns[0].get_path()
			next_btns[0].focus_neighbor_top = btns[btns.size() - 1].get_path()
	for i in btns.size():
		var b: Button = btns[i]
		if i > 0:
			b.focus_neighbor_left = btns[i - 1].get_path()
		elif wrap and btns.size() > 1:
			b.focus_neighbor_left = btns[btns.size() - 1].get_path()
		if i < btns.size() - 1:
			b.focus_neighbor_right = btns[i + 1].get_path()
		elif wrap and btns.size() > 1:
			b.focus_neighbor_right = btns[0].get_path()
	if wrap and all_rows.size() > 1:
		var first_btns: Array = []
		_collect_buttons(all_rows[0], first_btns)
		var last_btns: Array = []
		_collect_buttons(all_rows[all_rows.size() - 1], last_btns)
		if not first_btns.is_empty() and not last_btns.is_empty():
			if row_index == 0 and top_neighbor == null:
				for b: Button in first_btns:
					b.focus_neighbor_top = last_btns[last_btns.size() - 1].get_path()
			if row_index == all_rows.size() - 1:
				for b: Button in last_btns:
					b.focus_neighbor_bottom = first_btns[0].get_path()


static func format_points(ps: Node, allocated: int = -1, total: int = -1, menu_name: String = "") -> String:
	if ps == null:
		return "Skill Points: ?"
	var available: int = int(ps.skill_points)
	var prefix: String = ""
	if menu_name != "":
		prefix = "%s · " % menu_name
	if allocated < 0:
		return "%sSkill Points: %d" % [prefix, available]
	if total < 0:
		return "%sSkill Points: %d   (asignados: %d)" % [prefix, available, allocated]
	return "%sSkill Points: %d   (asignados: %d / %d)" % [prefix, available, allocated, total]




static func _chain_items(items: Array, wrap: bool) -> void:
	for it in items:
		if it is Control and (it as Control).focus_mode == Control.FOCUS_NONE:
			(it as Control).focus_mode = Control.FOCUS_ALL
	if items.size() < 2:
		return
	for i in items.size():
		var it: Control = items[i]
		if i > 0:
			it.focus_neighbor_top = items[i - 1].get_path()
		elif wrap:
			it.focus_neighbor_top = items[items.size() - 1].get_path()
		if i < items.size() - 1:
			it.focus_neighbor_bottom = items[i + 1].get_path()
		elif wrap:
			it.focus_neighbor_bottom = items[0].get_path()


static func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
		return
	for c in n.get_children():
		_collect_buttons(c, out)


static func _connect_scroll_follow(scroll: ScrollContainer) -> void:
	if scroll.has_meta("_menu_nav_follow"):
		return
	scroll.set_meta("_menu_nav_follow", true)
	var viewport: Viewport = scroll.get_viewport()
	if viewport == null:
		return
	var cb := func(control: Control):
		if control == null:
			return
		var p: Node = control
		while p != null:
			if p == scroll:
				break
			p = p.get_parent()
		if p == null:
			return
		var ctrl_rect: Rect2 = control.get_global_rect()
		var scroll_rect: Rect2 = scroll.get_global_rect()
		if not scroll_rect.has_point(ctrl_rect.get_center()):
			scroll.ensure_control_visible(control)
	if not viewport.gui_focus_changed.is_connected(cb):
		viewport.gui_focus_changed.connect(cb)
	scroll.set_meta("_menu_nav_follow_cb", cb)
