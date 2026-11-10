class_name RunDirector
extends Node
## The run director: one endless run of levels from the Start Run Portal to the
## wipe that ends it, and the host-authoritative owner of everything inside it.
##
## What it owns: the run seed, the island being fought on, the level counter and
## its budget, the mobs it spawns (their names, factions, elites and bosses), the
## gold a run pays, the unlock keys a boss drops, the reward chests and
## pedestals, the Greed Totem, the shop level and its rack, the portal on, and
## the downed/revive contract of co-op.
##
## What it does not own: damage (the shared `Combat` and the mob classes), health
## (the bodies), movement (the possession controller) or the upgrade engine (each
## player's `RoguelitePlayer`). It asks those systems and reports what happened.
##
## Co-op shape. The host runs the whole loop. Guests receive three kinds of
## reliable event - `state` (which level and island), `prop` (which chest, rack or
## portal exists, with its serial), and `mob` (a spawned hostile, named so the
## session's snapshots find it) - plus unreliable `fx` flashes. Their inputs
## arrive as requests: start, use a prop, choose a draft, buy a ware, rebind a
## hand, swap hands. No guest ever spawns a wave, rolls a chest or applies a
## proc.

signal state_changed

const StageScript = preload("res://scripts/roguelite/roguelite_stage.gd")
const PlayerScript = preload("res://scripts/roguelite/run_player.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const ProcFx = preload("res://scripts/roguelite/proc_fx.gd")
const ProcProjectile = preload("res://scripts/roguelite/proc_projectile.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const ArmorLoot = preload("res://scripts/roguelite/armor_loot.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const CombatScript = preload("res://scripts/combat.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const PlayerArcher = preload("res://scripts/archer.gd")
const ThrownScript = preload("res://scripts/thrown_weapon.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const DevilScript = preload("res://scripts/devil_mob.gd")
const CloneScript = preload("res://scripts/ranger_clone.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")

## A run is levels, endless. Every level is a wave; every tenth level is a boss;
## the level before a boss is a shop. A depth block is ten levels of one island's
## ground, and every cleared level stands three gates - the wood, the cave and the
## pit - so the faction fought is the party's own choice, for as long as the band
## keeps standing.
const LEVELS_PER_ISLAND := 10
const BOSS_EVERY := 10
## The shop level stands at 9, 19, 29 ... - always the level before the boss.
const SHOP_LEVEL := BOSS_EVERY - 1
## The live cap and the spawn cadence: a wave is a queue that feeds the island,
## not a hundred bodies dropped on one frame.
## A wave is a crowd: the live cap is what the island can carry at once and the
## budget below is how many bodies the level is worth, so a level one wave is ten
## to fifteen things coming at the party instead of five or six.
const LIVE_CAP_BASE := 20
const LIVE_CAP_PER_PLAYER := 6
const SPAWN_INTERVAL := 0.28
const FIRST_WAVE_DELAY := 1.6
const INTERACT_REACH := 3.4
const RETARGET_INTERVAL := 0.9
## The island's bodies are given no town to be peaceful about. `MobSenses` reads a
## non-finite centre as "there is no ring here", so the wave fights on every metre
## of its island instead of standing off from the middle of it.
const NO_SAFE_RING := Vector3.INF
## The budget a level spends before the co-op multiplier. It grows with the island
## and with the level inside it, so the tenth level of the tenth island is a wall
## and the second body in the party does not fight the first body's wave.
const LEVEL_BUDGET := 26.0
const ISLAND_GROWTH := 1.26
const WAVE_GROWTH := 1.13
## The run opens under its own line. Level one is the first wave a new player
## swings at, so the health dial starts 30% under the curve above and is back on
## it by the opening island's last level: the ramp is the first island's own
## length, so the next island keeps the curve untouched. Only the pool is eased -
## `rate` is not, because a soft opening is a shorter fight, not a slower one.
const OPENING_HEALTH_SCALE := 0.7

## The island's edge is not a wall. A body may walk out past the treeline into the
## fog - the ground runs `RogueliteStage.OUTER_DEPTH` further - and this is what
## answers for it: a warning first, and then the middle of the map and a share of
## whatever life the body has left. `BOUNDS_COST` is a share of the *current* pool,
## so it can never be the blow that kills somebody.
const BOUNDS_SECONDS := 6.0
const BOUNDS_COST := 0.3

## The three factions and what every biome fields. `cost` is the budget a body
## spends; `kind` is which class builds it.
const FACTIONS := {
	"watchers": [
		{"kind": "watcher", "species": "hollow_runt", "cost": 1.0, "weight": 5},
		{"kind": "watcher", "species": "hollow_warden", "cost": 3.0, "weight": 4},
		{"kind": "archer", "species": "hollow_warden", "cost": 4.0, "weight": 2},
	],
	"demons": [
		{"kind": "devil", "species": "spawn", "cost": 1.0, "weight": 5},
		{"kind": "devil", "species": "hell_goat", "cost": 2.0, "weight": 4},
		{"kind": "devil", "species": "succubus", "cost": 3.0, "weight": 3},
		{"kind": "devil", "species": "beast", "cost": 3.5, "weight": 2},
		{"kind": "devil", "species": "gargoyle", "cost": 4.5, "weight": 1},
	],
	# The pit fields its own: a wave of blood clones, never a watcher. Each
	# biome's table is its faction and nothing borrowed from another island.
	# A clone costs what a ranger is worth - seven - because it is one: a real
	# kit, a dodge, a guard, and a pool the run scales like every other body. At
	# three a level-two pit fielded nine of them and a standing body lasted two
	# seconds; the pit is a band of duellists, not a firing squad.
	"clones": [
		{"kind": "clone", "species": "", "cost": 7.0, "weight": 5},
		{"kind": "clone", "species": "", "cost": 7.0, "weight": 5},
	],
}

## The boss each faction sends on its last wave.
const BOSSES := {
	"watchers": {"kind": "archer", "species": "hollow_warden", "cost": 10.0, "boss": true},
	"demons": {"kind": "devil", "species": "gargoyle", "cost": 10.0, "boss": true},
	"clones": {"kind": "clone", "species": "", "cost": 10.0, "boss": true},
}

## The three gates every cleared level stands, and the one the party takes is the
## island it fights next. Nothing cycles any more: the choice is the player's, so
## a run is the sequence of doors they walked through.
const GATES := [
	{"biome": "wilderness", "faction": "watchers"},
	{"biome": "caves", "faction": "demons"},
	{"biome": "arena", "faction": "clones"},
]
## What a faction's bodies are worth before depth is asked for. These are the
## base values: the island and wave curve below is one multiplier on all of them,
## so the three gates are a choice of *kind*, and how deep the party has gone is
## the same wall behind every one.
## Watchers are the yardstick - a body and a club. Demons carry their own mass:
## far more pool and a heavier blow, bought with the small spawns that make up
## most of their crowd. Clones sit between and fight like a ranger.
const FACTION_TUNING := {
	"watchers": {"health": 1.0, "rate": 1.0, "damage": 1.0},
	"demons": {"health": 1.45, "rate": 1.05, "damage": 1.35},
	# A clone is a ranger's body with a ranger's kit, so it does not need a
	# multiplier to be dangerous: its pool is 85% of a ranger's and its blows 45%
	# of one, and what it carries is what an early party can beat. A body left
	# standing in the pit's second wave falls in about ten seconds, the same
	# order as the wood; what makes the pit the hard gate is the kit and the AI.
	"clones": {"health": 0.85, "rate": 1.0, "damage": 0.45},
}
## Where the three gates stand: a shallow arc past the reward cluster, 24 degrees
## between neighbours so the arches never touch and a line of sight from the
## chest reads all three.
const GATE_REACH := 9.5
const GATE_FAN := 0.4189

var world = null
var stage = null
var players: Dictionary = {}      # peer_id -> RoguelitePlayer
var run_active := false
var run_seed := 0
## The island a level stands on, 0-based. It is `(level - 1) / LEVELS_PER_ISLAND`.
var stage_index := 0
var biome_id := "wilderness"
## The level inside its island, 1..10. The global level is
## `stage_index * LEVELS_PER_ISLAND + wave`.
var wave := 0
var level := 0
var wave_active := false
## The level has been fought out and its rewards stand on the dirt.
var level_cleared := false
var boss_level := false
## The safe level before a boss: no mobs, the shop and the rack, and the three
## gates to the boss.
var shop_level := false
## A guest's copy of the host's purse. The host reads its own `Warband` total;
## a guest cannot see that machine's `PlayerState`, so the wire carries the total
## after every change and this is what the plate reads.
var gold_mirror := 0
var total_kills := 0
var keys_earned := 0
var draft_offers: Dictionary = {} # serial -> {peer_id: Array[String]}
var shop_wares: Dictionary = {}   # serial -> Array[Dictionary]

var _rng := RandomNumberGenerator.new()
var _saved: Dictionary = {}
var _mobs: Array = []
var _mob_specs: Dictionary = {}   # instance id -> spec
var _props: Array = []
var _props_by_serial: Dictionary = {}
var _opened: Dictionary = {}
## Which peers have already taken a chest's, pedestal's or totem's offer. One
## prop, one helping each: a four-player party does not lose three drafts because
## one body reached the pedestal first.
var _users: Dictionary = {}
var _queue: Array[Dictionary] = []
var _spawn_clock := 0.0
var _retarget_clock := 0.0
var _serial := 0
var _mob_serial := 0
var _killed: Dictionary = {}
var _down_clock := 0.0
var _throw_clock: Dictionary = {}  # peer -> seconds
var _throw_charges: Dictionary = {}  # peer -> charges
## Standing damage fields: a shot's own aura, a thrown void, a body's shockwave.
## One list, ticked at four a second, so a zone costs a dictionary and not a node.
var _zones: Array = []
## Open bleeds: one dictionary per body, ticked at four a second. A bleed is a
## hit's own delayed wound, not a zone: it follows the body it opened.
var _bleeds: Array = []
## Bodies put down since the last Bonus Chests payout.
var _chest_kills := 0
## Each guest's chosen hands, sent to the host because the host is the one that
## dresses every body in a run. Keyed by peer id.
var guest_loadouts: Dictionary = {}
var _loadout_sent_seed := -1
var _client := false
## `{peer: seconds}` - how long each run body has been standing outside the island's
## fight ring. Cleared the frame the body comes back in.
var _outside: Dictionary = {}
## How long since the warning last went out, so a stray is told once a second and
## not once a frame.
var _outside_notice := 0.0
## `weapon id -> {weapon, bow, sword, dagger}`: what `apply_loadout` would put on
## the rig for that piece. The square's dress compares against these every frame.
var _hand_signatures: Dictionary = {}


# --- lifecycle -------------------------------------------------------------

func setup(world_node: Node3D) -> void:
	world = world_node
	_client = bool(world.get("_client")) if world != null else false


func is_running() -> bool:
	return run_active


func is_client() -> bool:
	return _client


func player_for(body) -> Variant:
	if body == null or not is_instance_valid(body):
		return null
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run) and run.body == body:
			return run
	return null


func player_of_peer(peer_id: int):
	return players.get(peer_id)


## The run a body is inside, `null` when no live run owns it. The paperdoll
## reads the run's own armour through this: a chest's piece lives on the run,
## not in the roster, so the body inside it is the only place it exists.
func run_of_merc(merc_id: int) -> Variant:
	if merc_id <= 0:
		return null
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run) and int(run.merc_id) == merc_id:
			return run
	return null


## The armour a run has put on `merc_id`, `{slot: piece}`, empty when no run
## owns that body. The player page displays it over the wardrobe's own kit.
func armor_for_merc(merc_id: int) -> Dictionary:
	var run = run_of_merc(merc_id)
	if run == null:
		return {}
	var raw: Variant = run.armor
	return raw if raw is Dictionary else {}


## The pair in the hands of the body a run owns: `main` is the piece the hand is
## holding now (`_active_slot`) and `off` the other one TAB reaches. `{}` when no
## run owns the body, which leaves the wardrobe's own kit as the truth. The
## character page draws this over the roster, exactly as it draws the run's
## armour: the hands a player fights with are the run's, not the wardrobe's.
func hands_for_merc(merc_id: int) -> Dictionary:
	var run = run_of_merc(merc_id)
	if run == null:
		return {}
	return _hands_of(str(run.ranged_id), str(run.melee_id), str(run._active_slot), "run")


## The pair the rack bound, as the square shows it: the ranged piece is the one
## in the hand (the same hand the run starts on) and the melee piece is not held
## until TAB on the island. `{}` while a run is live - the island owns the hands.
func square_hands() -> Dictionary:
	if run_active:
		return {}
	return _hands_of(_roster_loadout("ranged"), "", "ranged", "rack")


func _hands_of(ranged_id: String, melee_id: String, active: String,
		source: String) -> Dictionary:
	var main_id := ranged_id if active != "melee" else melee_id
	var off_id := "" if source == "rack" else (melee_id if active != "melee" else ranged_id)
	return {"main": main_id, "off": off_id, "slot": active, "source": source}


func local_peer() -> int:
	if world == null or world.get("controller") == null:
		return 1
	return int(world.controller.local_peer_id)


func party_size() -> int:
	var session = _session()
	if session != null and session.has_method("peer_count"):
		return maxi(1, int(session.peer_count()))
	# Offline, the wave belongs to one soul even when the square lent a squad:
	# the budget contract is per *connected player*, and an AI body is not one.
	return 1


## BEGIN. Host only: starts a fresh seed, dresses the party in the loadout they
## chose in town, stands level one under their feet and sends its wave. A guest's
## press is a request to the host.
func start_run() -> Dictionary:
	if run_active:
		return {"ok": false, "message": "A run is already live."}
	if _client:
		var request := {"t": "start", "loadout": _local_loadout()}
		send_request(request)
		return {"ok": true, "message": "The host is opening a run."}
	if world == null or world.get("controller") == null:
		return {"ok": false, "message": "The run needs the world around it."}
	var built := _collect_party()
	if built.is_empty():
		return {"ok": false, "message": "No body to put in the run."}
	run_seed = randi() & 0x7fffffff
	_rng.seed = run_seed
	run_active = true
	stage_index = 0
	wave = 1
	level = 1
	level_cleared = false
	shop_level = false
	boss_level = false
	# The purse is not reset: gold is the player's, and a run spends what the
	# town's racks, vendors and bosses have filled.
	total_kills = 0
	keys_earned = 0
	draft_offers.clear()
	shop_wares.clear()
	# A run's prop serials start at one again: a stale `_opened` from the last run
	# would spend this run's first chest before it was ever touched.
	_opened.clear()
	_killed.clear()
	_outside.clear()
	_outside_notice = 0.0
	_serial = 0
	_mob_serial = 0
	_begin_island(_first_biome(), built)
	_begin_level()
	_broadcast_state()
	var line := "THE RUN OPENS  ·  %s  ·  LEVEL 1" % StageScript.biome(biome_id).name
	_status(line)
	return {"ok": true, "message": line}


func _first_biome() -> String:
	# The wood always opens the run: it is the one island that teaches the loop
	# before a demon or a clone asks a harder question.
	return "wilderness"


## Stand a new island under the party: the biome changes, the bodies move in and
## a fresh runtime takes the rack's pair. The level itself is begun separately,
## so a shop level and a boss level use the same ground.
func _begin_island(new_biome: String, field: Array = []) -> void:
	biome_id = new_biome
	# A new island is a new edge: nothing counted outside the last one applies.
	_outside.clear()
	_outside_notice = 0.0
	wave_active = false
	level_cleared = false
	shop_level = false
	boss_level = false
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	_build_stage()
	_move_party_in(field if not field.is_empty() else _collect_party())
	_spawn_runners()
	state_changed.emit()


## Begin the level the run's counters currently name. A combat level queues its
## wave; the shop level queues nothing and stands the stalls; the boss level
## queues the boss and its escort.
func _begin_level() -> void:
	level = stage_index * LEVELS_PER_ISLAND + wave
	shop_level = wave == SHOP_LEVEL
	boss_level = wave == BOSS_EVERY
	level_cleared = false
	wave_active = false
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	if shop_level:
		var shop_pedestal := _spawn_shop_level()
		_status("LEVEL %d  ·  SHOP LEVEL  ·  the boss waits beyond the gates" % level, 5.0)
		_draft_ai_at(shop_pedestal)
		_broadcast_state()
		return
	wave_active = true
	var budget := wave_budget()
	if boss_level:
		_queue.append(BOSSES.get(StageScript.biome(biome_id).faction, BOSSES["watchers"]))
		budget -= 10.0
	# Elites from the second level of an island on: a heavier body every other
	# wave, and the boss level's escort always carries one.
	if wave >= 2 and not boss_level:
		var elite_spec := _pick_spec(true)
		if not elite_spec.is_empty():
			_queue.append(elite_spec)
			budget -= float(elite_spec.cost)
	while budget > 0.0:
		var spec := _pick_spec(false)
		if spec.is_empty():
			break
		_queue.append(spec)
		budget -= maxf(0.5, float(spec.cost))
	_spawn_clock = FIRST_WAVE_DELAY
	var line := "LEVEL %d  ·  %d bodies inbound" % [level, _queue.size()]
	if boss_level:
		line = "LEVEL %d  ·  BOSS  ·  %s STIRS" % [level, str(StageScript.biome(biome_id).name)]
	_status(line)
	_broadcast_state()


## The shop level: the town's business standing on the level's own ground. No
## mobs, no clock - the gates to the boss are the only way on, and a player can
## stand here as long as they like.
func _spawn_shop_level() -> Node3D:
	var wares := _shop_wares()
	var shop_payload := {"wares": wares}
	# The shop level's business is one cluster too: the stall, the rack and the
	# pedestal stand a few paces apart, with the three gates beyond them.
	var shop = _spawn_prop("shop", stage.reward_point(0, 4, 3.2), shop_payload)
	if shop != null:
		shop_wares[int(shop.get_meta("serial"))] = wares
		_broadcast_prop(shop, "shop", shop_payload)
	var rack = _spawn_prop("rack", stage.reward_point(1, 4, 3.2), {})
	if rack != null:
		_broadcast_prop(rack, "rack", {})
	# Every shop level offers one more upgrade: the safe level is also the breath
	# before the wall. It is one draft per body, exactly like the wave's pedestal.
	var pedestal := _stand_pedestal(stage.reward_point(2, 4, 3.2),
		Mods.SURFACE_SHOP_PEDESTAL)
	# The boss is fought in whichever biome the party walks into.
	_spawn_gates(level + 1)
	return pedestal


func _build_stage() -> void:
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = StageScript.new()
	stage.name = "RogueliteIsland"
	stage.stage_index = stage_index
	stage.position = StageScript.centre_for(stage_index)
	world.add_child(stage)
	stage.build(biome_id, run_seed, stage_index)


## Bring the whole field onto the island. A body's own world is the campaign's
## 1900 m square; an island is 34 m across, so the bound is lifted and the body
## is put on its entry post. The campaign seat is saved and restored on the way
## out, exactly as the arena ring does it.
func _collect_party() -> Array:
	var out: Array = []
	if world == null or world.get("controller") == null:
		return out
	for body in _world_bodies():
		if is_instance_valid(body) and _flag(body, "alive", true):
			out.append(body)
	return out


func _move_party_in(field: Array) -> void:
	var posts: Array[Vector3] = stage.entry_posts(field.size()) if stage != null else []
	for index in field.size():
		var body = field[index]
		if not is_instance_valid(body):
			continue
		# The seat to return to is the campaign's, saved on the first island and
		# never overwritten by an island post on the way through.
		if not _saved.has(body):
			_saved[body] = {
				"position": (body as Node3D).global_position,
				"bounds": _num(body, "bounds", 31.5),
				"mask": int(body.combat.target_mask) if body.combat != null else 2,
				"weapon": str(body.rig.get("weapon")) if body.get("rig") != null else "",
			}
		body.bounds = 6000.0
		if body.combat != null:
			body.combat.target_mask = 2
		var post: Vector3 = posts[index] if index < posts.size() else stage.floor_point(Vector2.ZERO)
		(body as Node3D).global_position = post
		(body as Node3D).velocity = Vector3.ZERO
		if body.has_method("revive_from_downed") and _flag(body, "downed", false):
			body.revive_from_downed(1.0)


## One runtime per body. The loadout it applies is the one the rack bound: the
## body's hands become the ranged piece, and TAB reaches the melee piece, without
## the campaign's roster ever being written.
func _spawn_runners() -> void:
	# A body that already has a runtime keeps it: the mods are the *run's*, not
	# the island's, and a fresh engine on every portal would delete the draft the
	# party just fought for.
	var previous := players
	players.clear()
	for body in _world_bodies():
		if not is_instance_valid(body) or not _flag(body, "alive", true):
			continue
		var merc := _merc_of(body)
		var peer := _peer_of_merc(merc)
		var run = null
		for old_peer in previous:
			var candidate = previous[old_peer]
			if candidate != null and is_instance_valid(candidate) and candidate.body == body:
				run = candidate
				break
		if run != null and is_instance_valid(run):
			run.director = self
			run.peer_id = peer
			run.merc_id = merc
			players[peer] = run
			if body.get("combat") != null:
				body.combat.ammo_gate = Callable()
			_apply_hands(run, "ranged")
			_throw_charges[peer] = int(Weapons.resolve(run.melee_id).get("throw_charges", 0))
			_throw_clock[peer] = 0.0
			run.apply_stats()
			continue
		var ranged := _loadout_for(peer, "ranged")
		var melee := _loadout_for(peer, "melee")
		run = PlayerScript.new()
		world.add_child(run)
		run.bind(body, self, peer, merc, ranged, melee)
		run._active_slot = "ranged"
		players[peer] = run
		if body.get("combat") != null:
			body.combat.ammo_gate = Callable()
		_apply_hands(run, "ranged")
		_throw_charges[peer] = int(Weapons.resolve(melee).get("throw_charges", 0))
		_throw_clock[peer] = 0.0
		run.apply_stats()
		if float(body.health) <= 1.0:
			body.health = float(body.max_health)


func _merc_of(body) -> int:
	if world == null or world.get("controller") == null:
		return -1
	return int(world.controller.merc_of(body))


func _peer_of_merc(merc_id: int) -> int:
	if world == null or world.get("controller") == null:
		return 1
	for peer in world.controller.possessing_peers():
		if int(world.controller.merc_for_peer(peer)) == merc_id:
			return int(peer)
	# An unpossessed squadmate fights under its own mercenary id.
	return 1000 + maxi(1, merc_id)


func _roster_loadout(slot: String) -> String:
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("loadout_for"):
		return str(meta.loadout_for(slot))
	return "bow_twig" if slot == "ranged" else "hatchet_makeshift"


## The hands a body enters with. A guest's own choice is the guest's: it arrives
## with the start request (or a moment after the first state), is validated
## against the registry, and only then becomes that body's pair.
func _loadout_for(peer_id: int, slot: String) -> String:
	if peer_id != local_peer() and guest_loadouts.has(peer_id):
		var table: Dictionary = guest_loadouts[peer_id]
		var id := str(table.get(slot, ""))
		if Weapons.has(id) and Weapons.slot_of(id) == slot:
			return id
	return _roster_loadout(slot)


func _local_loadout() -> Dictionary:
	var meta = get_node_or_null("/root/Roguelite")
	if meta == null:
		return {"ranged": "bow_twig", "melee": "hatchet_makeshift"}
	return {"ranged": str(meta.loadout_for("ranged")),
		"melee": str(meta.loadout_for("melee"))}


func remember_loadout(peer_id: int, table: Variant) -> void:
	if typeof(table) != TYPE_DICTIONARY:
		return
	var raw: Dictionary = table
	var clean := {}
	for slot in ["ranged", "melee"]:
		var id := str(raw.get(slot, ""))
		if Weapons.has(id) and Weapons.slot_of(id) == slot:
			clean[slot] = id
	if clean.size() == 2:
		guest_loadouts[peer_id] = clean


## Dress the body for one hand without touching the roster: the campaign's kit
## keeps its armour, trinkets and copies; only the held piece and the pose change.
func _apply_hands(run, slot: String) -> void:
	if run == null or not is_instance_valid(run) or run.body == null:
		return
	var weapon_id := str(run.ranged_id) if slot == "ranged" else str(run.melee_id)
	if _dress_weapon(run.body, run.merc_id, weapon_id):
		run._active_slot = slot


## Put one weapon in a body's hands while keeping everything else it wears. The
## roster is never written: a run's weapons are the run's, and the piece the
## campaign gave the body is still in its ledger when the island is done with it.
func _dress_weapon(body, merc_id: int, weapon_id: String) -> bool:
	if body == null or not is_instance_valid(body) or weapon_id.is_empty():
		return false
	var profile := Weapons.resolve(weapon_id)
	if profile.is_empty():
		return false
	var gear: Dictionary = {}
	if world != null and world.get("warband") != null and merc_id > 0:
		gear = world.warband.roster.equipped_of(merc_id)
	# Armour a chest handed out in this run sits over the roster's kit for the
	# length of the run: a hand flip re-dresses the body, and the pieces the
	# party won on the island must not fall back to the wardrobe's set.
	var run = player_for(body)
	var pieces := {}
	for armor_slot in ArmorData.SLOTS:
		var won: Dictionary = run.armor_piece(str(armor_slot)) \
			if run != null and is_instance_valid(run) else {}
		if not won.is_empty():
			pieces[armor_slot] = int(won.get("set", ArmorData.NONE))
			continue
		var item_id := str(gear.get(str(armor_slot), ""))
		pieces[armor_slot] = int((State.ITEMS.get(item_id, {}) as Dictionary).get("set", ArmorData.NONE))
	var trinkets := {
		"neck": str(gear.get("neck", "")),
		"ring1": str(gear.get("ring1", "")),
		"ring2": str(gear.get("ring2", "")),
		"off": "",
	}
	var loadout: Dictionary = State.build_loadout(weapon_id, "", pieces, trinkets, true)
	if body.get("rig") != null and body.rig.has_method("apply_loadout"):
		# The player's equipped abilities ride into the run beside the piece: a
		# run body is still that mercenary's body, and a hand flip re-dresses it,
		# so the list has to come from the roster here or the bar would empty
		# every time the hands changed.
		if world != null and world.get("warband") != null and merc_id > 0 \
				and body.rig.has_method("set_ability_loadout"):
			body.rig.set_ability_loadout(
				world.warband.roster.hotbar_order_of(merc_id))
		body.rig.apply_loadout(loadout)
	if body.get("combat") != null:
		body.combat.stop()
	return true


## What a body wears right now, in the shape the loot's floor reads. The rig is
## the truth: a piece won from an earlier chest is already on it, so the next
## chest cannot roll under it.
func _worn_armor(run) -> Dictionary:
	var worn := {}
	for slot in ArmorData.SLOTS:
		worn[str(slot)] = ArmorData.NONE
	if run == null or not is_instance_valid(run) or run.body == null \
			or not is_instance_valid(run.body):
		return worn
	var rig = run.body.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("armor_piece"):
		for slot in ArmorData.SLOTS:
			worn[str(slot)] = int(rig.armor_piece(str(slot)))
	return worn


## The piece leaving the chest: up out of the lid, a beat hanging with its name
## over it, then into the body that opened the chest. Presentation only - the
## piece is already on the run when this is called - and a guest draws the same
## pop from the host's `armor` event.
func _pop_armor(piece: Dictionary, from: Vector3, run) -> void:
	var to := from
	var hover := from + Vector3.UP * 1.35
	if run != null and is_instance_valid(run) and run.body != null \
			and is_instance_valid(run.body) and run.body is Node3D:
		var body_at: Vector3 = (run.body as Node3D).global_position
		to = body_at + Vector3.UP * 1.25
		var toward := from.direction_to(body_at)
		toward.y = 0.0
		if toward.length_squared() > 0.001:
			hover += toward.normalized() * 0.35
	ProcFx.loot_pop(stage if is_instance_valid(stage) else world,
		from + Vector3.UP * 0.72, hover, to, ArmorLoot.title_of(piece),
		ArmorLoot.detail_of(piece), ArmorLoot.colour_of(piece))


## The Town Hub's own dress: a body standing in the square holds the ranged
## piece the rack bound, so what is chosen at the rack is what is seen and what
## the portal then carries onto the island. The world calls this when a body comes
## inside the walls and again when the rack binds a new piece, and calls
## `controller.refresh_gear` on exit: the campaign's kit is never overwritten,
## only set aside while the body is inside the walls. It is presentation, not a
## lock - a piece the page wears over it is the body's until it walks out and in
## again - so the page reads the rig (`body_holds`) rather than assuming this
## dress is still what the hand is holding.
func dress_town_body(body) -> void:
	if world == null or run_active or not is_instance_valid(body):
		return
	var merc := _merc_of(body)
	if merc <= 0:
		return
	var weapon_id := _roster_loadout("ranged")
	if body_holds(body, weapon_id):
		return
	_dress_weapon(body, merc, weapon_id)


## Whether the rig already carries `weapon_id`'s profile. Asked by the square's
## dress before it spends a loadout, and by the character page: a hand-row naming
## the rack's piece is only true while the rig still holds it.
func body_holds(body, weapon_id: String) -> bool:
	var rig = body.get("rig") if body != null else null
	if rig == null or not is_instance_valid(rig) or not rig.has_method("apply_loadout"):
		return false
	var signature := _hand_signature(weapon_id)
	if signature.is_empty():
		return false
	return str(rig.get("weapon")) == str(signature["weapon"]) \
		and int(rig.get("bow_index")) == int(signature["bow"]) \
		and int(rig.get("sword_index")) == int(signature["sword"]) \
		and int(rig.get("dagger_index")) == int(signature["dagger"])


## The four rig fields `apply_loadout` sets from the main hand, per weapon id.
func _hand_signature(weapon_id: String) -> Dictionary:
	if weapon_id.is_empty():
		return {}
	var cached: Variant = _hand_signatures.get(weapon_id)
	if cached is Dictionary:
		return cached
	var loadout := State.build_loadout(weapon_id, "", {}, {}, false)
	var signature := {"weapon": str(loadout.get("weapon", "none")),
		"bow": int(loadout.get("bow", 0)), "sword": int(loadout.get("sword", 0)),
		"dagger": int(loadout.get("dagger", 0))}
	_hand_signatures[weapon_id] = signature
	return signature


## TAB inside a run. The campaign's swap is a roster verb; an arena run's swap is
## the other hand of the same choice, and it is the host's to make for a guest.
func swap_hands(body) -> void:
	var run = player_for(body)
	if run == null:
		return
	# Cursed Arsenal locks the *pieces*, not the hands: the pair cannot be
	# replaced for the rest of the run, but a body still reaches both of them.
	var next := "melee" if str(run._active_slot) == "ranged" else "ranged"
	if _client:
		send_request({"t": "swap"})
		_apply_hands(run, next)
		return
	_apply_hands(run, next)
	_broadcast({"t": "hands", "peer": run.peer_id, "slot": next})


## The rack bound a new piece to a body in a live run (a shop level, where the
## town's business stands on the island). Re-profile the hands and put the piece
## in them; a guest's request reaches the host through `rebind`.
func rebind_hand(peer_id: int, slot: String, weapon_id: String) -> void:
	if slot != "ranged" and slot != "melee":
		return
	if not Weapons.has(weapon_id) or Weapons.slot_of(weapon_id) != slot:
		return
	if _client:
		send_request({"t": "rebind", "slot": slot, "weapon": weapon_id})
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return
	if slot == "ranged":
		run.ranged_id = weapon_id
	else:
		run.melee_id = weapon_id
	run._set_profiles()
	_apply_hands(run, slot)
	_throw_charges[peer_id] = int(Weapons.resolve(run.melee_id).get("throw_charges", 0))
	_throw_clock[peer_id] = 0.0
	run.apply_stats()
	if not _client:
		_broadcast({"t": "rebind", "peer": peer_id, "slot": slot, "weapon": weapon_id})


# --- the frame -------------------------------------------------------------

func tick(delta: float) -> void:
	if not run_active:
		return
	_tick_throw_regen(delta)
	if _client:
		state_changed.emit()
		return
	_tick_bounds(delta)
	_tick_zones(delta)
	_tick_bleeds(delta)
	if level_cleared or shop_level:
		_tick_down_check(delta)
		state_changed.emit()
		return
	if not wave_active:
		state_changed.emit()
		return
	_spawn_clock -= delta
	if _spawn_clock <= 0.0 and not _queue.is_empty() and _live_mobs() < _live_cap():
		_spawn_clock = SPAWN_INTERVAL
		_spawn_from_queue()
	_retarget_clock += delta
	if _retarget_clock >= RETARGET_INTERVAL:
		_retarget_clock = 0.0
		_retarget_mobs()
	_tick_down_check(delta)
	# A wipe ends the run in that call: the stage is gone, the party is unbound,
	# and `_clear_level` would stand its props on nothing.
	if not run_active:
		state_changed.emit()
		return
	if _queue.is_empty() and _live_mobs() == 0:
		_clear_wave()
	state_changed.emit()


## The island's edge, watched. The fight ring is the island's own turf; the band
## past it is walkable ground with a treeline in it, so a body that walks out is
## told to come back rather than stopped by an invisible wall. It has `BOUNDS_SECONDS`
## to do it. A body that does not is put in the middle of the map and pays
## `BOUNDS_COST` of the life it has left.
##
## The clock is per body, so two strays are two clocks, and a body that walks back
## in loses its clock entirely.
func _tick_bounds(delta: float) -> void:
	if stage == null or not is_instance_valid(stage):
		_outside.clear()
		return
	var centre: Vector3 = stage.global_position
	var reach: float = stage.play_radius()
	var soonest := INF
	for peer in players.keys():
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		var body = run.body
		if body == null or not is_instance_valid(body) or not _flag(body, "alive", true) \
				or _flag(body, "downed", false):
			_outside.erase(peer)
			continue
		var point: Vector3 = (body as Node3D).global_position
		if Vector2(point.x - centre.x, point.z - centre.z).length() <= reach:
			_outside.erase(peer)
			continue
		var seconds := float(_outside.get(peer, 0.0)) + delta
		if seconds >= BOUNDS_SECONDS:
			_outside.erase(peer)
			_pull_back(body)
			continue
		_outside[peer] = seconds
		soonest = minf(soonest, BOUNDS_SECONDS - seconds)
	if soonest == INF:
		_outside_notice = 0.0
		return
	# The warning is the only thing between a body and its life, so it goes out on
	# the first frame outside and then once a second.
	_outside_notice += delta
	if _outside_notice >= 1.0 or _outside_notice == delta:
		_outside_notice = 0.0
		_status("RETURN TO THE FIGHT  ·  %d" % maxi(1, int(ceil(soonest))), 1.2)


## Put a stray back in the middle of the island and charge it for the walk. The
## price is a share of the *current* pool - a body on its last legs loses little -
## and it is taken before the body is moved, so the number the plate shows is the
## one the body paid.
func _pull_back(body) -> void:
	var paid := 0.0
	if body != null and is_instance_valid(body) and body.has_method("pay_cost"):
		paid = float(body.pay_cost(BOUNDS_COST))
	if body != null and is_instance_valid(body):
		(body as Node3D).global_position = stage.middle()
		(body as Node3D).velocity = Vector3.ZERO
		if body.has_method("accept_network_input"):
			body.accept_network_input(Vector2.ZERO, false)
	_status("OUT OF THE FIGHT  ·  %d life gone  ·  the middle of the ring" % roundi(paid), 4.0)


func _tick_throw_regen(delta: float) -> void:
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		var def: Dictionary = Weapons.resolve(run.melee_id)
		var regen := float(def.get("throw_regen", 0.0))
		var cap := int(def.get("throw_charges", 0))
		if regen <= 0.0 or cap <= 0:
			continue
		_throw_clock[peer] = float(_throw_clock.get(peer, 0.0)) + delta
		if float(_throw_clock[peer]) >= regen:
			_throw_clock[peer] = 0.0
			_throw_charges[peer] = mini(cap, int(_throw_charges.get(peer, 0)) + 1)


func _tick_down_check(_delta: float) -> void:
	var standing := 0
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		if not run.is_downed():
			standing += 1
	# A cleared island is not a wipe: bodies on the dirt are waiting for the
	# chest to raise them. Only a live wave with nobody standing ends the run.
	if standing == 0 and not players.is_empty() and wave_active:
		_finish_run(false)


# --- levels ----------------------------------------------------------------

## The level's spend. The island's base grows every ten levels, the level inside
## it grows every wave, and co-op scales the whole thing by +50% for every player
## past the first: two bodies do not fight the same wave.
func wave_budget() -> float:
	var base := LEVEL_BUDGET * pow(ISLAND_GROWTH, float(maxi(0, stage_index)))
	var growth := pow(WAVE_GROWTH, float(maxi(0, wave - 1)))
	var party := 1.0 + 0.5 * float(maxi(0, party_size() - 1))
	# The greed rows that buy bodies are paid for in bodies: Rising Star, Up The
	# Ante and Juggernaut all add to the wave's own budget.
	return base * growth * party * (1.0 + _party_stat("enemy_count_mult"))


func _pick_spec(force_elite: bool) -> Dictionary:
	var faction := str(StageScript.biome(biome_id).faction)
	var pool: Array = FACTIONS.get(faction, FACTIONS["watchers"])
	var rows: Array[Dictionary] = []
	var total := 0.0
	for raw in pool:
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		rows.append(row)
		total += float(row.get("weight", 1.0))
	if rows.is_empty():
		return {}
	var roll := _rng.randf_range(0.0, total)
	var chosen: Dictionary = rows[rows.size() - 1]
	for row in rows:
		roll -= float(row.get("weight", 1.0))
		if roll <= 0.0:
			chosen = row
			break
	chosen = chosen.duplicate(true)
	if force_elite:
		chosen["elite"] = true
		chosen["cost"] = float(chosen.get("cost", 2.0)) * 1.6
	return chosen


func _live_cap() -> int:
	return LIVE_CAP_BASE + LIVE_CAP_PER_PLAYER * maxi(0, party_size() - 1)


func queue_clear() -> void:
	_queue.clear()


func _spawn_from_queue() -> void:
	# Two bodies a beat: enough that a wave arrives as pressure, few enough that
	# the frame a dozen capsules appear on is not the frame a player loses to it.
	var spawned := 0
	while not _queue.is_empty() and spawned < 2:
		var spec: Dictionary = _queue.pop_front()
		var at: Vector3 = stage.random_point(_rng, 6.0) if stage != null else Vector3.ZERO
		_spawn_spec(spec, at)
		spawned += 1
		if _live_mobs() >= _live_cap():
			return


## Every hostile of this level still on its feet, for anything that draws over
## them (the health bars) or counts them. The count above is this list's length,
## read without building it.
func live_mobs() -> Array:
	var out: Array = []
	for mob in _mobs:
		if is_instance_valid(mob) and _flag(mob, "alive", true):
			out.append(mob)
	return out


func _live_mobs() -> int:
	var live := 0
	for mob in _mobs:
		if is_instance_valid(mob) and _flag(mob, "alive", true) and not _flag(mob, "replica", false):
			live += 1
	return live


func _retarget_mobs() -> void:
	var bodies := _body_targets()
	for mob in _mobs:
		if not is_instance_valid(mob) or not _flag(mob, "alive", true):
			continue
		if _flag(mob, "replica", false):
			continue
		if "targets" in mob:
			mob.targets = bodies
		var nearest = _nearest_body(mob.global_position)
		if nearest == null or not mob.has_method("hunt"):
			continue
		# A body already on a quarry is left alone. `hunt` is the order to take one
		# up (and it re-arms the opening charge), so re-issuing it every beat would
		# hold a wave at a run for the whole level - and a clone has no `player`
		# field at all, which is what writing one here used to raise, every beat.
		if mob.has_method("hunting") and bool(mob.call("hunting")):
			continue
		mob.call("hunt", nearest)


## The bodies a typed mob can hold: `devil_mob.gd` declares its quarry list as
## `Array[CharacterBody3D]`, so an untyped array is a type error at the assignment,
## not a missing property.
func _body_targets() -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	for body in _standing_bodies():
		if body is CharacterBody3D:
			out.append(body)
	return out


func _standing_bodies() -> Array:
	var out: Array = []
	for body in _world_bodies():
		if is_instance_valid(body) and _flag(body, "alive", true) and not _flag(body, "downed", false):
			out.append(body)
	return out


func _nearest_body(at: Vector3):
	var best = null
	var best_distance := INF
	for body in _standing_bodies():
		var distance: float = (body as Node3D).global_position.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func _clear_wave() -> void:
	wave_active = false
	_queue.clear()
	_clear_level()


# --- mob spawning ----------------------------------------------------------

## How far under the authored line the wave's health rides, by the level the run
## is on: `OPENING_HEALTH_SCALE` on level one, `1.0` from the tenth level on, and
## a straight line between them. The run is endless, so this is read from `level`
## and never from `wave`: the ramp belongs to the opening island, not to the first
## level of every island.
func opening_health_scale() -> float:
	var played := float(maxi(0, level - 1)) / float(maxi(1, LEVELS_PER_ISLAND - 1))
	return lerpf(OPENING_HEALTH_SCALE, 1.0, clampf(played, 0.0, 1.0))


## The base values the current gate's faction fights on (`FACTION_TUNING`).
func faction_tuning() -> Dictionary:
	return FACTION_TUNING.get(str(StageScript.biome(biome_id).faction),
		FACTION_TUNING["watchers"])


## The depth curve every faction's base rides: one number for the level, before
## the faction's own base is applied. The opening ramp is part of it, so a first
## level is soft whichever gate was taken; nothing else about the wave is.
func depth_health() -> float:
	return (1.0 + 0.13 * float(stage_index) + 0.055 * float(wave)) \
		* opening_health_scale()


func _spawn_spec(spec: Dictionary, at: Vector3) -> void:
	# The base is the faction's; the depth curve is one multiplier on top of it,
	# so a demon gate at level 12 is a harder island than the wood at level 12 and
	# both are easier than either at level 40.
	var tuning := faction_tuning()
	var life := depth_health() * float(tuning.get("health", 1.0))
	var rate := (1.0 + 0.05 * float(stage_index) + 0.02 * float(wave)) \
		* float(tuning.get("rate", 1.0))
	if bool(spec.get("elite", false)):
		life *= 1.9
		rate *= 1.12
	if bool(spec.get("boss", false)):
		life *= 3.1
		rate *= 1.15
	# One pool per body in the run: a second player - a guest or an AI squadmate -
	# doubles every hostile's health, so the party's fight is longer, never easier.
	# The count is the same party the plate reads as ALIVE, and the same one the
	# pedestal draws a row for: everyone who fights scales the wave.
	life *= float(maxi(1, players.size()))
	# The greed mods that make enemies crueller are the party's own: the worst
	# case of every player is what the island answers with.
	var enemy_damage := float(tuning.get("damage", 1.0))
	var enemy_speed := 1.0
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		enemy_damage = maxf(enemy_damage, 1.0 + run.engine.stat("enemy_damage_mult"))
		enemy_speed = maxf(enemy_speed, 1.0 + run.engine.stat("enemy_speed_mult"))
	rate *= enemy_speed
	# Double Trouble's own cost: every body arrives with a bigger pool.
	life *= 1.0 + _party_stat("enemy_health_mult")
	var mob = null
	match str(spec.get("kind", "watcher")):
		"devil":
			mob = _build_devil(spec, at, life, rate, enemy_damage)
		"archer":
			mob = _build_watcher(spec, at, life, rate, enemy_damage, true)
		"clone":
			mob = _build_clone(spec, at, life, rate)
		_:
			mob = _build_watcher(spec, at, life, rate, enemy_damage, false)
	if mob == null:
		return
	_mobs.append(mob)
	_mob_specs[mob.get_instance_id()] = spec
	if world != null and world.get("guards") is Array:
		world.guards.append(mob)
	_broadcast({"t": "mob", "name": str(mob.name), "spec": spec,
		"at": mob.global_position, "life": life, "rate": rate,
		"damage": enemy_damage})
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		_mark_elite(mob, bool(spec.get("boss", false)))


func _mob_name(prefix: String) -> String:
	_mob_serial += 1
	return "Rogue%s_%02d_%04d" % [prefix, stage_index, _mob_serial]


func _build_watcher(spec: Dictionary, at: Vector3, life: float, rate: float,
		damage_scale: float, is_archer: bool):
	var mob = (ArcherScript.new() if is_archer else WatcherScript.new())
	mob.name = _mob_name("A" if is_archer else "W")
	mob.mob_id = str(spec.get("species", "hollow_warden"))
	# The wave's scale rides the body's own dial, read in `_ready` after the runt
	# rule: a runt is a third of a pool at every level, and a warden stays a warden
	# on the opening island's soft line.
	mob.pool_scale = maxf(0.05, life)
	mob.position = at
	world.add_child(mob)
	mob.global_position = at
	mob.home = at
	# The island is an arena, not a town: it names no safe ring, so its centre is
	# not a sanctuary and the wave engages a ranger standing on it.
	mob.safe_center = NO_SAFE_RING
	mob.player = _nearest_body(at)
	# A watcher hunts the nearest body through `player`; only the clone reads a
	# `targets` list, and a class that has no such field is left alone.
	if "targets" in mob:
		mob.targets = _body_targets()
	if is_archer:
		mob.elite = bool(spec.get("elite", false)) or bool(spec.get("boss", false))
		mob.set_anchor(at)
		mob.host = world
	# The watcher's dials, after the body exists: the blow it lands and how often.
	if "blow_scale" in mob:
		mob.blow_scale = damage_scale * (1.35 if bool(spec.get("elite", false)) else 1.0)
	if "swing_gap_scale" in mob:
		mob.swing_gap_scale = 1.0 / maxf(rate, 0.05)
	if "windup_scale" in mob:
		mob.windup_scale = 1.0 / maxf(rate, 0.12)
	# An archer is not a hidden ambusher in a run: it stands its watch on the
	# island, so `hunt` is allowed to hand it a quarry instead of the body
	# clearing its own target every frame until something hits it.
	if is_archer and mob.has_method("stand_watch"):
		mob.stand_watch()
	if mob.has_method("mob_wake"):
		mob.mob_wake()
	# The piece in a melee body's hand. An archer keeps the bow its own `_ready`
	# put there: arming it a club took the string out of the fight.
	if not is_archer and mob.has_method("arm"):
		mob.arm(_watcher_arm())
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	# Every body of the wave is put on the party the frame it lands, melee or bow:
	# a wave that had to find the player by sight alone stood facing whatever it
	# spawned against, and half an island is outside a 140-degree cone.
	_engage(mob, at)
	return mob


## Point a body the wave has just placed at the party. A wave is a fight the
## moment it lands: the nearest standing ranger is handed over as the quarry, so
## nothing stands facing the wall it spawned against waiting to be noticed.
func _engage(mob, at: Vector3) -> void:
	if mob == null or not is_instance_valid(mob):
		return
	var target = _nearest_body(at)
	if target == null or not mob.has_method("hunt"):
		return
	mob.hunt(target)


func _watcher_arm() -> String:
	var arms := ["club_makeshift", "axe_makeshift", "sword_short", "dagger_iron"]
	return str(arms[_rng.randi_range(0, arms.size() - 1)])


func _build_devil(spec: Dictionary, at: Vector3, life: float, rate: float,
		damage_scale: float):
	var mob := DevilScript.new()
	var label := _mob_name("D")
	mob.name = label
	mob.mob_id = str(spec.get("species", "hell_goat"))
	mob.position = at
	world.add_child(mob)
	# The mob class renames itself in `_ready`; the stream finds a body by name,
	# so the run's own name has to be the last word.
	mob.name = label
	mob.global_position = at
	mob.home = at
	mob.safe_center = NO_SAFE_RING
	mob.player = _nearest_body(at)
	mob.targets = _body_targets()
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	if mob.has_method("apply_difficulty"):
		mob.apply_difficulty(life, rate)
	if damage_scale > 1.0:
		mob.profile["damage"] = float(mob.profile.get("damage", 8.0)) * damage_scale
	_engage(mob, at)
	return mob


func _build_clone(spec: Dictionary, at: Vector3, life: float, rate: float):
	var mob := CloneScript.new()
	world.add_child(mob)
	mob.name = _mob_name("C")
	# One depth block above the wave for a boss, never two: the boss is already
	# three times the pool, and its kit should read as the next block's, not as a
	# body from twenty levels deeper than the party.
	mob.configure(_mob_serial, stage_index + 1 + (1 if bool(spec.get("boss", false)) else 0),
		true, "scene")
	# What one of its blows is worth: the pit's base, on the same table the pool
	# and the speed come from. A clone carries a real kit; this is the hand that
	# holds it, not a second body.
	mob.damage_scale = float(faction_tuning().get("damage", 1.0))
	mob.spawn_at(at, at.direction_to(stage.global_position + Vector3(0.0, 0.0, 1.0)))
	mob.targets = _body_targets()
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	if mob.has_method("apply_difficulty"):
		mob.apply_difficulty(life, rate)
	mob.aggro_range = 60.0
	mob.leash = 80.0
	_engage(mob, at)
	return mob


## Guest-side replica of a host spawn. The session's snapshot stream finds a body
## by name, so the copy must exist before the first state arrives; it runs no AI
## and writes nothing but what the wire says.
func _spawn_replica(event: Dictionary) -> void:
	var spec: Dictionary = event.get("spec", {})
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var mob = null
	var kind := str(spec.get("kind", "watcher"))
	if kind == "devil":
		mob = DevilScript.new()
		mob.mob_id = str(spec.get("species", "hell_goat"))
		world.add_child(mob)
		mob.global_position = at
	elif kind == "clone":
		mob = CloneScript.new()
		world.add_child(mob)
		mob.configure(int(event.get("serial", 0)), stage_index + 1, false, "scene")
		mob.spawn_at(at)
	else:
		mob = (ArcherScript.new() if kind == "archer" else WatcherScript.new())
		# A species is read by `_ready`; a replica must be told before it enters
		# the tree, exactly as a host spawn is.
		mob.mob_id = str(spec.get("species", "hollow_warden"))
		# A replica is built at the host's own scale: the wave's life is the
		# health the guest must show, not one it rolls for itself. Both watcher
		# classes take it as the same dial.
		mob.pool_scale = maxf(0.1, float(event.get("life", 1.0)))
		world.add_child(mob)
		mob.global_position = at
	if mob == null:
		return
	mob.name = str(event.get("name", _mob_name("R")))
	if mob.has_method("mark_replica"):
		mob.mark_replica()
	else:
		mob.set("replica", true)
	if "safe_center" in mob:
		mob.safe_center = NO_SAFE_RING
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		_mark_elite(mob, bool(spec.get("boss", false)))
	_mobs.append(mob)
	if world.get("guards") is Array:
		world.guards.append(mob)


func _mark_elite(mob, boss: bool) -> void:
	if mob == null or not is_instance_valid(mob):
		return
	var label := Label3D.new()
	label.text = "BOSS" if boss else "ELITE"
	label.font_size = 64 if boss else 40
	label.pixel_size = 0.006
	label.modulate = Color(1.0, 0.42, 0.26) if boss else Color(1.0, 0.78, 0.35)
	label.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	label.outline_size = 14
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 3.1 if boss else 2.6, 0.0)
	mob.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.2)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0.0, 2.0, 0.0)
	mob.add_child(light)


