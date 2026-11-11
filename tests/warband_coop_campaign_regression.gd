extends SceneTree
## Two real processes play one campaign from one warband: the host opens its own
## world with `GameFlow.host_campaign()`, a guest child joins it with
## `join_campaign()`, and everything the shared pool promises has to hold.
##
## Nothing is built by hand. The host writes a warband save holding a two-body
## squad on the trail bookmark and opens it; the guest has a campaign of its own
## on disk (one mercenary called Own Man) and must get it back untouched when the
## session ends. The guest is sent the host's warband, fields the host's bodies,
## and is seated by the host in the first free one.
##
## Then the rule the whole mode hangs on: with one body left, the soul already
## inside it keeps it and the other soul watches it. The guest's body is finished,
## the host keeps its own, the guest's panel says who it is watching, and a body
## that comes free afterwards goes to the soul that had been waiting.
##
## The host leg runs by default; the guest is the same script started with
## `-- --coop-client <port> <savepath>`.

const WORLD_SCENE := "res://scenes/warband_world.tscn"
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const State = preload("res://scripts/player_state.gd")
const REPORT_NAME := "CoopReport"
const TRAIL_POINT := Vector3(6.0, 0.0, -90.0)
## The two bodies the host's save stands on the trail.
const SQUAD_NAMES := ["Aldous", "Brine"]
## The body a third mercenary brings onto the field while the guest waits for one.
const LATE_NAME := "Bren"
## Whole-run budget: two real world builds and a handful of waits.
const WATCHDOG_SECONDS := 55.0

var checks := 0
var failures := 0
var warband
var state
var flow
var world
var report
var child_pid := -1
var host_save := ""
var client_save := ""
var host_purse := ""
var client_purse := ""
var deadline_ms := 0
var reports: Dictionary = {}
var guest_left := false
## Every failed guest check, carried home in the report so the host's log shows it.
var failed_checks: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		failed_checks.append(message)
		push_error(message)
		print("WARBAND_COOP_CAMPAIGN_FAIL  ", message)

# --- the shared RPC node ---------------------------------------------------

class Report:
	extends Node
	signal submitted(payload: Dictionary)
	signal probe_requested(tag: String)
	signal strike_requested(point: Vector3)
	signal finish_requested()

	@rpc("any_peer", "call_remote", "reliable")
	func submit(payload: Dictionary) -> void:
		submitted.emit(payload)

	@rpc("authority", "call_remote", "reliable")
	func probe(tag: String) -> void:
		probe_requested.emit(tag)

	@rpc("authority", "call_remote", "reliable")
	func strike(point: Vector3) -> void:
		strike_requested.emit(point)

	@rpc("authority", "call_remote", "reliable")
	func finish() -> void:
		finish_requested.emit()

# --- small shared helpers --------------------------------------------------

func _abs(path: String) -> String:
	return path if path.is_absolute_path() else ProjectSettings.globalize_path(path)

func _remove(path: String) -> void:
	if path.is_empty():
		return
	var full := _abs(path)
	if FileAccess.file_exists(full):
		DirAccess.remove_absolute(full)

func _new_temp(tag: String) -> String:
	return OS.get_temp_dir().path_join("warband_coop_%d_%d_%s.json" % [
		OS.get_process_id(), Time.get_ticks_usec(), tag])

func _world_is_ready() -> bool:
	var scene := current_scene
	return scene != null and str(scene.scene_file_path) == WORLD_SCENE \
		and scene.has_method("stats")

## A tip left on the screen from the opening would follow a bodiless soul into
## its first fight: put it away.
func _close_any_card() -> void:
	if world == null or not is_instance_valid(world):
		return
	var tips = world.get("tips")
	if tips != null and is_instance_valid(tips):
		tips.hide()

func _wait_until(predicate: Callable, timeout: float) -> bool:
	var limit := int(timeout * 1000.0)
	if deadline_ms > 0:
		limit = mini(limit, deadline_ms - Time.get_ticks_msec())
	var until := Time.get_ticks_msec() + maxi(limit, 0)
	while Time.get_ticks_msec() < until:
		_close_any_card()
		if bool(predicate.call()):
			return true
		await process_frame
	_close_any_card()
	return bool(predicate.call())

# --- entry -----------------------------------------------------------------

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--coop-client"):
		await _client_run()
	else:
		await _host_run()

# --- host ------------------------------------------------------------------

