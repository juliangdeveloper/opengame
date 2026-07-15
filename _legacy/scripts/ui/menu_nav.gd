extends RefCounted
class_name MenuNavHelper
## Static helpers for the unified menu system.
##
## Use these to wire focus chains, scroll-follow, and points display
## the same way across every menu. Combined with MenuFocusable for
## D-pad auto-repeat, this gives every menu the same UX.
##
## Usage:
##   # 1. Wire a list of focusables (one per row)
##   MenuNavHelper.bind_list(items, scroll_container, wrap=true)
##
##   # 2. Wire a row of buttons (e.g. -1/+1/-5/+5)
##   MenuNavHelper.bind_row(row, all_rows, row_index, top_neighbor)
##
##   # 3. Show the unified points
##   points_label.text = MenuNavHelper.format_points(ps, allocated)


## Bind a list of focusables to a scroll container.
##   items: Array[Control] in display order (top→bottom or left→right)
##   scroll: ScrollContainer wrapping the items (may be null)
##   wrap: bool — wrap-around at first/last (default true)
static func bind_list(items: Array, scroll: ScrollContainer, wrap: bool = true) -> void:
	if items.is_empty():
		return
	_chain_items(items, wrap)
	if scroll and scroll is ScrollContainer:
		_connect_scroll_follow(scroll)


## Bind a row of buttons (e.g. -1/+1/-5/+5) in the context of all
## sibling rows. Wires:
##   - Intra-row left/right chain (HBox default + wrap)
##   - Inter-row top/bottom chain
##   - First row's top → top_neighbor (e.g. BindingButton)
##   - First row's first button ↑ → last row's last button (wrap)
##   - Last row's last button ↓ → first row's first button (wrap)
static func bind_row(row: HBoxContainer, all_rows: Array, row_index: int, top_neighbor: Control = null, wrap: bool = true) -> void:
	if row == null:
		return
	var btns: Array = []
	_collect_buttons(row, btns)
	if btns.is_empty():
		return
	# Inter-row chain
	if row_index > 0:
		var prev_btns: Array = []
		_collect_buttons(all_rows[row_index - 1], prev_btns)
		if not prev_btns.is_empty():
			# TODOS los botones de este row ↑ → último botón del row previo
			for b: Button in btns:
				b.focus_neighbor_top = prev_btns[prev_btns.size() - 1].get_path()
			# Último botón del row previo ↓ → primer botón de este row
			prev_btns[prev_btns.size() - 1].focus_neighbor_bottom = btns[0].get_path()
	elif row_index == 0 and top_neighbor:
		# TODOS los botones del primer row ↑ → top_neighbor (BindingButton)
		for b: Button in btns:
			b.focus_neighbor_top = top_neighbor.get_path()
	if row_index < all_rows.size() - 1:
		var next_btns: Array = []
		_collect_buttons(all_rows[row_index + 1], next_btns)
		if not next_btns.is_empty():
			# TODOS los botones de este row ↓ → primer botón del row siguiente
			for b: Button in btns:
				b.focus_neighbor_bottom = next_btns[0].get_path()
			# Primer botón del row siguiente ↑ → último botón de este row
			next_btns[0].focus_neighbor_top = btns[btns.size() - 1].get_path()
	# Intra-row left/right chain with wrap
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
	# Wrap-around inter-row
	if wrap and all_rows.size() > 1:
		var first_btns: Array = []
		_collect_buttons(all_rows[0], first_btns)
		var last_btns: Array = []
		_collect_buttons(all_rows[all_rows.size() - 1], last_btns)
		if not first_btns.is_empty() and not last_btns.is_empty():
			if row_index == 0 and top_neighbor == null:
				# First row's ALL buttons ↑ → last row's last button (wrap)
				for b: Button in first_btns:
					b.focus_neighbor_top = last_btns[last_btns.size() - 1].get_path()
			if row_index == all_rows.size() - 1:
				# Last row's ALL buttons ↓ → first row's first button (wrap)
				for b: Button in last_btns:
					b.focus_neighbor_bottom = first_btns[0].get_path()


## Format the points display the same way in every spending menu.
## Single source of truth: ProgressionState.skill_points.
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


# ===== internal helpers =====


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
	# Incluir también los Buttons deshabilitados: focus_neighbor debe
	# estar seteado en ellos para que el chain no se rompa (un D-up
	# desde un botón habilitado puede necesitar pasar por uno deshabilitado
	# para llegar al destino). Los disabled no disparan `pressed`, pero
	# sí pueden recibir focus.
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
		# Only act if the control is a descendant of this scroll
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