func _free_mobs() -> void:
	for mob in _mobs:
		if is_instance_valid(mob):
			if world != null and world.get("guards") is Array and world.guards.has(mob):
				world.guards.erase(mob)
			(mob as Node).queue_free()
	_mobs.clear()
	_mob_specs.clear()


func _on_enemy_defeated(enemy, reward: int) -> void:
	if _client or not is_instance_valid(enemy):
		return
	var id: int = (enemy as Node).get_instance_id()
	if _killed.has(id):
		return
	_killed[id] = true
	var spec: Dictionary = _mob_specs.get(id, {})
	_mobs.erase(enemy)
	if world != null and world.get("guards") is Array and world.guards.has(enemy):
		world.guards.erase(enemy)
	total_kills += 1
	# A kill pays gold and leaves nothing else behind: the hand is empty of loot
	# and the body is not a container. Gold is the one currency the run spends
	# (the keys a boss banks are the ledger's, not the purse's), so the wave a
	# party cuts down is exactly what fills the purse it buys with.
	var killer = _killer_of(enemy)
	var mult := 1.0
	if killer != null and is_instance_valid(killer):
		mult = (killer as Object).currency_multiplier()
	var gain := int(ceil(maxf(1.0, float(reward)) * 2.5 * mult))
	_award_gold(gain)
	# The boss is the only thing in the game that pays unlock keys. Every tenth
	# level, one more weapon can be earned; an elite pays gold and nothing else.
	if bool(spec.get("boss", false)):
		_award_keys(3 + int(stage_index / 2), "level %d boss falls" % level)
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		# An elite or a boss comes apart in a way a runt does not: a low ring, a
		# scatter of ashes and a moment of dark red, sized to the body's pool.
		var pool := float((enemy as Object).get("max_health")) \
			if (enemy as Object).get("max_health") != null else 120.0
		ProcFx.kill_pop(stage, (enemy as Node3D).global_position,
			Color(1.0, 0.7, 0.3), clampf(pool / 120.0, 0.8, 3.0))
	# Bonus Chests pays on a body count, not on the level: a chest every
	# `extra_chest_kills` kills, dropped where the body fell.
	var rhythm := int(round(_party_stat("extra_chest_kills")))
	if rhythm > 0:
		_chest_kills += 1
		if _chest_kills >= rhythm:
			_chest_kills = 0
			_spawn_wild_chest((enemy as Node3D).global_position)
	state_changed.emit()
	# The living count and the purse are on the state: a kill is exactly the
	# moment a guest's plate has to hear about them.
	_broadcast_state()


