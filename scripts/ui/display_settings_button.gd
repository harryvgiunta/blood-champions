class_name DisplaySettingsButton
extends Button
## The display row: one fullscreen toggle, shared by the Escape window and the
## campaign's quick menu.
##
## It owns no mode of its own - it asks the `Settings` autoload and every press
## is a call on it - so the label, the window and the file cannot disagree.
## Built from a plain `Button` with text, so it constructs and can be pressed in
## a headless regression that has no window to move.

signal changed


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 46)
	add_theme_font_size_override("font_size", 13)
	pressed.connect(_on_pressed)
	refresh()


func _ready() -> void:
	refresh()


## Repaint from the autoload. Safe before the node is in the tree: the row then
## says what the defaults would be and repaints for real on `_ready`.
func refresh() -> void:
	text = "DISPLAY:  FULLSCREEN" if is_fullscreen() else "DISPLAY:  WINDOWED"


## Whether the window is fullscreen, as the manager answers it. A headless run
## is answered from the stored preference.
func is_fullscreen() -> bool:
	var settings := _settings()
	return settings != null and bool(settings.window_fullscreen())


func _on_pressed() -> void:
	var settings := _settings()
	if settings == null:
		return
	settings.toggle_fullscreen()
	refresh()
	changed.emit()


func _settings() -> Node:
	# A node built before it is parented has no `/root` to ask.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings")
