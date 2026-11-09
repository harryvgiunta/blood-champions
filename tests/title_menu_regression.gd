extends SceneTree
## The title screen: two doors and nothing else. PLAY opens the one world on this
## machine - making its save slot on the first launch, resuming it after - and
## hosts it; JOIN GAME is the guest's form. There are no campaigns to name, list
## or load, and the old host panel and checkpoint doors are gone.
##
## The door presses come last and nothing awaits a frame after them: a press
## queues the flow's scene change, and this test checks what the flow was told,
## not the world it opens.

const STATE_SAVE := "user://title_menu_state.json"
const WARBAND_SAVE := "user://title_menu_warband.json"
const SLOT_ROOT := "user://title_menu_saves"
const DOOR_TEXTS := ["PLAY", "JOIN GAME"]

var state
var warband
var flow
var cache
var slots
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TITLE_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	for name in names:
		var child := path.path_join(name)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(child)):
			_remove_tree(child)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _open_title():
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	return title

func _escape(title) -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	title._unhandled_input(event)

func run() -> void:
	check(str(ProjectSettings.get_setting("application/run/main_scene")) == "res://title.tscn",
		"the title screen is the game's entry scene")
	check(str(ProjectSettings.get_setting("application/config/name")) == "Blood Champions",
		"the project is Blood Champions")
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	cache = root.get_node("NetCache")
	slots = root.get_node("SaveSlots")
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	slots.root_path = SLOT_ROOT
	_remove_tree(SLOT_ROOT)
	slots.load_index()
	state.save_path = STATE_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.take_notice()
	cache.reset()

	await _check_doors()
	_check_escape()
	_check_join_form()
	_check_notice()
	_check_play()

	flow.leave_warband()
	flow.active = false
	flow.take_notice()
	state.reset(false)
	cache.reset()
	_remove_tree(SLOT_ROOT)
	_remove(cache.save_path)
	_remove(STATE_SAVE)
	_remove(WARBAND_SAVE)
	print("TITLE_MENU_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

## Two doors, in order, and nothing else in the column that can be pressed.
func _check_doors() -> void:
	var title = _open_title()
	await process_frame
	var column: Node = title.get_node_or_null("Doors")
	check(column != null, "the title has its Doors column")
	var doors: Array = []
	if column != null:
		for child in column.get_children():
			if child is BaseButton:
				doors.append(child)
	check(doors.size() == 2, "the column holds exactly two doors (%d)" % doors.size())
	var texts: Array = []
	for door in doors:
		texts.append(str(door.text))
	check(texts == DOOR_TEXTS, "the doors read %s in that order (%s)" % [str(DOOR_TEXTS), str(texts)])
	if doors.size() == 2:
		check(doors[0] == title.play_button and doors[1] == title.join_button,
			"the door members are the two buttons in the column")
	check(title.play_button.theme_type_variation == "PrimaryButton",
		"PLAY is the primary door")
	check(not title.has_method("_open_campaigns"), "there is no campaign list to open")
	check(not title.has_method("_open_host"), "there is no host panel to open")
	check(title.get("new_campaign_button") == null, "there is no NEW CAMPAIGN door")
	check(title.get("campaigns_button") == null, "there is no CAMPAIGNS door")
	for door in doors:
		check(door.visible, "%s is visible" % door.text)
	title.free()

## Escape closes the join form, and with nothing open it opens the settings.
func _check_escape() -> void:
	var title = _open_title()
	title._open_join()
	_escape(title)
	check(not title._join_layer.visible, "Escape closes the join form")
	_escape(title)
	check(title.settings.is_open(), "Escape with nothing open opens the settings")
	_escape(title)
	check(not title.settings.is_open(), "Escape closes the settings again")
	title.free()

func _check_join_form() -> void:
	cache.remember("CachedRanger", "100.64.0.12", 7999)
	var title = _open_title()
	title.join_button.pressed.emit()
	check(title._join_layer.visible, "JOIN GAME opens the join form")
	check(title._name_input.text == "CachedRanger" and title._address_input.text == "100.64.0.12"
		and int(title._port_input.value) == 7999, "the join form restores the cached name, address and port")
	check(title._name_input.max_length == 16, "a join name is at most sixteen characters")
	cache.remember("FreshRanger", "100.64.0.44", 8111)
	cache.remember_host("FreshRanger", 9001)
	title._close_join()
	check(not title._join_layer.visible, "the join form can be cancelled")
	title._open_join()
	check(title._name_input.text == "FreshRanger" and title._address_input.text == "100.64.0.44"
		and int(title._port_input.value) == 8111, "the join form rereads the cache every time it opens")

	# An empty address is refused on the form, and nothing is joined.
	title._address_input.text = "   "
	title._confirm_join()
	check(title._form_error.text == "Enter the host's address.",
		"an empty address is refused (%s)" % title._form_error.text)
	check(title._join_layer.visible, "a refused join keeps the form open")
	check(flow.warband_intent.is_empty() and flow.session == null, "a refused join opens no session")
	check(cache.address == "100.64.0.44", "a refused join remembers nothing")

	# What the player typed is what is dialled, not the SpinBox's stale value.
	title._address_input.text = "100.64.0.77"
	title._port_input.get_line_edit().text = "8123"
	check(int(title._port_input.value) == 8111,
		"the typed port is still only text on the SpinBox (%d)" % int(title._port_input.value))
	title._confirm_join()
	var intent: Dictionary = flow.warband_intent
	check(str(intent.get("mode", "")) == "join" and not intent.is_empty(),
		"a filled join form dials the host (%s)" % str(intent))
	check(str(intent.get("address", "")) == "100.64.0.77" and int(intent.get("port", 0)) == 8123,
		"JOIN dials the address and port that were typed (%s)" % str(intent))
	check(cache.address == "100.64.0.77" and cache.port == 8123,
		"the typed endpoint is what the cache remembers")
	check(not title._join_layer.visible, "a join closes the form")
	flow.leave_warband()
	check(flow.session == null and flow.warband_intent.is_empty(), "the checked join leaves no session")

	# A port outside the field's range is refused where the player can see it.
	title._open_join()
	title._address_input.text = "100.64.0.77"
	title._port_input.get_line_edit().text = "80"
	title._confirm_join()
	check(title._form_error.text == "Choose a UDP port between 1024 and 65535.",
		"an out-of-range typed port is refused (%s)" % title._form_error.text)
	check(title._join_layer.visible, "a refused port keeps the form open")
	check(title._port_input.get_line_edit().text == "80", "the refused port is left as typed")
	check(cache.port == 8123 and flow.warband_intent.is_empty(),
		"a refused port dials and remembers nothing")
	title._port_input.get_line_edit().text = "7777x"
	title._confirm_join()
	check(title._join_layer.visible and cache.port == 8123,
		"a non-numeric typed port is refused too")
	title.free()
	cache.reset()

func _check_notice() -> void:
	var title = _open_title()
	title._on_notice_posted("The host left.")
	check(title._status.text == "The host left.", "a notice is written on the title")
	title.free()

## PLAY: the first press makes the one world and hosts it; a second press resumes
## the same slot instead of making a second one.
func _check_play() -> void:
	var title = _open_title()
	check(slots.slots.is_empty(), "this machine has no world yet")
	cache.player_name = "HostRanger"
	cache.host_port = 9099
	title.play_button.pressed.emit()
	var intent: Dictionary = flow.warband_intent
	check(str(intent.get("mode", "")) == "host", "PLAY opens a host session (%s)" % str(intent))
	check(int(intent.get("port", 0)) == 9099 and str(intent.get("name", "")) == "HostRanger",
		"PLAY hosts on the cached name and port")
	check(str(intent.get("scene", "")) == "res://scenes/warband_world.tscn",
		"and opens the one world")
	check(slots.slots.size() == 1, "PLAY made the world's one save slot")
	check(not slots.active.is_empty() and slots.active == str(slots.slots[0]["id"]),
		"and bound it")
	check(flow.active, "the flow is live")
	title.free()
	flow.leave_warband()

	# A second PLAY resumes the same slot rather than making another.
	var id := str(slots.active)
	title = _open_title()
	title.play_button.pressed.emit()
	check(slots.slots.size() == 1 and slots.active == id,
		"a second PLAY resumes the same world slot")
	title.free()
	flow.leave_warband()