func _killer_of(enemy) -> Variant:
	var last := int(enemy.get("last_hitter")) if "last_hitter" in enemy else -1
	if last < 0:
		return null
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run) or run.body == null:
			continue
		if int(run.body.get("slot")) == last:
			return run
	return null


## The purse every mode spends from. Gold lives in `PlayerState` behind the
## `Warband` autoload, so the town's vendors, the altar's purse and this island's
## stall all read one number: a kill on the island buys a piece at the rack.
func gold() -> int:
	if _client:
		return gold_mirror
	if world != null and world.get("warband") != null:
		return int(world.warband.gold())
	return 0


func _award_gold(amount: int) -> void:
	if amount <= 0:
		return
	# The world's own funnel is the one place a kill is paid, so the campaign's
	# strip and this plate can never drift: it writes the shared purse and
	# repaints the band's counter. Guests are told the resulting total rather
	# than the delta, so a lost or reordered event cannot leave two peers
	# counting different purses.
	if world != null and world.has_method("_pay_kill"):
		world.call("_pay_kill", amount)
	gold_mirror = gold()
	_broadcast({"t": "gold", "total": gold_mirror})


func _award_keys(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	keys_earned += amount
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("award_keys"):
		meta.award_keys(amount, reason)
	_broadcast({"t": "keys", "amount": amount, "reason": reason})


# --- the island's furniture ------------------------------------------------

func _spawn_prop(kind: String, at: Vector3, payload: Dictionary) -> Node3D:
	var node: Node3D = null
	match kind:
		"chest":
			node = Props.chest(stage, at, str(payload.get("tier", "chest")), payload)
		"pedestal":
			# The cards are the local body's three; the payload carries the whole
			# party's table for the wire and the host's books.
			node = Props.pedestal(stage, at, offers_of(payload, local_peer()), payload)
		"greed":
			node = Props.greed_totem(stage, at, payload)
		"shop":
			node = Props.shop(stage, at, payload.get("wares", []), payload)
		"rack":
			node = Props.rack(stage, at, payload)
		"portal":
			# The lintel carries the gate's own name (its faction and biome); the
			# destination is in the payload and the prompt line.
			node = Props.portal(stage, at, str(payload.get("biome", biome_id)),
				str(payload.get("title", payload.get("name", "GATE"))), payload)
	if node == null:
		return null
	_serial += 1
	node.set_meta("serial", _serial)
	_props.append(node)
	_props_by_serial[_serial] = node
	return node


func _broadcast_prop(node: Node3D, kind: String, payload: Dictionary) -> void:
	if node == null:
		return
	_broadcast({"t": "prop", "serial": int(node.get_meta("serial")), "kind": kind,
		"at": node.global_position, "payload": payload})


func _clear_stage_props() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			(prop as Node).queue_free()
	_props.clear()
	_props_by_serial.clear()
	_opened.clear()
	_users.clear()
	draft_offers.clear()
	# A standing field belongs to the level that opened it: a new island is a new
	# set of coordinates and a fresh mob list. A bleed has the same lifetime.
	_zones.clear()
	_bleeds.clear()


## The level is beaten. Every reward stands on the ground and the three gates
## wait for the chest to be opened: a fight pays gold, a level pays an upgrade
## choice, and the gate taken decides the biome of the next level.
func _clear_level() -> void:
	# Belt and braces: every reward below is stood on the island, and a run that
	# has ended has no island left to stand them on.
	if not is_instance_valid(stage):
		return
	level_cleared = true
	wave_active = false
	queue_clear()
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		run.stage_clear()
	_award_gold(12 + 6 * stage_index + 2 * wave)
	# The reward chest, and the extra mini-chest Buried Cache rolls for. A boss
	# leaves its own hoard, on the same one-chest contract.
	var tier := "elite" if boss_level else "chest"
	# The rewards stand together: the chest and the pedestal a step from it are one
	# cluster on the island's party side, so the walk after a wave is a few paces and
	# not a lap of the rim. The three gates stand one short walk past them.
	var chest_at: Vector3 = stage.reward_point(0)
	var chest = _spawn_prop("chest", chest_at, {"tier": tier, "level": level})
	_broadcast_prop(chest, "chest", {"tier": tier, "level": level})
	var extra_chance := 0.0
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run):
			extra_chance = maxf(extra_chance, run.engine.stat("chest_chance"))
	if extra_chance > 0.0 and _rng.randf() < extra_chance:
		var mini = _spawn_prop("chest", stage.reward_point(3, 6, 5.0), {"tier": "mini"})
		_broadcast_prop(mini, "chest", {"tier": "mini"})
	# Care Package and Hoarder bury a chest on a rhythm rather than a chance: one
	# every `extra_chest_islands` islands, which is a promise a player can count.
	var island_rhythm := int(round(_party_stat("extra_chest_islands")))
	if island_rhythm > 0 and (stage_index + 1) % island_rhythm == 0:
		var buried = _spawn_prop("chest", stage.reward_point(4, 6, 5.0), {"tier": "mini"})
		_broadcast_prop(buried, "chest", {"tier": "mini"})
	# The choice: three upgrades each, on a pedestal. This is the run's only
	# growth, and every body in the run draws its own three.
	var pedestal := _stand_pedestal(stage.reward_point(1))
	# The Greed Totem stands on every third level: not on the shop level, where
	# the shop is the point, and not beside a boss.
	if not boss_level and wave % 3 != 0:
		var greed := _spawn_prop("greed", stage.reward_point(1, 6, 5.0), {})
		if greed != null:
			_broadcast_prop(greed, "greed", {})
	# Three gates on: the next level stands behind each of them, and the one the
	# party takes is the biome it fights there.
	_spawn_gates(level + 1)
	_status("LEVEL %d CLEARED  ·  open the chest  ·  three gates wait" % level, 5.0)
	# The allies choose after the clear line, so their picks are the line the
	# party reads rather than one the level's own message overwrites.
	_draft_ai_at(pedestal)
	_broadcast_state()


