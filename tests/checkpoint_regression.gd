extends SceneTree
## Auto save / checkpoints: the campaign remembers how far it got.
##
## The warband save is now also a bookmark. Standing anywhere out on the road
## writes `trail_start` at the soul's own feet; the town square writes `town`. The
## bookmark rides in the same file as the roster, stash and essence, so a load is
## one truthful picture, and it must survive a save/load round trip, refuse a file
## that changed outside the game outright (`SaveFile`'s MAC) rather than half-read
## it, and never appear in a file written before checkpoints existed.
##
## This drives the real world twice: once opening on a trail bookmark (the party
## stands in a ring on the bookmark with the squad walking and the bookmark itself
## not rewritten), then walks the soul into the square so the town bookmark
## replaces it, then opens a second world on that town bookmark. The restore door
## is exercised separately: a downed body wakes, the dead stay dead, and a
## checkpoint with no living body refuses to be loaded at all.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const SaveFileScript = preload("res://scripts/save_file.gd")
const WorldScene := "res://scenes/warband_world.tscn"
const TEST_SAVE := "user://checkpoint_player.json"
const WARBAND_SAVE := "user://checkpoint_warband.json"
const OLD_SAVE := "user://checkpoint_v3.json"
const BAD_SAVE := "user://checkpoint_bad.json"
const TAMPERED_SAVE := "user://checkpoint_tampered.json"
const SLOT_ROOT := "user://checkpoint_saves"

var state
var warband
var flow
var game
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("CHECKPOINT_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A campaign folder holds two files, so removing one means walking it.
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

func run() -> void:
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BAD_SAVE, TAMPERED_SAVE]:
		_remove(path)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"

	check_persistence()
	check_sanitising()
	check_tamper()
	check_restore()
	await check_world_resume()
	check_wipe_door()
	await check_retry_reload()
	await check_title_doors()
	await check_out_of_the_square_and_back()
	_finish()

