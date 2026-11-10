extends SceneTree
## The arena: a mirrored warband in a chamber of the Weeping Hollow, three tiers
## of it.
##
## What this owns: the door in the square, the room drawn out of the delve's own
## plan for this bout and cut out of it whole, the field moved into that chamber,
## every way out of it shut, three foes built out of the three tiers' kits, the AI
## closing the distance, a win that pays the purse, and the return that puts every
## body back where it stood.

const WORLD = "res://scenes/warband_world.tscn"
const ArenaCaveScript = preload("res://scripts/warband/arena_cave.gd")
const DelveLayout = preload("res://scripts/warband/delve_layout.gd")
const TEST_SAVE := "user://arena_regression_state.json"
const WARBAND_SAVE := "user://arena_regression_warband.json"

var game
var arena
var warband
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ARENA_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	flow.active = false
	flow.world_start = "town"

	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var waited := 0.0
	while waited < 30.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	check(game.bodies.size() >= 1, "the town stands the warband up (%d bodies)" % game.bodies.size())

	arena = game.get("arena")
	check(arena != null, "the world owns a ring")
	if arena == null:
		_finish()
		return

	# The door: a service in the square, with a point a body can walk to.
	var point: Vector3 = game.town.service_point("arena")
	check(point != Vector3.ZERO, "the square has an arena gate")
	check(game.town.service_at(point) == "arena", "and the gate resolves as its own service")

	await _check_tiers()
	await _check_draw()
	await _check_fight()
	_finish()


## The three tier's kits, on the bodies the chamber builds.
func _check_tiers() -> void:
	for tier in ["easy", "medium", "hard"]:
		check(arena.set_difficulty(tier), "the arena takes the %s tier" % tier)
		check(arena.difficulty == tier, "and remembers it (%s)" % arena.difficulty)
	check(not arena.set_difficulty("brutal"), "a tier the arena does not have is refused")
	arena.set_difficulty("hard")
	check(arena.difficulty == "hard", "a refusal leaves the tier where it was")
	await physics_frame


## The draw: which rooms the Hollow lends the arena, and that a bout never gets the
## one the last bout was fought in.
func _check_draw() -> void:
	var ids: Array = ArenaCaveScript.room_ids()
	check(ids.size() >= 20, "the Hollow lends the arena %d rooms" % ids.size())
	var wrong: Array = []
	for id in ids:
		var room: Dictionary = DelveLayout.room(str(id))
		if room.is_empty() or bool(room.get("tunnel", false)):
			wrong.append("%s is no hall" % str(id))
			continue
		var rect: Rect2 = room["rect"]
		if minf(rect.size.x, rect.size.y) < ArenaCaveScript.MIN_SIDE:
			wrong.append("%s is %dx%d m" % [str(id), roundi(rect.size.x), roundi(rect.size.y)])
	check(wrong.is_empty(), "every room lent to the arena is a hall wide enough to fight in (%s)"
		% str(wrong))
	for hall in ["den", "gallery", "ossuary", "chapel", "mere", "garden", "lair"]:
		check(ids.has(hall), "the draw holds %s" % hall)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var seen := {}
	var repeats := 0
	var unknown: Array = []
	var previous := ""
	for draw in 60:
		var picked := ArenaCaveScript.pick_room(rng, previous)
		if not ids.has(picked):
			unknown.append(picked)
		if picked == previous:
			repeats += 1
		seen[picked] = true
		previous = picked
	check(unknown.is_empty(), "the draw only ever picks a room of the plan (%s)" % str(unknown))
	check(repeats == 0, "no bout is fought in the room the last one was (%d repeats)" % repeats)
	check(seen.size() >= 6, "the draw moves through the plan (%d rooms in 60)" % seen.size())

	# The gate's own board: the press that starts a bout, and the room it names.
	var gate: Vector3 = game.town.service_point("arena")
	check(game.town.interact_at(1, gate) == "arena", "G at the gate opens the arena's page")
	var board = game.town.arena_menu
	check(board != null, "the gate has a board in the campaign")
	if board != null:
		check(board.is_open(), "and it is open")
		var named := str(arena.room_label())
		check(not named.is_empty(), "the board draws a chamber for the bout (%s)" % named)
		check(str(board._status.text).find(named) >= 0,
			"and names it (%s)" % str(board._status.text))
		board.close()
		check(not board.is_open(), "and it closes again")
	await physics_frame