## The three gates of a cleared level, one per faction. `next_level` is the level
## behind all three: the gates differ in what the party fights, never in how far
## it has got.
func _spawn_gates(next_level: int) -> void:
	var kind := _kind_for_level(next_level)
	for slot in GATES.size():
		var gate: Dictionary = GATES[slot]
		var gate_biome := str(gate.get("biome", "wilderness"))
		var payload := {
			"next_level": next_level,
			"kind": kind,
			"biome": gate_biome,
			"faction": str(gate.get("faction", "watchers")),
			"title": str(StageScript.biome(gate_biome).name),
			"name": "%s  ·  %s" % [_portal_label(next_level, kind),
				str(StageScript.biome(gate_biome).name)],
		}
		var portal = _spawn_prop("portal", _gate_point(slot), payload)
		_broadcast_prop(portal, "portal", payload)


## Where a gate stands: a shallow arc past the reward cluster, clear of the
## chest, the pedestal, the totem and the buried chests.
func _gate_point(slot: int) -> Vector3:
	var anchor: Vector3 = stage.reward_point(0)
	var angle := PI * 0.5 + GATE_FAN * (float(slot) - 1.0)
	return Vector3(anchor.x + cos(angle) * GATE_REACH, anchor.y,
		anchor.z + sin(angle) * GATE_REACH)


## What kind of level stands at `level_number`: a shop before every boss, a boss
## every tenth, and a fight in between.
func _kind_for_level(level_number: int) -> String:
	var mark := level_number % BOSS_EVERY
	if mark == 0:
		return "boss"
	if mark == SHOP_LEVEL:
		return "shop"
	return "combat"


func _portal_label(level_number: int, kind: String) -> String:
	if kind == "boss":
		return "LEVEL %d  ·  THE BOSS" % level_number
	if kind == "shop":
		return "LEVEL %d  ·  THE SHOP" % level_number
	return "LEVEL %d" % level_number


## The pedestal's offers, one row of three per body in the run. Each player rolls
## their own draft - the run's growth is theirs, and so are the three names in
## front of them - and a body already at its ceiling on a mod never sees that row.
func _draft_for_party(surface: String = Mods.SURFACE_PEDESTAL) -> Dictionary:
	var out: Dictionary = {}
	# The ladder uses the best luck in the party: a lucky body is lucky for the
	# warband, which is the one line that keeps a co-op pedestal fair without
	# rolling a different tier for every chair.
	var best := _party_luck()
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		var offers: Array = run.draft(best, surface)
		if offers.is_empty():
			continue
		out[int(peer)] = offers
	return out


## The luck the party's surfaces roll with: the highest any body carries.
func _party_luck() -> int:
	var best := 0
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run):
			best = maxi(best, int(run.luck()))
	return best


## The highest value of one stat any body in the party carries. A shared prop is
## rolled once, so the party's best row is the one the surface answers with.
## Every family any body in the party can use. The shelf is shared; the buyer's
## own `take_mod` still refuses a row that does not fit the hand at the counter.
func _party_carrier_tags() -> Array[String]:
	var out: Array[String] = []
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		for tag in run.carrier_tags():
			if not out.has(tag):
				out.append(tag)
	return out


func _party_stat(key: String) -> float:
	var best := 0.0
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run):
			best = maxf(best, float(run.engine.stat(key)))
	return best


## The offers one peer may pick from. A pedestal's payload carries the whole
## party's table, because every machine draws only its own body's three cards; a
## payload that predates the table is read as the one shared row it was.
func offers_of(payload: Dictionary, peer_id: int) -> Array:
	var raw: Variant = payload.get("offers", [])
	if raw is Dictionary:
		var row: Variant = (raw as Dictionary).get(int(peer_id), [])
		return row if row is Array else []
	return raw if raw is Array else []


func _offers_for(serial: int, peer_id: int) -> Array:
	var table: Dictionary = draft_offers.get(serial, {})
	var row: Variant = table.get(int(peer_id))
	if row is Array:
		return row
	var prop: Node3D = _props_by_serial.get(serial)
	if prop != null and is_instance_valid(prop):
		return offers_of(Props.payload_of(prop), peer_id)
	return []


## Stand the level's pedestal with a row of cards for every body in the run. A
## wave's pedestal is the common chest; the shop level's is the narrower one.
func _stand_pedestal(at: Vector3, surface: String = Mods.SURFACE_PEDESTAL) -> Node3D:
	var table := _draft_for_party(surface)
	var pedestal = _spawn_prop("pedestal", at, {"offers": table})
	if pedestal == null:
		return null
	var serial := int(pedestal.get_meta("serial"))
	draft_offers[serial] = table
	_broadcast_prop(pedestal, "pedestal", {"offers": table})
	return pedestal


## Let every AI body take its pick at once. A squadmate has nobody to read the
## cards for it, so it chooses at random the moment the reward lands and the
## party never waits on a body that cannot answer.
func _draft_ai_at(pedestal: Node3D) -> void:
	if pedestal == null or not is_instance_valid(pedestal):
		return
	var serial := int(pedestal.get_meta("serial"))
	_ai_draft(serial, draft_offers.get(serial, {}))


## Every run body no peer is inside: the warband's own squadmates. A squadmate
## fights on its own, so it drafts on its own too.
func ai_peers() -> Array[int]:
	var out: Array[int] = []
	var held: Array = []
	if world != null and world.get("controller") != null:
		held = world.controller.possessing_peers()
	for peer in players:
		var id := int(peer)
		if id > 0 and not held.has(id):
			out.append(id)
	return out