func _finish() -> void:
	Engine.time_scale = 1.0
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	flow.active = false
	flow.world_start = "town"
	for path in [TEST_SAVE, WARBAND_SAVE, OLD_SAVE, BAD_SAVE, TAMPERED_SAVE]:
		_remove(path)
	_remove_tree(SLOT_ROOT)
	print("CHECKPOINT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- the record itself -----------------------------------------------------

func _seed_warband() -> void:
	warband.reset_state()
	var first: int = warband.add_mercenary("Ash")
	warband.roster.equip(first, "main", "sword_short")
	warband.add_mercenary("Bram")
	warband.add_mercenary("Wren")
	warband.stash.add("dagger_ironwood", 1)
	warband.save_state()

func check_persistence() -> void:
	_seed_warband()
	check(not warband.has_checkpoint(), "a fresh warband has no checkpoint")
	warband.save_checkpoint("trail_start", "trail", Vector3(4.5, 0.25, -90.0), "ON THE ROAD")
	# The file is a sealed container, not JSON: nothing a cheater would open reads
	# the roster, and the checkpoint rides inside the same envelope as the rest.
	var opened: Dictionary = SaveFileScript.inspect(WARBAND_SAVE)
	check(bool(opened.get("ok", false)), "the checkpoint writes a save file")
	if not bool(opened.get("ok", false)):
		return
	check(str(opened.get("format", "")) == SaveFileScript.SEALED,
		"and it is sealed, not JSON (%s)" % str(opened.get("format", "")))
	check(not FileAccess.get_file_as_string(WARBAND_SAVE).contains("mercenaries"),
		"whose roster keys are not readable in the bytes on disk")
	var data: Dictionary = opened.get("data", {})
	check(data.get("checkpoint", {}) is Dictionary, "the file carries a checkpoint block")
	var stored: Dictionary = warband.sanitise_checkpoint(data.get("checkpoint", {}))
	check(stored.get("id", "") == "trail_start", "the bookmark names the tutorial's end")
	check(stored.get("area", "") == "trail", "the bookmark is on the trail")
	check(warband.checkpoint_position().distance_to(Vector3(4.5, 0.25, -90.0)) < 0.01,
		"the position survives the round trip")
	check(warband.checkpoint_label() == "ON THE ROAD", "the label survives too")

	# Mutating the warband after the bookmark must not change the bookmark, and a
	# reload must bring back the state the file holds.
	warband.add_mercenary("Het")
	warband.clear_checkpoint()
	check(not warband.has_checkpoint(), "a bookmark can be cleared")
	check(warband.load_state(), "the save loads")
	check(warband.roster.count() == 3, "the reload is the file's roster, not the live one (%d)" % warband.roster.count())
	check(warband.checkpoint_id() == "trail_start", "and the file's bookmark is back")

	# A file written before checkpoints existed still loads, at the town.
	var old: Dictionary = warband.to_dict()
	old["version"] = 3
	old.erase("checkpoint")
	check(SaveFileScript.write(OLD_SAVE, old), "a v3 body is written for the old-save path")
	warband.save_path = OLD_SAVE
	check(warband.load_state(), "a v3 save loads")
	check(not warband.has_checkpoint(), "a v3 save carries no bookmark")
	check(warband.roster.count() == 3, "and its roster is intact")
	warband.save_path = WARBAND_SAVE
	warband.load_state()
	check(warband.checkpoint_id() == "trail_start", "the v4 bookmark is restored for the next checks")

func check_sanitising() -> void:
	check(warband.sanitise_checkpoint({}).is_empty(), "no record means no bookmark")
	check(warband.sanitise_checkpoint({"id": "", "area": "trail", "position": [0, 0, 0]}).is_empty(),
		"a nameless bookmark is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "nowhere", "position": [0, 0, 0]}).is_empty(),
		"an area the campaign keeps no bookmark for is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": [0, 0]}).is_empty(),
		"a two-value position is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": ["a", 0, 0]}).is_empty(),
		"a non-numeric position is refused")
	check(warband.sanitise_checkpoint({"id": "x", "area": "trail", "position": [INF, 0, 0]}).is_empty(),
		"an infinite position is refused")
	var good: Dictionary = warband.sanitise_checkpoint(
		{"id": " town ", "area": "town", "position": [1, 2, 3], "at": 7})
	check(good.get("id", "") == "town" and good.get("area", "") == "town", "a clean record is accepted")
	check(warband.checkpoint_vector(good) == Vector3(1, 2, 3), "and reads back as a point")

	# A save that carries a garbage bookmark - a build that wrote one, or a payload
	# a tool re-sealed with the game's own keys - is normalised on load rather than
	# poisoning the session.
	var bad: Dictionary = warband.to_dict()
	bad["checkpoint"] = {"id": "x", "area": "everywhere", "position": "here"}
	check(SaveFileScript.write(BAD_SAVE, bad), "a save with a garbage bookmark is written")
	var previous_path: String = warband.save_path
	warband.save_path = BAD_SAVE
	check(warband.load_state(), "a file with a garbage bookmark still loads")
	check(not warband.has_checkpoint(), "and drops the garbage")
	warband.save_path = previous_path
	warband.load_state()

## The container's own check, and the whole point of the tag: a save whose bytes
## changed after the game wrote it is refused **whole**. A purse, a key count or a
## roster rewritten by a tool is not loaded "as far as it parses" - it is not
## loaded at all, and the live warband is left exactly as it was.
func check_tamper() -> void:
	_seed_warband()
	var before: int = warband.roster.count()
	var source := FileAccess.open(WARBAND_SAVE, FileAccess.READ)
	check(source != null, "the sealed save opens for the tamper check")
	if source == null:
		return
	var raw := source.get_buffer(source.get_length())
	source.close()
	# One bit, inside the ciphertext: the frame is still well formed, so only the
	# MAC can catch it.
	var at := SaveFileScript.HEADER + SaveFileScript.NONCE_BYTES \
		+ SaveFileScript.SIZE_BYTES + 8
	raw[at] = raw[at] ^ 0x01
	var out := FileAccess.open(TAMPERED_SAVE, FileAccess.WRITE)
	check(out != null, "the edited copy is written")
	if out == null:
		return
	out.store_buffer(raw)
	out.close()
	var problem := str(SaveFileScript.inspect(TAMPERED_SAVE).get("problem", ""))
	check(problem == "tampered", "the container names the edit (%s)" % problem)
	var previous: String = warband.save_path
	warband.save_path = TAMPERED_SAVE
	check(not warband.load_state(), "an edited save does not load")
	check(warband.roster.count() == before,
		"and the live warband is not half-replaced (%d)" % warband.roster.count())
	warband.save_path = previous
	check(warband.load_state(), "the untouched save still loads")
	# The checks after this one restore from the trail bookmark, so hand it back
	# exactly as `check_persistence` left it.
	warband.save_checkpoint("trail_start", "trail", Vector3(4.5, 0.25, -90.0), "ON THE ROAD")
	check(warband.checkpoint_id() == "trail_start", "and the trail bookmark is back")