func _host_run() -> void:
	deadline_ms = Time.get_ticks_msec() + int(WATCHDOG_SECONDS * 1000.0)
	warband = root.get_node_or_null("Warband")
	state = root.get_node_or_null("PlayerState")
	flow = root.get_node_or_null("GameFlow")
	check(warband != null and state != null and flow != null,
		"The Warband, PlayerState and GameFlow autoloads exist")
	if warband == null or state == null or flow == null:
		await _host_done()
		return

	host_save = _new_temp("host_save")
	client_save = _new_temp("client_save")
	host_purse = host_save + ".purse"
	client_purse = client_save + ".purse"
	_remove(host_save)
	_remove(client_save)
	state.save_path = host_purse
	state.reset(false)
	warband.save_path = host_save
	warband.reset_state()
	flow.active = false

	for merc_name in SQUAD_NAMES:
		var merc_id: int = warband.add_mercenary(str(merc_name))
		var equipped: Dictionary = warband.roster.equip(merc_id, "main", "sword_short")
		check(bool(equipped.get("ok", false)),
			"Mercenary %s takes its shortsword" % str(merc_name))
	# A spare on the shelf: the guest's own press is what has to wear it. And one
	# warden's ichor beside it: the guest's press at the altar spends the pool the
	# whole party shares.
	warband.stash.add("sword_arming", 1)
	warband.stash.add("ichor_vial", 1)
	warband.save_checkpoint("trail_start", "trail", TRAIL_POINT, "COOP")
	check(warband.has_checkpoint(), "The host's save holds the trail bookmark")
	check(FileAccess.file_exists(host_save), "The host save was written")
	var host_roster: Array[int] = warband.roster.ids()
	check(host_roster.size() == SQUAD_NAMES.size(), "The save holds the two-body squad (%d)"
		% host_roster.size())

	# The whole session runs over a link that is not instantaneous. Localhost is
	# the one link on which prediction, interpolation and the hitbox rewind can
	# all be wrong and still agree: at 0.1 ms the past and the present are the
	# same frame. 60 ms each way with 20 ms of jitter is a cable or a Tailscale
	# path, and it is the only way this test measures netcode rather than luck.
	# Set before the socket opens, because the session reads it on `setup`, and
	# inherited by the guest process this test spawns.
	OS.set_environment("IRONWOOD_COOP_LAG", "0.06")
	OS.set_environment("IRONWOOD_COOP_JITTER", "0.02")
	# And it loses pose packets, the way a bad link does: the streams marked
	# `lossy` are exactly the ones the wire already sends unreliably (snapshots,
	# the mob stream, missiles, move frames), so a death, a leave or a combat verb
	# is still never thrown away. Loss is what a `stale` copy, a re-sync and a
	# replayed input frame are for; latency alone does not exercise them.
	OS.set_environment("IRONWOOD_COOP_DROP", "0.05")

	var probe := PacketPeerUDP.new()
	check(probe.bind(0) == OK, "The fixture gets an available UDP port")
	var port := probe.get_local_port()
	probe.close()
	if port <= 0:
		await _host_done()
		return

	flow.active = true
	flow.host_campaign(port, "Host", flow.HOST_CHECKPOINT)
	var opened := await _wait_until(func(): return _world_is_ready() and flow.session != null \
		and str(flow.warband_role()) == "host", 25.0)
	check(opened, "HOST GAME opens the campaign world as the host")
	if not opened:
		await _host_done()
		return
	world = current_scene
	_close_any_card()
	check(str(world.get("start_area")) == "checkpoint",
		"The host opens on the saved bookmark (%s)" % str(world.get("start_area")))
	var host_bodies: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(host_bodies.size() == SQUAD_NAMES.size(),
		"The host fields the saved squad (%d)" % host_bodies.size())
	check(flow.session.world == world, "The session is attached to the campaign world")
	check(flow.session.shared_warband, "The campaign session shares one warband")

	report = Report.new()
	report.name = REPORT_NAME
	report.submitted.connect(_store_report)
	root.add_child(report)

	var child_args := PackedStringArray(["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--script", get_script().resource_path,
		"--", "--coop-client", str(port), client_save])
	child_pid = OS.create_process(OS.get_executable_path(), child_args)
	check(child_pid > 0, "The guest process starts")
	if child_pid <= 0:
		await _host_done()
		return

	var joined := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 2, 30.0)
	check(joined, "A real guest process joins the campaign session")
	if not joined:
		await _host_done()
		return
	var guest_peer := _client_peer()
	check(guest_peer > 1, "The host sees the guest's peer id (%d)" % guest_peer)
	if guest_peer <= 1:
		await _host_done()
		return

	# --- one pool between them ---------------------------------------------
	var seated := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, 0)) > 0, 30.0)
	check(seated, "HOST GAME seats the guest in a body")
	if not seated:
		await _host_done()
		return
	var guest_merc := int(flow.session.ownership().get(guest_peer, -1))
	check(guest_merc > 0, "HOST GAME seats the guest in a body (%d)" % guest_merc)
	check(not host_roster.has(guest_merc),
		"and it is not one of the host's mercenaries (%s of %s)" % [
			str(guest_merc), str(host_roster)])
	check(warband.roster.is_player(guest_merc),
		"it is the guest's own character")
	check(warband.roster.name_of(guest_merc) == "Guest",
		"named after the player who joined (%s)" % warband.roster.name_of(guest_merc))
	check(not warband.roster.is_reserve(guest_merc),
		"and on the field whatever the band's cap says")
	check(warband.band_field_count() == SQUAD_NAMES.size(),
		"the recruiter's oath count is untouched (%d)" % warband.band_field_count())
	check(str(warband.roster.equipped_of(guest_merc).get("main", "")) == warband.STARTING_RANGED,
		"their hands hold the pair a new game opens with (%s)" % str(
			warband.roster.equipped_of(guest_merc).get("main", "")))
	check(int(flow.session.ownership().get(1, 0)) > 0
		and int(flow.session.ownership().get(1, 0)) != guest_merc,
		"The host keeps a body of its own")
	var host_merc := int(flow.session.ownership().get(1, -1))
	check(flow.session.controller.body_for_peer(guest_peer) != null,
		"The host's field holds the guest's body")

	# The host's map is one reliable RPC in front of the guest's own controller:
	# wait until the seat has actually landed there before asking that soul to
	# press a key, or the press is made by a spectator with no body.
	report.probe.rpc_id(guest_peer, "seat")
	var guest_ready := await _wait_until(func(): return reports.has("seat") \
		and bool((reports["seat"] as Dictionary).get("own_body", false)), 10.0)
	check(guest_ready, "The guest's own world seats it in the body the host gave it")

	# --- the recruiter's board is the host's -------------------------------
	# A guest plays a lent warband: the board closes on its own page, and the verb
	# behind it refuses even if something presses it.
	check(bool(warband.lent) == false and bool(flow.session.shared_warband),
		"the campaign session shares one warband")
	report.probe.rpc_id(guest_peer, "recruiter")
	var board := await _wait_until(func(): return reports.has("recruiter"), 10.0)
	check(board, "The guest answers for the recruiter's board")
	if board:
		var view: Dictionary = reports["recruiter"]
		check(bool(view.get("hides_hires", false)),
			"and its hire rows are closed to a guest")
		check(not bool(view.get("hired", true)),
			"a hire asked for anyway is refused (%s)" % str(view.get("message", "")))

	# --- the purse moves without the books ---------------------------------
	# A kill's gold changes nothing in the roster or the stash, so it must not cost
	# every guest a whole campaign reload: one number goes out on its own.
	warband.award_gold(37)
	await create_timer(0.4).timeout
	report.probe.rpc_id(guest_peer, "purse")
	var purse_seen := await _wait_until(func(): return reports.has("purse"), 10.0)
	check(purse_seen, "The guest answers for the host's purse")
	if purse_seen:
		check(int((reports["purse"] as Dictionary).get("gold", -1)) == warband.gold(),
			"The guest's purse is the host's (%s vs %s)" % [
				str((reports["purse"] as Dictionary).get("gold", -1)), str(warband.gold())])

	# --- a guest's press wears gear on the host's books --------------------
	# The character screen on a guest is the host's warband: the verb travels as a
	# request, the host runs the same verb on its own books, and the guest sees
	# the result when the copy comes back. The page's slot press only ever puts a
	# piece on - there is no unequip press any more - so this is the equip request
	# and its mirror; here the host checks that the request landed on its books.
	var geared := await _wait_until(func(): return reports.has("gear"), 20.0)
	check(geared, "The guest reports its gear press")
	if geared:
		var data: Dictionary = reports["gear"]
		var geared_merc := int(data.get("merc", 0))
		check(geared_merc == guest_merc and warband.roster.is_player(geared_merc),
			"The guest dressed its own character (%d of %s)" % [
				geared_merc, str(host_roster)])
		check(str(warband.roster.equipped_of(geared_merc).get("main", "")) == "sword_arming",
			"and the host wore the spare on its own books (%s)"
				% str(warband.roster.equipped_of(geared_merc).get("main", "")))
		check(warband.stash.pooled_count("sword_arming") == 0,
			"with the spare off the host's shelf (%d)"
				% warband.stash.pooled_count("sword_arming"))

	# The rest of the test measures the wire, not the wood: a cultist that happens
	# to stand inside its reach would stagger the body between a press and its
	# blow, and the band's own sweep would claim the corpse and the drop before
	# the guest's press. Replicas still snapshot; they just do not think, and the
	# escort holds its ground.
	for guard in world.get("guards"):
		if is_instance_valid(guard):
			guard.set("replica", true)
	var squad = world.get("squad")
	if squad != null:
		squad.following = false
	# The band's own unpossessed bodies keep their errands, and one of those is
	# steel on the ground: an ally walks to a drop and takes it for the stash. The
	# drops below are the guest's own press, so the allies stand well clear first.
	for merc_id in warband.roster.ids():
		if int(merc_id) == host_merc or int(merc_id) == guest_merc:
			continue
		var ally = flow.session.controller.body_of(int(merc_id))
		if ally != null and is_instance_valid(ally):
			(ally as Node3D).global_position += Vector3(0.0, 0.0, 90.0)

	# --- the guest's verbs land on the host's field ------------------------
	# A body the host alone fields stands in front of the guest. The guest
	# presses its own attack, and the host resolves the blow, books the corpse
	# and drops the steel; then the guest's K and its corpse screen take a piece
	# each. This is the whole guest half of the campaign in one pass: an intent
	# becomes a hit, a death becomes a record, and a record becomes a take.
	# The body the host fields for the guest: the guest's own world seated it in
	# the host's warband, and every press below is made from it.
	var combat_actor = flow.session.controller.body_for_peer(guest_peer)
	check(combat_actor != null and is_instance_valid(combat_actor),
		"The guest's body stands before the fight")
	# A new character carries the pair a new game opens with, and its hands hold
	# the bow: the swing below is a sword blow, so the host puts the spare blade in
	# the guest's main hand on its own books. The guest's press is the subject of
	# the check; the hands are the fixture's to set.
	var armed_book: Dictionary = warband.equip_merc(guest_merc, "main", "sword_arming")
	check(bool(armed_book.get("ok", false)),
		"The host puts a blade in the guest's hand (%s)" % str(armed_book.get("message", "")))
	flow.session.controller.refresh_gear(guest_merc)
	flow.session._push_warband(true)
	var steel := await _wait_until(func(): return combat_actor != null \
		and is_instance_valid(combat_actor) \
		and str(combat_actor.rig.weapon) in ["sword", "dual"] \
		and float(combat_actor.combat.attack_progress) >= 0.999, 8.0)
	check(steel, "and the host's copy of its body holds steel and is ready (%s)"
		% str(combat_actor.rig.weapon if is_instance_valid(combat_actor) else "gone"))
	var dummy = null
	var drop = null
	var corpse_id := 0
	if combat_actor != null and is_instance_valid(combat_actor):
		var WatcherScript = load("res://scripts/warband/cage_watcher.gd")
		dummy = WatcherScript.new()
		dummy.name = "CoopDummy"
		dummy.mob_id = "hollow_warden"
		dummy.health_pool = 8.0
		var forward: Vector3 = -(combat_actor as Node3D).global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var point: Vector3 = (combat_actor as Node3D).global_position + forward * 1.5
		dummy.position = point
		world.add_child(dummy)
		dummy.global_position = point
		dummy.set("replica", true)
		# No arm: the only drop near the guest is the piece the host spawns for
		# the K check, so `_nearest_pickup` cannot pick another body's steel.
		dummy.defeated.connect(Callable(world, "_on_enemy_defeated"))
		world.guards.append(dummy)
		# Enough frames for the rewind to hold the body and for the guest's own
		# playout tick to fall inside that history: the guest names the tick it was
		# drawing, which trails the host's newest by the delay it draws remote
		# bodies at (about seven ticks). A body recorded for four frames is a body
		# the guest's blade is judged against before it existed.
		for _beat in 24:
			await physics_frame
		reports.erase("strike")
		report.strike.rpc_id(guest_peer, point + Vector3.UP * 1.2)
		var press_seen := await _wait_until(func(): return reports.has("strike"), 5.0)
		check(press_seen and bool((reports.get("strike", {}) as Dictionary).get("sent", false)),
			"The guest's own press is sent from the body it was given")
		# The tick a guest names is read back by the host against the bodies that
		# guest was looking at. Its clock has to trail the newest snapshot by the
		# delay its own eye draws a remote body at, or every correction is short:
		# a blow that looked landed is refused, a body is hit where it had already
		# stopped being. Left on the clock's default this read 1.5 ticks against
		# the body's 7.2 - a hundred milliseconds of the wrong moment.
		if press_seen:
			var seen: Dictionary = reports.get("strike", {})
			var clock_delay := float(seen.get("clock_delay", -1.0))
			var replica_delay := float(seen.get("replica_delay", -1.0))
			var newest := int(seen.get("newest", -1))
			var view := int(seen.get("view", -1))
			check(replica_delay > 0.0 and absf(clock_delay - replica_delay) < 1.0,
				"The tick a guest names is the tick it draws (%.2f vs %.2f)"
					% [clock_delay, replica_delay])
			check(newest >= 0 and view >= 0 and float(newest - view) >= 5.0,
				"and it trails the newest snapshot by that delay (%d vs %d, %.2f ticks)"
					% [newest, view, clock_delay])
			# The link really was on, both ways: the guest's intents sat in its
			# uplink queue and were released, or this run proves nothing about
			# latency. The host's own count is checked with the same intent.
			# At 60 Hz the press lands about two-thirds of a second in: the town
			# has no warcamp to walk through before the fight now, so the floor
			# only has to prove a steady stream went through the link.
			check(int(seen.get("uplink", 0)) > 30,
				"The guest's intents ran through the simulated link (%d released)"
					% int(seen.get("uplink", 0)))
			# One release per owned body per tick, and the warcamp's guards are
			# gone: the count follows the three bodies the host fields, so the
			# floor is well under the old warband-of-ten number.
			check(int(flow.session._link.released) > 50,
				"The host's poses ran through the simulated link too (%d released)"
					% int(flow.session._link.released))
			# Passing through a queue is not the same as being delayed by it: the
			# hold time is what the game felt.
			var wait := float(flow.session._link.mean_wait())
			check(wait >= 0.06 and wait <= 0.10,
				"The host's poses were held for the delay asked for (%.3f s)" % wait)
			check(int(flow.session._link.discarded) > 0,
				"And the link lost pose packets, as an unreliable one does (%d)"
					% int(flow.session._link.discarded))
			check(float(flow.session._link.drop) > 0.0,
				"with the losses typed: deaths and leaves are reliable and never drop")
		# The swing is a round trip, and a press is only a swing if the host's copy
		# of the body had its blade ready when it landed: the guest predicts its
		# own clock, and under load the two disagree for a beat. A player presses
		# again when the blow does not land; the fixture does the same, up to a few
		# times, rather than pinning the whole check on one frame of luck.
		var struck := false
		for _attempt in 4:
			struck = await _wait_until(func(): return is_instance_valid(dummy) \
				and (not bool(dummy.get("alive")) \
					or float(dummy.get("health")) < float(dummy.get("max_health"))), 2.0)
			if struck:
				break
			for _beat in 30:
				await physics_frame
			reports.erase("strike")
			report.strike.rpc_id(guest_peer, point + Vector3.UP * 1.2)
			await _wait_until(func(): return reports.has("strike"), 3.0)
		check(struck, "The guest's swing reaches the host's field (%s hp)"
			% str(dummy.get("health") if is_instance_valid(dummy) else "gone"))
		if is_instance_valid(dummy) and bool(dummy.get("alive")):
			dummy.take_damage(999.0, 0)
		var vacuum = world.get("loot")
		var bodies := await _wait_until(func(): return vacuum != null \
			and not (vacuum.corpse_ids() as Array).is_empty(), 5.0)
		if bodies:
			corpse_id = int((vacuum.corpse_ids() as Array)[0])
		check(corpse_id > 0, "The guest's kill leaves a body to search")
		# The record goes out reliably, so the guest sees the same body.
		report.probe.rpc_id(guest_peer, "corpse")
		var seen := await _wait_until(func(): return reports.has("corpse"), 10.0)
		check(seen, "The guest's corpse screen lists the host's body")
		if seen:
			check(int((reports["corpse"] as Dictionary).get("corpses", 0)) > 0,
				"The guest imported the corpse record")
		var emptied := await _wait_until(func(): return corpse_id > 0 \
			and not vacuum.has_corpse(corpse_id), 10.0)
		check(emptied, "The guest's take empties the host's body")
		# And a drop on the host's ground is a drop the guest's K can take.
		var at: Vector3 = (combat_actor as Node3D).global_position + Vector3(0.8, 0.0, 0.0)
		drop = world.spawn_pickup("sword_short", at)
		check(drop != null, "The host drops a piece beside the guest")
		# A guest names a point and the point is only a hint: the host takes a drop
		# for a body only when the piece is in *that body's* reach. The guest's
		# replica knows where every drop lies, so without this a modified client
		# names a distant piece at its own position and empties the host's ground.
		var distant_at: Vector3 = at + Vector3(30.0, 0.0, 0.0)
		var distant = world.spawn_pickup("sword_short", distant_at)
		check(distant != null, "The host also drops a piece across the field")
		if distant != null:
			check(not bool(world.loot_for_peer(guest_peer, "drop", 0, "sword_short",
				(distant as Node3D).global_position)),
				"a drop named at its own position but out of the body's reach is refused")
			check(is_instance_valid(distant) and not bool(distant.get("collected")),
				"and that piece stays on the host's ground")
		for _beat in 3:
			await process_frame
		report.probe.rpc_id(guest_peer, "drop")
		var taken := await _wait_until(func(): return drop != null \
			and is_instance_valid(drop) and bool(drop.get("collected")), 10.0)
		check(taken, "The guest's K takes the host's drop")
		# The booking happens on the host, so the guest's own looted list can only
		# be fed from the wire: the list is how a guest reads what the warband is
		# winning, and an empty one for a whole session is the "no loot stream"
		# report.
		var piece_name := str(State.ITEMS.get("sword_short", {}).get("name", "sword_short"))
		var fed := await _wait_until(func(): return world.loot_feed != null \
			and " ".join(world.loot_feed.lines()).to_upper().contains(
				piece_name.to_upper()), 5.0)
		check(fed, "the guest's looted list carries the host's booking (%s)" % str(
			world.loot_feed.lines() if world.loot_feed != null else []))
	# --- the square raises its own, either way round ----------------------
	# A party may fight in the town; that is allowed. What may not happen is a
	# player losing the session to it: a body that goes down on the square's ground
	# is picked up by the other soul's own five seconds, and never bleeds out.
	var host_body = flow.session.controller.body_of(host_merc)
	var host_at: Vector3 = (host_body as Node3D).global_position
	var guest_at: Vector3 = (combat_actor as Node3D).global_position
	var square: Vector3 = world.town.global_position
	(host_body as Node3D).global_position = square + Vector3(-1.0, 0.2, 2.0)
	(combat_actor as Node3D).global_position = square + Vector3(1.0, 0.2, 2.0)
	for _beat in 10:
		await physics_frame
	check(world.town.in_square(host_body) and world.town.in_square(combat_actor),
		"both souls stand on the square's ground")
	# The guest's body goes down: the host holds its revive.
	combat_actor.enter_downed(1)
	check(bool(combat_actor.get("downed")), "a blow puts the guest's body on the floor")
	check(bool(combat_actor.get("home_ground")),
		"and the town marks the ground it fell on as its own")
	var host_channel := bool(world._revive_from(host_body, true))
	check(host_channel, "the host opens a revive on the guest's body")
	var guest_up := await _wait_until(
		func(): return not bool(combat_actor.get("downed")), 8.0)
	check(guest_up, "five seconds of the host's hands stands the guest up")
	# And the other way round: the guest's own G on the host's body.
	host_body.enter_downed(2)
	check(bool(host_body.get("downed")), "the host's body goes down on the square")
	report.probe.rpc_id(guest_peer, "revive")
	var host_up := await _wait_until(func(): return not bool(host_body.get("downed")), 10.0)
	check(host_up, "and the guest's own press stands the host back up")
	check(bool(host_body.get("alive")) and bool(combat_actor.get("alive")),
		"neither soul lost a body to the scrap")
	# Back out to the trail for the rest of the run: the square's rule is the
	# square's, and the road is the campaign's.
	(host_body as Node3D).global_position = host_at
	(combat_actor as Node3D).global_position = guest_at
	for _beat in 10:
		await physics_frame
	check(not world.town.in_square(host_body), "the party is back on the road")

	# --- killing the guest's body with the last one left -------------------
	# A blow on a downed campaign body finishes it. The soul inside is ejected,
	# and with the host's own body the only one left standing, the guest watches.
	var guest_actor = flow.session.controller.body_of(guest_merc)
	var host_actor = flow.session.controller.body_of(host_merc)
	check(guest_actor != null and is_instance_valid(guest_actor), "The guest's body stands")
	check(host_actor != null and is_instance_valid(host_actor), "The host's body stands")
	if guest_actor != null and is_instance_valid(guest_actor) and host_actor != null:
		guest_actor.enter_downed(host_actor.slot)
		guest_actor.take_damage(200.0, host_actor.slot)
		if not bool(guest_actor.get("alive")):
			check(true, "The guest's body is finished")
		else:
			check(false, "The guest's body is finished (%s health, downed %s)"
				% [str(guest_actor.get("health")), str(guest_actor.get("downed"))])
	var ejected := await _wait_until(
		func(): return int(flow.session.ownership().get(guest_peer, -1)) == 0, 15.0)
	check(ejected, "The finished body's soul is let go (%s)"
		% str(flow.session.ownership().get(guest_peer, -1)))
	if not ejected:
		await _host_done()
		return
	check(int(flow.session.ownership().get(1, 0)) == host_merc,
		"The soul already inside the last body keeps it")
	check(host_actor != null and is_instance_valid(host_actor) and bool(host_actor.alive),
		"The last body is still standing with its soul inside")
	check(flow.session.controller.merc_for_peer(guest_peer) <= 0,
		"The host's field no longer seats the guest")
	check(not flow.session.controller.possessing_peers().has(guest_peer),
		"The guest is a watcher on the host's field")

	report.probe.rpc_id(guest_peer, "watch")
	var watch_seen := await _wait_until(func(): return reports.has("watch"), 15.0)
	check(watch_seen, "The guest reports what it is watching")
	if watch_seen:
		var data: Dictionary = reports["watch"]
		check(int(data.get("own_merc", 1)) <= 0,
			"The guest's soul is in no body (%s)" % str(data.get("own_merc")))
		check(int(data.get("watching", -1)) == host_merc,
			"The guest watches the body somebody else is inside (%s)" % str(data.get("watching")))
		check(str(data.get("watching_holder", "")) == "Host",
			"The guest's panel names who has it (%s)" % str(data.get("watching_holder")))
		check(bool(data.get("mission_watch", false)),
			"The guest's panel says it is watching instead of showing a dead soul")
		check(str(data.get("role", "")) == "client" and bool(data.get("lent", false)),
			"The guest is still playing the host's lent warband")
		check(int(data.get("failures", 1)) == 0,
			"The guest's own checks all pass (%d failed): %s"
				% [int(data.get("failures", 1)), str(data.get("failed", []))])

	# --- a name sworn after the guest fell is the host's ally --------------
	# The soul that waits is not owed a mercenary the recruiter hired: the new
	# body stands up as the band's own and nobody is moved into it.
	var late_id: int = warband.add_mercenary(LATE_NAME)
	warband.roster.equip(late_id, "main", "sword_short")
	check(not warband.roster.is_reserve(late_id), "The third name has a place on the field")
	var fielded := await _wait_until(
		func(): return flow.session.controller.body_of(late_id) != null, 5.0)
	check(fielded, "The host's world fields the third body")
	var host_field: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(fielded and host_field.has(flow.session.controller.body_of(late_id)),
		"and wires it with the rest of the band")
	check(warband.roster.has(late_id), "The warband takes a third body (%d)" % late_id)
	for _beat in 30:
		await physics_frame
	check(int(flow.session.ownership().get(guest_peer, 0)) == 0,
		"the waiting soul is not handed the band's new body (%s)"
			% str(flow.session.ownership().get(guest_peer, 0)))
	check(warband.souls.occupied_by(late_id) == 0,
		"the new body is the squad's own (%d)" % warband.souls.occupied_by(late_id))
	check(int(flow.session.ownership().get(1, 0)) == host_merc,
		"The host was never moved out of its body")
	report.probe.rpc_id(guest_peer, "late")
	var late_seen := await _wait_until(func(): return reports.has("late"), 15.0)
	check(late_seen, "The guest reports the field it is watching")
	if late_seen:
		var late: Dictionary = reports["late"]
		check(int(late.get("own_merc", 1)) <= 0,
			"The guest's soul is still in no body (%s)" % str(late.get("own_merc")))
		check(bool(late.get("fields_late", false)),
			"and its world stands the host's new body up as a replica")

	# --- the guest leaves, its own campaign comes back ---------------------
	report.finish.rpc_id(guest_peer)
	var left := await _wait_until(
		func(): return flow.session != null and flow.session.peer_count() == 1, 20.0)
	check(left, "The host is alone again after the guest leaves")
	if left and flow.session != null and flow.session.controller != null:
		check(not flow.session.connected_peers().has(guest_peer),
			"The departed peer is gone from the session")
		var freed := await _wait_until(
			func(): return flow.session == null or flow.session.controller == null \
				or flow.session.controller.body_for_peer(guest_peer) == null, 5.0)
		check(freed, "The departed guest no longer owns a body on the host")
		check(warband.souls.occupied_by(late_id) == 0, "The router frees the departed body")
		check(warband.roster.has(late_id), "The host's warband keeps the body it took on")
	await _host_done()

