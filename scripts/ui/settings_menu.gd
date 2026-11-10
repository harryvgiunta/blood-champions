class_name SettingsMenu
extends CanvasLayer
## The settings window Escape brings up: a short index, a SOUND page, a DISPLAY
## page and the controls sheet.
##
## It owns no audio or display state of its own - the sound page talks to the
## `Audio` autoload and the display row to `Settings`, and every value painted
## here is read back from them - so a slider dragged here and the mix written to
## disk, or a mode pressed here and the window that follows it, cannot disagree.
##
## The pointer is free while it is up (the ledger frame takes it), but the world
## is never paused: a hosted session keeps running behind the page, exactly as
## the quick menu does.

signal closed

const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const SoundPageScript = preload("res://scripts/ui/sound_settings_page.gd")
const DisplayButtonScript = preload("res://scripts/ui/display_settings_button.gd")
const KeybindPageScript = preload("res://scripts/ui/keybind_page.gd")

const PANEL_SIZE := Vector2(620, 520)
## The controls sheet is a whole keyboard wide: the frame itself grows for it.
const KEYS_PANEL_SIZE := Vector2(1140, 760)
const PAGE_ROOT := "root"
const PAGE_SOUND := "sound"
const PAGE_DISPLAY := "display"
const PAGE_KEYS := "keys"
const DIM := Color(0.02, 0.015, 0.01, 0.82)

var sound_button: Button
## The index's DISPLAY row; the page it opens is the shared fullscreen row.
var display_button: Button
var keys_button: Button
var close_button: Button
var back_button: Button
## The one sound page, shared with the quick menu's copy of the same idea.
var sound_page
## The shared fullscreen row: the same one the quick menu shows.
var fullscreen_button
## The one controls sheet, on the same footing.
var keys_page

var _root: Control
var _frame
var _pages: Dictionary = {}     # page name -> Control
var _page := PAGE_ROOT
var _built := false
var _opened := false


func _ready() -> void:
	_build()
	visible = _opened


## Escape walks back one page at a time: a sub-page returns to the index and the
## index closes the window. An owning scene may check `is_open()` first as well;
## whichever runs first consumes the key, so the page never closes twice.
func _unhandled_input(event: InputEvent) -> void:
	if not _opened or not event.is_action_pressed("ui_cancel"):
		return
	if _page != PAGE_ROOT:
		show_page(PAGE_ROOT)
	else:
		close()
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _opened


func open() -> void:
	_build()
	_opened = true
	visible = true
	show_page(PAGE_ROOT)
	refresh()
	_free_pointer()
	_note("open", {})


func close() -> void:
	if not _opened:
		return
	_opened = false
	visible = false
	closed.emit()


func toggle() -> void:
	if _opened:
		close()
	else:
		open()


func page() -> String:
	return _page


## Switch the visible page. Unknown names fall back to the index.
func show_page(name: String) -> void:
	if not _pages.has(name):
		name = PAGE_ROOT
	_page = name
	for key in _pages.keys():
		(_pages[key] as Control).visible = key == name
	_apply_chrome()
	# A page is a view of the managers, so entering it repaints it: the mode may
	# have moved while the window stood on its index.
	if name == PAGE_DISPLAY and fullscreen_button != null:
		fullscreen_button.refresh()


## The controls sheet is wider than the index, so the window itself changes size
## and title with the page; every other page puts the settings window back.
func _apply_chrome() -> void:
	if _frame == null:
		return
	if _page == PAGE_KEYS:
		_frame.configure("Keys", "cage")
		_set_panel_size(KEYS_PANEL_SIZE)
	else:
		_frame.configure("Settings", "gear")
		_set_panel_size(PANEL_SIZE)


## The frame is centred, so its four offsets are all a page size needs.
func _set_panel_size(panel: Vector2) -> void:
	_frame.offset_left = -panel.x * 0.5
	_frame.offset_right = panel.x * 0.5
	_frame.offset_top = -panel.y * 0.5
	_frame.offset_bottom = panel.y * 0.5