# --- the restore door ------------------------------------------------------

func check_restore() -> void:
	# A body that was down at the bookmark gets up; a body that was dead stays so.
	var ids: Array = warband.roster.ids()
	warband.roster.set_state(int(ids[0]), Contracts.HealthState.DOWNED)
	warband.roster.set_health(int(ids[0]), 3.0)
	warband.roster.set_state(int(ids[1]), Contracts.HealthState.DEAD)
	warband.save_state()
	var credits: int = int(state.credits)
	flow.world_start = "town"
	check(flow.restore_checkpoint(), "the restore door opens on a real bookmark")
	check(flow.world_start == "checkpoint", "and names the checkpoint as the world's start")
	check(warband.roster.state_of(int(ids[0])) == Contracts.HealthState.ALIVE,
		"a downed body is woken by the reload")
	check(warband.roster.health_of(int(ids[0])) >= warband.roster.max_health_of(int(ids[0])) * 0.5,
		"at half the body's own pool or better (%f)" % warband.roster.health_of(int(ids[0])))
	check(warband.roster.state_of(int(ids[1])) == Contracts.HealthState.DEAD,
		"a dead body stays dead")
	check(int(state.credits) == credits, "the purse is never rolled back by a reload")

	# No bookmark, and a bookmark with nobody standing, both refuse.
	warband.clear_checkpoint()
	warband.save_state()
	check(not flow.restore_checkpoint(), "a save without a bookmark cannot be resumed")
	for merc_id in warband.roster.ids():
		warband.roster.set_state(int(merc_id), Contracts.HealthState.DEAD)
	warband.save_checkpoint("town", "town", Vector3.ZERO, "EMPTY")
	flow.world_start = "town"
	check(not flow.restore_checkpoint(), "a bookmark whose whole squad is dead refuses to load")
	check(flow.world_start == "town", "and leaves the start where it was")

# --- the world opening on a bookmark ---------------------------------------

func _build_world() -> void:
	game = load(WorldScene).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout

func check_world_resume() -> void:
	_seed_warband()
	# Two bodies on their feet, one dead: a resume fields the two.
	var ids: Array = warband.roster.ids()
	warband.roster.set_state(int(ids[2]), Contracts.HealthState.DEAD)
	warband.save_checkpoint("trail_start", "trail", Vector3(6.0, 0.0, -90.0), "ON THE ROAD")
	flow.world_start = "checkpoint"
	await _build_world()
	if game == null or not game.has_method("stats"):
		check(false, "the world loaded for the trail resume")
		return
	check(game.start_area == "checkpoint", "the world opens on the bookmark (%s)" % game.start_area)
	check(game.bodies.size() == 2, "the bookmark's standing bodies take the field (%d)" % game.bodies.size())
	check(game.squad.following, "the squad walks with the soul")
	var anchor: Vector3 = warband.checkpoint_position()
	for body in game.bodies:
		# A bookmark is a place on the ground: the world re-grounds the point it
		# holds, so the body stands at the record's x/z and the terrain's height.
		var flat := Vector2(body.global_position.x - anchor.x,
			body.global_position.z - anchor.z).length() if is_instance_valid(body) else -1.0
		check(is_instance_valid(body) and flat < 8.0,
			"a resumed body stands on the bookmark (%.1f m)" % flat)
	check(warband.checkpoint_id() == "trail_start", "the resumed trail does not rewrite its own bookmark")

	# Walking into the square advances the bookmark to the town.
	var soul = game.controller.active_body(1)
	check(soul != null, "the soul is in a body")
	if soul != null:
		soul.global_position = game.town.global_position + Vector3(0, 1.0, 0)
		await create_timer(0.3).timeout
		check(game.town.in_square(soul), "the teleported soul is inside the square (%.1f, %.1f vs %.1f, %.1f)" % [
			soul.global_position.x, soul.global_position.z,
			game.town.global_position.x, game.town.global_position.z])
	check(warband.checkpoint_id() == "town", "the town square writes the town bookmark (%s)" % warband.checkpoint_id())
	check(warband.checkpoint_area() == "town", "and says so")
	check(FileAccess.file_exists(WARBAND_SAVE), "the town bookmark is on disk at once")
	await check_town_silence(soul)
	game.queue_free()
	await process_frame
	game = null

	# The town bookmark opens a world in the square, with no lesson and no cages
	# to cut.
	flow.world_start = "checkpoint"
	await _build_world()
	if game == null or not game.has_method("stats"):
		check(false, "the world loaded for the town resume")
		return
	check(game.start_area == "checkpoint", "the town bookmark is a checkpoint start (%s)" % game.start_area)
	check(game.bodies.size() == 2, "the town resume fields the standing bodies (%d)" % game.bodies.size())
	for body in game.bodies:
		check(is_instance_valid(body) and game.town.in_square(body),
			"a resumed body stands in the square")
	check(game.controller.active_body(1) != null, "the soul is seated in the square")
	check(warband.checkpoint_id() == "town", "the town resume keeps its own bookmark")

