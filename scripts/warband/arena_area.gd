extends Node3D
## GHOST OF THE WARBAND: the arena, and the warband it puts in the ring with you.
##
## The third door out of Hearthstead, and the only one that is a *fight* and
## nothing else. `enter()` cuts one chamber of the Weeping Hollow out of the
## delve's own floor plan (`arena_cave.gd`), stands it far above the campaign's
## ground, moves the whole field into it and stands a mirrored warband on the far
## arc: the same bodies, the same ten slots, the same skills - a tank, a blade and
## a bow, dressed to the difficulty and driven by the same honest rules a
## squadmate is.
##
## **The chamber is drawn, not authored.** Every hall the Hollow is dug from can
## host a bout - the watchers' den, the drowned gallery, the ossuary, the pale
## garden, the black mere, the bone chapel, the rooted hall, the old workings, the
## demons' ring, Gorehorn's lair - and `ArenaCave.pick_room` draws a different one
## for each fight, never the one the last bout was fought in. The room comes with
## its own ground, rock, dripstone, lights and props, exactly as the delve builds
## it, and every way out of it is shut: a fight is a room with no way past.
##
## **Three tiers, three different fights.**
##
##   * **EASY** - makeshift steel and rags: clubs, a wooden shield, no anoint at
##     all. The AI closes in a straight line, swings on a long beat and almost
##     never guards.
##   * **MEDIUM** - leather and mail, real blades and a proper bow, one anointed
##     piece between the three. It guards on half its exchanges, holds a beat
##     before it swings and steps off the line, and the bow works the range it
##     wants instead of standing.
##   * **HARD** - plate, greatswords and a longbow, an annointed piece on every
##     body. It guards most exchanges, leads its swings at where the body is
##     going, casts what its steel knows and never stands still for free.
##
## Nothing here is a quest and nothing is gated: the ring is a place a warband
## walks into to find out whether its gear and its hands are good enough, and the
## purse it can make is the only thing it keeps.
##
## How a foe fights is not this file's: the ladder - close, guard, step off the
## line, swing into the beat - is `duel_brain.gd`, and the Hollow's own demon
## lords fight on the same one. This scene only dresses the bodies, hands the
## ladder its tier and writes the answer into the foe's hands.

