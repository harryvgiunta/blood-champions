extends Node
## Autoload `Settings`: the preferences that belong to the machine, not to a
## campaign.
##
## Today that is the display mode. The mix stays with `Audio` because a level is
## a bus write and its four values are the mixer's; what lives here is the other
## kind of setting - one a player sets once and expects the next launch to keep.
##
## The mode is a *preference*, not a readout: it is applied to the window when
## the manager comes up and again on every change, and written to
## `user://settings.json` on that change, so a quit or a crash cannot lose it.
## A headless run has no window to move; it keeps the preference and reads
## `user://settings_test.json` under `--script`, never the player's file.

const DEFAULT_SAVE_PATH := "user://settings.json"
const TEST_SAVE_PATH := "user://settings_test.json"
const SAVE_VERSION := 1

## Where the preferences are remembered. A regression points this at its own
## file, the same way the mix and the state autoloads do.
var save_path := DEFAULT_SAVE_PATH

## Whether the game should be fullscreen. The window is made to agree on boot
## and on every change; where there is no window (headless) this is the answer.
var fullscreen := false


func _ready() -> void:
	# A headless regression is not the player's session: it must never read or
	# write the preferences a person set on this machine.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = TEST_SAVE_PATH
	load_settings()
	apply_window()
	_note("boot", {"fullscreen": fullscreen, "window": window_mode_name()})


## Put the chosen mode on the game window. A headless run has none, and a
## missing window is not an error: the preference is still the truth.
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window == null:
		return
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


## Remember `value` and make the window follow it now. The file is written on
## the change, so a mode the player set survives the next launch.
func set_fullscreen(value: bool) -> void:
	var changed := fullscreen != value
	fullscreen = value
	# Always re-apply: a compositor may have refused the last attempt, and a
	# press that asks for the mode already stored is still a request for it.
	apply_window()
	if not changed:
		return
	save_settings()
	_note("display", {"fullscreen": fullscreen, "window": window_mode_name()})


## Flip what the window is actually doing (the row's own answer), so a mode the
## OS changed under the game is answered rather than ignored. In a headless run
## `window_fullscreen()` is the stored preference, so the flip is the same one.
func toggle_fullscreen() -> bool:
	set_fullscreen(not window_fullscreen())
	return fullscreen


## Whether the window is fullscreen right now. A headless run has no window to
## ask, so the stored preference answers.
func window_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless":
		return fullscreen
	var window := get_window()
	if window == null:
		return fullscreen
	return window.mode == Window.MODE_FULLSCREEN \
		or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN


func window_mode_name() -> String:
	return "fullscreen" if window_fullscreen() else "windowed"


## Read the file back. A missing file keeps the defaults; an unreadable one is a
## warning and the value already held, never a half-applied file.
func load_settings() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ignoring unreadable settings at %s" % save_path)
		return
	var data: Dictionary = parsed
	fullscreen = bool(data.get("fullscreen", fullscreen))


func save_settings() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write settings to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"fullscreen": fullscreen,
	}))
	file.close()


func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("settings", message, data)