# --- the town is where the score stops -------------------------------------

## The soundtrack is the wood's: it rides the cages and the whole kilometre of
## trail. Reaching the town is the end of the run, so the square is silent - and
## the wood takes its score back the moment the squad walks back out through the
## gate, with a band between the two answers so a body on the line cannot flicker
## it.
func check_town_silence(soul) -> void:
	var audio = root.get_node_or_null("Audio")
	check(audio != null, "the mixer is up")
	if audio == null or soul == null:
		return
	# The world scene's scene-change sync has no `current_scene` in this harness,
	# so the track is set here: the rule under test is the town's own, not the
	# manager's.
	audio.play_music("warband")
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"the square stops the soundtrack (%s)" % str(audio.music_track))
	# Asked again with the score back up, because holding the rule has to be
	# idempotent - the manager answers a scene change with its own track.
	audio.play_music("warband")
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"and goes on stopping it while the soul stands there (%s)" % str(audio.music_track))
	# Just outside the square but inside the hysteresis band: hold, not restart.
	var half: float = game.town.WALL_RADIUS + 2.0
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, half + 2.0)
	await create_timer(0.2).timeout
	check(not game.town.in_square(soul), "the body is out of the square itself")
	check(str(audio.music_track).is_empty(), "a body in the band keeps the silence (%s)"
		% str(audio.music_track))
	# Well clear of the square: back to the wood, and the chase with it.
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, half + 30.0)
	await create_timer(0.2).timeout
	check(str(audio.music_track) == "warband",
		"the wood takes its score back (%s)" % str(audio.music_track))
	# And walking in again silences it again.
	soul.global_position = game.town.global_position + Vector3(0.0, 1.0, 0.0)
	await create_timer(0.2).timeout
	check(str(audio.music_track).is_empty(),
		"and the square stops it a second time (%s)" % str(audio.music_track))


# --- the wipe door ---------------------------------------------------------

func check_wipe_door() -> void:
	check(not bool(game._reload_checkpoint()),
		"a regression harness (GameFlow inactive) never reloads the world")
	# The door a wipe pulls is `restore_checkpoint()`; the scene hand-off after it
	# is the same world load the two resumes above already exercised.
	check(flow.restore_checkpoint(), "the checkpoint a wipe would load is restorable")
	check(flow.world_start == "checkpoint", "and names the checkpoint start")
	warband.clear_checkpoint()
	warband.save_state()
	flow.active = true
	check(not bool(game._reload_checkpoint()), "a warband with no bookmark has no way back")
	flow.active = false


## The wipe door end to end: the flow restores the bookmark and opens the world on
## it, with the bodies it held. This is the exact call `_reload_checkpoint()` makes
## once a live campaign has fallen.
func check_retry_reload() -> void:
	game.queue_free()
	await process_frame
	game = null
	_seed_warband()
	warband.save_checkpoint("trail_start", "trail", Vector3(6.0, 0.0, -90.0), "ON THE ROAD")
	flow.active = true
	check(flow.retry_checkpoint(), "the retry door restores the bookmark")
	var resumed = await _wait_world(8.0)
	check(resumed != null, "the retry door opens the world")
	if resumed != null:
		check(resumed.start_area == "checkpoint", "on the checkpoint start")
		check(resumed.bodies.size() == 3, "with the bookmark's bodies (%d)" % resumed.bodies.size())
		check(resumed.start_area == "checkpoint" and not paused,
			"with no lesson to read")
		check(resumed.controller.active_body(1) != null, "the soul is seated")
	flow.active = false
	if current_scene != null:
		current_scene.queue_free()
		await process_frame