const CaveScript = preload("res://scripts/warband/arena_cave.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const WarbandLooks = preload("res://scripts/warband/warband_looks.gd")
const DuelBrainScript = preload("res://scripts/warband/duel_brain.gd")
const VoiceLibrary = preload("res://scripts/audio/voice_library.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

const DIFFICULTIES := ["easy", "medium", "hard"]
const DEFAULT_DIFFICULTY := "easy"

## What the three foes are: a tank, a blade and a bow, in that order.
const ROLES := ["tank", "melee", "bow"]

## The three kits. `armor` is an `ArmorData.SET_IDS` entry worn on every slot the
## set has; `annoints` says how many ability welds the body's main hand carries.
const KITS := {
	"easy": [
		{"main": "club_makeshift", "off": "shield_wood", "armor": "makeshift", "annoints": 0},
		{"main": "dagger_ironwood", "off": "", "armor": "makeshift", "annoints": 0},
		{"main": "dagger_ironwood", "off": "", "armor": "makeshift", "annoints": 0},
	],
	"medium": [
		{"main": "sword_arming", "off": "shield_buckler", "armor": "mail", "annoints": 1},
		{"main": "dagger_iron", "off": "sword_short", "armor": "leather", "annoints": 0},
		{"main": "bow_short", "off": "", "armor": "leather", "annoints": 0},
	],
	"hard": [
		{"main": "sword_great", "off": "", "armor": "plate", "annoints": 2},
		{"main": "sword_short", "off": "dagger_iron", "armor": "plate", "annoints": 1},
		{"main": "bow_long", "off": "", "armor": "mail", "annoints": 1},
	],
}

## How each tier behaves. `guard` is the share of exchanges a body raises its
## guard on, `beat` the pause it holds before a swing, `step` the seconds it
## spends circling between blows, `lead` how far it aims ahead of a moving body,
## `range` where it stops closing. These are the numbers `duel_brain.gd` fights
## on; a temper without `window` swings on its beat alone, which is the pit's own
## rule - only the Hollow's duelists wait for an opening.
const TEMPER = {
	"easy": {"guard": 0.15, "beat": 0.85, "step": 0.35, "lead": 0.0, "range": 1.6},
	"medium": {"guard": 0.5, "beat": 0.45, "step": 0.6, "lead": 0.35, "range": 2.4},
	"hard": {"guard": 0.85, "beat": 0.15, "step": 0.85, "lead": 0.8, "range": 3.2},
}

## The purse a win pays, by tier.
const PURSE := {"easy": 40, "medium": 120, "hard": 300}

var host = null
var active := false
var finished := ""
var difficulty := DEFAULT_DIFFICULTY
var foes: Array = []
var party: Array = []
## The chamber this bout is fought in (`ArenaCave`, null when no fight holds).
var cave = null
## The room the last chamber was cut from (`Layout.ROOMS` id): the next bout is
## never fought in it while there is another room to draw.
var room_id := ""
## What the HUD calls the last chamber (`THE OSSUARY`), kept across the fight.
var _room_label := ""
## `{body: {position, bounds, mask}}` for the field as it was before the chamber.
var _saved: Dictionary = {}
## `{foe: DuelBrain}` - each foe's own clock inside the fight's ladder.
var _tracks: Dictionary = {}
## The squad's own hostile list as it was before the chamber borrowed it.
var _squad_watchers = null
## The squad's own map as it was before the chamber lent it the room's
## (`arena_cave.gd`): the room's colliders, not the wood's ground.
var _nav_before = null
## Whether the map was lent at all - a squad with no map keeps none.
var _nav_lent := false
## `[light, was_visible]` for every directional light of the world's, so the sun
## and moon can be put out for the fight and put back as they were.
var _sun_states: Array = []
## The dice the chamber is drawn from: a fresh room, and its growth, every bout.
var _draw := RandomNumberGenerator.new()
var _clock := 0.0


func setup(world: Node3D) -> void:
	host = world
	_draw.randomize()


func is_open() -> bool:
	return active


## What the HUD calls the place the fight is held: `THE OSSUARY`, `THE DEN`. The
## last chamber's name stays after the fight is over, so the board can say where
## the band has just been.
func room_label() -> String:
	return _room_label


## Which difficulty the ring will be fought on. Unknown words are refused.
func set_difficulty(tier: String) -> bool:
	if not DIFFICULTIES.has(tier):
		return false
	difficulty = tier
	return true


## Walk the field into the chamber. The whole field goes: a demo that let a player
## leave two bodies at the gate would be a fight the warband wins with a roster
## the chamber never sees.
func enter(tier: String = "") -> Dictionary:
	if active:
		return {"ok": false, "message": "The arena is already holding a fight."}
	if host == null:
		return {"ok": false, "message": "The arena needs a campaign."}
	if not tier.is_empty():
		set_difficulty(tier)
	var built := _collect_party()
	if built.is_empty():
		return {"ok": false, "message": "No body to put in the arena."}
	if not _build_chamber():
		return {"ok": false, "message": "The Hollow has no room to fight in."}
	_party_into_chamber(built)
	_foes_into_chamber()
	_lend_the_squad()
	active = true
	_sync_eye(true)
	finished = ""
	_clock = 0.0
	if host.hud != null:
		host.hud.set_status("THE ARENA  ·  %s  ·  %s  ·  the gate is G when it is over" % [
			room_label(), difficulty.to_upper()], 4.0)
	return {"ok": true, "message": "The chamber holds %d." % foes.size()}


## Out of the chamber, back to where the party stood. Safe to call when it is not
## open (a scene reload, a guest leaving).
func leave() -> void:
	if cave != null and is_instance_valid(cave):
		cave.queue_free()
	cave = null
	for foe in foes:
		if is_instance_valid(foe):
			(foe as Node).queue_free()
	foes.clear()
	for entry in _saved.keys():
		var body = entry
		if not is_instance_valid(body):
			continue
		var spot: Dictionary = _saved[entry]
		(body as Node3D).global_position = spot["position"]
		body.bounds = float(spot["bounds"])
		if body.combat != null:
			body.combat.target_mask = int(spot["mask"])
		if body.has_method("accept_network_input"):
			body.accept_network_input(Vector2.ZERO, false)
	_restore_the_squad()
	_saved.clear()
	_tracks.clear()
	party.clear()
	active = false
	_sync_eye(true)
	finished = ""


## The gate's own press: only a finished fight lets a body out.
func try_leave() -> bool:
	if not active:
		return false
	if finished.is_empty():
		if host != null and host.hud != null:
			host.hud.set_status("Not yet: somebody is still standing across the room.", 2.5)
		return true
	leave()
	if host != null and host.hud != null:
		host.hud.set_status("THE ARENA  ·  back out of the rock", 3.0)
	return true


func foes_standing() -> int:
	var count := 0
	for foe in foes:
		if is_instance_valid(foe) and bool(foe.get("alive")) and not bool(foe.get("downed")):
			count += 1
	return count


func party_standing() -> int:
	var count := 0
	for body in party:
		if is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed")):
			count += 1
	return count


# --- the frame -------------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	_clock += delta
	_drive_foes(delta)
	# The foes are bodies this scene owns, not the soul controller's: nothing else
	# steps them, so the chamber is where they are integrated - intent first, then
	# the one `step()` a frame the controller gives its own squad.
	var actors: Array = _actors()
	for foe in foes:
		if not is_instance_valid(foe):
			continue
		# A foe on its chest is out of the fight, and the chamber is not a place to
		# leave somebody bleeding: the body is finished where it lies so the pit
		# reads as a pit and the loot window has a corpse to open.
		if bool(foe.get("downed")):
			foe.take_damage(1.0, 99)
			continue
		if not bool(foe.get("alive")):
			continue
		foe.step(delta, actors, int(_clock * 60.0))
	if finished.is_empty():
		if foes_standing() == 0:
			_finish("won")
		elif party_standing() == 0:
			_finish("lost")


func _finish(result: String) -> void:
	finished = result
	if host == null or host.hud == null:
		return
	if result == "won":
		var purse := int(PURSE.get(difficulty, 0))
		if host.warband != null and purse > 0:
			host.warband.award_gold(purse)
		host.hud.set_status("%s IS YOURS  ·  %d gold  ·  G at the gate" % [room_label(), purse], 6.0)
	else:
		host.hud.set_status("%s TAKES THE BAND  ·  G at the gate" % room_label(), 6.0)


# --- the chamber and the field ---------------------------------------------

func _collect_party() -> Array:
	var out: Array = []
	if host.controller == null:
		return out
	for merc_id in host.warband.alive_merc_ids():
		if host.warband.roster.is_reserve(merc_id):
			continue
		var body = host.controller.body_of(merc_id)
		if body != null and is_instance_valid(body) and bool(body.get("alive")):
			out.append(body)
	return out


## Cut this bout's chamber out of the Hollow's plan and stand it at the arena's
## height: one room, drawn fresh, never the one the last bout was fought in.
##
## A room costs a fifth to a quarter of a second to cut when it has never been
## grown in this session (the rock's skin, its dripstone, its map), so the board
## calls this while a player is reading the tiers (`prepare`), and `enter` only
## cuts one itself when nobody has.
func _build_chamber() -> bool:
	if cave != null and is_instance_valid(cave):
		return true
	var next := CaveScript.pick_room(_draw, room_id)
	if next.is_empty():
		return false
	cave = CaveScript.new()
	cave.name = "ArenaChamber"
	# The chamber places itself at `ArenaCave.centre()`: the room's own floor is
	# authored in the plan's frame, so its posts are world space and the ground a
	# body lands on is exactly under it.
	host.add_child(cave)
	cave.build(next, _draw.randi())
	room_id = next
	_room_label = cave.room_label()
	return true


## Draw and cut the chamber the next bout will be fought in, ahead of the press.
## Idempotent: a chamber already cut is the one that will be used. A guest cuts
## nothing: the room is drawn from this machine's dice, so a guest that built its
## own would be standing in a different chamber from the host.
func prepare() -> bool:
	if host == null or active or bool(host.get("_client")):
		return false
	return _build_chamber()


func _party_into_chamber(field: Array) -> void:
	party = field
	var seats: Dictionary = cave.seat(field.size(), int(KITS.get(difficulty,
		KITS[DEFAULT_DIFFICULTY]).size()))
	var posts: Array = seats["party"]
	var yaw := float(seats["party_yaw"])
	for index in field.size():
		var body = field[index]
		_saved[body] = {
			"position": (body as Node3D).global_position,
			"bounds": float(body.get("bounds")),
			"mask": int(body.combat.target_mask) if body.combat != null else 1,
		}
		# The campaign's bodies carry a 31.5 m square around the origin as their
		# whole world, and the chamber stands 260 m up: a body that kept its bound
		# could not take a step in it.
		body.bounds = 6000.0
		if body.combat != null:
			body.combat.target_mask = 4
		_stand(body, posts[index], yaw)
	if host.controller != null:
		var soul_id: int = host.controller.merc_for_peer(host.controller.local_peer_id)
		if soul_id > 0:
			var soul = host.controller.body_of(soul_id)
			if soul != null and is_instance_valid(soul):
				host.controller.activate(host.controller.local_peer_id, soul_id)


func _foes_into_chamber() -> void:
	foes.clear()
	_tracks.clear()
	var kits: Array = KITS.get(difficulty, KITS[DEFAULT_DIFFICULTY])
	var seats: Dictionary = cave.seat(party.size(), kits.size())
	var posts: Array = seats["foes"]
	var yaw := float(seats["foe_yaw"])
	for index in kits.size():
		var kit: Dictionary = kits[index]
		var body = BodyScript.new()
		body.name = "ArenaFoe%d" % (index + 1)
		body.appearance = WarbandLooks.profile_for(90 + index)
		body.voice_id = VoiceLibrary.profile_for(90 + index)
		host.add_child(body)
		body.authoritative = true
		body.combat.damage_enabled = true
		body.configure(index, "Foe %d" % (index + 1), posts[index])
		body.bounds = 6000.0
		body.combat.target_mask = 4
		body.is_local = false
		_stand(body, posts[index], yaw)
		_dress(body, kit)
		foes.append(body)
		# One `DuelBrain` per foe: its own guard window, beat and circling side.
		_tracks[body] = DuelBrainScript.new()


## Stand one body on a post, facing `yaw`. A body this machine drives takes the
## teleport through its own clock (`teleport_to`); a replica only takes the point,
## because the host owns where it stands.
func _stand(body, at: Vector3, yaw: float) -> void:
	if bool(body.get("authoritative")) and body.has_method("teleport_to"):
		body.teleport_to(at, yaw)
	else:
		(body as Node3D).global_position = at
		var rig = body.get("rig")
		if rig != null:
			rig.global_basis = Basis(Vector3.UP, yaw)
	var velocity = body.get("velocity")
	if velocity != null:
		(body as Node3D).velocity = Vector3.ZERO



## Put a tier's kit on a body: the set on every slot it has, the blade in the
## main hand, and as many ability welds on that blade as the tier pays for.
func _dress(body, kit: Dictionary) -> void:
	var set_id := str(kit.get("armor", "makeshift"))
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = ArmorData.NONE
	var set_index: int = ArmorData.SET_IDS.find(set_id)
	if set_index >= 0:
		for slot in ArmorData.SLOTS:
			pieces[str(slot)] = set_index
	var main_id := str(kit.get("main", ""))
	var off_id := str(kit.get("off", ""))
	var abilities: Array[String] = []
	var wanted := int(kit.get("annoints", 0))
	if wanted > 0:
		var main_row: Dictionary = State.ITEMS.get(main_id, {})
		var off_row: Dictionary = State.ITEMS.get(off_id, {})
		for id in AbilityRules.unlockable_ids():
			if abilities.size() >= wanted:
				break
			if AbilityRules.fits_gear(AbilityRules.by_id(id), main_row, off_row):
				abilities.append(id)
	body.rig.apply_loadout(State.build_loadout(main_id, off_id, pieces))
	body.rig.ability_loadout = abilities


# --- the foes' brains ------------------------------------------------------

func _drive_foes(delta: float) -> void:
	var temper: Dictionary = TEMPER.get(difficulty, TEMPER[DEFAULT_DIFFICULTY])
	for foe in foes:
		if not is_instance_valid(foe):
			continue
		if not bool(foe.get("alive")) or bool(foe.get("downed")):
			continue
		_drive_foe(foe, temper, delta)


## One foe's tick: the ladder in `duel_brain.gd` decides, this scene only hands
## the decision to the body's own hands - a guard, a draw, a swing, a step.
func _drive_foe(foe, temper: Dictionary, delta: float) -> void:
	var brain = _tracks.get(foe)
	if brain == null:
		brain = DuelBrainScript.new()
		_tracks[foe] = brain
	var target = _nearest_body(foe)
	if target == null:
		foe.accept_network_input(Vector2.ZERO, false)
		return
	var here: Vector3 = (foe as Node3D).global_position
	var at: Vector3 = (target as Node3D).global_position
	var weapon := str(foe.rig.weapon)
	var answer: Dictionary = brain.tick(delta, temper, {
		"position": here,
		"target": at,
		"target_velocity": _velocity_of(target),
		"weapon": weapon,
		"ready": _blade_free(foe),
		"can_draw": bool(foe.combat.can_draw()),
		"blocking": bool(foe.combat.blocking),
		"swing": "stab" if weapon == "dagger" else "overhead",
	})
	if bool(answer["guard"]):
		foe.combat.start_block(at - here)
	else:
		foe.combat.stop_block()
	if bool(answer["draw"]):
		foe.combat.begin_draw()
		foe.accept_network_input(Vector2.ZERO, false)
		return
	var variant := str(answer["swing"])
	if not variant.is_empty():
		foe.combat.begin_melee("right", variant)
	var move: Vector3 = answer["move"]
	_steer(foe, move, bool(answer["run"]))


## Walk a body: the one movement write. `running` decides the pace.
func _steer(foe, direction: Vector3, running: bool) -> void:
	if direction.length_squared() <= 0.000001 or foe.has_method("accept_network_input") == false:
		return
	foe.accept_network_input(Vector2(direction.x, direction.z), running)


## How a body is moving this tick, for the brain's lead: a body that is not one
## of the field's (a fixture, a corpse) is standing still.
func _velocity_of(target) -> Vector3:
	var velocity = target.get("velocity")
	return Vector3(velocity.x, 0.0, velocity.z) if velocity != null else Vector3.ZERO


## The band's own squad fights what is in front of it, and the world's one hostile
## list is the wood's: the chamber hands the allies the foes and the room's own map
## for the length of the fight and takes them back afterwards, so a camp of wardens
## is not hunted through a stone wall and an ally walks round the dripstone of a
## room it has never been in.
func _lend_the_squad() -> void:
	if host.squad == null:
		return
	_squad_watchers = host.squad.watchers
	host.squad.watchers = foes
	host.squad.following = true
	host.squad.engage_radius = 60.0
	if cave != null:
		_nav_before = host.squad.nav
		host.squad.nav = cave.nav
		_nav_lent = true
		host.squad.relocate()


func _restore_the_squad() -> void:
	if host == null or host.squad == null:
		return
	if _squad_watchers != null:
		host.squad.watchers = _squad_watchers
	_squad_watchers = null
	if _nav_lent and host.squad != null:
		host.squad.nav = _nav_before
		host.squad.relocate()
	_nav_lent = false
	_nav_before = null


## The rock's air over the eye while the chamber holds a fight, and the campaign's
## own sky back when it does not: a cave under the wood's sun, at the wood's
## ambient, is a cave that looks like a lit grey box. Every directional light the
## campaign owns goes out with it - the world's sun, the town's moon - because a
## light with no position in the sky reaches into the rock as well as out of it.
func _sync_eye(force: bool = false) -> void:
	if host == null:
		return
	var camera: Camera3D = host.get("camera")
	if camera != null:
		var air: Environment = cave.environment if active and cave != null else null
		if force or camera.environment != air:
			camera.environment = air
	if active:
		_darken_the_world()
	else:
		_relight_the_world()


## Put every directional light the world owns out, remembering what it was.
func _darken_the_world() -> void:
	if not _sun_states.is_empty():
		return
	for node in host.find_children("*", "DirectionalLight3D", true, false):
		var lamp := node as DirectionalLight3D
		_sun_states.append([lamp, lamp.visible])
		lamp.visible = false


## Back the way they were: a sun that was already out stays out.
func _relight_the_world() -> void:
	for entry in _sun_states:
		var lamp = entry[0]
		if is_instance_valid(lamp):
			(lamp as DirectionalLight3D).visible = bool(entry[1])
	_sun_states.clear()


## Every body in the chamber, for the step's own collision and reach queries.
func _actors() -> Array:
	var out: Array = []
	for body in party:
		if is_instance_valid(body):
			out.append(body)
	for foe in foes:
		if is_instance_valid(foe):
			out.append(foe)
	return out


func _nearest_body(foe):
	var best = null
	var best_distance := INF
	for body in party:
		if not is_instance_valid(body) or not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		var distance: float = (foe as Node3D).global_position.distance_to(
			(body as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## The same gate `Combat.begin_melee` applies, asked before the swing so a body
## still recovering is never handed a blow that would be refused.
func _blade_free(foe) -> bool:
	if str(foe.rig.weapon) not in ["sword", "dagger", "dual"]:
		return false
	return float(foe.combat.clash_cooldown) <= 0.0 \
		and float(foe.combat.attack_progress) >= 0.999 \
		and bool(foe.rig.can_begin_melee("right"))