## One whole fight: the party walks in, the foes come at it, and it ends.
func _check_fight() -> void:
	var party_before: Array = game.bodies.duplicate()
	var spots: Dictionary = {}
	for body in party_before:
		spots[body] = body.global_position
	var gold_before: int = warband.gold()

	arena.set_difficulty("easy")
	var result: Dictionary = arena.enter("easy")
	check(bool(result.get("ok", false)), "the arena opens (%s)" % str(result.get("message", "")))
	check(arena.active, "and it is holding a fight")
	check(arena.foes.size() == 3, "three foes stand across it (%d)" % arena.foes.size())
	check(arena.party.size() == party_before.size(),
		"the whole field walks in (%d of %d)" % [arena.party.size(), party_before.size()])
	var in_ring := true
	for body in arena.party:
		if body.global_position.y < 100.0:
			in_ring = false
	check(in_ring, "every body stands in the chamber, not in the square")
	check(arena.foes_standing() == 3, "nobody is down at the bell")

	# The chamber: one room of the Hollow's own plan, drawn for this bout.
	var cave = arena.cave
	check(cave != null and is_instance_valid(cave), "the chamber is built")
	check(ArenaCaveScript.room_ids().has(arena.room_id),
		"the bout is fought in a room of the plan (%s)" % str(arena.room_id))
	check(not str(arena.room_label()).is_empty(),
		"and the HUD has its name (%s)" % str(arena.room_label()))
	if cave == null:
		_finish()
		return
	var box: AABB = cave.bounds()
	check(box.size.x > 10.0 and box.size.y > 4.0 and box.size.z > 10.0,
		"the chamber is a room, not a corridor (%s)" % str(box.size))
	check(cave.light_count() > 0, "the room keeps its own light (%d lamps)" % cave.light_count())
	var stood := 0
	for body in arena.party:
		if cave.contains(body.global_position):
			stood += 1
	check(stood == arena.party.size(), "the party stands inside the room (%d of %d)"
		% [stood, arena.party.size()])
	var across := 0
	for foe in arena.foes:
		if cave.contains(foe.global_position):
			across += 1
	check(across == arena.foes.size(), "and the foes stand in it too (%d of %d)"
		% [across, arena.foes.size()])
	check(game.camera.environment == cave.environment,
		"the eye takes the cave's own air while the fight holds")
	var suns := 0
	for node in game.find_children("*", "DirectionalLight3D", true, false):
		if (node as DirectionalLight3D).visible:
			suns += 1
	check(suns == 0, "the world's suns are out while the eye is in the rock (%d lit)" % suns)

	# The two lines: the party at the near end of the room and the foes at the far
	# one, so the fight is a crossing.
	await physics_frame
	var party_mid := Vector3.ZERO
	for body in arena.party:
		party_mid += body.global_position
	party_mid /= float(maxi(1, arena.party.size()))
	var foe_mid := Vector3.ZERO
	for foe in arena.foes:
		foe_mid += foe.global_position
	foe_mid /= float(maxi(1, arena.foes.size()))
	var centre: Vector3 = box.position + box.size * 0.5
	check(party_mid.distance_to(foe_mid) > 6.0, "the two lines stand apart (%.1f m)"
		% party_mid.distance_to(foe_mid))
	check(party_mid.distance_to(centre) < box.size.length() * 0.5
		and foe_mid.distance_to(centre) < box.size.length() * 0.5,
		"and both stand inside the room's own footprint")

	# Every way out of the room the plan cut is shut with rock: a line walked out of
	# the middle of the chamber through an opening meets the rock that closed it, and
	# never gets out past it.
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var ways: Array = cave.doorways()
	var shut := 0
	for way in ways:
		var at: Vector3 = way["at"]
		var from := Vector3(centre.x, party_mid.y + 0.9, centre.z)
		var out := Vector3(at.x - centre.x, 0.0, at.z - centre.z).normalized()
		var to := Vector3(at.x, from.y, at.z) + out * 3.0
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty() and hit["position"].distance_to(from) <= from.distance_to(to) + 0.5:
			shut += 1
	check(not ways.is_empty(), "the room has ways out to shut (%d)" % ways.size())
	check(shut == ways.size(), "every one of them is shut with rock (%d of %d)"
		% [shut, ways.size()])

	# The kit is the tier's: makeshift steel and no anoint on easy.
	for foe in arena.foes:
		var main_id := str(foe.rig.get("main_id") if foe.rig.get("main_id") != null else "")
		check(not bool(foe.get("downed")) and bool(foe.get("alive")), "a foe stands at the bell")
		check(str(foe.rig.weapon) in ["sword", "dagger", "bow"],
			"a foe holds a weapon (%s)" % str(foe.rig.weapon))
	var easy_mains: Array = []
	for foe in arena.foes:
		easy_mains.append(str(foe.rig.main_item_id()) if foe.rig.has_method("main_item_id") else "")
	check(not easy_mains.is_empty(), "the foes' hands are readable")

	# The AI closes: a foe that never walks is a statue with a sword.
	var start: Array = []
	for foe in arena.foes:
		start.append(foe.global_position)
	for frame in 90:
		await physics_frame
	var closed := 0
	for index in arena.foes.size():
		var foe = arena.foes[index]
		if is_instance_valid(foe) and foe.global_position.distance_to(start[index]) > 1.5:
			closed += 1
	check(closed >= 2, "the foes come at the band (%d of 3 moved)" % closed)

	# A finished fight: every foe down is a win, and a win pays.
	for foe in arena.foes:
		if is_instance_valid(foe):
			foe.take_damage(900.0, 99)
	for frame in 5:
		await physics_frame
	check(arena.foes_standing() == 0, "the chamber is empty of foes (%d)" % arena.foes_standing())
	check(arena.finished == "won", "and the fight is won (%s)" % arena.finished)
	check(warband.gold() == gold_before + int(arena.PURSE.get("easy", 0)),
		"the win pays the easy purse (%d -> %d)" % [gold_before, warband.gold()])

	# The gate lets the party out, and every body stands where it stood.
	check(arena.try_leave(), "the gate takes the press")
	await physics_frame
	await physics_frame
	check(not arena.active, "the pit is closed")
	check(arena.foes.is_empty(), "and no foe is left in it")
	check(arena.cave == null, "and the chamber is torn down after it")
	check(game.camera.environment == null, "the eye is back under the world's own sky")
	var relit := 0
	for node in game.find_children("*", "DirectionalLight3D", true, false):
		if (node as DirectionalLight3D).visible:
			relit += 1
	check(relit > 0, "and the world's suns are lit again (%d)" % relit)
	var back := 0
	for body in party_before:
		if is_instance_valid(body) and body.global_position.distance_to(spots[body]) < 1.0:
			back += 1
	check(back == party_before.size(),
		"every body is back where it stood (%d of %d)" % [back, party_before.size()])


func _finish() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("ARENA_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