## The AI's half of the draft: one random offer out of each ally's own three. The
## run's rng makes the pick, so the same seed fields the same allies the same way.
func _ai_draft(serial: int, table: Dictionary) -> void:
	var picks: PackedStringArray = []
	for peer in ai_peers():
		var offers: Array = table.get(peer, [])
		if offers.is_empty():
			continue
		var run = players.get(peer)
		if run == null or not is_instance_valid(run):
			continue
		var mod_id := str(offers[_rng.randi_range(0, offers.size() - 1)])
		var result: Dictionary = run.take_mod(mod_id)
		# The choice is made whether or not the row will take: an ally that never
		# answers its own card would hold the pedestal open forever.
		_claim_use(serial, peer)
		if not bool(result.get("ok", false)):
			continue
		_broadcast({"t": "mod", "peer": peer, "id": mod_id,
			"message": str(result.get("message", ""))})
		picks.append("%s: %s" % [_run_label(run), Mods.name_of(mod_id)])
	if picks.is_empty():
		return
	# The plate's banner is one line, so a full band's picks are named up to three
	# and counted after: seven names and seven mods would run off both edges.
	var shown := picks.slice(0, 3)
	var line := "THE ALLIES CHOOSE  ·  %s" % "  ·  ".join(shown)
	if picks.size() > shown.size():
		line += "  ·  +%d MORE" % (picks.size() - shown.size())
	_status(line, 5.0)


func _run_label(run) -> String:
	if run == null or not is_instance_valid(run):
		return "AN ALLY"
	if int(run.peer_id) == local_peer():
		return "YOU"
	if world != null and world.get("warband") != null and int(run.merc_id) > 0:
		var label := str(world.warband.roster.name_of(int(run.merc_id)))
		if not label.is_empty():
			return label.to_upper()
	return "AN ALLY"


func _shop_wares() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var island := stage_index + 1
	var count := 3 + int(round(_party_stat("shop_offers")))
	var ids := Mods.draft(_rng, count, Mods.surface_tiers(Mods.SURFACE_STALL, island),
		_party_luck(), island, [], _party_carrier_tags())
	# Ring Of Value keeps one ware at half price, and it is always the first: a
	# discount a player cannot find on the shelf is not a discount.
	var discount := _party_stat("shop_discount")
	for index in ids.size():
		var id := ids[index]
		var tier := Mods.rarity_of(id)
		var price := Mods.stall_price(tier, level)
		if index == 0 and discount > 0.0:
			price = maxi(1, int(round(float(price) * (1.0 - discount))))
		out.append({"id": id, "name": Mods.name_of(id), "price": price,
			"rarity": tier})
	return out


# --- interaction -----------------------------------------------------------

func nearest_prop(at: Vector3, reach: float = INTERACT_REACH) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for prop in _props:
		if not is_instance_valid(prop):
			continue
		var distance: float = (prop as Node3D).global_position.distance_to(at)
		if distance <= best_distance:
			best_distance = distance
			best = prop
	return best


## `G` on the island. True when the press belonged to the arena; the world's own
## loot, cages and town services are then never reached.
func interact(actor) -> bool:
	if not run_active or actor == null or not is_instance_valid(actor):
		return false
	var prop := nearest_prop((actor as Node3D).global_position)
	if prop == null:
		return false
	var kind := Props.prop_kind(prop)
	if kind.is_empty():
		return false
	var serial := int(prop.get_meta("serial", 0))
	if _client:
		var payload := Props.payload_of(prop)
		# The two choices are local windows over host-owned facts: the offers and
		# the wares already arrived with the prop, so the guest picks here and
		# the press that spends anything still goes to the host.
		if kind == "pedestal":
			var hud = world.get("roguelite_hud")
			if hud != null and hud.has_method("open_draft"):
				hud.open_draft(serial, offers_of(payload, local_peer()))
				return true
		elif kind == "shop":
			var shop_hud = world.get("roguelite_hud")
			if shop_hud != null and shop_hud.has_method("open_shop"):
				shop_hud.open_shop(serial, payload.get("wares", []))
				return true
		elif kind == "rack":
			var town_node = world.get("town") if world != null else null
			var panel = town_node.get("forge_panel") if town_node != null else null
			if panel != null and panel.has_method("open"):
				panel.open("rack")
				return true
		send_request({"t": "use", "serial": serial})
		# A chest opens for everyone at once in the wire's own time; locally the
		# prop stays until the host's `prop_gone` arrives.
		_status("Sent to the host.", 1.5)
		return true
	match kind:
		"chest":
			_open_chest(serial, actor)
		"pedestal":
			_open_draft(serial, actor)
		"greed":
			_open_greed(serial, actor)
		"shop":
			_open_shop(serial, actor)
		"rack":
			var town_node = world.get("town") if world != null else null
			var panel = town_node.get("forge_panel") if town_node != null else null
			if panel != null and panel.has_method("open"):
				panel.open("rack")
		"portal":
			_take_portal(serial, actor)
		_:
			return false
	return true


func prompt_line(actor) -> String:
	if not run_active or actor == null or not is_instance_valid(actor):
		return ""
	var prop := nearest_prop((actor as Node3D).global_position)
	if prop == null:
		if shop_level:
			return "SHOP LEVEL  ·  spend, kit up, then take a gate"
		if level_cleared:
			return "LEVEL %d CLEARED  ·  the gates wait" % level
		return ""
	match Props.prop_kind(prop):
		"chest":
			if _opened.has(int(prop.get_meta("serial", 0))):
				return ""
			return "G  -  OPEN THE CHEST"
		"pedestal":
			return "G  -  CHOOSE AN UPGRADE"
		"greed":
			return "G  -  BARGAIN WITH THE GREED TOTEM"
		"shop":
			return "G  -  SPEND %d GOLD" % gold()
		"rack":
			return "G  -  THE WEAPON RACK"
		"portal":
			if not shop_level and not _opened.has("chest"):
				return "THE GATES ARE SEALED  ·  open the chest first"
			var payload := Props.payload_of(prop)
			return "G  -  TAKE THE GATE TO %s" % str(payload.get("name", "THE NEXT LEVEL"))
	return ""