func _client_peer() -> int:
	if flow == null or flow.session == null:
		return 0
	for peer_id in flow.session.connected_peers():
		if int(peer_id) != 1:
			return int(peer_id)
	return 0

func _store_report(payload: Dictionary) -> void:
	var tag := str(payload.get("tag", payload.get("kind", "report")))
	reports[tag] = payload
	if str(payload.get("kind", "")) == "error":
		print("WARBAND_COOP_CLIENT_ERROR  ", str(payload.get("detail", "")), "  (tag=", tag, ")")

func _host_done() -> void:
	if child_pid > 0:
		var grace := Time.get_ticks_msec() + 1500
		while OS.is_process_running(child_pid) and Time.get_ticks_msec() < grace:
			await create_timer(0.05).timeout
		if OS.is_process_running(child_pid):
			OS.kill(child_pid)
			var reaped := Time.get_ticks_msec() + 2000
			while OS.is_process_running(child_pid) and Time.get_ticks_msec() < reaped:
				await create_timer(0.05).timeout
	if flow != null and flow.session != null:
		flow.leave_warband()
	if current_scene != null:
		current_scene.queue_free()
	_remove(host_save)
	_remove(client_save)
	_remove(host_purse)
	_remove(client_purse)
	await process_frame
	print("WARBAND_COOP_CAMPAIGN_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- client ----------------------------------------------------------------

func _client_run() -> void:
	deadline_ms = Time.get_ticks_msec() + int((WATCHDOG_SECONDS - 4.0) * 1000.0)
	var args := OS.get_cmdline_user_args()
	var index := args.find("--coop-client")
	check(index >= 0 and args.size() >= index + 2, "The guest leg was given a port and a save path")
	if index < 0 or args.size() < index + 2:
		quit(1)
		return
	var port := int(args[index + 1])
	client_save = args[index + 2]
	client_purse = client_save + ".purse"
	warband = root.get_node_or_null("Warband")
	state = root.get_node_or_null("PlayerState")
	flow = root.get_node_or_null("GameFlow")
	check(warband != null and state != null and flow != null,
		"The guest's autoloads exist")
	if warband == null or state == null or flow == null:
		quit(1)
		return

	# A campaign of its own, on disk: the guest must get exactly this back.
	state.save_path = client_purse
	state.reset(false)
	warband.save_path = client_save
	warband.reset_state()
	warband.add_mercenary("Own Man")
	warband.save_state()
	check(FileAccess.file_exists(client_save), "The guest's own campaign was written")
	var own_text := FileAccess.get_file_as_string(client_save)

	flow.active = true
	flow.join_campaign("127.0.0.1", port, "Guest")

	report = Report.new()
	report.name = REPORT_NAME
	report.probe_requested.connect(_on_probe)
	report.strike_requested.connect(_on_strike)
	report.finish_requested.connect(_on_finish)
	root.add_child(report)

	var opened := await _wait_until(func(): return _world_is_ready(), 25.0)
	check(opened, "The guest's campaign world opens on the host's warband")
	if not opened:
		_submit({"kind": "error", "tag": "fatal", "detail": "the world never opened"})
		await _client_done(1)
		return
	world = current_scene
	_close_any_card()

	check(str(flow.warband_role()) == "client", "The guest reports the client role (%s)"
		% str(flow.warband_role()))
	check(str(world.get("start_area")) == "guest", "The guest opens as a guest (%s)"
		% str(world.get("start_area")))
	check(bool(warband.lent), "The guest plays the host's lent warband")
	check(warband.roster.count() >= SQUAD_NAMES.size(),
		"The guest fields the host's roster (%d)" % warband.roster.count())
	check(FileAccess.get_file_as_string(client_save) == own_text,
		"The borrowed warband never touches the guest's own save")
	var bodies: Array = world.get("bodies") if world.get("bodies") is Array else []
	check(bodies.size() >= SQUAD_NAMES.size(),
		"The guest fields the host's bodies (%d)" % bodies.size())
	var guest_guards: Array = world.get("guards") if world.get("guards") is Array else []
	# The town seeds no mobs of its own and the wire never invents one, so an
	# empty list is the right answer here; what must never stand on a guest is a
	# mob that runs its own brain.
	var all_replicas := true
	for guard in guest_guards:
		if not bool(guard.get("replica")):
			all_replicas = false
	check(all_replicas, "Every mob the guest fields is a replica (%d)" % guest_guards.size())

	var seated := await _wait_until(func(): return _own_merc() > 0, 25.0)
	check(seated, "The host seats the guest's soul in a body (%s)" % str(_own_merc()))
	if not seated:
		_submit({"kind": "error", "tag": "seat", "detail": "no body after the host's map: %s"
			% str(_probe_payload("seat"))})
		await _client_done(1)
		return
	check(_own_merc() != -1 and int(flow.session.ownership().get(_own_peer(), 0)) == _own_merc(),
		"The guest's map agrees with its own body")

	# --- the guest's own gear press wears the host's spare ------------------
	# Driven the way a player drives it: open the character screen, click the worn
	# main slot for the pieces the warband owns and choose the spare. On a lent copy
	# the press is a request; the piece moves when the host's copy comes back.
	var gear_merc := _own_merc()
	var worn_before := str(warband.roster.equipped_of(gear_merc).get("main", ""))
	check(worn_before != "sword_arming" and warband.stash.pooled_count("sword_arming") == 1,
		"The guest sees the host's spare on the shelf (%d)" % warband.stash.pooled_count("sword_arming"))
	var doll = DollScript.new()
	doll.name = "GuestDoll"
	root.add_child(doll)
	doll.configure(warband)
	doll.open(gear_merc)
	await process_frame
	doll.open_slot_menu("main")
	var spare_row: Variant = null
	for child in doll._menu_rows.get_children():
		if str(child.get_meta("item_id", "")) == "sword_arming":
			spare_row = child
	check(spare_row is Button, "the guest's gear page lists the spare blade")
	if spare_row is Button:
		(spare_row as Button).pressed.emit()
	check(str(warband.roster.equipped_of(gear_merc).get("main", "")) == worn_before,
		"and the press does not change the lent copy by itself (%s)" % doll.status_text())
	var worn := await _wait_until(func(): return str(
		warband.roster.equipped_of(gear_merc).get("main", "")) == "sword_arming", 12.0)
	check(worn, "The host's answer wears the piece on the guest's copy (%s) after [%s]" % [
		str(warband.roster.equipped_of(gear_merc).get("main", "")), doll.status_text()])
	check(str(flow.session.controller.seat_loadout(gear_merc).get("main", "")) == "sword_arming",
		"and the guest's own body wears it (%s)" % str(
			flow.session.controller.seat_loadout(gear_merc).get("main", "")))
	doll.close()
	_submit({"kind": "gear", "tag": "gear", "merc": gear_merc,
		"worn": str(warband.roster.equipped_of(gear_merc).get("main", ""))})

	var told := await _wait_until(func(): return guest_left, int((WATCHDOG_SECONDS - 30.0) * 1000.0))
	if not told:
		_submit({"kind": "error", "tag": "finish", "detail": "the host never dismissed the guest"})
	await _client_done(0 if told else 1)

func _own_peer() -> int:
	var id := root.multiplayer.get_unique_id()
	return id if id > 0 else 1

func _own_merc() -> int:
	if world == null or flow == null or flow.session == null or flow.session.controller == null:
		return -1
	return int(flow.session.controller.merc_for_peer(_own_peer()))

func _watching_merc() -> int:
	var body = flow.session.controller.watching() if flow.session != null \
		and flow.session.controller != null else null
	if body == null or not is_instance_valid(body):
		return -1
	return int(flow.session.controller.merc_of(body))

func _on_probe(tag: String) -> void:
	if world == null or not is_instance_valid(world):
		_submit({"kind": "error", "tag": tag, "detail": "the guest has no world"})
		return
	if tag == "watch" or tag == "seat":
		# The map that took this soul's body away has just landed; the eye and the
		# body panel settle on the next physics frame, so the report is read after
		# a couple of them rather than on the frame the map arrived.
		for _beat in 4:
			await physics_frame
		await process_frame
	elif tag == "late":
		# The band's new body arrives with the host's warband copy and its
		# snapshots, on their own clocks: the report waits for the replica.
		var late_merc := -1
		for merc_id in warband.roster.ids():
			if warband.roster.name_of(int(merc_id)) == LATE_NAME:
				late_merc = int(merc_id)
		await _wait_until(func(): return late_merc <= 0 or flow.session == null \
			or flow.session.controller == null \
			or flow.session.controller.body_of(late_merc) != null, 5.0)
		var late_payload := _probe_payload(tag)
		late_payload["fields_late"] = late_merc > 0 and flow.session != null \
			and flow.session.controller != null \
			and flow.session.controller.body_of(late_merc) != null
		_submit(late_payload)
		return
	elif tag == "revive":
		# The guest's own G, held: the scene's revive verb through the intent
		# channel, exactly as the key press runs it.
		var controls = flow.session.controller if flow.session != null else null
		if controls == null or controls.active_actor == null:
			_submit({"kind": "probe", "tag": tag, "opened": false})
			return
		var opened := bool(controls.act("revive", true))
		_submit({"kind": "probe", "tag": tag, "opened": opened})
		return
	elif tag == "recruiter":
		# The warband screen is a local page; the board on it is the host's. Read
		# what a guest's page shows, and press the verb behind it anyway.
		var page = world.get("screen")
		if page == null:
			_submit({"kind": "probe", "tag": tag, "hides_hires": false})
			return
		page.open()
		await process_frame
		var rows_hidden := true
		for hire_row in page._hire_rows:
			if (hire_row["root"] as Node).visible:
				rows_hidden = false
		var hire: Dictionary = warband.hire(warband.town_board()[0])
		_submit({"kind": "probe", "tag": tag, "hides_hires": rows_hidden,
			"hired": bool(hire.get("ok", false)),
			"message": str(hire.get("message", ""))})
		page.close()
		return
	elif tag == "corpse":
		# The record is a reliable RPC behind the kill's snapshot: wait for it, then
		# take the lot through the same intent a row click sends.
		var vacuum = world.get("loot")
		await _wait_until(func(): return vacuum != null \
			and not (vacuum.corpse_ids() as Array).is_empty(), 5.0)
		var ids: Array = vacuum.corpse_ids() if vacuum != null else []
		if ids.is_empty():
			_submit({"kind": "probe", "tag": tag, "corpses": 0})
			return
		world.call("request_loot_take", int(ids[0]), "", Vector3.ZERO, true)
		_submit({"kind": "probe", "tag": tag, "corpses": ids.size(),
			"corpse": int(ids[0])})
		return
	elif tag == "drop":
		# The host's K test: the guest's own hand on its own world's drop, which
		# travels as an intent and is booked on the other machine. The drop is
		# announced on the host's loot poll, so wait for the copy to land here and
		# take the piece the test named, not whatever else happens to lie nearer.
		var arrived := await _wait_until(func(): return _find_drop("sword_short") != null, 5.0)
		if arrived:
			world.call("_try_loot")
		_submit({"kind": "probe", "tag": tag, "near": arrived})
		return
	_submit(_probe_payload(tag))


## The guest's own copy of a named drop, or null while it has not landed yet.
func _find_drop(item_id: String):
	var vacuum = world.get("loot") if world != null else null
	if vacuum == null:
		return null
	for pickup in vacuum.pickups():
		if is_instance_valid(pickup) and not bool(pickup.get("collected")) \
				and str(pickup.get("item_id")) == item_id:
			return pickup
	return null


## A swing the host asked the guest's body for: the owning peer presses its own
## attack with the aim point the host chose.
func _on_strike(point: Vector3) -> void:
	if flow == null or flow.session == null or flow.session.controller == null:
		return
	var controller = flow.session.controller
	var actor = controller.active_actor
	var sent := false
	if actor != null:
		# A swing in flight refuses the next one, and the host would see a press
		# that never became a blade. The player presses when the hands are ready;
		# the fixture waits for the same moment rather than guessing a delay.
		for _beat in 90:
			if float(actor.combat.attack_progress) >= 0.999:
				break
			await physics_frame
		sent = controller.act("melee", {"aim": point, "hand": "right",
			"variant": "overhead"})
	# What the host is about to rewind against, from the guest's own books: the
	# clock that answers `view_tick()` and the delay a remote body is really
	# drawn at. They have to be the same number or the blow is judged against a
	# moment nobody was looking at.
	var replica = controller.body_for_peer(1)
	var replica_delay := -1.0
	if replica != null and is_instance_valid(replica):
		var timeline = replica.get("_timeline")
		if timeline != null:
			replica_delay = float(timeline.floor_delay_ticks)
	_submit({"kind": "strike", "tag": "strike", "actor": actor != null,
		"sent": sent, "view": controller.view_tick(),
		"newest": int(controller._clock.newest_tick()),
		"clock_delay": float(controller._clock.timeline.floor_delay_ticks),
		"replica_delay": replica_delay,
		"uplink": int(controller.sync._link.released),
		"owned": int(controller.merc_for_peer(controller.local_peer_id)),
		"active": int(controller.merc_of(actor)) if actor != null else -1})

func _probe_payload(tag: String) -> Dictionary:
	var controller = flow.session.controller if flow.session != null else null
	var watching := _watching_merc()
	var holder := ""
	var lines: Array[String] = []
	var hud = world.get("hud")
	if hud != null and is_instance_valid(hud):
		if hud.has_method("body_lines"):
			lines = hud.body_lines()
		if controller != null:
			holder = str(flow.session.name_of(controller.watched_peer()))
	return {
		"kind": "probe",
		"tag": tag,
		"role": str(flow.warband_role()) if flow != null else "",
		"start_area": str(world.get("start_area")),
		"lent": bool(warband.lent) if warband != null else false,
		"roster": warband.roster.count() if warband != null else -1,
		"own_merc": _own_merc(),
		"own_body": _own_merc() > 0 and controller != null and controller.body_of(_own_merc()) != null,
		"watching": watching,
		"watching_holder": holder,
		"mission_watch": lines.size() >= 2 and String(lines[1]).contains("no body is free"),
		"body_lines": lines,
		"gold": warband.gold() if warband != null else -1,
		"failed": failed_checks,
	}

func _on_finish() -> void:
	guest_left = true
	if flow != null:
		flow.leave_warband()

func _submit(payload: Dictionary) -> void:
	if report == null or not is_instance_valid(report):
		return
	payload["checks"] = checks
	payload["failures"] = failures
	report.submit.rpc_id(1, payload)

func _client_done(code: int) -> void:
	# The session is over: the guest's own campaign must be the one it wrote.
	if warband != null and not flow.session:
		check(not bool(warband.lent), "The loan ends with the session")
		check(warband.roster.count() == 1 and warband.roster.name_of(warband.roster.ids()[0]) == "Own Man",
			"The guest's own campaign comes back (%d bodies)" % warband.roster.count())
	_submit({"kind": "done", "tag": "done"})
	await process_frame
	if flow != null and flow.session != null:
		flow.leave_warband()
	_remove(client_purse)
	await process_frame
	quit(code if failures == 0 else 1)