## Repaint from the managers. Called on open, and after every move.
func refresh() -> void:
	if sound_page != null:
		sound_page.refresh()
	if fullscreen_button != null:
		fullscreen_button.refresh()


## The numbers the page is showing, for a regression to compare with the mixer.
func values() -> Dictionary:
	return sound_page.values() if sound_page != null else {}


# --- pages -----------------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	layer = 14

	_root = Control.new()
	_root.name = "SettingsRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = LedgerThemeScript.get_theme()
	add_child(_root)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = DIM
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)

	_frame = LedgerFrameScript.new()
	_frame.name = "SettingsFrame"
	_frame.configure("Settings", "gear")
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -PANEL_SIZE.x * 0.5
	_frame.offset_right = PANEL_SIZE.x * 0.5
	_frame.offset_top = -PANEL_SIZE.y * 0.5
	_frame.offset_bottom = PANEL_SIZE.y * 0.5
	_root.add_child(_frame)

	_pages[PAGE_ROOT] = _build_root(_frame.body)
	_pages[PAGE_SOUND] = _build_sound(_frame.body)
	_pages[PAGE_DISPLAY] = _build_display(_frame.body)
	_pages[PAGE_KEYS] = _build_keys(_frame.body)
	show_page(PAGE_ROOT)
	refresh()


func _build_root(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Index"
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	_section(column, "SETTINGS")
	var note := _label(column, "Escape closes this. The ledger keeps the mix and the window.",
		12, LedgerThemeScript.INK_MUTED)
	# Clipped, never wrapped: see the note in `sound_settings_page.gd`.
	note.clip_text = true

	sound_button = _button(column, "SOUND", "PrimaryButton", 56)
	sound_button.pressed.connect(func(): show_page(PAGE_SOUND))
	column.add_child(sound_button)

	display_button = _button(column, "DISPLAY", "", 48)
	display_button.pressed.connect(func(): show_page(PAGE_DISPLAY))
	column.add_child(display_button)

	keys_button = _button(column, "KEYS", "", 48)
	keys_button.pressed.connect(func(): show_page(PAGE_KEYS))
	column.add_child(keys_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	close_button = _button(column, "CLOSE", "", 48)
	close_button.pressed.connect(close)
	column.add_child(close_button)
	return column


func _build_sound(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Sound"
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	column.visible = false
	_section(column, "SOUND")

	sound_page = SoundPageScript.new()
	sound_page.name = "SoundPage"
	column.add_child(sound_page)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	back_button = _button(column, "BACK", "", 48)
	back_button.pressed.connect(func(): show_page(PAGE_ROOT))
	column.add_child(back_button)
	return column


func _build_display(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Display"
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	column.visible = false
	_section(column, "DISPLAY")

	var note := _label(column, "The next launch starts in the mode last set.", 12,
		LedgerThemeScript.INK_MUTED)
	note.clip_text = true

	fullscreen_button = DisplayButtonScript.new()
	fullscreen_button.name = "Fullscreen"
	column.add_child(fullscreen_button)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var back := _button(column, "BACK", "", 48)
	back.name = "DisplayBack"
	back.pressed.connect(func(): show_page(PAGE_ROOT))
	column.add_child(back)
	return column


func _build_keys(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Keys"
	column.add_theme_constant_override("separation", 10)
	parent.add_child(column)
	column.visible = false
	_section(column, "CONTROLS")

	keys_page = KeybindPageScript.new()
	keys_page.name = "KeybindPage"
	keys_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(keys_page)

	var back := _button(column, "BACK", "", 48)
	back.name = "KeysBack"
	back.pressed.connect(func(): show_page(PAGE_ROOT))
	column.add_child(back)
	return column


# --- furniture -------------------------------------------------------------

func _section(parent: Node, text: String) -> Label:
	return _label(parent, text, 10, LedgerThemeScript.BLOOD)


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, variation: String, height: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.focus_mode = Control.FOCUS_NONE
	if not variation.is_empty():
		button.theme_type_variation = variation
	return button


func _free_pointer() -> void:
	# Headless runs have no pointer to free.
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("settings", message, data)
