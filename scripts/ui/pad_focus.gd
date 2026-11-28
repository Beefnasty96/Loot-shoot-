class_name PadFocus
extends RefCounted
## Controller support for menus: D-pad / left stick move the highlight
## (wrapping top <-> bottom), A presses, B goes back (InputSetup binds A/B to
## ui_accept / ui_cancel). If nothing is highlighted — a tap on the screen
## clears it — the first pad or arrow press highlights the first button again.


## Make a vertical list of controls wrap: down from the last goes to the first, up from the first to the last.
static func wrap(controls: Array) -> void:
	var list: Array = controls.filter(func(c): return c is Control and c.focus_mode != Control.FOCUS_NONE)
	if list.size() < 2:
		return
	var first: Control = list[0]
	var last: Control = list[list.size() - 1]
	last.focus_neighbor_bottom = last.get_path_to(first)
	first.focus_neighbor_top = first.get_path_to(last)


## Call from _input / _unhandled_input: if nothing has focus and this is a menu
## press, focus `first` and eat the event. Returns true if it did.
static func recover(event: InputEvent, viewport: Viewport, first: Control) -> bool:
	if first == null or not first.is_visible_in_tree() or viewport.gui_get_focus_owner() != null:
		return false
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept"]:
		if event.is_action_pressed(a):
			first.grab_focus()
			viewport.set_input_as_handled()
			return true
	return false


## Every focusable control under `node`, in tree order.
static func focusables(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Control and (c is BaseButton or c is Range) and c.focus_mode != Control.FOCUS_NONE:
			out.append(c)
		out.append_array(focusables(c))
	return out