func _wait_world(timeout: float) -> Node:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(timeout * 1000.0):
		await process_frame
		if current_scene != null and current_scene.has_method("stats"):
			# Give the world one physics tick to seat its bodies.
			await process_frame
			return current_scene
	return null


## The title has no campaign list and no host panel any more: PLAY opens the one
## world and JOIN puts a friend in it. The checkpoint system is still the world's
## own door (`restore_checkpoint`), tested above.
func check_title_doors() -> void:
	var title = load("res://title.tscn").instantiate()
	root.add_child(title)
	await process_frame
	check(title.play_button != null and str(title.play_button.text) == "PLAY",
		"the title carries the PLAY door")
	check(title.join_button != null and str(title.join_button.text) == "JOIN GAME",
		"and the JOIN GAME door")
	check(title.get("campaigns_button") == null and title.get("new_campaign_button") == null,
		"there is no campaign list and no new-campaign door")
	title.queue_free()
	await process_frame


# --- out of the square and back --------------------------------------------

## The bookmark only moves forward: `CHECKPOINT_ORDER` is ["trail_start", "town"],
## so a body that steps out of the square writes the road at its own feet, the
## square writes the town, and walking back out never pulls the line back to the
## road. A body standing in the square is never told to reach it, and the walk in
## counts its metres down, never back up.
func check_out_of_the_square_and_back() -> void:
	warband.reset_state()
	warband.clear_checkpoint()
	flow.world_start = "town"
	await _build_world()
	if game == null or not game.has_method("stats"):
		check(false, "the world opened at the town")
		return
	var soul = game.controller.focus_body()
	check(soul != null, "the party has a body to walk")
	if soul == null:
		return
	var centre: Vector3 = game.town.global_position
	# A point out past the square's wall: the world's own checkpoint writer calls
	# anywhere outside it "the road".
	var gate: Vector3 = centre + Vector3(0.0, 0.0, 40.0)
	# A fresh campaign opens in the square, so the world writes the town bookmark
	# on its own first frame: the book starts on the town, not empty.
	check(warband.checkpoint_id() == "town",
		"opening in the square writes the town bookmark (%s)" % warband.checkpoint_id())
	# Forget it, the way an old file without a bookmark is: the road is what this
	# section is about, and `CHECKPOINT_ORDER` would otherwise never let the trail
	# be written after the town.
	warband.clear_checkpoint()
	# Out on the road: the bookmark follows the soul's own feet, not the gate.
	var outside: Vector3 = gate + (gate - centre).normalized() * 24.0
	soul.global_position = Vector3(outside.x, soul.global_position.y, outside.z)
	await create_timer(0.2).timeout
	game._check_checkpoints()
	check(warband.checkpoint_id() == "trail_start",
		"the road writes the trail bookmark (%s)" % warband.checkpoint_id())
	check(warband.checkpoint_area() == "trail", "and says so")
	var feet: Vector3 = warband.checkpoint_position()
	check(Vector2(feet.x - soul.global_position.x, feet.z - soul.global_position.z).length() < 1.5,
		"the bookmark stands at the soul's own feet (%.1f, %.1f vs %.1f, %.1f)"
		% [feet.x, feet.z, soul.global_position.x, soul.global_position.z])
	# In the square: the town replaces it.
	soul.global_position = centre + Vector3(0.0, 1.0, 0.0)
	await create_timer(0.2).timeout
	game._check_checkpoints()
	check(warband.checkpoint_id() == "town",
		"the square writes the town bookmark (%s)" % warband.checkpoint_id())
	# Several frames standing in the square: the bookmark stays put.
	for frame in 4:
		soul.global_position = centre + Vector3(0.0, 1.0, 0.0)
		game._check_checkpoints()
		check(warband.checkpoint_id() == "town",
			"frame %d in the square keeps the town bookmark (%s)" % [frame, warband.checkpoint_id()])
	check(game.hud.status_line().contains("HEARTHSTEAD"),
		"the status line stays on the town (%s)" % game.hud.status_line())
	# Walking back out does not pull the bookmark back to the road either.
	soul.global_position = gate + Vector3(0.0, 1.0, 0.0)
	game._check_checkpoints()
	check(warband.checkpoint_id() == "town",
		"walking back out keeps the town bookmark (%s)" % warband.checkpoint_id())
