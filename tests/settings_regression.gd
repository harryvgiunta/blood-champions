extends SceneTree
## Settings regression: the preferences outside a campaign survive a relaunch.
##
## The display mode is the live one; the mix has its own file and the audio
## regression owns that contract. A headless run cannot move a window, so what
## is proven here is the stored preference, the boot path that reads it back,
## the file's own schema, and the two windows that write it - the title's
## Escape page and the campaign's quick menu, through the same shared row.

const SettingsScript = preload("res://scripts/settings_store.gd")
const DisplayButtonScript = preload("res://scripts/ui/display_settings_button.gd")
const SettingsMenuScript = preload("res://scripts/ui/settings_menu.gd")
const WarbandMenuScript = preload("res://scripts/warband/warband_menu.gd")

const TEST_SAVE := "user://settings_test.json"
const WINDOWED := "DISPLAY:  WINDOWED"
const FULLSCREEN := "DISPLAY:  FULLSCREEN"

var checks := 0
var failures := 0
var settings


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("SETTINGS_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _read() -> Dictionary:
	if not FileAccess.file_exists(TEST_SAVE):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _fresh(name_text: String) -> Node:
	# A fresh manager is a relaunch: it reads the file in `_ready`, not a value
	# handed to it by the running one.
	var node = SettingsScript.new()
	node.name = name_text
	root.add_child(node)
	return node


func run() -> void:
	_remove_save()
	settings = root.get_node_or_null("Settings")
	check(settings != null, "the Settings autoload is missing")
	if settings == null:
		quit(1)
		return
	settings.save_path = TEST_SAVE
	settings.fullscreen = false
	settings.save_settings()

	# The file is the schema the next launch reads, and a fresh manager is that
	# launch: the mode it starts with is the mode last written.
	var data := _read()
	check(int(data.get("version", 0)) == 1, "the settings file has no schema version")
	check(data.has("fullscreen"), "the settings file does not carry the display mode")
	check(not bool(data.get("fullscreen", true)), "a windowed mode was written as fullscreen")

	var reload := _fresh("SettingsReload")
	check(reload.save_path == TEST_SAVE, "a script run must use its own settings file")
	check(not reload.fullscreen, "a relaunch did not read the windowed mode back")
	check(not reload.window_fullscreen(), "a headless manager forgot the mode it read")

	reload.set_fullscreen(true)
	check(reload.fullscreen, "set_fullscreen did not remember the mode")
	var written := _read()
	check(bool(written.get("fullscreen", false)), "the fullscreen mode was not written to disk")

	var again := _fresh("SettingsAgain")
	check(again.fullscreen, "a relaunch did not read the fullscreen mode back")
	check(again.window_fullscreen(), "a headless relaunch should answer from the preference")
	again.apply_window()
	check(again.fullscreen, "applying a mode with no display lost the preference")
	again.set_fullscreen(false)
	check(not again.fullscreen, "the mode could not be set back to windowed")

	# The shared row: text, press, text. One implementation, so this is also the
	# quick menu's row and the title page's.
	settings.fullscreen = false
	var host := Control.new()
	root.add_child(host)
	var row = DisplayButtonScript.new()
	host.add_child(row)
	check(row.text == WINDOWED, "the row does not start windowed (%s)" % row.text)
	row.pressed.emit()
	check(settings.fullscreen, "the row did not write the fullscreen mode")
	check(row.text == FULLSCREEN, "the row did not repaint as fullscreen (%s)" % row.text)
	row.pressed.emit()
	check(not settings.fullscreen, "the row did not write the windowed mode")
	check(row.text == WINDOWED, "the row did not repaint as windowed (%s)" % row.text)

	# The title's Escape window: an index row, a page, and the shared toggle on
	# it. The row is what a player at the title has, so it must exist and work.
	var menu = SettingsMenuScript.new()
	menu.name = "TestSettings"
	root.add_child(menu)
	menu.open()
	check(menu.page() == "root", "the settings window did not open on its index")
	check(menu.display_button != null and menu.display_button.is_visible_in_tree(),
		"the index has no DISPLAY entry")
	menu.display_button.pressed.emit()
	check(menu.page() == "display", "the DISPLAY entry did not open its page")
	check(menu.fullscreen_button != null and menu.fullscreen_button.is_visible_in_tree(),
		"the display page has no fullscreen row")
	check(menu.fullscreen_button.text == WINDOWED, "the display page starts fullscreen")
	menu.fullscreen_button.pressed.emit()
	check(settings.fullscreen, "the title's display page did not write the mode")
	check(menu.fullscreen_button.text == FULLSCREEN, "the title's display page did not repaint")
	menu.show_page("root")
	check(menu.page() == "root", "the display page did not walk back to the index")
	menu.close()
	check(not menu.is_open(), "the settings window stayed open")
	menu.queue_free()

	# The campaign's quick menu keeps its row on the settings page and says what
	# the press did on its status line.
	settings.fullscreen = false
	var quick = WarbandMenuScript.new()
	quick.name = "TestWarbandMenu"
	root.add_child(quick)
	quick.open()
	quick.show_page("sound")
	check(quick.display_button != null, "the quick menu has no display row")
	check(quick.display_button.text == WINDOWED, "the quick menu's row starts fullscreen")
	quick.display_button.pressed.emit()
	check(settings.fullscreen, "the quick menu's row did not write the mode")
	check(quick.status_text() == "Fullscreen. The ledger stays one page deep.",
		"the quick menu did not say the switch happened (%s)" % quick.status_text())
	quick.display_button.pressed.emit()
	check(not settings.fullscreen, "the quick menu's row did not write it back")
	check(quick.status_text() == "Windowed. Drag the border to resize.",
		"the quick menu did not say the window came back (%s)" % quick.status_text())
	quick.close()
	quick.queue_free()

	# An unreadable file is a warning and the value already held, never a mode
	# invented from half a line.
	var broken := _fresh("SettingsBroken")
	broken.save_path = TEST_SAVE
	broken.fullscreen = true
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	# Valid JSON of the wrong shape: the guard must not read a mode from it.
	file.store_string("[]")
	file.close()
	broken.load_settings()
	check(broken.fullscreen, "an unreadable file overwrote the mode it held")

	settings.fullscreen = false
	settings.save_settings()
	settings.apply_window()
	_remove_save()
	broken.queue_free()
	again.queue_free()
	reload.queue_free()
	host.queue_free()
	print("SETTINGS_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