func _open_chest(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or not is_instance_valid(prop) or _opened.has(serial):
		return
	var run = player_for(actor)
	if run == null:
		return
	var peer := int(run.peer_id)
	if not _claim_use(serial, peer):
		_status("That chest has already given you its share.", 2.0)
		return
	var payload := Props.payload_of(prop)
	var tier := str(payload.get("tier", "chest"))
	var mult: float = float(run.currency_multiplier())
	var pay_base := 24 if tier == "mini" else (60 if tier == "elite" else 38)
	var pay := int(round(float(pay_base + 10 * stage_index) * mult))
	_award_gold(pay)
	# The chest also hands its opener its mods. It is not a choice; the pedestal
	# is. A chest is the floor of the run's power, not its ceiling - and a boss's
	# hoard is the one place a run's ceiling comes from, so it always carries a
	# legendary.
	var island := stage_index + 1
	var hoard := boss_level and tier != "mini"
	var count := 1 + int(round(run.engine.stat("chest_mods")))
	if hoard:
		count = maxi(2, count)
	var surface := Mods.SURFACE_HOARD if hoard else Mods.SURFACE_CHEST
	var roll: Array[String] = Mods.hoard(_rng, count, int(run.luck()), island,
		[], run.carrier_tags()) if hoard else Mods.draft(_rng, count,
		Mods.surface_tiers(surface, island), int(run.luck()), island, [],
		run.carrier_tags())
	for id in roll:
		var result: Dictionary = run.take_mod(str(id))
		if not bool(result.get("ok", false)):
			continue
		_broadcast({"t": "mod", "peer": peer, "id": str(id),
			"message": str(result.get("message", ""))})
		_status(str(result.get("message", "")), 4.0)
	# One piece of armour per body that opens the chest, on top of the mods and
	# gold. The slot is random, the set is what this level's ladder can pay and
	# never worse than the piece already worn there, and a small chance that
	# grows with the level welds one to three modifiers to it. The piece is the
	# run's own: `wear_armor` puts it on the rig and takes its modifiers, and the
	# roster is never written - the campaign's kit is back in the wardrobe when
	# the portal spits the party into the square.
	var excluded: Array = []
	for id in run.engine.stacks:
		if int(run.engine.stacks[id]) >= Mods.max_stacks(str(id)):
			excluded.append(str(id))
	for id in roll:
		excluded.append(str(id))
	var piece := ArmorLoot.roll(_rng, level, island, _worn_armor(run),
		int(run.luck()), excluded, run.carrier_tags())
	var landed: Dictionary = run.wear_armor(piece)
	if landed.is_empty():
		landed = piece
	_pop_armor(landed, prop.global_position, run)
	_broadcast({"t": "armor", "peer": peer, "piece": landed,
		"at": prop.global_position})
	# A chest is the co-op contract's revive: whoever was on the dirt stands up
	# at half the pool the first time the party opens the reward.
	var first_open := tier != "mini" and not _opened.has("chest")
	if first_open:
		_opened["chest"] = true
		for other_peer in players:
			var other = players[other_peer]
			if other != null and is_instance_valid(other) and other.revive_for_clear():
				_broadcast({"t": "revived", "peer": other_peer})
		_broadcast({"t": "unseal"})
		_status("THE CHEST IS OPEN  ·  %s %s  ·  the gates open" % [
			ArmorLoot.title_of(landed), ArmorLoot.detail_of(landed)], 4.5)
	else:
		_status(ArmorLoot.status_line(landed), 4.5)
	_release_if_spent(serial, "chest", prop)
	state_changed.emit()


## Book one peer's use of a shared prop. False when this peer has already had
## its helping.
func _claim_use(serial: int, peer_id: int) -> bool:
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return false
	users[peer_id] = true
	_users[serial] = users
	return true


## Free a shared prop once every body it was stood for has had its helping. The
## chest only disappears on the last connected player; a pedestal drew a row for
## every body in the run, AI included, and is spent once all of them have chosen.
func _release_if_spent(serial: int, fx_kind: String, prop: Node3D) -> bool:
	var users: Dictionary = _users.get(serial, {})
	var table: Dictionary = draft_offers.get(serial, {})
	if table.is_empty():
		# A chest is shared by the connected players; a pedestal with no row for
		# anyone (every body at its ceiling) follows the same rule.
		if users.size() < maxi(1, party_size()):
			return false
	else:
		# A pedestal is spent once every body it drew for has taken a row - a
		# body it drew nothing for never holds it open.
		for peer in table:
			if not users.has(int(peer)):
				return false
	if prop == null or not is_instance_valid(prop):
		prop = _props_by_serial.get(serial)
	_opened[serial] = true
	_users.erase(serial)
	draft_offers.erase(serial)
	if prop != null and is_instance_valid(prop):
		_props.erase(prop)
		_props_by_serial.erase(serial)
		_broadcast({"t": "prop_gone", "serial": serial, "fx": fx_kind})
		match fx_kind:
			"chest":
				ProcFx.ring(stage, prop.global_position, Color(1.0, 0.8, 0.4), 2.4)
			"pedestal":
				ProcFx.flare(stage, prop.global_position + Vector3.UP,
					Color(0.7, 0.85, 1.0), 0.8)
			"greed":
				ProcFx.ring(stage, prop.global_position, Color(0.8, 0.16, 0.12), 2.2)
		prop.queue_free()
	return true


func _open_draft(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return
	var run = player_for(actor)
	if run == null:
		return
	var peer := int(run.peer_id)
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer):
		_status("You have already taken your choice from this pedestal.", 2.0)
		return
	var offers := _offers_for(serial, peer)
	if offers.is_empty():
		# Every mod this body could still take is already at its ceiling: there
		# is no card to read, and no reason to hold the pedestal for it.
		_claim_use(serial, peer)
		_release_if_spent(serial, "pedestal", prop)
		_status("This pedestal holds nothing you have not already taken.", 2.0)
		return
	var hud = world.get("roguelite_hud")
	if hud != null and hud.has_method("open_draft"):
		hud.open_draft(serial, offers)
	else:
		# Without a panel (a headless harness, a body with no HUD) the first
		# offer is taken: a press must never do nothing.
		choose_draft(peer, serial, 0)


## A draft choice, host side. `peer` is the chooser (a guest's request carries
## the sender, never a claimed id).
func choose_draft(peer_id: int, serial: int, index: int) -> Dictionary:
	if _client:
		send_request({"t": "choose", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return {"ok": false, "message": "That pedestal is spent."}
	var offers := _offers_for(serial, peer_id)
	if index < 0 or index >= offers.size():
		return {"ok": false, "message": "That is not one of the offers."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return {"ok": false, "message": "You have already taken your choice."}
	var result: Dictionary = run.take_mod(str(offers[index]))
	if not bool(result.get("ok", false)):
		return result
	_claim_use(serial, peer_id)
	_broadcast({"t": "mod", "peer": peer_id, "id": str(offers[index]),
		"message": str(result.get("message", ""))})
	_release_if_spent(serial, "pedestal", prop)
	return result


func _open_greed(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return
	var run = player_for(actor)
	if run == null:
		return
	var users: Dictionary = _users.get(serial, {})
	if users.has(run.peer_id):
		_status("The totem has already taken its cut from you.", 2.0)
		return
	var offer := Mods.greed_offer(_rng, run.engine.stacks)
	if offer.is_empty():
		_status("The totem has nothing left to sell you.", 3.0)
		return
	# The bargain: the mod is free, and the body pays a fifth of its own pool in
	# blood on the spot. A body on its last legs cannot take the deal.
	var price := float(run.body.max_health) * 0.2
	if float(run.body.health) <= price + 1.0:
		_status("The totem will not take a body that is already dying.", 3.0)
		return
	var result: Dictionary = run.take_mod(offer)
	if not bool(result.get("ok", false)):
		return
	# The price is paid only for a bargain that was actually struck.
	run.body.health = maxf(1.0, float(run.body.health) - price)
	_claim_use(serial, run.peer_id)
	_broadcast({"t": "mod", "peer": run.peer_id, "id": offer,
		"message": str(result.get("message", ""))})
	_release_if_spent(serial, "greed", prop)
	_status("THE TOTEM TAKES ITS CUT  ·  %s" % Mods.name_of(offer), 4.0)


func _open_shop(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	var wares: Array = shop_wares.get(serial, Props.payload_of(prop).get("wares", []))
	var hud = world.get("roguelite_hud")
	if hud != null and hud.has_method("open_shop"):
		hud.open_shop(serial, wares)
		return
	# No panel: the first ware is the press.
	var buyer = player_for(actor)
	var buyer_peer := int(buyer.peer_id) if buyer != null else local_peer()
	buy(serial, 0, buyer_peer)


func buy(serial: int, index: int, peer_id: int) -> Dictionary:
	if _client:
		send_request({"t": "buy", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return {"ok": false, "message": "That stall is gone."}
	var wares: Array = shop_wares.get(serial, [])
	if index < 0 or index >= wares.size():
		return {"ok": false, "message": "That is not one of the wares."}
	var ware: Dictionary = wares[index]
	if bool(ware.get("sold", false)):
		return {"ok": false, "message": "That one is already sold."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var price := int(ware.get("price", 0))
	if gold() < price:
		return {"ok": false, "message": "The stall wants %d gold; the purse holds %d." % [
			price, gold()]}
	var result: Dictionary = run.take_mod(str(ware.get("id", "")))
	if not bool(result.get("ok", false)):
		return result
	if world != null and world.get("warband") != null:
		world.warband.spend_gold(price)
	gold_mirror = gold()
	_broadcast({"t": "gold", "total": gold_mirror})
	ware["sold"] = true
	wares[index] = ware
	shop_wares[serial] = wares
	_broadcast({"t": "sold", "serial": serial, "index": index, "price": price,
		"peer": peer_id})
	_broadcast({"t": "mod", "peer": peer_id, "id": str(ware.get("id", "")),
		"message": str(result.get("message", ""))})
	return result


## A gate out of a cleared level or a shop level. The host presses it - the host
## owns the level and the party follows; a guest's press is a request and is
## refused here rather than teleporting the table. The gate taken is the biome
## the next level is fought in.
func _take_portal(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	var run = player_for(actor)
	if run == null:
		return
	if int(run.peer_id) != local_peer():
		_status("The host takes the gate.", 2.0)
		return
	if not shop_level and not _opened.has("chest"):
		_status("The gates do not open until the chest is opened.", 3.0)
		return
	if not level_cleared and not shop_level:
		return
	advance_level(str(Props.payload_of(prop).get("biome", biome_id)))


func _peer_label(peer_id: int) -> String:
	if peer_id == local_peer():
		return "YOU"
	if world != null and world.get("warband") != null:
		return world.warband.roster.name_of(_merc_for_peer(peer_id)).to_upper()
	return "P%d" % peer_id


func _merc_for_peer(peer_id: int) -> int:
	if world == null or world.get("controller") == null:
		return -1
	return int(world.controller.merc_for_peer(peer_id))


## Take the next level. Host only. `chosen_biome` is the gate the party walked
## through: the next level is fought in that biome, and the ground is rebuilt for
## it. A new depth block is new ground whatever the gate says, because the island
## itself moves.
func advance_level(chosen_biome: String = "") -> void:
	if not run_active or _client:
		return
	if not (level_cleared or shop_level):
		return
	var next := level + 1
	var next_island := int((next - 1) / LEVELS_PER_ISLAND)
	var target := chosen_biome if not chosen_biome.is_empty() else biome_id
	var moved := next_island != stage_index or target != biome_id
	wave = int((next - 1) % LEVELS_PER_ISLAND) + 1
	stage_index = next_island
	if moved:
		_begin_island(target)
	_begin_level()
	_broadcast_state()
	var kind := _kind_for_level(next)
	if kind == "shop":
		_status("LEVEL %d  ·  SHOP LEVEL  ·  kit up before the boss" % next, 4.0)
	elif kind == "boss":
		_status("LEVEL %d  ·  BOSS  ·  %s" % [next,
			str(StageScript.biome(biome_id).name)], 4.0)
	else:
		_status("LEVEL %d  ·  %s" % [next, str(StageScript.biome(biome_id).name)], 4.0)


# --- ending ----------------------------------------------------------------

## The run ends when the band does. There is no final level: the record is the
## level the last body fell on, and the boss key it earned stays banked.
func _finish_run(_won: bool = false) -> void:
	if not run_active:
		return
	var reached := level
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("note_run"):
		meta.note_run(reached, total_kills)
	_broadcast({"t": "end", "won": false, "level": reached})
	_close_run()
	_status("THE BAND FALLS AT LEVEL %d  ·  back to Hearthstead" % reached, 6.0)


func _close_run() -> void:
	run_active = false
	wave_active = false
	level_cleared = false
	shop_level = false
	boss_level = false
	level = 0
	wave = 0
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		# A run is over; nobody leaves it on the dirt. The roster, the HUD and
		# the world's wipe rule all expect a party that is still standing.
		if run.body != null and is_instance_valid(run.body) \
				and _flag(run.body, "downed", false):
			run.body.revive_from_downed(1.0)
		run.unbind()
		run.queue_free()
	players.clear()
	for body in _saved.keys():
		if not is_instance_valid(body):
			continue
		var spot: Dictionary = _saved[body]
		(body as Node3D).global_position = spot.get("position", (body as Node3D).global_position)
		body.bounds = float(spot.get("bounds", 31.5))
		if body.combat != null:
			body.combat.target_mask = int(spot.get("mask", 2))
		if body.has_method("accept_network_input"):
			body.accept_network_input(Vector2.ZERO, false)
		var merc := _merc_of(body)
		if merc > 0 and world != null and world.get("controller") != null:
			world.controller.refresh_gear(merc)
		if world != null and world.has_method("_wire_projectiles"):
			world._wire_projectiles(body)
	_saved.clear()
	_throw_clock.clear()
	_throw_charges.clear()
	_killed.clear()
	_chest_kills = 0
	var hud = world.get("roguelite_hud") if world != null else null
	if hud != null and hud.has_method("close_all"):
		hud.close_all()
	state_changed.emit()


# --- firing and throwing ---------------------------------------------------

## A run body released a bow or a staff. Answers true when the run owned the
## shot; false leaves the campaign's own firing path to spend it.
func fire(actor, origin: Vector3, direction: Vector3, speed: float, charge: float) -> bool:
	var run = player_for(actor)
	if run == null or not is_instance_valid(run):
		return false
	if run.is_downed():
		return true
	var plan: Dictionary = run.fire_plan(origin, direction)
	if plan.is_empty():
		return false
	# The arena has no quiver: a run is fought with the weapon, not the campaign's
	# stock of shafts. `_spawn_runners` clears the body's ammo gate for the run and
	# `_close_run` hands the campaign's gate back.
	var rig = actor.rig
	var base := float(CombatScript.damage_for(int(rig.bow_index), charge,
		rig.ranged_scale(), rig.flat_bonus("flat_ranged")))
	var profile: Dictionary = run.ranged_profile
	var shots := maxi(1, int(plan.get("shots", 1)))
	var split_shots := maxi(0, int(plan.get("split_shots", 0)))
	var arrow_split := maxi(0, int(plan.get("arrow_split", 0)))
	var split_end := 1 + split_shots
	var arrow_split_end := split_end + arrow_split
	var spread := deg_to_rad(float(plan.get("spread", 0.0)))
	# A split fan needs a fan: a bow with no spread of its own still looses its
	# extra shafts a couple of degrees apart, or they would fly as one arrow.
	if shots > 1:
		spread = maxf(spread, deg_to_rad(2.5))
	var damage_scale := float(plan.get("damage_scale", 1.0)) * float(profile.get("damage_mult", 1.0))
	var crit := bool(plan.get("crit", false))
	if crit:
		damage_scale *= float(plan.get("crit_mult", 2.0))
	var size := float(plan.get("size", 1.0))
	var travel := maxf(0.2, float(plan.get("speed", 1.0)))
	var fall := maxf(0.0, float(plan.get("drop", 1.0)))
	for index in shots:
		var angle := 0.0
		if shots > 1:
			angle = spread * (float(index) - float(shots - 1) * 0.5) * 0.5
		else:
			angle = _rng.randf_range(-spread, spread) * 0.5
		var shot_direction := direction.rotated(Vector3.UP, angle)
		# The first arrow carries the full number; the split fan's extras carry
		# 85%, Split Fletching's carry 25%, and an extra from Double Nock or a
		# recast pays in full.
		var factor := 1.0
		if index >= 1 and index < split_end:
			factor = 0.85
		elif index >= split_end and index < arrow_split_end:
			factor = 0.25
		var damage := base * damage_scale * factor
		var arrow := ArrowScript.new()
		arrow.source_id = int(actor.slot)
		arrow.shooter = actor
		arrow.hit_mask = 1 | 2
		arrow.authoritative_damage = true
		arrow.crit = crit
		arrow.proc_coeff = float(plan.get("proc", 1.0))
		arrow.pierce_growth = run.engine.stat("pierce_growth")
		arrow.gravity_scale = fall
		arrow.damage_filter = run.damage_filter()
		arrow.bounces = int(plan.get("ricochet", 0))
		arrow.bounce_scale = run.engine.hop_scale()
		arrow.homing = float(plan.get("homing", 0.0))
		arrow.spiral = float(plan.get("spiral", 0.0))
		arrow.impact_scale = maxf(0.0, float(plan.get("knockback", 1.0))
			* float(profile.get("gore", 1.0)))
		arrow.homing_provider = Callable(self, "nearest_enemy")
		arrow.bounce_provider = Callable(self, "bounce_target")
		arrow.on_hit = run.hit_hook(profile)
		# A shaft that burns out without a body is the miss Hot Streak counts.
		if not arrow.impacted.is_connected(run.note_shot_impact):
			arrow.impacted.connect(run.note_shot_impact)
		world._arm_projectile(arrow, actor)
		world.add_child(arrow)
		if absf(size - 1.0) > 0.001:
			arrow.scale = Vector3.ONE * size
		# `launch` owns the pierce budget (it resets it from its own argument), so
		# the profile's pierce is handed there rather than written before it.
		arrow.launch(origin, shot_direction, speed * travel, damage,
			world._projectile_exclude(actor), rig.last_arrow_visual_origin,
			int(plan.get("pierce", 0)))
		world._keep_projectile(arrow)
	if shots > 1 or bool(plan.get("scatter", false)):
		ProcFx.flare(stage, origin, Color(0.85, 0.9, 1.0), 0.2)
	return true


## A run body let a blade go. Multi-charge throwing weapons keep their own clock;
## anything else is one throw on a rhythm, exactly as the campaign has it.
func throw_weapon(actor, origin: Vector3, direction: Vector3, speed: float,
		charge: float, weapon: String, weapon_index: int) -> bool:
	var run = player_for(actor)
	if run == null or not is_instance_valid(run):
		return false
	if run.is_downed():
		return true
	var profile: Dictionary = run.melee_profile
	var peer: int = int(run.peer_id)
	var cap: int = int(profile.get("throw_charges", 0))
	if cap > 0:
		var have := int(_throw_charges.get(peer, cap))
		if have <= 0:
			_status("No throw left in the hand  ·  it comes back.", 1.5)
			return true
		_throw_charges[peer] = have - 1
	var rolled: Dictionary = run.engine.roll_crit()
	var crit: bool = bool(rolled.get("crit", false))
	var damage: float = float(CombatScript.throw_damage(weapon, weapon_index, charge,
		actor.rig.throw_scale()))
	damage *= run.damage_multiplier() * float(profile.get("damage_mult", 1.0))
	if crit:
		damage *= float(rolled.get("mult", 2.0))
	var thrown := ThrownScript.new()
	thrown.weapon = weapon
	thrown.weapon_index = weapon_index
	thrown.source_id = int(actor.slot)
	thrown.shooter = actor
	thrown.hit_mask = 1 | 2 | 4
	thrown.authoritative_damage = true
	thrown.crit = crit
	thrown.proc_coeff = float(profile.get("proc", 1.0)) * run.proc_multiplier()
	thrown.gore_mult = float(profile.get("gore", 1.0))
	thrown.impact_scale = maxf(0.0, float(profile.get("knockback", 1.0))
		* run.engine.knockback_multiplier())
	thrown.gravity_scale = 1.35 if str(profile.get("archetype", "")) in [
		"throwing_axe", "javelin"] else 1.0
	thrown.on_hit = run.hit_hook(profile)
	thrown.damage_filter = run.damage_filter()
	thrown.blade_length = float(PlayerArcher.dagger_profile(weapon_index).length) if weapon == "dagger" else float(PlayerArcher.SWORD_DATA[
			clampi(weapon_index, 0, PlayerArcher.SWORD_DATA.size() - 1)].length)
	world._arm_projectile(thrown, actor)
	world.add_child(thrown)
	thrown.piece_id = ""
	thrown.launch(origin, direction, speed, damage, world._projectile_exclude(actor))
	world._keep_projectile(thrown)
	return true


## The nearest hostile a homing shot may turn toward: alive, not a replica and
## not already pierced.
func nearest_enemy(from: Vector3, exclude: Dictionary = {}) -> Node3D:
	var best: Node3D = null
	var best_distance := 30.0
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if exclude.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = mob
	return best


## A ricochet's next body: inside `reach` of the impact and not already struck.
func bounce_target(at: Vector3, taken: Dictionary = {}, reach: float = 12.0) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if taken.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(at)
		if distance <= best_distance and distance > 0.3:
			best_distance = distance
			best = mob
	return best


# --- effects ---------------------------------------------------------------

## The proc engine's decisions become things in the world here. Host only: a
## guest's own effects arrive as the host's `fx` broadcast.
##
## Every branch that lands in the world also draws its own consequence, in the
## colour of the row that fired it (`_proc_colour`). The kinds are deliberately
## not interchangeable: a splash gouts, a spike rises, a whirlwind turns, a blast
## is a pressure front. A host and a guest run the same art for the same kind, so
## a peer that misses the event loses one flash and nothing else.
func execute_effect(run, effect: Dictionary) -> void:
	if run == null or not is_instance_valid(run) or effect.is_empty():
		return
	var at := _body_point(run)
	match str(effect.get("kind", "")):
		"heal":
			var healed: float = float(effect.get("amount", 0.0))
			run.heal(healed)
			ProcFx.heal_motes(world, at, _proc_colour(effect, ProcFx.HEAL),
				clampf(healed * 0.2, 0.3, 3.0))
			_broadcast_fx("heal", at, [], effect, {"power": healed})
		"currency":
			# A negative amount is the price a greed row charges for a landed
			# blow: it leaves the shared purse, it is not awarded backwards.
			var amount: float = float(effect.get("amount", 0.0)) \
				* run.currency_multiplier()
			if amount < 0.0:
				_spend_gold(int(round(-amount)))
			else:
				_award_gold(int(round(amount)))
			ProcFx.gold_glints(world, at, _proc_colour(effect, ProcFx.GOLD),
				clampf(absf(amount) * 0.2, 0.3, 3.0))
			_broadcast_fx("gold", at, [], effect, {"power": amount})
		"kill_credit":
			pass
		"arc":
			_spawn_arc(run, effect)
		"nova":
			_spawn_nova(run, effect)
		"chain":
			_spawn_chain(run, effect)
		"bomb":
			_spawn_bomb(run, effect)
		"shockwave":
			_spawn_shockwave(run, effect)
		"blast", "spike", "splash":
			_blast(run, effect, str(effect.get("kind", "blast")))
		"double":
			_direct_hit(run, effect)
		"zone":
			_open_zone(run, effect)
		"drop_card":
			_drop_card(run, effect)
		"level_up":
			_level_up(run, effect)
		"wound":
			run.defer_wound(effect.get("target"), float(effect.get("damage", 0.0)))
			var wound_at := _point_of(effect, at)
			ProcFx.wound_sear(world, wound_at, _proc_colour(effect, ProcFx.BLOOD))
			_broadcast_fx("wound", wound_at, [], effect)
		"bleed":
			_open_bleed(run, effect)
		"whirlwind":
			_blast(run, effect, "whirlwind")


## The body a run's own effects are centred on: chest height, so a mote, a coin
## and a pillar all leave from the figure rather than from its boots.
func _body_point(run) -> Vector3:
	if run != null and is_instance_valid(run) and run.body != null \
			and is_instance_valid(run.body):
		return run.body.global_position + Vector3.UP * 1.1
	return stage.global_position if is_instance_valid(stage) else Vector3.ZERO


## Where an effect happened: the feet of the victim it named when it has one (a
## wound opens on the body that took it), otherwise the fallback the caller already
## resolved. Floor art starts on the floor.
func _point_of(effect: Dictionary, fallback: Vector3) -> Vector3:
	var target = effect.get("target")
	if target != null and is_instance_valid(target) and target is Node3D:
		return (target as Node3D).global_position
	return effect.get("position", fallback)


## The same point dropped onto the island's own floor. A shot's impact sits on the
## chest of the body it hit, and a pool, a thorn ring or a vortex drawn there would
## hang in the air - the damage volume is a cylinder, so its art is a ground
## area even when the blow landed high.
func _ground(at: Vector3) -> Vector3:
	if not is_instance_valid(stage):
		return at
	return Vector3(at.x, stage.global_position.y, at.z)


## The colour a proc's art is drawn in: the effect kind's own hue, pulled toward
## the rarity of the row that fired it. Two players carrying Arrow Nova and
## Chain Lightning see different ribbons from the same hit, which is the whole
## point of naming the row on the request; a request with no row keeps the hue.
func _proc_colour(effect: Dictionary, base: Color) -> Color:
	var mod := str(effect.get("mod", ""))
	if mod.is_empty():
		return base
	var rarity := Mods.rarity_of(mod)
	var tint: Color = Mods.RARITY_COLOUR.get(rarity, base)
	return base.lerp(tint, 0.45)


## One blow's spill: everything alive inside `radius` pays `damage`, never the
## body the blow already landed on. The `visual` names which art the consequence
## wears - a pressure front for a blast, a gout for splash damage, a ring of thorns
## for a spike, a spiral for a whirlwind - because four rows firing the same maths
## must never read as the same upgrade.
func _blast(run, effect: Dictionary, visual: String) -> void:
	var at: Vector3 = effect.get("position", run.body.global_position if run.body != null else Vector3.ZERO)
	var radius: float = maxf(0.5, float(effect.get("radius", 3.0)))
	var damage: float = float(effect.get("damage", 0.0))
	if damage <= 0.0:
		return
	var skip = effect.get("target")
	var source := int(run.body.slot) if run.body != null else -1
	var hit := false
	for mob in _mobs.duplicate():
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if mob == skip or not _flag(mob, "alive", true):
			continue
		if (mob as Node3D).global_position.distance_to(at) > radius:
			continue
		if mob.has_method("take_damage"):
			mob.take_damage(damage, source, false)
			hit = true
			if _flag(mob, "alive", true) == false:
				run.proc_hit(mob, true, damage)
	if not hit:
		return
	var colour := _proc_colour(effect, ProcFx.SPARK)
	var floor_at := _ground(at)
	# A crit burst is splash maths with a different promise: the star is the crit
	# itself, and the pressure front is only its wake.
	if str(effect.get("mod", "")) == "crit_blast":
		ProcFx.crit_star(world, at + Vector3.UP * 1.0, colour)
		ProcFx.blast_front(world, floor_at, radius, colour)
		_broadcast_fx("crit", floor_at, [], effect, {"radius": radius})
		return
	match visual:
		"spike":
			ProcFx.spike_ring(world, floor_at, radius, colour)
		"splash":
			ProcFx.splash_gout(world, floor_at, radius, colour)
		"whirlwind":
			ProcFx.whirl_vortex(world, floor_at, radius, colour)
		_:
			ProcFx.blast_front(world, floor_at, radius, colour)
	_broadcast_fx(visual, floor_at, [], effect, {"radius": radius})


## Double Tap's second booking: the same body, again, no proc of its own.
func _direct_hit(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	if target == null or not is_instance_valid(target):
		return
	if not _flag(target, "alive", true) or not target.has_method("take_damage"):
		return
	var damaged := float(effect.get("damage", 0.0))
	if damaged <= 0.0:
		return
	var source := int(run.body.slot) if run.body != null else -1
	target.take_damage(damaged, source, false)
	var at: Vector3 = (target as Node3D).global_position + Vector3.UP * 1.15
	ProcFx.double_flash(world, at, _proc_colour(effect, ProcFx.SPARK))
	_broadcast_fx("double", at, [], effect)
	if _flag(target, "alive", true) == false:
		run.proc_hit(target, true, damaged)


## A standing field: a shot's own aura. One entry, ticked at four a second, and
## it costs a dictionary rather than a node with an Area3D on it. The field's own
## art is a `proc_aura.gd` node that pulses for exactly the field's duration, so
## the light a player sees is the volume they are standing in.
func _open_zone(run, effect: Dictionary) -> void:
	var duration: float = maxf(0.1, float(effect.get("duration", 3.0)))
	var per_tick: float = float(effect.get("damage", 0.0)) * 0.25
	if per_tick <= 0.0:
		return
	var at: Vector3 = effect.get("position", run.body.global_position if run.body != null else Vector3.ZERO)
	var radius := float(effect.get("radius", 2.5))
	var floor_at := _ground(at)
	_zones.append({"position": at, "radius": radius,
		"per_tick": per_tick, "left": duration, "clock": 0.0,
		"source": int(run.body.slot) if run.body != null else -1, "run": run})
	ProcFx.zone_field(world, floor_at, radius, duration,
		_proc_colour(effect, ProcFx.HEAL))
	_broadcast_fx("zone", floor_at, [], effect,
		{"radius": radius, "seconds": duration})


func _tick_zones(delta: float) -> void:
	if _zones.is_empty():
		return
	var keep: Array = []
	for entry in _zones:
		var zone: Dictionary = entry
		var left := float(zone.get("left", 0.0)) - delta
		var clock := float(zone.get("clock", 0.0)) + delta
		if left <= 0.0:
			continue
		if clock >= 0.25:
			clock = 0.0
			var at: Vector3 = zone.get("position", Vector3.ZERO)
			var radius: float = float(zone.get("radius", 2.5))
			var amount: float = float(zone.get("per_tick", 0.0))
			var source := int(zone.get("source", -1))
			var run = zone.get("run")
			for mob in _mobs.duplicate():
				if not is_instance_valid(mob) or not (mob is Node3D):
					continue
				if not _flag(mob, "alive", true):
					continue
				if (mob as Node3D).global_position.distance_to(at) > radius:
					continue
				if mob.has_method("take_damage"):
					mob.take_damage(amount, source, false)
					if run != null and _flag(mob, "alive", true) == false:
						run.proc_hit(mob, true, amount)
		zone["left"] = left
		zone["clock"] = clock
		keep.append(zone)
	_zones = keep


## One landed melee hit opens a bleed on the body: a quarter of the wound every
## quarter-second for `seconds`. It follows the body, so a mob that runs does not
## leave its blood behind, and it pays through the same `take_damage` funnel as
## every other wound.
func _open_bleed(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	var total := maxf(0.0, float(effect.get("damage", 0.0)))
	var seconds := maxf(0.1, float(effect.get("seconds", 3.0)))
	if total <= 0.0:
		return
	var ticks := maxf(1.0, seconds / 0.25)
	_bleeds.append({
		"target": target, "per_tick": total / ticks, "left": seconds,
		"clock": 0.0, "source": int(run.body.slot) if run.body != null else -1,
		"run": run,
	})
	# The wound is drawn where the body stands, and it keeps dripping for as long
	# as the clock does: one pool plus a drip emitter, never a node per tick.
	var at: Vector3 = (target as Node3D).global_position
	ProcFx.bleed_drip(world, at, seconds, _proc_colour(effect, ProcFx.BLOOD))
	_broadcast_fx("bleed", at, [], effect, {"seconds": seconds})


func _tick_bleeds(delta: float) -> void:
	if _bleeds.is_empty():
		return
	var keep: Array = []
	for entry in _bleeds:
		var target = entry.get("target")
		if target == null or not is_instance_valid(target) \
				or not _flag(target, "alive", true):
			continue
		var left := float(entry.get("left", 0.0)) - delta
		var clock := float(entry.get("clock", 0.0)) + delta
		if clock >= 0.25:
			clock = 0.0
			var amount := float(entry.get("per_tick", 0.0))
			var run = entry.get("run")
			target.take_damage(amount, int(entry.get("source", -1)), false)
			if run != null and _flag(target, "alive", true) == false:
				run.proc_hit(target, true, amount)
		if left > 0.0:
			entry["left"] = left
			entry["clock"] = clock
			keep.append(entry)
	_bleeds = keep


## Rare Treasure: a body leaves one card on the ground for whoever reaches it. The
## pedestal is the card, so the drop is a pedestal with one offer per body.
func _drop_card(run, effect: Dictionary) -> void:
	var candidates: Array[String] = []
	for id in run.engine.stacks:
		if int(run.engine.stacks[id]) < Mods.max_stacks(str(id)):
			candidates.append(str(id))
	var at: Vector3 = effect.get("position", Vector3.ZERO)
	var offer := Mods.draft(_rng, 1, Mods.surface_tiers(Mods.SURFACE_STALL,
		stage_index + 1), int(run.luck()), stage_index + 1, candidates,
		run.carrier_tags())
	if offer.is_empty():
		return
	var table: Dictionary = {}
	for peer in players:
		var held = players[peer]
		if held == null or not is_instance_valid(held):
			continue
		if int(held.engine.stacks.get(offer[0], 0)) >= Mods.max_stacks(offer[0]):
			continue
		table[int(peer)] = offer
	if table.is_empty():
		return
	var card = _spawn_prop("pedestal", Vector3(at.x, stage.global_position.y, at.z),
		{"offers": table})
	if card == null:
		return
	draft_offers[int(card.get_meta("serial"))] = table
	_broadcast_prop(card, "pedestal", {"offers": table})


## Level Up: two carried rows gain a stack, chosen from what the body holds and
## has not finished. It is the pool's only row that writes to other rows.
func _level_up(run, effect: Dictionary) -> void:
	var picks := maxi(1, int(effect.get("count", 2)))
	var rows: Array[String] = []
	for id in run.engine.stacks:
		if int(run.engine.stacks[id]) < Mods.max_stacks(str(id)):
			rows.append(str(id))
	var raised := 0
	while raised < picks and not rows.is_empty():
		var index := _rng.randi_range(0, rows.size() - 1)
		var id := rows[index]
		rows.remove_at(index)
		if run.engine.add_mod(id):
			raised += 1
	if raised > 0:
		run.apply_stats()
		_status("LEVEL UP  ·  %d upgrade%s stronger" % [raised, "" if raised == 1 else "s"], 4.0)
		# The row that raises other rows gets the tallest read in the file: a
		# column of gold out of the body, so the whole party sees who grew.
		var at := _body_point(run) - Vector3.UP * 1.1
		ProcFx.level_pillar(world, at, _proc_colour(effect, ProcFx.GOLD))
		_broadcast_fx("level_up", at, [], effect)


## A chest dropped by the wave rather than by the level: Bonus Chests' payout.
func _spawn_wild_chest(at: Vector3) -> void:
	var ground := Vector3(at.x, stage.global_position.y, at.z)
	var chest = _spawn_prop("chest", ground, {"tier": "mini"})
	if chest != null:
		_broadcast_prop(chest, "chest", {"tier": "mini"})
		_status("A CHEST FALLS  ·  the dead pay out", 3.0)


## A greed row's price in gold: it leaves the shared purse, and the plate reads
## the new total rather than a delta.
func _spend_gold(amount: int) -> void:
	if amount <= 0:
		return
	if world != null and world.get("warband") != null:
		world.warband.spend_gold(amount)
		gold_mirror = gold()
		_broadcast({"t": "gold", "total": gold_mirror})


func _proc_projectile(run, effect: Dictionary, kind: String, origin: Vector3,
		direction: Vector3, speed: float, radius: float = 0.0) -> Node:
	var node = ProcProjectile.new()
	node.name = "Proc%s" % kind.capitalize()
	node.kind = kind
	node.source_id = int(run.body.slot) if run.body != null else -1
	node.shooter = run.body
	node.hit_mask = 1 | 2
	node.damage = float(effect.get("damage", 0.0))
	node.crit = bool(effect.get("crit", false))
	node.proc = float(effect.get("proc", 1.0))
	node.pierce = int(effect.get("pierce", 0))
	node.radius = radius
	node.life = 1.1
	node.delay = float(effect.get("delay", 0.0))
	node.hit_callback = Callable(run, "proc_hit")
	world.add_child(node)
	node.launch(origin, direction, speed, float(effect.get("damage", 0.0)))
	return node


func _spawn_arc(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	if target == null or not is_instance_valid(target):
		return
	var at: Vector3 = effect.get("position", run.body.global_position)
	var target_at: Vector3 = (target as Node3D).global_position + Vector3.UP * 1.1
	var aim := (target_at - at)
	if aim.length_squared() < 0.001:
		return
	var node = _proc_projectile(run, effect, "dagger", at + Vector3.UP * 1.2,
		aim.normalized(), 26.0, 0.3)
	node.homing_target = target
	node.homing_turn = 8.0
	ProcFx.arc_blade(world, at + Vector3.UP * 1.2, target_at,
		_proc_colour(effect, ProcFx.SPARK))
	_broadcast_fx("arc", at, [target_at], effect)


func _spawn_nova(run, effect: Dictionary) -> void:
	var at: Vector3 = effect.get("position", run.body.global_position)
	var count := maxi(3, int(effect.get("count", 8)))
	var base := _rng.randf_range(0.0, TAU)
	for index in count:
		var angle := base + TAU * float(index) / float(count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_proc_projectile(run, effect, "splinter", at + Vector3.UP * 1.1,
			direction, 20.0, 0.45)
	ProcFx.nova_ring(world, at + Vector3.UP * 0.12,
		_proc_colour(effect, ProcFx.SPARK), count)
	_broadcast_fx("nova", at, [], effect)


func _spawn_chain(run, effect: Dictionary) -> void:
	var from: Vector3 = effect.get("position", run.body.global_position)
	var targets := int(effect.get("targets", 3))
	var damage := float(effect.get("damage", 0.0))
	var hit := {}
	var cursor := from + Vector3.UP * 1.2
	var last = effect.get("target")
	if last != null and is_instance_valid(last):
		hit[(last as Node).get_instance_id()] = true
		cursor = (last as Node3D).global_position + Vector3.UP * 1.2
	var points: Array = []
	for _index in targets:
		var found = _nearest_hostile_excluding(cursor, hit, 14.0)
		if found == null:
			break
		var point: Vector3 = (found as Node3D).global_position + Vector3.UP * 1.2
		points.append(point)
		hit[(found as Node).get_instance_id()] = true
		if found.has_method("take_damage"):
			if run.body != null and found.has_method("note_attacker"):
				found.note_attacker(run.body)
			found.take_damage(damage, int(run.body.slot) if run.body != null else -1, false)
			if _flag(found, "alive", true) == false:
				run.proc_hit(found, true, damage)
		cursor = point
	if points.is_empty():
		return
	# One web for the whole chain, not one arc per leg: the legs of a chain are one
	# thing the player did, and the last node's halo is brighter than the last hop.
	ProcFx.chain_web(world, from + Vector3.UP * 1.2, points,
		_proc_colour(effect, ProcFx.BLOOD))
	_broadcast_fx("chain", from, points, effect)


func _nearest_hostile_excluding(from: Vector3, taken: Dictionary, reach: float):
	var best = null
	var best_distance := reach
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if taken.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = mob
	return best


func _spawn_bomb(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	var at: Vector3 = effect.get("position", run.body.global_position)
	if target != null and is_instance_valid(target):
		at = (target as Node3D).global_position + Vector3.UP * 1.0
	var node = _proc_projectile(run, effect, "bomb", at,
		Vector3.ZERO, 0.0, float(effect.get("radius", 3.0)))
	node.delay = float(effect.get("delay", 1.2))
	node.life = node.delay + 0.5
	ProcFx.bomb_charge(world, at, float(effect.get("radius", 3.0)),
		float(effect.get("delay", 1.2)),
		_proc_colour(effect, ProcFx.BLOOD))
	_broadcast_fx("bomb", at, [], effect, {"radius": float(effect.get("radius", 3.0)),
		"seconds": float(effect.get("delay", 1.2))})


func _spawn_shockwave(run, effect: Dictionary) -> void:
	if run.body == null:
		return
	var forward: Vector3 = effect.get("forward", Vector3.FORWARD)
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -run.body.global_transform.basis.z
	forward = forward.normalized()
	var damage: float = float(effect.get("damage_scale", 0.45)) * float(run.melee_profile.get("proc", 1.0)) * 60.0 * run.damage_multiplier()
	var node = _proc_projectile(run, {"damage": damage, "pierce": effect.get("pierce", 1),
		"crit": bool(effect.get("crit", false))}, "wave",
		run.body.global_position + Vector3.UP * 0.9 + forward * 1.2,
		forward, 18.0, 1.4)
	node.life = 0.42
	ProcFx.shockwave_arc(world, run.body.global_position,
		forward, _proc_colour(effect, ProcFx.SPARK))
	_broadcast_fx("wave", run.body.global_position,
		[run.body.global_position + forward * 6.0], effect)


## One effect, as its peers will draw it. `effect` travels for the two fields the
## art needs and gameplay never does: the row that fired it (the colour) and
## nothing else - damages are the host's, and a guest draws the consequence, not
## the maths. Radius, duration and power ride `extra` for the kinds that need them.
func _broadcast_fx(kind: String, at: Vector3, points: Array,
		effect: Dictionary = {}, extra: Dictionary = {}) -> void:
	var event := {"t": "fx", "kind": kind, "at": at, "points": points}
	var mod := str(effect.get("mod", ""))
	if not mod.is_empty():
		event["mod"] = mod
	for key in extra:
		event[key] = extra[key]
	_broadcast(event)


# --- wire ------------------------------------------------------------------

func _session():
	if world == null:
		return null
	var flow = world.get("flow")
	if flow == null:
		return null
	return flow.get("session")


func _broadcast(event: Dictionary) -> void:
	if _client:
		return
	var session = _session()
	if session != null and session.has_method("send_roguelite_event"):
		session.send_roguelite_event(event)


func _broadcast_state() -> void:
	_broadcast({"t": "state", "seed": run_seed, "island": stage_index + 1,
		"stage": stage_index + 1, "level": level, "wave": wave,
		"levels_per_island": LEVELS_PER_ISLAND, "biome": biome_id,
		"faction": str(StageScript.biome(biome_id).faction),
		"active": wave_active, "cleared": level_cleared,
		"boss_level": boss_level, "boss": boss_level, "shop_level": shop_level,
		"kind": _kind_for_level(level),
		"gold": gold(), "living": _live_mobs(), "kills": total_kills})


func send_request(request: Dictionary) -> void:
	var kind := str(request.get("t", ""))
	if kind in ["start", "sync"] and not request.has("loadout"):
		request["loadout"] = _local_loadout()
	var session = _session()
	if session != null and session.has_method("send_roguelite_request"):
		session.send_roguelite_request(request)


## Host: a guest's request, already attributed by the wire's sender id.
func handle_request(peer_id: int, request: Dictionary) -> void:
	if _client or not run_active:
		return
	var body = world.controller.body_for_peer(peer_id) if world != null else null
	match str(request.get("t", "")):
		"start":
			remember_loadout(peer_id, request.get("loadout"))
			start_run()
		"loadout":
			remember_loadout(peer_id, request.get("loadout"))
			var runner = players.get(peer_id)
			if runner != null and is_instance_valid(runner):
				runner.ranged_id = _loadout_for(peer_id, "ranged")
				runner.melee_id = _loadout_for(peer_id, "melee")
				runner._set_profiles()
				_apply_hands(runner, str(runner._active_slot))
		"sync":
			remember_loadout(peer_id, request.get("loadout"))
			# A guest that joined under a live run is owed the whole picture:
			# which island, which wave, what is standing on it and what is lying
			# on it.
			if run_active:
				_broadcast_state()
				for serial in _props_by_serial:
					var prop: Node3D = _props_by_serial[serial]
					if prop != null and is_instance_valid(prop):
						_broadcast({"t": "prop", "serial": serial,
							"kind": Props.prop_kind(prop),
							"at": prop.global_position,
							"payload": Props.payload_of(prop)})
				for mob in _mobs:
					if not is_instance_valid(mob) or _flag(mob, "replica", false):
						continue
					var spec: Dictionary = _mob_specs.get((mob as Node).get_instance_id(), {})
					_broadcast({"t": "mob", "name": str((mob as Node).name), "spec": spec,
						"at": (mob as Node3D).global_position, "life": 1.0, "rate": 1.0,
						"damage": 1.0})
		"swap":
			if body != null:
				swap_hands(body)
		"use":
			if body != null:
				_use_serial(int(request.get("serial", 0)), body, peer_id)
		"choose":
			choose_draft(peer_id, int(request.get("serial", 0)), int(request.get("index", 0)))
		"buy":
			buy(int(request.get("serial", 0)), int(request.get("index", 0)), peer_id)
		"rebind":
			var slot := str(request.get("slot", ""))
			var weapon := str(request.get("weapon", ""))
			if Weapons.has(weapon) and Weapons.slot_of(weapon) == slot:
				rebind_hand(peer_id, slot, weapon)


func _use_serial(serial: int, actor, peer_id: int = 1) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	match Props.prop_kind(prop):
		"chest":
			_open_chest(serial, actor)
		"pedestal":
			_open_draft(serial, actor)
		"greed":
			_open_greed(serial, actor)
		"shop":
			_open_shop(serial, actor)
		"rack":
			var town_node = world.get("town") if world != null else null
			var panel = town_node.get("forge_panel") if town_node != null else null
			if panel != null and panel.has_method("open"):
				panel.open("rack")
		"portal":
			_take_portal(serial, actor)


## Guest: a reliable event from the host.
func apply_event(event: Dictionary) -> void:
	match str(event.get("t", "")):
		"state":
			_apply_state(event)
		"prop":
			_apply_prop(event)
		"prop_gone":
			_apply_prop_gone(event)
		"mod":
			_apply_mod(event)
		"armor":
			_apply_armor(event)
		"gold":
			# The host's total, not a delta: a guest's plate is the host's purse.
			gold_mirror = maxi(0, int(event.get("total", gold_mirror)))
			state_changed.emit()
		"keys":
			var meta = get_node_or_null("/root/Roguelite")
			if meta != null:
				meta.award_keys(int(event.get("amount", 0)), str(event.get("reason", "")))
		"mob":
			if _client:
				_spawn_replica(event)
		"hands":
			var run = players.get(int(event.get("peer", 0)))
			if run != null and is_instance_valid(run):
				_apply_hands(run, str(event.get("slot", "ranged")))
		"rebind":
			var rebinding = players.get(int(event.get("peer", 0)))
			var rebind_slot := str(event.get("slot", ""))
			var rebind_weapon := str(event.get("weapon", ""))
			if rebinding != null and is_instance_valid(rebinding) \
					and Weapons.has(rebind_weapon):
				if rebind_slot == "ranged":
					rebinding.ranged_id = rebind_weapon
				elif rebind_slot == "melee":
					rebinding.melee_id = rebind_weapon
				rebinding._set_profiles()
				_apply_hands(rebinding, rebind_slot)
		"fx":
			_apply_fx(event)
		"revived":
			var run = players.get(int(event.get("peer", 0)))
			if run != null and is_instance_valid(run):
				run.body.revive_from_downed(0.5)
		"unseal":
			_opened["chest"] = true
		"sold":
			# The ware is the event's whole business: what it cost arrives as the
			# authoritative total on the `gold` event, so a guest never subtracts a
			# price of its own and never counts a purse twice.
			var serial := int(event.get("serial", 0))
			var wares: Array = shop_wares.get(serial, [])
			var index := int(event.get("index", 0))
			if index >= 0 and index < wares.size():
				var ware: Dictionary = wares[index]
				ware["sold"] = true
				wares[index] = ware
		"notice":
			_status(str(event.get("text", "")), float(event.get("seconds", 3.0)))
		"end":
			if _client:
				var meta = get_node_or_null("/root/Roguelite")
				if meta != null and meta.has_method("note_run"):
					meta.note_run(int(event.get("level", 0)), total_kills)
				_close_run()
				_status("THE RUN IS OVER  ·  back to Hearthstead", 5.0)


func _apply_state(event: Dictionary) -> void:
	var was_running := run_active
	run_seed = int(event.get("seed", run_seed))
	var new_stage := maxi(0, int(event.get("island", int(event.get("stage", 1)))) - 1)
	var new_level := int(event.get("level", level))
	var new_biome := str(event.get("biome", biome_id))
	if not was_running or new_level != level:
		_clear_stage_props()
	# Ground is rebuilt when the party moves to a new depth block, when the run
	# begins, or when a gate changed the biome inside the same block: the dressing
	# follows the door that was taken, not the island counter.
	var rebuild := not was_running or new_stage != stage_index \
		or not is_instance_valid(stage) or new_biome != biome_id
	if rebuild:
		stage_index = new_stage
		biome_id = new_biome
		run_active = true
		_build_stage()
		_spawn_runner_replicas()
	level = new_level
	wave = int(event.get("wave", wave))
	wave_active = bool(event.get("active", false))
	level_cleared = bool(event.get("cleared", false))
	shop_level = bool(event.get("shop_level", false))
	boss_level = bool(event.get("boss_level", false))
	gold_mirror = int(event.get("gold", gold_mirror))
	total_kills = int(event.get("kills", total_kills))
	if _client and run_active and _loadout_sent_seed != run_seed:
		# The host dressed this body before it heard from this machine; tell it
		# the pair the rack actually bound here.
		_loadout_sent_seed = run_seed
		send_request({"t": "loadout", "loadout": _local_loadout()})
	state_changed.emit()


func _spawn_runner_replicas() -> void:
	# Guests do not simulate, but their HUD needs a runtime per body for the mod
	# list and the local hand's profile. The body's own hooks are the host's.
	if players.is_empty():
		for body in _world_bodies():
			if not is_instance_valid(body):
				continue
			var merc := _merc_of(body)
			var peer := _peer_of_merc(merc)
			var run = PlayerScript.new()
			world.add_child(run)
			run.bind(body, self, peer, merc, _roster_loadout("ranged"),
				_roster_loadout("melee"))
			players[peer] = run
			if body.get("combat") != null:
				body.combat.ammo_gate = Callable()
			_apply_hands(run, "ranged")


func _apply_prop(event: Dictionary) -> void:
	if not is_instance_valid(stage):
		return
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var kind := str(event.get("kind", ""))
	var payload: Dictionary = event.get("payload", {})
	var node := _spawn_prop(kind, at, payload)
	if node == null:
		return
	var serial := int(event.get("serial", 0))
	if serial > 0:
		node.set_meta("serial", serial)
		_props_by_serial[serial] = node
	if kind == "shop":
		shop_wares[serial] = payload.get("wares", [])


func _apply_prop_gone(event: Dictionary) -> void:
	var serial := int(event.get("serial", 0))
	var prop: Node3D = _props_by_serial.get(serial)
	_opened[serial] = true
	_props_by_serial.erase(serial)
	_props.erase(prop)
	if prop != null and is_instance_valid(prop):
		prop.queue_free()
	var kind := str(event.get("fx", ""))
	if is_instance_valid(stage):
		match kind:
			"chest":
				ProcFx.ring(stage, (prop as Node3D).global_position if prop != null else stage.global_position,
					Color(1.0, 0.8, 0.4), 2.4)
			"pedestal":
				ProcFx.flare(stage, stage.global_position, Color(0.7, 0.85, 1.0), 0.8)


func _apply_mod(event: Dictionary) -> void:
	var peer := int(event.get("peer", 0))
	var run = players.get(peer)
	if run == null or not is_instance_valid(run):
		return
	run.take_mod(str(event.get("id", "")))
	if peer == local_peer():
		_status(str(event.get("message", Mods.name_of(str(event.get("id", ""))))), 4.0)
	state_changed.emit()


## A chest's piece as the host rolled it. The body puts it on and takes its
## welded modifiers here, in the order the host took them, and the pop is drawn
## from the chest the host named - a guest's rig and engine carry what the
## host's do.
func _apply_armor(event: Dictionary) -> void:
	var run = players.get(int(event.get("peer", 0)))
	if run == null or not is_instance_valid(run):
		return
	var raw: Variant = event.get("piece", {})
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return
	var piece: Dictionary = raw
	var kept: Dictionary = run.wear_armor(piece)
	if kept.is_empty():
		kept = piece
	var at := Vector3.ZERO
	if run.body != null and is_instance_valid(run.body) and run.body is Node3D:
		at = (run.body as Node3D).global_position
	var sent: Variant = event.get("at")
	if sent is Vector3:
		at = sent
	_pop_armor(kept, at, run)
	state_changed.emit()


## The host's effect, as a guest draws it. Every kind is the same art the host
## drew, in the same colour, because both sides read the row it names and mix the
## same tint; a kind nobody drew here is a host's newer build, and the guest
## simply shows nothing for it.
func _apply_fx(event: Dictionary) -> void:
	if not is_instance_valid(stage):
		return
	var kind := str(event.get("kind", ""))
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var points: Array = event.get("points", [])
	var effect := {"mod": str(event.get("mod", ""))}
	var radius := float(event.get("radius", 2.0))
	var seconds := float(event.get("seconds", 1.0))
	var power := float(event.get("power", 1.0))
	match kind:
		"arc":
			if points.is_empty():
				return
			var aim: Vector3 = (points[0] as Vector3) - at
			if aim.length_squared() < 0.001:
				return
			ProcFx.arc_blade(world, at + Vector3.UP * 1.2, points[0],
				_proc_colour(effect, ProcFx.SPARK))
			_spawn_visual_proc("dagger", at + Vector3.UP * 1.2, aim.normalized(),
				26.0, 0.3)
		"nova":
			ProcFx.nova_ring(world, at + Vector3.UP * 0.12,
				_proc_colour(effect, ProcFx.SPARK), 8)
			for index in 8:
				var angle := TAU * float(index) / 8.0
				_spawn_visual_proc("splinter", at + Vector3.UP * 1.1,
					Vector3(cos(angle), 0.0, sin(angle)), 20.0, 0.45)
		"chain":
			ProcFx.chain_web(world, at + Vector3.UP * 1.2, points,
				_proc_colour(effect, ProcFx.BLOOD))
		"bomb":
			ProcFx.bomb_charge(world, at, radius, seconds,
				_proc_colour(effect, ProcFx.BLOOD))
			_spawn_visual_proc("bomb", at, Vector3.ZERO, 0.0, radius)
		"wave":
			var wave_forward := Vector3.FORWARD
			if not points.is_empty():
				wave_forward = ((points[0] as Vector3) - at).normalized()
			ProcFx.shockwave_arc(world, at, wave_forward,
				_proc_colour(effect, ProcFx.SPARK))
			_spawn_visual_proc("wave", at + Vector3.UP * 0.9 + wave_forward * 1.2,
				wave_forward, 18.0)
		"blast":
			ProcFx.blast_front(world, at, radius, _proc_colour(effect,
				ProcFx.SPARK))
		"splash":
			ProcFx.splash_gout(world, at, radius, _proc_colour(effect,
				ProcFx.BLOOD))
		"spike":
			ProcFx.spike_ring(world, at, radius, _proc_colour(effect,
				ProcFx.SPARK))
		"whirlwind":
			ProcFx.whirl_vortex(world, at, radius, _proc_colour(effect,
				ProcFx.SPARK))
		"double":
			ProcFx.double_flash(world, at, _proc_colour(effect, ProcFx.SPARK))
		"crit":
			ProcFx.crit_star(world, at + Vector3.UP * 1.0,
				_proc_colour(effect, ProcFx.SPARK))
			ProcFx.blast_front(world, at, radius, _proc_colour(effect,
				ProcFx.SPARK))
		"zone":
			ProcFx.zone_field(world, at, radius, seconds,
				_proc_colour(effect, ProcFx.HEAL))
		"bleed":
			ProcFx.bleed_drip(world, at, seconds, _proc_colour(effect,
				ProcFx.BLOOD))
		"heal":
			ProcFx.heal_motes(world, at, _proc_colour(effect, ProcFx.HEAL),
				clampf(power * 0.2, 0.3, 3.0))
		"gold":
			ProcFx.gold_glints(world, at, _proc_colour(effect, ProcFx.GOLD),
				clampf(absf(power) * 0.2, 0.3, 3.0))
		"wound":
			ProcFx.wound_sear(world, at, _proc_colour(effect, ProcFx.BLOOD))
		"level_up":
			ProcFx.level_pillar(world, at, _proc_colour(effect, ProcFx.GOLD))


## A guest's copy of a proc: the same body, the same flight, no damage.
func _spawn_visual_proc(kind: String, origin: Vector3, direction: Vector3,
		speed: float, radius: float = 0.0) -> void:
	var node = ProcProjectile.new()
	node.visual_only = true
	node.kind = kind
	node.radius = radius
	node.life = 1.0
	if kind == "bomb":
		node.delay = 1.2
		node.life = 1.7
	world.add_child(node)
	node.launch(origin, direction, speed, 0.0)


# --- reporting -------------------------------------------------------------

func state() -> Dictionary:
	return {
		"active": run_active,
		"biome": biome_id,
		"biome_name": str(StageScript.biome(biome_id).name),
		"faction": str(StageScript.biome(biome_id).faction),
		"stage": stage_index + 1,
		"island": stage_index + 1,
		"level": level,
		"wave": wave,
		"level_in_island": wave,
		"levels_per_island": LEVELS_PER_ISLAND,
		"wave_active": wave_active,
		"cleared": level_cleared,
		"boss": boss_level,
		"boss_level": boss_level,
		"shop_level": shop_level,
		"kind": _kind_for_level(level),
		"gold": gold(),
		"keys": keys_earned,
		"kills": total_kills,
		"living": _live_mobs(),
		"party": players.size(),
		"queue": _queue.size(),
		"local_peer": local_peer(),
	}


func _status(text: String, seconds: float = 3.0) -> void:
	if world != null and world.get("hud") != null and world.hud.has_method("set_status"):
		world.hud.set_status(text, seconds)
	# A refusal or a bargain is the party's news, not the host's alone: the same
	# line goes to every guest so a press that did nothing says why there too.
	if not _client and not text.is_empty():
		_broadcast({"t": "notice", "text": text, "seconds": seconds})


## `Object.get` takes a property name and nothing else, while `Dictionary.get`
## takes a fallback. These three helpers keep the arena's many `bool(body.get(...,
## true))` reads from becoming a runtime error on a Node.
static func _flag(object, key: String, fallback: bool = false) -> bool:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else bool(value)


static func _num(object, key: String, fallback: float = 0.0) -> float:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else float(value)


func _world_bodies() -> Array:
	if world == null:
		return []
	var found: Variant = world.get("bodies")
	return found if found is Array else []
