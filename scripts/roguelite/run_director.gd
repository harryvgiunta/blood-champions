class_name RunDirector
extends Node
## The run director: one endless run of levels from the Start Run Portal to the
## wipe that ends it, and the host-authoritative owner of everything inside it.
##
## What it owns: the run seed, the island being fought on, the level counter and
## its budget, the mobs it spawns (their names, factions, elites and bosses), the
## gold a run pays, the unlock keys a boss drops, the reward chests, the shop
## level and its rack, the portal on, and the downed/revive contract of co-op.
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
const AbilityRules = preload("res://scripts/ability_rules.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const CombatScript = preload("res://scripts/combat.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const PlayerArcher = preload("res://scripts/archer.gd")
const ThrownScript = preload("res://scripts/thrown_weapon.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const CasterScript = preload("res://scripts/warband/watcher_caster.gd")
const DemonFireScript = preload("res://scripts/warband/demon_fire.gd")
const DevilScript = preload("res://scripts/devil_mob.gd")
const CloneScript = preload("res://scripts/ranger_clone.gd")
const CloneAi = preload("res://scripts/clone_ai.gd")
## The board a shop level's recruiter stands on: who there is to buy, what they
## carry and what they cost (`scripts/warband/recruit_catalog.gd`).
const Recruits = preload("res://scripts/warband/recruit_catalog.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")

## A run is levels, endless. Every level is a wave; every tenth level is a boss;
## a market stands at 6, 16, 26 ... and the full shop at 9, 19, 29 ... - the
## market is the breath after five combat levels, the shop is the one before the
## boss. A depth block is ten levels of one island's ground, and every cleared
## level stands three gates - the wood, the cave and the pit - so the faction
## fought is the party's own choice, for as long as the band keeps standing.
const LEVELS_PER_ISLAND := 10
const BOSS_EVERY := 10
## The mid-block market: five combat levels first, then a smaller stall and one
## extra chest, no Weapon Rack. This is Crab's current five-combat-then-shop beat.
const MARKET_LEVEL := 6
## The full shop stands at 9, 19, 29 ... - always the level before the boss.
const SHOP_LEVEL := BOSS_EVERY - 1
## The market carries fewer wares than the full shop; both add `shop_offers`.
const MARKET_WARES := 2
const SHOP_WARES := 3
## Every stop stands a recruiter: a board of three bodies, one of each archetype,
## sold for gold and re-rolled on every level load. A recruit is bought for the
## run - it spends no deployment place and adds no pool to the island
## (`_player_count`) - and it dies for good (`WarbandBody.expendable`).
const SHOP_HIRES := 3
## The live cap and the spawn cadence: a wave is a queue that feeds the island,
## not a crowd dropped on one frame. The budget below is how many bodies the
## level is worth; the queue fields them one at a time.
## The level's opening rhythm, one wait per body: the first waits ten seconds,
## the next nine, down to one. The ten entries are the low-level wave; every body
## past the tenth comes at the tail. The waits keep the front of the queue slow
## and turn quick only at the end - not a straight ten-to-one ramp.
const SPAWN_LEAD := 10.0
const SPAWN_TAIL := 1.0
const SPAWN_STEPS := [SPAWN_LEAD, 9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.2, 2.2, SPAWN_TAIL]
## The most bodies a level keeps on the field at once: ten at the opening depth
## block, two more per block and per extra connected player. A field with nothing
## on it pulls the next body in at once (`_tick_spawn`), so this is the ceiling on
## pressure, not a metronome.
const LIVE_CAP_BASE := 10
const LIVE_CAP_PER_ISLAND := 2
const LIVE_CAP_PER_PLAYER := 2
## What a frame can pay for, which is the *other* half of the ceiling above: the
## depth figure is how hard the level means to press, and this is how many bodies
## the machine running it can keep on the floor while it does. Every body on the
## field costs every physics tick - its sweep, its sight, its feet - and when the
## frame slips the engine runs several ticks in a frame to catch up, each of them
## paying for the whole crowd again. That is the shape of a wave that collapses:
## forty bodies at 55 fps become seven, and it does not come back until the wave
## does. So the island measures its own frame and fields only the bodies it can
## afford, a body a beat, with the depth cap as the ceiling and `BUDGET_FLOOR` as
## the least it will ever press with. The wave is unchanged - the queued bodies
## still arrive, in their turn, as the ones on the floor die - so a deep level is
## fought in waves that fit the frame rather than in a crowd that does not.
const BUDGET_SLOW_MS := 20.0
const BUDGET_FAST_MS := 14.0
const BUDGET_FLOOR := 6
const BUDGET_INTERVAL := 0.75
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

## The peer id an AI-driven body is filed under: a squadmate has no peer, so the
## run files it at `ALLY_PEER_BASE` + its mercenary id (`_peer_of_merc`). A real
## peer is a human at the table, and only humans scale the island (`_player_count`).
const ALLY_PEER_BASE := 1000

## The three factions and what every biome fields. `cost` is the budget a body
## spends; `kind` is which class builds it.
const FACTIONS := {
	"watchers": [
		{"kind": "watcher", "species": "hollow_runt", "cost": 1.0, "weight": 5},
		{"kind": "watcher", "species": "hollow_warden", "cost": 3.0, "weight": 4},
		{"kind": "archer", "species": "hollow_warden", "cost": 4.0, "weight": 2},
		# The Hollow's caster earns its place from level five: one random fire
		# rite, the new Fire Ray among them. It costs a bowman and then some -
		# a line spell is worth more than a single arrow - and it stays rare so
		# a wave still reads as the wood's bodies with a caster in it.
		{"kind": "caster", "species": "hollow_warden", "cost": 4.5,
			"weight": 3, "min_level": 5},
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
	# A clone costs a ranger's worth and then some - fourteen, so a base budget of
	# 26 buys two - because a real kit, a dodge and a guard are worth more than a
	# warden's club. At seven the first pit a gate can hand a party (level two,
	# the earliest door out of the wood) stood four bodies on an open gate and
	# melee still could not get through it; half the crowd is the pit as it reads.
	"clones": [
		{"kind": "clone", "species": "", "cost": 14.0, "weight": 5},
		{"kind": "clone", "species": "", "cost": 14.0, "weight": 5},
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

## A gate is a contract now: a destination, a trial, and the chest the next
## level keeps. Trials are the only combat modifiers in this first slice; the
## opening/elite/swarm three are enough to make the choice read without adding
## a new objective.
const TRIAL_OPEN := "open"
const TRIAL_ELITE := "elite"
const TRIAL_SWARM := "swarm"
const TRIALS := [TRIAL_OPEN, TRIAL_ELITE, TRIAL_SWARM]
const TRIAL_LABEL := {
	TRIAL_OPEN: "OPEN",
	TRIAL_ELITE: "ELITE",
	TRIAL_SWARM: "SWARM",
}
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
## A market or the full shop: no mobs, the stall and the shop's chest.
## `market_level` is the light version at level 6; `shop_level` is true for both.
var shop_level := false
var market_level := false
## A guest's copy of the host's purse. The host reads its own `Warband` total;
## a guest cannot see that machine's `PlayerState`, so the wire carries the total
## after every change and this is what the plate reads.
var gold_mirror := 0
var total_kills := 0
var keys_earned := 0
var draft_offers: Dictionary = {} # serial -> {peer_id: Array[String]}
var shop_wares: Dictionary = {}   # serial -> Array[Dictionary]
## The recruiter's board each stop stood: serial -> Array[Dictionary] of
## `RecruitCatalog.offer` rows. Rolled with the stall's rack, on the level load.
var recruit_board: Dictionary = {} # serial -> Array[Dictionary]
## The contract the current level was fought under: its trial and the chest it
## promised. Set at run start, then by the gate the party takes.
var active_contract: Dictionary = {}
var _trial_budget_mult := 1.0
var _trial_live_cap_add := 0
var _trial_extra_elites := 0
## The crowd the frame has earned: how many bodies the island keeps on the floor
## right now, between `BUDGET_FLOOR` and the depth cap (`_live_cap`). 0 until the
## island has measured a frame, which reads as the depth cap.
var _earned_cap := 0
## The frame as the engine last drew it, milliseconds, smoothed.
var _frame_ms := 0.0
var _budget_clock := 0.0
## The route board rolls on its own generator so it cannot perturb the reward
## or mob rolls when code order changes.
var _route_rng := RandomNumberGenerator.new()
## A casting body's rite rolls on its own generator too: adding a spell to an
## archer must not shift the run's reward or mob sequence, which is the same
## reason the route board has its own.
var _rite_rng := RandomNumberGenerator.new()
## The admin console's gate roll counter. The route board is deterministic in
## `run_seed` and the level, so a "roll again" press is the one thing that has to
## move the seed: it is folded into the gate's own seed and reset with the run.
var _gate_salt := 0
## Which bodies have already been paid the chest's gold/armour. A choice chest
## is opened again by the same body until it picks; the payout happens once.
var _chest_paid: Dictionary = {}
## The serials of the level's **main** chests - the contract's promise, once a
## soul - and the ones a soul has opened. The party is raised on the first, and
## the gates unseal when the last one is opened, so nobody walks a gate out of a
## level whose own box they never opened.
var _main_chests: Array[int] = []
var _main_open: Dictionary = {}
## True once this level's first main chest has raised the downed.
var _level_raised := false

var _rng := RandomNumberGenerator.new()
var _saved: Dictionary = {}
var _mobs: Array = []
## The bodies this level has already killed. A corpse leaves `_mobs` the frame it
## falls - it is no target - and leaves the world when the next level begins.
var _corpses: Array = []
var _mob_specs: Dictionary = {}   # instance id -> spec
var _props: Array = []
var _props_by_serial: Dictionary = {}
var _opened: Dictionary = {}
## Which peers have already taken a chest's offer. One box, one helping: a chest
## is stood for one soul and spends itself when that soul picks.
var _users: Dictionary = {}
var _queue: Array[Dictionary] = []
var _spawn_clock := 0.0
## Bodies this level's queue has already fielded: the next wait comes off the
## queue's own progress (`spawn_interval`).
var _spawn_done := 0
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
var _client := false
## `{peer: seconds}` - how long each run body has been standing outside the island's
## fight ring. Cleared the frame the body comes back in.
var _outside: Dictionary = {}
## How long since the warning last went out, so a stray is told once a second and
## not once a frame.
var _outside_notice := 0.0


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


## The run a body is inside, `null` when no live run owns it. The character
## screen reads the run's own armour through this: a chest's piece lives on the
## run, not in the roster, so the body inside it is the only place it exists.
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
## holding now (`_active_slot`) and `off` the other one TAB reaches. Both are the
## body's own kit - the run reads the inventory through `Weapons.hand_pair`, so
## the page names the same two pieces the island carries. `{}` when no run owns
## the body, which leaves the roster's worn rows as the whole truth.
func hands_for_merc(merc_id: int) -> Dictionary:
	var run = run_of_merc(merc_id)
	if run == null:
		return {}
	return _hands_of(str(run.ranged_id), str(run.melee_id), str(run._active_slot))


func _hands_of(ranged_id: String, melee_id: String, active: String) -> Dictionary:
	var main_id := ranged_id if active != "melee" else melee_id
	var off_id := melee_id if active != "melee" else ranged_id
	return {"main": main_id, "off": off_id}


## The skill keys the run's own upgrades have bought the body this session, 0
## outside a run: `Widened Bar` is one per stack and the rig clamps the row at
## `AbilityRules.MAX_SLOT_COUNT`. The screen draws the row the fight fires, so it
## reads the same figure the body was dressed with.
func bar_keys_for_merc(merc_id: int) -> int:
	var run = run_of_merc(merc_id)
	if run == null or run.engine == null:
		return 0
	return clampi(int(run.engine.stat("hotbar_slots")), 0,
		AbilityRules.MAX_SLOT_COUNT - AbilityRules.SLOT_COUNT)


## The upgrades the run has taken on a body, in the pool's own order: one row per
## card with its stack count. Empty outside a run, which is what the screen says
## when no island is live.
func upgrades_for_merc(merc_id: int) -> Array[Dictionary]:
	var run = run_of_merc(merc_id)
	if run == null or run.engine == null:
		return []
	return run.engine.mod_list()


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


## BEGIN. Host only: starts a fresh seed, carries the party's own kit onto the
## island, stands level one under their feet and sends its wave. A guest's press
## is a request to the host.
func start_run() -> Dictionary:
	if run_active:
		return {"ok": false, "message": "A run is already live."}
	if _client:
		send_request({"t": "start"})
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
	market_level = false
	boss_level = false
	# The purse is not reset: gold is the player's, and a run spends what the
	# town's racks, vendors and bosses have filled.
	total_kills = 0
	keys_earned = 0
	draft_offers.clear()
	shop_wares.clear()
	recruit_board.clear()
	_chest_paid.clear()
	active_contract = _starter_contract()
	_route_rng.seed = run_seed
	_rite_rng.seed = run_seed ^ 0x5bd1e995
	_gate_salt = 0
	_trial_budget_mult = 1.0
	_trial_live_cap_add = 0
	_trial_extra_elites = 0
	# The crowd the last run's frames earned is not this machine's answer for this
	# one: the island measures its own frame before it thins anything.
	_earned_cap = 0
	_frame_ms = 0.0
	_budget_clock = 0.0
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
	market_level = false
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
	market_level = wave == MARKET_LEVEL
	shop_level = market_level or wave == SHOP_LEVEL
	boss_level = wave == BOSS_EVERY
	level_cleared = false
	wave_active = false
	queue_clear()
	_spawn_done = 0
	_spawn_clock = spawn_interval(0)
	_clear_stage_props()
	_free_mobs()
	if active_contract.is_empty():
		active_contract = _starter_contract()
	_apply_contract()
	if shop_level:
		var stop_chest := _spawn_shop_level(market_level)
		var line := "LEVEL %d  ·  SHOP LEVEL  ·  the boss waits beyond the gates" % level
		if market_level:
			line = "LEVEL %d  ·  MARKET  ·  spend, then the road continues" % level
		_status(line, 5.0)
		# The allies pick after the stop's line, exactly as they do after a wave.
		var stop_payout := str(stop_chest.get("payout", ""))
		if stop_payout == Mods.PAYOUT_CARDS or stop_payout == Mods.PAYOUT_SKILLS:
			_draft_ai(str(stop_chest.get("surface", "")), str(stop_chest.get("tier", "")))
		_broadcast_state()
		return
	wave_active = true
	var budget := wave_budget()
	if boss_level:
		var boss_spec: Dictionary = (BOSSES.get(StageScript.biome(biome_id).faction,
			BOSSES["watchers"]) as Dictionary).duplicate(true)
		# The boss archer is an archer: from level two it carries a rite too.
		_queue.append(_assign_rite(boss_spec))
		budget -= 10.0
	# Elites from the second level of an island on: a heavier body every other
	# wave, and the boss level's escort always carries one.
	if wave >= 2 and not boss_level:
		var elite_spec := _pick_spec(true)
		if not elite_spec.is_empty():
			_queue.append(elite_spec)
			budget -= float(elite_spec.cost)
	for _extra in _trial_extra_elites:
		var extra_spec := _pick_spec(true)
		if extra_spec.is_empty():
			break
		_queue.append(extra_spec)
		budget -= float(extra_spec.cost)
	while budget > 0.0:
		var spec := _pick_spec(false)
		if spec.is_empty():
			break
		_queue.append(spec)
		budget -= maxf(0.5, float(spec.cost))
	_spawn_clock = spawn_interval(0)
	var line := "LEVEL %d  ·  %d bodies inbound" % [level, _queue.size()]
	var trial_label := str(TRIAL_LABEL.get(str(active_contract.get("trial", "")), ""))
	if trial_label != "" and trial_label != "OPEN":
		line = "LEVEL %d  ·  %s  ·  %s  ·  %d bodies inbound" % [level,
			trial_label, str(StageScript.biome(biome_id).name), _queue.size()]
	if boss_level:
		line = "LEVEL %d  ·  BOSS  ·  %s STIRS" % [level, str(StageScript.biome(biome_id).name)]
	_status(line)
	_broadcast_state()


## A shop stop: the town's business standing on the level's own ground. No mobs,
## no clock, and a player can stand here as long as they like. The full shop at
## 9 carries the rack; the mid-block market at 6 is the smaller stop.
## Answers the chest promise it stood, so the allies can read their card off it.
func _spawn_shop_level(market: bool = false) -> Dictionary:
	var wares := _shop_wares(market)
	var shop_payload := {
		"wares": wares,
		"market": market,
		"label": "THE MARKET" if market else "THE SHOP ISLAND",
	}
	# The stop's business is one cluster: the stall, the rack (full shop only) and
	# the chest stand a few paces apart, with the three gates beyond them.
	var shop = _spawn_prop("shop", stage.reward_point(0, 4, 3.2), shop_payload)
	if shop != null:
		shop_wares[int(shop.get_meta("serial"))] = wares
		_broadcast_prop(shop, "shop", shop_payload)
	# The recruiter stands his own desk at every stop, market or shop: three bodies
	# for sale, re-rolled with this level, on the fourth place of the cluster's own
	# ring - across from the stall, so a body reading one is not inside the other's
	# reach.
	var hires := _shop_hires()
	var recruiter_payload := {
		"hires": hires,
		"market": market,
		"label": "THE RECRUITER",
	}
	var recruiter = _spawn_prop("recruiter", stage.reward_point(3, 4, 3.2),
		recruiter_payload)
	if recruiter != null:
		recruit_board[int(recruiter.get_meta("serial"))] = hires
		_broadcast_prop(recruiter, "recruiter", recruiter_payload)
	if not market:
		var rack = _spawn_prop("rack", stage.reward_point(1, 4, 3.2), {})
		if rack != null:
			_broadcast_prop(rack, "rack", {})
	# Every stop offers one more upgrade: the safe level is also the breath
	# before the wall, and the chest is the one prop that deals one. Its surface
	# and tier are the route's own roll on this level, so a party that walks in
	# twice in the same seed reads the same promise.
	var chest_slot := 1 if market else 2
	var promise := _stand_stop_chest(chest_slot, maxi(1, player_peers().size()))
	# The next level is fought in whichever biome the party walks into.
	_spawn_gates(level + 1)
	return promise


func _build_stage() -> void:
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = StageScript.new()
	stage.name = "RogueliteIsland"
	stage.stage_index = stage_index
	stage.position = StageScript.centre_for(stage_index)
	world.add_child(stage)
	stage.build(biome_id, run_seed, stage_index)
	# The Hollow's chamber carries its own air - a fog and an ambient light the
	# open islands do not have; an open island hands the eye the world's sky back.
	if world != null and world.get("camera") != null:
		world.camera.environment = stage.air()


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
	var yaw: float = stage.entry_yaw() if stage != null else 0.0
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
		# The island is nobody's home ground: the town's hold on a downed body is
		# the square's rule and stops at its stakes.
		body.home_ground = false
		if body.combat != null:
			body.combat.target_mask = 2
		var post: Vector3 = posts[index] if index < posts.size() else stage.floor_point(Vector2.ZERO)
		(body as Node3D).global_position = post
		(body as Node3D).rotation.y = yaw
		(body as Node3D).velocity = Vector3.ZERO
		if body.has_method("revive_from_downed") and _flag(body, "downed", false) \
				and not _flag(body, "expendable", false):
			# The walk onto the island stands a soul up at full health; a hireling
			# on his chest is the ten seconds' business and is not carried in.
			body.revive_from_downed(1.0)


## One runtime per body. The loadout it applies is the body's own kit, read out of
## the inventory through `hand_pair_for`: the two weapon sets the town's page
## shows are the two hands the island carries, without the campaign's roster ever
## being written.
func _spawn_runners() -> void:
	# A body that already has a runtime keeps it: the mods are the *run's*, not
	# the island's, and a fresh engine on every portal would delete the draft the
	# party just fought for. The copy has to be a real one - a Dictionary is a
	# reference, so `players` on its own is emptied by the `clear()` below and
	# every body would walk onto the next island with an empty engine.
	var previous := players.duplicate()
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
			run._active_slot = "ranged" if not str(run.ranged_id).is_empty() else "melee"
			_apply_hands(run, str(run._active_slot))
			_throw_charges[peer] = int(Weapons.resolve(run.melee_id).get("throw_charges", 0))
			_throw_clock[peer] = 0.0
			run.apply_stats()
			continue
		var pair := hand_pair_for(merc)
		var ranged := str(pair.get("ranged", ""))
		var melee := str(pair.get("melee", ""))
		run = PlayerScript.new()
		world.add_child(run)
		run.bind(body, self, peer, merc, ranged, melee)
		run._active_slot = "ranged" if not ranged.is_empty() else "melee"
		players[peer] = run
		if body.get("combat") != null:
			body.combat.ammo_gate = Callable()
		_apply_hands(run, str(run._active_slot))
		_throw_charges[peer] = int(Weapons.resolve(melee).get("throw_charges", 0))
		_throw_clock[peer] = 0.0
		run.apply_stats()
		if float(body.health) <= 1.0:
			body.health = float(body.max_health)


## The two weapons a body carries into the run: the inventory's own hands, one per
## weapon set, classified by the armory's registry. Never a ledger and never a
## default pair - a body whose kit holds nothing walks in with empty hands.
func hand_pair_for(merc_id: int) -> Dictionary:
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ranged": "", "melee": ""}
	return Weapons.hand_pair(warband.roster, merc_id)


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
	return ALLY_PEER_BASE + maxi(1, merc_id)


## How many human souls are in the party. The island's pools scale with this and
## with nothing else: an AI body - a squadmate the town's desk swore, or a body
## hired off the shop's own board - fights the same wave a lone soul does, so
## buying help makes the fight longer to win, never newer to survive.
func _player_count() -> int:
	var count := 0
	for peer in players:
		if int(peer) < ALLY_PEER_BASE:
			count += 1
	return maxi(1, count)


## Dress the body for one hand without touching the roster: the campaign's kit
## keeps its armour, trinkets and copies; only the held piece and the pose change.
## An empty hand dresses the body bare rather than leaving the other hand's piece
## in it under this hand's name.
func _apply_hands(run, slot: String) -> void:
	if run == null or not is_instance_valid(run) or run.body == null:
		return
	var weapon_id := str(run.ranged_id) if slot == "ranged" else str(run.melee_id)
	if _dress_weapon(run.body, run.merc_id, weapon_id):
		run._active_slot = slot


## Put one weapon in a body's hands while keeping everything else it wears. The
## roster is never written: a run's weapons are the run's, and the piece the
## campaign gave the body is still in its ledger when the island is done with it.
## An empty `weapon_id` is a bare hand, which is what a body whose kit carries no
## piece for that hand really holds.
func _dress_weapon(body, merc_id: int, weapon_id: String) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not weapon_id.is_empty() and Weapons.resolve(weapon_id).is_empty():
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
	var trinkets := {"off": ""}
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


## TAB inside a run. The campaign's swap is a roster verb; an arena run's swap is
## the other hand of the same kit, and it is the host's to make for a guest.
func swap_hands(body) -> void:
	var run = player_for(body)
	if run == null:
		return
	# Cursed Arsenal locks the *pieces*, not the hands: the pair cannot be
	# replaced for the rest of the run, but a body still reaches both of them.
	var next := "melee" if str(run._active_slot) == "ranged" else "ranged"
	var other := str(run.ranged_id) if next == "ranged" else str(run.melee_id)
	if other.is_empty():
		# An empty hand has nothing to put up; the rig stays on the piece it
		# holds rather than being asked to wear nothing under the other name.
		_status("The other hand is empty: the body's kit carries one piece.")
		return
	if _client:
		send_request({"t": "swap"})
		_apply_hands(run, next)
		return
	_apply_hands(run, next)
	_broadcast({"t": "hands", "peer": run.peer_id, "slot": next})


## The rack pressed a hand for a body in a live run (a shop level, where the
## town's business stands on the island). The piece is worn through the warband -
## the inventory is the one place a carried weapon comes from - and the run then
## re-reads the pair, so the island holds exactly what the page shows. A guest's
## request reaches the host through `rebind`.
func rebind_hand(peer_id: int, slot: String, weapon_id: String) -> Dictionary:
	if slot != "ranged" and slot != "melee":
		return {"ok": false, "message": "That is not a hand."}
	if not Weapons.has(weapon_id) or Weapons.slot_of(weapon_id) != slot:
		return {"ok": false, "message": "That piece does not belong to that hand."}
	if _client:
		send_request({"t": "rebind", "slot": slot, "weapon": weapon_id})
		return {"ok": true, "pending": true, "message": "The host is changing the hand."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "No body of that peer is in the run."}
	if bool(run.hands_locked_now()):
		return {"ok": false, "message": "The hands are locked for this run."}
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ok": false, "message": "There is no warband to draw the piece from."}
	var result := _wear_hand(run, slot, weapon_id)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", ""))}
	_broadcast({"t": "rebind", "peer": peer_id, "slot": slot, "weapon": weapon_id})
	return {"ok": true, "message": str(result.get("message", ""))}


## Wear one piece in one of a run body's hands: the warband moves the copy and
## the run re-reads the pair it carries, so the island holds exactly what the
## page shows. Shared by the rack's press (`rebind_hand`) and the admin console's
## grant, which is why the lock is checked by the caller.
func _wear_hand(run, slot: String, weapon_id: String) -> Dictionary:
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ok": false, "message": "There is no warband to draw the piece from."}
	var peer_id := int(run.peer_id)
	var result: Dictionary = warband.equip_hand(int(run.merc_id), slot, weapon_id)
	if not bool(result.get("ok", false)):
		return result
	var pair := hand_pair_for(int(run.merc_id))
	run.ranged_id = str(pair.get("ranged", ""))
	run.melee_id = str(pair.get("melee", ""))
	run._set_profiles()
	_apply_hands(run, slot)
	_throw_charges[peer_id] = int(Weapons.resolve(run.melee_id).get("throw_charges", 0))
	_throw_clock[peer_id] = 0.0
	run.apply_stats()
	return result


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
	_tick_budget(delta)
	_tick_spawn(delta)
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
		if stage.contains(point):
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
	return base * growth * party * (1.0 + _party_stat("enemy_count_mult")) \
		* _trial_budget_mult


func _pick_spec(force_elite: bool) -> Dictionary:
	var faction := str(StageScript.biome(biome_id).faction)
	var pool: Array = FACTIONS.get(faction, FACTIONS["watchers"])
	var rows: Array[Dictionary] = []
	var total := 0.0
	for raw in pool:
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		# A row may open later than the island does: the Hollow's caster first
		# walks at level five, whatever gate the party took to get there.
		if level < int(row.get("min_level", 0)):
			continue
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
	return _assign_rite(chosen)


## Roll the fire rite a casting body carries, on the authority, into the spec:
## every peer builds the same body carrying the same spell. The Hollow's casters
## wait for level five; its archers begin casting at level two, so the second
## wave already answers a bow with a spell. A spec that is neither, or is below
## its level, is returned untouched.
func _assign_rite(spec: Dictionary) -> Dictionary:
	var spell_level := 0
	match str(spec.get("kind", "")):
		"caster": spell_level = 5
		"archer": spell_level = 2
	if spell_level <= 0 or level < spell_level:
		return spec
	var rites: Array = DemonFireScript.RITE_POOL
	# An archer holds a ring 8-16 m out. A rite that reaches less than its own
	# near edge would be a spell the body never gets to use, so the bow's pool is
	# the rites that reach at least that far.
	if str(spec.get("kind", "")) == "archer":
		var ranged: Array = []
		for rite in rites:
			var row: Dictionary = DemonFireScript.spell(str(rite))
			if float(row.get("range", 0.0)) >= float(ArcherScript.HOLD_NEAR):
				ranged.append(rite)
		if not ranged.is_empty():
			rites = ranged
	spec["spell"] = str(rites[_rite_rng.randi_range(0, rites.size() - 1)])
	return spec


## How many bodies the island keeps on the floor: the depth's own figure, capped
## by the crowd this machine has been able to run. `_earned_cap` is 0 until a
## frame has been measured, which is the depth cap.
func _live_cap() -> int:
	var depth := _depth_cap()
	if _earned_cap <= 0:
		return depth
	return mini(depth, _earned_cap)


## What this level means to press with, before the frame is asked (`_live_cap`).
func _depth_cap() -> int:
	return LIVE_CAP_BASE + LIVE_CAP_PER_ISLAND * maxi(0, stage_index) \
		+ LIVE_CAP_PER_PLAYER * maxi(0, party_size() - 1) + _trial_live_cap_add


## The frame's own say in the crowd above. `TIME_PROCESS` is the last drawn frame
## as the engine measured it - the only reading here that includes everything a
## frame pays for: the scripts, the renderer's setup and whatever the platform
## waits on. Smoothed, so one shader compile or one save is not a reason to thin
## the wave, and stepped once per `BUDGET_INTERVAL`, so a wave eases into what the
## machine can hold instead of snapping.
func _tick_budget(delta: float) -> void:
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if frame_ms > 0.0:
		_frame_ms = _frame_ms + (frame_ms - _frame_ms) * 0.15
	_budget_clock += delta
	if _budget_clock < BUDGET_INTERVAL:
		return
	_budget_clock = 0.0
	var depth := _depth_cap()
	if _earned_cap <= 0 or _earned_cap > depth:
		_earned_cap = depth
	elif _frame_ms > BUDGET_SLOW_MS and _earned_cap > BUDGET_FLOOR:
		# The worse the frame, the faster the crowd comes down: a frame twice the
		# budget loses two bodies a beat, four times loses four - so a collapse is
		# answered in a couple of seconds instead of half a minute, and a machine
		# that is merely a little slow still gives its wave time to be a wave.
		var over := 1 + int(_frame_ms / BUDGET_SLOW_MS)
		_earned_cap = maxi(BUDGET_FLOOR, _earned_cap - over)
	elif _frame_ms < BUDGET_FAST_MS and _earned_cap < depth:
		_earned_cap += 1


## The wait before the body at `index` of the queue: the opening ten follow
## `SPAWN_STEPS` (10, 9, 8 ... 3.2, 2.2, 1) and every later body comes at the
## tail. The front of the queue is the slow part; the tail is quick.
func spawn_interval(index: int) -> float:
	return float(SPAWN_STEPS[index]) if index >= 0 and index < SPAWN_STEPS.size() \
		else SPAWN_TAIL


func queue_clear() -> void:
	_queue.clear()


## Feed the island one body at a time. The level's first body waits out its lead;
## after that, a field with nothing on it pulls the next body in at once, because
## an empty field is no pressure at all. A field that still has bodies waits for
## the level's own clock, and a field at the live cap waits for room.
func _tick_spawn(delta: float) -> void:
	if _queue.is_empty():
		return
	var live := _live_mobs()
	if live == 0 and _spawn_done > 0:
		_spawn_next()
		return
	if live >= _live_cap():
		return
	_spawn_clock -= delta
	if _spawn_clock <= 0.0:
		_spawn_next()


## Field the next body of the queue and set the clock to the wait after it.
func _spawn_next() -> void:
	if _queue.is_empty():
		return
	var spec: Dictionary = _queue.pop_front()
	var at: Vector3 = stage.random_point(_rng, 6.0) if stage != null else Vector3.ZERO
	_spawn_spec(spec, at)
	_spawn_done += 1
	_spawn_clock = spawn_interval(_spawn_done)


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
	# One pool per *soul* in the run: a second human at the table doubles every
	# hostile's health, so the party's fight is longer, never easier. An AI body
	# is not a soul - a squadmate hired at the town's desk or a recruit taken on
	# at a shop swings for the party without making the island any heavier, which
	# is what makes buying help worth its gold.
	life *= float(_player_count())
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
		"caster":
			mob = _build_watcher(spec, at, life, rate, enemy_damage, false, true)
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
		damage_scale: float, is_archer: bool, is_caster: bool = false):
	var mob
	if is_caster:
		mob = CasterScript.new()
	elif is_archer:
		mob = ArcherScript.new()
	else:
		mob = WatcherScript.new()
	mob.name = _mob_name("C" if is_caster else "A" if is_archer else "W")
	mob.mob_id = str(spec.get("species", "hollow_warden"))
	# The wave's scale rides the body's own dial, read in `_ready` after the runt
	# rule: a runt is a third of a pool at every level, and a warden stays a warden
	# on the opening island's soft line.
	mob.pool_scale = maxf(0.05, life)
	mob.position = at
	world.add_child(mob)
	mob.global_position = at
	mob.home = at
	# The wave's own rite, after `_ready` has built the kit from its fallback.
	if is_caster and mob.has_method("set_caster_spell"):
		mob.set_caster_spell(str(spec.get("spell", "")))
	elif is_archer and mob.has_method("set_fire_spell"):
		mob.set_fire_spell(str(spec.get("spell", "")))
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
	# put there, and a caster's hands are empty: arming either took the fight out
	# of the body the wave paid for.
	if not is_archer and not is_caster and mob.has_method("arm"):
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
	# How hard it fights is the session's dial (`CloneAi`), not the wave's: the
	# depth already picks the kit and the gate already picks the pool, and the
	# third hand on this body is the player's own difficulty.
	mob.ai_tier = CloneAi.current_tier
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
		if kind == "caster":
			mob = CasterScript.new()
			# The variant is seeded from the node's own ordinal, so a caster's
			# name has to be the run's name before `_ready`, exactly as on the
			# host. Its rite still arrives from the spec below.
			mob.name = str(event.get("name", _mob_name("R")))
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
	if kind != "caster":
		mob.name = str(event.get("name", _mob_name("R")))
	# The rite travels in the spec, so a guest's caster or archer is the host's.
	if kind == "caster" and mob.has_method("set_caster_spell"):
		mob.set_caster_spell(str(spec.get("spell", "")))
	elif kind == "archer" and mob.has_method("set_fire_spell"):
		mob.set_fire_spell(str(spec.get("spell", "")))
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
	label.name = CorpseHold.RANK_TAG
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
	# The field's dead go with the field's living: a corpse belongs to the level
	# it fell on, and the hold that would have kept it for five minutes is not
	# worth carrying into the next level's clean ground.
	for corpse in _corpses:
		if is_instance_valid(corpse):
			(corpse as Node).queue_free()
	_corpses.clear()
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
	_corpses.append(enemy)
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
			node = Props.chest(stage, at, str(payload.get("style", "chest")), payload)
		"shop":
			node = Props.shop(stage, at, payload.get("wares", []), payload)
		"recruiter":
			node = Props.recruiter(stage, at, payload.get("hires", []), payload)
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
	shop_wares.clear()
	recruit_board.clear()
	_chest_paid.clear()
	_main_chests.clear()
	_main_open.clear()
	_level_raised = false
	# A standing field belongs to the level that opened it: a new island is a new
	# set of coordinates and a fresh mob list. A bleed has the same lifetime.
	_zones.clear()
	_bleeds.clear()


## The contract a fresh run opens under. Level one has no gate behind it, so its
## chest is the island's first: an ABILITY chest of commons, three skills and one
## kept - the run opens by handing the player a skill, before a wave asks them to
## build a hand around one. A player who has opened every skill gets the teaching
## Attack chest instead, because a promise that pays nothing is not a promise.
func _starter_contract() -> Dictionary:
	var surface := Mods.CHEST_ABILITY if _ability_promise_available() else Mods.CHEST_ATTACK
	var chest := {"surface": surface, "tier": Mods.RARITY_COMMON, "mult": 1}
	return {
		"kind": "combat", "biome": "wilderness", "faction": "watchers",
		"trial": TRIAL_OPEN, "trial_params": {},
		"chest": chest, "label": _contract_label(chest, TRIAL_OPEN), "next_level": 1,
	}


func _trial_params(trial: String) -> Dictionary:
	match trial:
		TRIAL_ELITE:
			return {"budget_mult": 0.9, "extra_elites": 1}
		TRIAL_SWARM:
			return {"budget_mult": 1.5, "live_cap_add": 6}
	return {}


## What the trial pays on top of the promise it already priced: a swarm gate
## doubles it. The rung an elite gate buys is part of the promise the gate rolled,
## so there is nothing about the tier left to do here - which is exactly why a
## second raise could never be added back by accident.
func _contract_chest(trial: String, promise: Dictionary) -> Dictionary:
	return {"surface": str(promise.get("surface", "")),
		"tier": str(promise.get("tier", "")),
		"mult": 2 if trial == TRIAL_SWARM else 1}


## The line under a gate's lintel: what it promises and what it costs.
func _contract_label(chest: Dictionary, trial: String) -> String:
	var label := "%s  ·  %s" % [
		Mods.surface_label(str(chest.get("surface", ""))),
		str(chest.get("tier", Mods.RARITY_COMMON)).to_upper()]
	if int(chest.get("mult", 1)) > 1:
		label += "  ·  2X"
	return "%s  ·  %s" % [label, str(TRIAL_LABEL.get(trial, trial.to_upper()))]


func _shuffle(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := _route_rng.randi_range(0, index)
		var held = items[index]
		items[index] = items[other]
		items[other] = held


## The three doors of a cleared level. The factions stay in gate order so the
## three doors always face the same side of the reward cluster; what the route
## rolls is the **promise** - a chest surface and a tier - plus the trial that
## prices it. A party reads three different rewards and picks the one it wants
## and the fight it can stand.
func _gate_contracts(next_level: int) -> Array[Dictionary]:
	var kind := _kind_for_level(next_level)
	_route_rng.seed = (int(run_seed) ^ (next_level * 7919) ^ (_gate_salt * 104729)) \
		& 0x7fffffff
	var trials: Array = TRIALS.duplicate()
	_shuffle(trials)
	var island := stage_index + 1
	var luck := _party_luck()
	var hands := _party_hands()
	var promised: Array = []
	var out: Array[Dictionary] = []
	for slot in GATES.size():
		var gate: Dictionary = GATES[slot]
		var gate_biome := str(gate.get("biome", "wilderness"))
		var gate_faction := str(gate.get("faction", "watchers"))
		var trial := TRIAL_OPEN
		var chest: Dictionary = {}
		var label := ""
		if kind == "combat":
			trial = str(trials[slot])
			var promise := Mods.roll_promise(_route_rng, island, luck, hands,
				trial == TRIAL_ELITE, promised)
			# The first chest on a new island is an ABILITY chest: the door hands
			# the player a skill before the ground asks for a build. The trial still
			# prices the tier, so a swarm gate opens a legendary one and an open
			# gate a common one.
			if _opens_island(next_level) and _ability_promise_available():
				promise["surface"] = Mods.CHEST_ABILITY
			promised.append(str(promise.get("surface", "")))
			chest = _contract_chest(trial, promise)
			label = _contract_label(chest, trial)
		elif kind == "market":
			label = "MARKET"
		elif kind == "shop":
			label = "SHOP"
		elif kind == "boss":
			label = "HOARD"
			chest = {"surface": "", "tier": "", "mult": 1, "payout": Mods.PAYOUT_HOARD}
		var contract := {
			"kind": kind, "biome": gate_biome, "faction": gate_faction,
			"trial": trial, "trial_params": _trial_params(trial),
			"chest": chest, "label": label, "next_level": next_level,
		}
		out.append(contract)
	return out


## What stands on the ground for a promise: `WEAPONS  ·  EPIC CHEST`.
## Whether the run can still promise a skill: the ledger is the host's own, which
## is the only one this machine can read, and a player with every skill open is
## handed a card chest instead.
func _ability_promise_available() -> bool:
	var meta = get_node_or_null("/root/Roguelite")
	if meta == null:
		return true
	var opened: Dictionary = {}
	for id in meta.unlocked_abilities:
		opened[str(id)] = true
	for id in AbilityRules.unlockable_ids():
		if not opened.has(str(id)):
			return true
	return false


## Whether the level behind the gates is the first of a depth block - the level
## whose chest is the island's first.
func _opens_island(level_number: int) -> bool:
	return (int(level_number) - 1) % LEVELS_PER_ISLAND == 0


## The three skills an ABILITY chest lays out for one soul. They are skills the
## player has not opened (never a starter or a consumable), and **at least one is
## one the body can perform** with the pair it is wearing: a choice that cannot be
## used is not a choice. The other two may be for other hands, because a chest is
## also a reason to change them.
func _ability_offers(peer_id: int) -> Array[String]:
	var run = players.get(int(peer_id))
	if run == null or not is_instance_valid(run):
		return []
	var opened: Dictionary = {}
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null:
		for id in meta.unlocked_abilities:
			opened[str(id)] = true
	# The pair the body is actually wearing: a run body carries two pieces, and a
	# skill that fits either of them fits the body.
	var main_row: Dictionary = State.ITEMS.get(str(run.ranged_id), {})
	var off_row: Dictionary = State.ITEMS.get(str(run.melee_id), {})
	var fits: Array[String] = []
	var wild: Array[String] = []
	for id in AbilityRules.unlockable_ids():
		if opened.has(str(id)):
			continue
		if AbilityRules.by_id(str(id)).is_empty():
			continue
		if AbilityRules.fits_gear(AbilityRules.by_id(str(id)), main_row, off_row):
			fits.append(str(id))
		else:
			wild.append(str(id))
	_fisher_yates(fits)
	_fisher_yates(wild)
	var out: Array[String] = []
	if not fits.is_empty():
		out.append(fits.pop_front())
	while out.size() < 3 and not wild.is_empty():
		out.append(wild.pop_front())
	while out.size() < 3 and not fits.is_empty():
		out.append(fits.pop_front())
	_fisher_yates(out)
	return out


## One shuffle on the run's own reward generator, so two boxes stood on the same
## seed deal the same hands.
func _fisher_yates(items: Array) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var held = items[index]
		items[index] = items[other]
		items[other] = held


func _chest_title(surface: String, tier: String, mult: int) -> String:
	var label := Mods.surface_label(surface)
	var rank := str(tier).to_upper()
	if not rank.is_empty() and rank != Mods.RARITY_COMMON.to_upper():
		label += "  ·  " + rank
	label += "  CHEST"
	if mult > 1:
		label = "2X  " + label
	return label


## The offers one box lays out, a row per named peer. Each body rolls its own row
## off its own engine, so Big Chests and Hoarder move that body's count and no one
## else's. `chest_draft` is what guarantees every row is a whole hand, so a body is
## only left out when its own tier has nothing left for it at all.
##
## `only` names the peers to deal for: a box stood for one soul passes that soul,
## and the squad's own auto-draft passes the allies. Empty means every body in the
## run, which is what a shared cache a kill drops still deals.
func _chest_offers(surface: String, tier: String, only: Array = []) -> Dictionary:
	var table: Dictionary = {}
	var peers: Array = only if not only.is_empty() else players.keys()
	var skills := Mods.surface_payout(surface) == Mods.PAYOUT_SKILLS
	for peer in peers:
		var run = players.get(int(peer))
		if run == null or not is_instance_valid(run):
			continue
		var offers: Array = _ability_offers(int(peer)) if skills \
			else run.chest_draft(surface, tier)
		if offers.is_empty():
			continue
		table[int(peer)] = offers
	return table


func _active_chest_spec() -> Dictionary:
	var chest: Variant = active_contract.get("chest", {})
	if chest is Dictionary and not (chest as Dictionary).is_empty():
		return chest
	return {"surface": Mods.CHEST_ATTACK, "tier": Mods.RARITY_COMMON, "mult": 1}


# --- the level's boxes -----------------------------------------------------
#
# One box a soul. A co-op level does not stand one chest four bodies fight over:
# every player walks up to their own box, with their own name on it, and a 2X
# promise is a second box each. The rules that were about a shared prop - "the
# first main open raises the party", "the gates wait for the chest" - are still
# about the level, not the box.

## The souls a chest can be stood for: the peers actually inside a body this run
## owns, in id order. An AI squadmate is not one - it reads its card from the host
## the moment the level clears, so it never waits on a box nobody holds for it.
func player_peers() -> Array[int]:
	var held: Array = []
	if world != null and world.get("controller") != null:
		held = world.controller.possessing_peers()
	var out: Array[int] = []
	for peer in players:
		var id := int(peer)
		if id > 0 and held.has(id):
			out.append(id)
	out.sort()
	if out.is_empty():
		# A writer with no controller to ask - a harness, a guest whose field is
		# still building - still stands its boxes for the bodies it has.
		for peer in players:
			if int(peer) > 0:
				out.append(int(peer))
		out.sort()
	return out


## What a box's plate calls the soul it was stood for: the name the peer joined
## the session with, or its mercenary's name when nobody named the soul.
func _peer_name(peer_id: int) -> String:
	if world != null and world.has_method("soul_name"):
		var named := str(world.call("soul_name", peer_id))
		if not named.is_empty():
			return named
	var run = players.get(peer_id)
	if run != null and is_instance_valid(run) and int(run.merc_id) > 0 \
			and world != null and world.get("warband") != null:
		var merc_name := str(world.warband.roster.name_of(int(run.merc_id)))
		if not merc_name.is_empty():
			return merc_name
	return "P%d" % peer_id


## The colour the owner plate is painted: the same one the body's ring and its
## name plate already wear, so a player learns "mine is the teal one" once.
func _peer_colour(peer_id: int) -> Color:
	var run = players.get(peer_id)
	var slot := -1
	if run != null and is_instance_valid(run) and run.body != null \
			and is_instance_valid(run.body):
		slot = int(run.body.get("slot"))
	if slot < 0:
		return WarbandBody.RING_COLOURS[0]
	return WarbandBody.RING_COLOURS[slot % WarbandBody.RING_COLOURS.size()]


## Stand the level's boxes: every promise in `boxes`, once for every soul. Each
## one carries its owner's name and colour, and a main one carries that soul's own
## three-card draft, so opening a chest nobody else can take from is the whole of
## the interaction. The boxes stand in one ring on the island's party side - a
## soul's own set together - and the three gates stand one short walk past them.
##
## `slot_base`/`total` let a stop place its boxes inside its own cluster instead
## of taking the ring from the top.
func _stand_chests(boxes: Array[Dictionary], surface: String, tier: String,
		slot_base: int = 0, total: int = 0, reach: float = 0.0) -> void:
	if stage == null or not is_instance_valid(stage) or boxes.is_empty():
		return
	var souls := player_peers()
	var count := maxi(1, boxes.size() * maxi(1, souls.size()))
	var of := total if total > 0 else count
	# A ring wide enough to walk between the boxes but short of the gates at
	# 9.5 m: the walk after a wave stays a few paces.
	var ring := reach if reach > 0.0 else minf(7.0, 4.5 + 0.7 * float(count))
	var placed := 0
	for peer in souls:
		for box in boxes:
			# `promise` is the contract's surface and tier on the lid and its three
			# cards in the owner's hand; `main` is the gate seal, which only the
			# level's own contract boxes hold.
			var main := bool(box.get("main", false))
			var promise := bool(box.get("promise", main))
			var payout := str(box.get("payout", Mods.PAYOUT_ROLL))
			var style := str(box.get("style", "chest"))
			var payload := {
				"surface": surface if promise else "", "tier": tier if promise else "",
				"payout": payout, "mult": 1, "style": style, "level": level,
				"owner": peer, "owner_name": _peer_name(peer),
				"owner_colour": _peer_colour(peer),
			}
			if promise:
				payload["contract"] = active_contract
				if not surface.is_empty():
					payload["label"] = _chest_title(surface, tier, 1)
				if payout == Mods.PAYOUT_CARDS or payout == Mods.PAYOUT_SKILLS:
					payload["offers"] = _chest_offers(surface, tier, [peer])
					if payout == Mods.PAYOUT_SKILLS:
						payload["offer_kind"] = "skill"
			var at: Vector3 = stage.reward_point(slot_base + placed, of, ring)
			placed += 1
			var chest = _spawn_prop("chest", at, payload)
			if chest == null:
				continue
			var serial := int(chest.get_meta("serial"))
			_broadcast_prop(chest, "chest", payload)
			if payload.has("offers") and not (payload["offers"] as Dictionary).is_empty():
				draft_offers[serial] = payload["offers"]
			if main:
				_main_chests.append(serial)


func _apply_contract() -> void:
	_trial_budget_mult = 1.0
	_trial_live_cap_add = 0
	_trial_extra_elites = 0
	var params: Variant = active_contract.get("trial_params", {})
	if params is Dictionary:
		_trial_budget_mult = float((params as Dictionary).get("budget_mult", 1.0))
		_trial_live_cap_add = int((params as Dictionary).get("live_cap_add", 0))
		_trial_extra_elites = int((params as Dictionary).get("extra_elites", 0))


## The level is beaten. Every reward stands on the ground and the three gates
## wait for the chest to be opened: a fight pays gold, the chest pays what its
## surface promised - cards, keys or gear - and the gate taken decides the biome
## of the next level.
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
	# The reward chest is the contract's promise: a chest surface and a tier
	# chosen at the gate before the fight. A surface of cards lays out three rows
	# for the soul the box was stood for; a Key chest pays keys and a Gear chest
	# pays armour, so the three doors are three different rewards, not three rolls
	# of one ladder. A harder gate can promise a second chest; a boss still keeps
	# its own hoard.
	var spec := _active_chest_spec()
	var surface := str(spec.get("surface", ""))
	var tier := str(spec.get("tier", ""))
	var copies := maxi(1, int(spec.get("mult", 1)))
	var payout := Mods.surface_payout(surface)
	var style := "chest"
	if boss_level:
		surface = ""
		tier = ""
		copies = 1
		payout = Mods.PAYOUT_HOARD
		style = "elite"
	# The level's own boxes, in the order they stand: the contract's promise
	# (twice under a 2X gate), then the caches a body's own rows paid for.
	var boxes: Array[Dictionary] = []
	for copy in copies:
		boxes.append({"main": true, "payout": payout, "style": style})
	var extra_chance := float(_party_stat("chest_chance"))
	if extra_chance > 0.0 and _rng.randf() < extra_chance:
		boxes.append({"payout": Mods.PAYOUT_ROLL, "style": "mini"})
	# Care Package and Hoarder bury a chest on a rhythm rather than a chance: one
	# every `extra_chest_islands` islands, which is a promise a player can count.
	var island_rhythm := int(round(_party_stat("extra_chest_islands")))
	if island_rhythm > 0 and (stage_index + 1) % island_rhythm == 0:
		boxes.append({"payout": Mods.PAYOUT_ROLL, "style": "mini"})
	_stand_chests(boxes, surface, tier)
	# A level whose only reward is a cache still opens its own gates: nothing is
	# waiting on a box.
	if _main_chests.is_empty() and not _opened.has("chest"):
		_opened["chest"] = true
		_broadcast({"t": "unseal"})
	# Three gates on: the next level stands behind each of them, and the one the
	# party takes is the biome it fights there.
	_spawn_gates(level + 1)
	_status("LEVEL %d CLEARED  ·  open the chest  ·  three gates wait" % level, 5.0)
	# The allies choose after the clear line, so their picks are the line the
	# party reads rather than one the level's own message overwrites. They have
	# no box of their own: a squadmate reads its card from the host the moment
	# the chest stands.
	if payout == Mods.PAYOUT_CARDS or payout == Mods.PAYOUT_SKILLS:
		_draft_ai(surface, tier)
	_broadcast_state()


## The three gates of a cleared level, one per faction. `next_level` is the level
## behind all three: the gates differ in what the party fights, never in how far
## it has got.
func _spawn_gates(next_level: int) -> void:
	var contracts := _gate_contracts(next_level)
	for slot in contracts.size():
		var contract: Dictionary = contracts[slot]
		var gate_biome := str(contract.get("biome", "wilderness"))
		var label := str(contract.get("label", ""))
		var payload := {
			"next_level": next_level,
			"kind": str(contract.get("kind", "combat")),
			"biome": gate_biome,
			"faction": str(contract.get("faction", "watchers")),
			"title": str(StageScript.biome(gate_biome).name),
			"label": label,
			"name": "%s  ·  %s" % [label, str(StageScript.biome(gate_biome).name)],
			"contract": contract,
			# The Hollow's gates turn to face the party's own line; an island's
			# gates stand in their frame as the far rim always has.
			"yaw": stage.gate_yaw(slot),
		}
		var portal = _spawn_prop("portal", stage.gate_point(slot, GATE_FAN, GATE_REACH), payload)
		_broadcast_prop(portal, "portal", payload)


## What kind of level stands at `level_number`: a market at 6, the shop before
## every boss, a boss every tenth, and a fight in between.
func _kind_for_level(level_number: int) -> String:
	var mark := level_number % BOSS_EVERY
	if mark == 0:
		return "boss"
	if mark == MARKET_LEVEL:
		return "market"
	if mark == SHOP_LEVEL:
		return "shop"
	return "combat"


## The luck the party's surfaces roll with: the highest any body carries.
func _party_luck() -> int:
	var best := 0
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run):
			best = maxi(best, int(run.luck()))
	return best


## One hand per body, for the promise: a chest deals every body its own cards, so
## a surface is only promised where each of them can lay out a whole hand from
## the rows it has left.
func _party_hands() -> Array:
	var out: Array = []
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		out.append({"tags": run.carrier_tags(), "taken": run.maxed_mods()})
	return out


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


## The offers one peer may pick from. A chest's payload carries the whole party's
## table, because every machine draws only its own body's three cards; a payload
## that predates the table is read as the one shared row it was.
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


## The shop stop's chest: the same promise a gate makes, rolled by the route
## rather than chosen at a door. It stands where the wave would have, so a level
## spent in the stalls is still a level the run is paid for.
## Returns the promise it stood, so the squad can read its card off it.
func _stand_stop_chest(slot: int, souls: int) -> Dictionary:
	_route_rng.seed = int(run_seed) ^ (level * 4177)
	var island := stage_index + 1
	var promise := Mods.roll_promise(_route_rng, island, _party_luck(),
		_party_hands())
	var surface := str(promise.get("surface", ""))
	var tier := str(promise.get("tier", ""))
	var payout := Mods.surface_payout(surface)
	# The stop's own cluster: the stall and the rack keep their slots, and the
	# boxes go into the rest of the ring, a step wider for every extra soul.
	_stand_chests([{"payout": payout, "style": "chest", "promise": true}],
		surface, tier, slot, 4 + maxi(1, souls) - 1, 3.2 + 0.9 * float(maxi(0, souls - 1)))
	return {"surface": surface, "tier": tier, "payout": payout}


## Let every AI body take its pick at once. A squadmate has nobody to read the
## cards for it, so it chooses at random the moment the level clears and the
## party never waits on a body that cannot answer.
func _draft_ai(surface: String, tier: String) -> void:
	var allies := ai_peers()
	if allies.is_empty():
		return
	_ai_draft(_chest_offers(surface, tier, allies))


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


## The offer a squadmate takes for itself. The run's rng makes the pick, but a
## skill the body cannot perform is not an offer it can take: a fitting skill is
## preferred and the random pull runs across what the body can actually use, so a
## chest is never spent on a key that does nothing.
func _ai_pick(run, offers: Array) -> String:
	var usable: Array[String] = []
	var others: Array[String] = []
	for raw in offers:
		var id := str(raw)
		var definition: Dictionary = AbilityRules.by_id(id)
		if definition.is_empty() or AbilityRules.is_automatic(id):
			others.append(id)
			continue
		var rig = null
		if run != null and is_instance_valid(run) and run.body != null \
				and is_instance_valid(run.body):
			rig = run.body.get("rig")
		if rig != null and AbilityRules.fits_rig(definition, rig):
			usable.append(id)
	var pool: Array[String] = []
	pool.append_array(usable)
	pool.append_array(others)
	if pool.is_empty():
		return ""
	return pool[_rng.randi_range(0, pool.size() - 1)]


## The AI's half of the draft: one offer out of each ally's own three. The run's
## rng makes the pick, so the same seed fields the same allies the same way.
func _ai_draft(table: Dictionary) -> void:
	var picks: PackedStringArray = []
	for peer in ai_peers():
		var offers: Array = table.get(peer, [])
		if offers.is_empty():
			continue
		var run = players.get(peer)
		if run == null or not is_instance_valid(run):
			continue
		var picked := _ai_pick(run, offers)
		if picked.is_empty():
			continue
		var definition: Dictionary = AbilityRules.by_id(picked)
		if not definition.is_empty() and not AbilityRules.is_automatic(picked):
			# A squadmate has no ledger to write, so a skill it takes is the
			# body's: it goes on the bar, and the party is told whose hands took it.
			var warband = world.get("warband") if world != null else null
			if warband == null:
				continue
			var answer: Dictionary = warband.toggle_ability(int(run.merc_id), picked)
			if not bool(answer.get("ok", false)):
				continue
			_apply_hands(run, str(run._active_slot))
			picks.append("%s: %s" % [_run_label(run),
				str(definition.get("name", picked)).capitalize()])
			continue
		var result: Dictionary = run.take_mod(picked)
		if not bool(result.get("ok", false)):
			continue
		_broadcast({"t": "mod", "peer": peer, "id": picked,
			"message": str(result.get("message", ""))})
		picks.append("%s: %s" % [_run_label(run), Mods.name_of(picked)])
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


func _shop_wares(market: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var island := stage_index + 1
	var base := MARKET_WARES if market else SHOP_WARES
	var count := base + int(round(_party_stat("shop_offers")))
	var ids := Mods.roll_shelf(_rng, Mods.SOURCE_STALL, island, count,
		_party_luck(), [], _party_carrier_tags())
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


## The recruiter's board for this visit: three bodies, one of each archetype, in a
## shuffled order, priced by the level the board stands on and carried in the kit
## that level's rung is worth (`RecruitCatalog`). Rolled once per level load off
## the run's own RNG - the same rng the stall's rack comes off - so two visits to
## two level-6 markets sell three different recruits, and the same seed sells the
## same three.
func _shop_hires() -> Array[Dictionary]:
	return Recruits.offers(_rng, level)


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
		# The shop is a local window over host-owned facts: the wares arrived with
		# the prop, so the guest opens the board here and the press that spends
		# anything still goes to the host.
		if kind == "shop":
			var shop_hud = world.get("roguelite_hud")
			if shop_hud != null and shop_hud.has_method("open_shop"):
				shop_hud.open_shop(serial, payload.get("wares", []))
				return true
		elif kind == "recruiter":
			# The board is the host's list of bodies for sale, carried with the
			# prop; the press that spends the gold still goes to the host.
			var desk_hud = world.get("roguelite_hud")
			if desk_hud != null and desk_hud.has_method("open_recruiter"):
				desk_hud.open_recruiter(serial, payload.get("hires", []))
				return true
		elif kind == "chest" and payload.has("offers"):
			var chest_hud = world.get("roguelite_hud")
			var chest_offers: Array = offers_of(payload, local_peer())
			var chest_owner := int(payload.get("owner", 0))
			if chest_owner > 0 and chest_owner != local_peer():
				# The box is another soul's: say whose, and leave it alone. The
				# one press that spends it is its owner's.
				_status("%s'S CHEST  ·  open your own" % str(
					payload.get("owner_name", "ANOTHER SOUL")).to_upper(), 2.5)
				return true
			send_request({"t": "use", "serial": serial})
			if chest_hud != null and not chest_offers.is_empty() \
					and chest_hud.has_method("open_draft"):
				var offer_kind := str(payload.get("offer_kind", "mod"))
				var hint := "Choose one upgrade from the promised chest."
				if offer_kind == "skill":
					hint = "Choose one ability. It is yours from now on, and it " \
						+ "goes on the bar when the hands in them fit it."
				chest_hud.open_draft(serial, chest_offers,
					str(payload.get("label", "THE CHEST KEEPS ITS PROMISE")), hint,
					offer_kind, str(payload.get("tier", "")))
			elif chest_offers.is_empty():
				_status("This chest holds nothing you have not already taken.", 2.5)
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
		"shop":
			_open_shop(serial, actor)
		"recruiter":
			_open_recruiter(serial, actor)
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
		if market_level:
			return "MARKET  ·  spend, then take a gate"
		if shop_level:
			return "SHOP LEVEL  ·  spend, kit up, then take a gate"
		if level_cleared:
			return "LEVEL %d CLEARED  ·  the gates wait" % level
		return ""
	match Props.prop_kind(prop):
		"chest":
			var serial := int(prop.get_meta("serial", 0))
			if _opened.has(serial):
				return ""
			var chest_payload := Props.payload_of(prop)
			var owner := int(chest_payload.get("owner", 0))
			if owner > 0 and owner != local_peer():
				return "%s'S CHEST  ·  NOT YOURS" % str(
					chest_payload.get("owner_name", "ANOTHER SOUL")).to_upper()
			return "G  -  OPEN THE CHEST"
		"shop":
			return "G  -  SPEND %d GOLD" % gold()
		"recruiter":
			return "G  -  THE RECRUITER  ·  %d GOLD" % gold()
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
	var payload := Props.payload_of(prop)
	var owner := int(payload.get("owner", 0))
	if owner > 0 and owner != peer:
		# A box is stood for one soul. The press on somebody else's is answered
		# with whose it is, and nothing of theirs is spent.
		_status("%s'S CHEST  ·  open your own" % str(
			payload.get("owner_name", "ANOTHER SOUL")).to_upper(), 2.5)
		return
	var payout := str(payload.get("payout", Mods.PAYOUT_ROLL))
	var tier := str(payload.get("tier", ""))
	var style := str(payload.get("style", "chest"))
	var offers_table: Variant = draft_offers.get(serial, payload.get("offers", {}))
	var has_choice := (payout == Mods.PAYOUT_CARDS
			or payout == Mods.PAYOUT_SKILLS) and offers_table is Dictionary \
		and not (offers_table as Dictionary).is_empty()
	var users: Dictionary = _users.get(serial, {})
	if has_choice and users.has(peer):
		_status("You have already taken your choice from this chest.", 2.0)
		return
	# A choice chest can be opened again by the same body until it picks; its
	# payout is paid once, not once per look.
	var paid: Dictionary = _chest_paid.get(serial, {})
	var first_pay := not paid.has(peer)
	var landed: Dictionary = {}
	var roll: Array[String] = []
	var payout_line := ""
	var unsealed := false
	if first_pay:
		paid[peer] = true
		_chest_paid[serial] = paid
		if not has_choice and not _claim_use(serial, peer):
			_status("That chest has already given you its share.", 2.0)
			return
		var mult: float = float(run.currency_multiplier())
		var pay_base := 24
		if style != "mini":
			pay_base = 60 if payout == Mods.PAYOUT_HOARD \
				else 38 + 26 * Mods.tier_rank(tier)
		var pay := int(round(float(pay_base + 10 * stage_index) * mult))
		_award_gold(pay)
		var island := stage_index + 1
		var excluded: Array = []
		for id in run.engine.stacks:
			if int(run.engine.stacks[id]) >= Mods.max_stacks(str(id)):
				excluded.append(str(id))
		match payout:
			Mods.PAYOUT_CARDS:
				# The card is the reward: the draft at the bottom of this
				# function is the whole of a card chest, and its armour is the
				# Gear chest's business.
				pass
			Mods.PAYOUT_SKILLS:
				# Three skills stand on the lid and the soul keeps one, for good:
				# the draft below is the whole of an ABILITY chest.
				pass
			Mods.PAYOUT_KEYS:
				var keys := Mods.payout_count(tier)
				_award_keys(keys, "a %s key chest" % tier)
				payout_line = "THE KEY CHEST PAYS  ·  %d key%s  ·  the rack spends them" \
					% [keys, "" if keys == 1 else "s"]
			Mods.PAYOUT_GEAR:
				# A gear chest pays a piece a tier, and a better tier rolls off a
				# higher set: the promise is the armour, not a card.
				var pieces := Mods.payout_count(tier)
				for _index in pieces:
					landed = _roll_and_wear_armor(run, prop, excluded,
						Mods.tier_rank(tier), peer)
				payout_line = "THE GEAR CHEST PAYS  ·  %d piece%s" % [
					pieces, "" if pieces == 1 else "s"]
			Mods.PAYOUT_HOARD:
				var count := maxi(2, 1 + int(round(run.engine.stat("chest_mods"))))
				roll = Mods.hoard(_rng, count, int(run.luck()), island, [],
					run.carrier_tags())
				_take_roll(run, peer, roll, excluded)
				landed = _roll_and_wear_armor(run, prop, excluded, 0, peer)
			_:
				var cache_count := 1 + int(round(run.engine.stat("chest_mods")))
				roll = Mods.roll_shelf(_rng, Mods.SOURCE_CACHE, island,
					cache_count, int(run.luck()), excluded, run.carrier_tags())
				_take_roll(run, peer, roll, excluded)
				landed = _roll_and_wear_armor(run, prop, excluded, 0, peer)
		# A chest is the co-op contract's revive: whoever was on the dirt stands up
		# at half the pool the first time one of the level's main boxes is opened,
		# so a party is never stranded by a wave that went wrong. The gates unseal
		# when the last of those boxes is opened - every soul has had its look - and
		# a cache a kill paid for seals nothing.
		unsealed = _note_main_open(serial)
	if unsealed:
		var line := "THE CHEST IS OPEN  ·  the gates open"
		if not landed.is_empty():
			line = "THE CHEST IS OPEN  ·  %s %s  ·  the gates open" % [
				ArmorLoot.title_of(landed), ArmorLoot.detail_of(landed)]
		_status(line, 4.5)
	elif first_pay and _main_chests.has(serial):
		_status("%s'S CHEST IS OPEN  ·  %d of %d opened" % [
			str(payload.get("owner_name", "A SOUL")).to_upper(),
			_main_open.size(), _main_chests.size()], 4.0)
	elif not landed.is_empty():
		_status(ArmorLoot.status_line(landed), 4.5)
	# A key or a gear chest's own line is the last thing read: it is what it paid.
	if not payout_line.is_empty():
		_status(payout_line, 4.5)
	if payout == Mods.PAYOUT_CARDS or payout == Mods.PAYOUT_SKILLS:
		var offers := _offers_for(serial, peer)
		if offers.is_empty():
			_claim_use(serial, peer)
			_release_if_spent(serial, "chest", prop)
			_status("This chest holds nothing you have not already taken.", 2.5)
			state_changed.emit()
			return
		if int(run.peer_id) == local_peer():
			var hud = world.get("roguelite_hud")
			if hud != null and hud.has_method("open_draft"):
				var title := str(payload.get("label", "THE CHEST KEEPS ITS PROMISE"))
				var kind := str(payload.get("offer_kind", "mod"))
				var hint := "Choose one upgrade from the promised chest."
				if kind == "skill":
					hint = "Choose one ability. It is yours from now on, and it " \
						+ "goes on the bar when the hands in them fit it."
				hud.open_draft(serial, offers, title, hint, kind, tier)
			else:
				choose_draft(peer, serial, 0)
		state_changed.emit()
		return
	_release_if_spent(serial, "chest", prop)
	state_changed.emit()


## Roll one piece for a chest's opener and put it on: the slot is random, the set
## is what this level's ladder can pay raised by `floor_add` ranks, and a small
## chance that grows with the level welds one to three rows to it. Answers the
## piece as the body kept it.
func _roll_and_wear_armor(run, prop: Node3D, excluded: Array, floor_add: int,
		peer: int) -> Dictionary:
	var piece := ArmorLoot.roll(_rng, level, stage_index + 1, _worn_armor(run),
		int(run.luck()), excluded, run.carrier_tags(), floor_add)
	var landed: Dictionary = run.wear_armor(piece)
	if landed.is_empty():
		landed = piece
	_pop_armor(landed, prop.global_position, run)
	_broadcast({"t": "armor", "peer": peer, "piece": landed,
		"at": prop.global_position})
	return landed


## Take a rolled list of rows onto one body, one `mod` event a row so every
## machine books the same stacks in the same order.
func _take_roll(run, peer: int, roll: Array[String], excluded: Array) -> void:
	for id in roll:
		excluded.append(str(id))
		var result: Dictionary = run.take_mod(str(id))
		if not bool(result.get("ok", false)):
			continue
		_broadcast({"t": "mod", "peer": peer, "id": str(id),
			"message": str(result.get("message", ""))})
		_status(str(result.get("message", "")), 4.0)


## Book one peer's use of a shared prop. False when this peer has already had
## its helping.
func _claim_use(serial: int, peer_id: int) -> bool:
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return false
	users[peer_id] = true
	_users[serial] = users
	return true


## Free a chest once the soul it was stood for has had its helping. A box with no
## cards is spent by its owner's press; a shared cache a kill drops is spent by
## the last body at the party.
func _release_if_spent(serial: int, fx_kind: String, prop: Node3D) -> bool:
	var users: Dictionary = _users.get(serial, {})
	var table: Dictionary = draft_offers.get(serial, {})
	var owner := int(Props.payload_of(prop).get("owner", 0)) if prop != null else 0
	if table.is_empty():
		# One soul's box needs one press; a shared cache still waits for every
		# body at the party to take its own look.
		if users.size() < (1 if owner > 0 else maxi(1, party_size())):
			return false
	else:
		# A chest is spent once every body it drew for has taken a row - a body
		# it drew nothing for never holds it open.
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
		if fx_kind == "chest":
			ProcFx.ring(stage, prop.global_position, Color(1.0, 0.8, 0.4), 2.4)
		prop.queue_free()
	return true


## Book a soul's first press on one of the level's main boxes. The party is raised
## the first time any of them is opened; the gates unseal on the last, so a soul
## that has not had its look yet is not walked past. Answers whether this press
## opened the way on.
func _note_main_open(serial: int) -> bool:
	if not _main_chests.has(serial) or _main_open.has(serial):
		return false
	_main_open[serial] = true
	if not _level_raised:
		_level_raised = true
		for other_peer in players:
			var other = players[other_peer]
			if other != null and is_instance_valid(other) and other.revive_for_clear():
				_broadcast({"t": "revived", "peer": other_peer})
	if _main_open.size() < _main_chests.size():
		return false
	if _opened.has("chest"):
		return false
	_opened["chest"] = true
	_broadcast({"t": "unseal"})
	return true


## A draft choice, host side. `peer` is the chooser (a guest's request carries
## the sender, never a claimed id).
func choose_draft(peer_id: int, serial: int, index: int) -> Dictionary:
	if _client:
		send_request({"t": "choose", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return {"ok": false, "message": "That choice is spent."}
	var offers := _offers_for(serial, peer_id)
	if index < 0 or index >= offers.size():
		return {"ok": false, "message": "That is not one of the offers."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return {"ok": false, "message": "You have already taken your choice."}
	var picked := str(offers[index])
	if not AbilityRules.by_id(picked).is_empty() \
			and not AbilityRules.is_automatic(picked):
		return _take_ability(peer_id, serial, prop, picked)
	var result: Dictionary = run.take_mod(picked)
	if not bool(result.get("ok", false)):
		return result
	_claim_use(serial, peer_id)
	_broadcast({"t": "mod", "peer": peer_id, "id": picked,
		"message": str(result.get("message", ""))})
	_keep_leftovers(peer_id, prop, offers, picked)
	_release_if_spent(serial, Props.prop_kind(prop), prop)
	return result


## Faulty Chests: a card the chooser did not take stays on the ground as its own
## pickup, one a stack. The pickup is the same mini card chest a dropped card
## uses - one offer, that soul's own name on the lid - laid at the parent box's
## own feet so the walk back to it is a step, not a hunt.
func _keep_leftovers(peer_id: int, prop: Node3D, offers: Array,
		picked: String) -> void:
	if prop == null or not is_instance_valid(prop) or stage == null \
			or not is_instance_valid(stage):
		return
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return
	var kept := int(round(run.engine.stat("keep_offer")))
	if kept <= 0:
		return
	var left: Array[String] = []
	for id in offers:
		if str(id) != picked and not left.has(str(id)):
			left.append(str(id))
	kept = mini(kept, left.size())
	var at: Vector3 = prop.global_position
	var ground := Vector3(at.x, stage.global_position.y, at.z)
	for index in kept:
		var angle := TAU * float(index) / float(kept) + float(peer_id)
		var payload := {
			"payout": Mods.PAYOUT_CARDS, "style": "mini", "level": level,
			"owner": peer_id, "owner_name": _peer_name(peer_id),
			"owner_colour": _peer_colour(peer_id),
			"offers": {peer_id: [left[index]]}, "label": "AN UNCHOSEN CARD",
		}
		var card = _spawn_prop("chest", ground + Vector3(
			cos(angle) * 1.4, 0.0, sin(angle) * 1.4), payload)
		if card == null:
			continue
		draft_offers[int(card.get_meta("serial"))] = payload["offers"]
		_broadcast_prop(card, "chest", payload)


## A skill leaving an ABILITY chest. Two halves, and they belong to different
## owners: the **unlock** is the player's, so it is written only on the machine
## that owns the chooser's ledger (this one for the host, the guest's own over the
## network), while the **bar** is the body's, and the body is host-side whichever
## soul is inside it.
func _take_ability(peer_id: int, serial: int, prop: Node3D, ability_id: String) -> Dictionary:
	var run = players.get(int(peer_id))
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var definition: Dictionary = AbilityRules.by_id(ability_id)
	var display := str(definition.get("name", ability_id)).capitalize()
	var merc := int(run.merc_id)
	var warband = world.get("warband") if world != null else null
	var equipped := false
	if warband != null and merc > 0:
		var answer: Dictionary = warband.toggle_ability(merc, ability_id)
		equipped = bool(answer.get("ok", false))
		# The bar is drawn at dress time: re-dress the body so the key is on the
		# next frame's plate rather than the next level's.
		_apply_hands(run, str(run._active_slot))
	_claim_use(int(peer_id), serial)
	_broadcast({"t": "ability", "peer": int(peer_id), "id": ability_id,
		"message": display})
	_apply_ability_choice(int(peer_id), ability_id)
	var line := "%s  ·  %s" % [display, "on the bar" if equipped
		else "open; hands do not fit it yet"]
	_status("THE ABILITY CHEST PAYS  ·  " + line, 5.0)
	_release_if_spent(serial, Props.prop_kind(prop), prop)
	state_changed.emit()
	return {"ok": true, "id": ability_id, "equipped": equipped, "message": line}


## The unlock half of a skill pick. Keys and unlocks are a player's own, so a
## machine writes this only when the chooser is the soul inside it.
func _apply_ability_choice(peer_id: int, ability_id: String) -> void:
	if int(peer_id) != local_peer():
		return
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("grant_ability"):
		meta.grant_ability(ability_id)


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


## Open the recruiter's board. The mirror of `_open_shop`: the host reads its own
## board out of `recruit_board`, and a guest's copy of it arrived with the prop's
## payload, so a guest's window is a local render of host-owned facts.
func _open_recruiter(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	var hires: Array = recruit_board.get(serial, Props.payload_of(prop).get("hires", []))
	var hud = world.get("roguelite_hud")
	if hud != null and hud.has_method("open_recruiter"):
		hud.open_recruiter(serial, hires)
		return
	# No panel: the first body on the board is the press.
	var buyer = player_for(actor)
	var buyer_peer := int(buyer.peer_id) if buyer != null else local_peer()
	hire(serial, 0, buyer_peer)


## Buy one body off a recruiter's board. Host-authoritative exactly as `buy` is: a
## guest's press becomes a request and the host's answer is what stands a body up.
##
## The recruit is a warband mercenary from the frame it is paid for
## (`Warband.hire_recruit`), so it costs a place in no cap and its kit is locked;
## the field stands it up on the sprites' own frame (`stand_up_field`), and it is
## then handed a run runtime here, because `_spawn_runners` is otherwise called
## once an island. A recruit that dies is reaped like any dead name, and nothing
## in the run brings it back (`WarbandBody.expendable`).
func hire(serial: int, index: int, peer_id: int) -> Dictionary:
	if _client:
		send_request({"t": "hire", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return {"ok": false, "message": "That recruiter is gone."}
	var board: Array = recruit_board.get(serial, [])
	if index < 0 or index >= board.size():
		return {"ok": false, "message": "That is not one of the recruiter's bodies."}
	var offer: Dictionary = board[index]
	if bool(offer.get("sold", false)):
		return {"ok": false, "message": "That one has already been bought."}
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ok": false, "message": "The warband is not here."}
	var result: Dictionary = warband.hire_recruit(offer)
	if not bool(result.get("ok", false)):
		return result
	# The body is the roster's from this frame, so the field can stand it up now
	# rather than on the next physics tick - and the runtime goes on it in the same
	# press, or the recruit would fight without its stats until the next island.
	if world.has_method("stand_up_field"):
		world.call("stand_up_field")
	_spawn_runners()
	gold_mirror = gold()
	_broadcast({"t": "gold", "total": gold_mirror})
	offer["sold"] = true
	board[index] = offer
	recruit_board[serial] = board
	_broadcast({"t": "sold", "serial": serial, "index": index,
		"price": int(offer.get("price", 0)), "peer": peer_id})
	_broadcast({"t": "notice", "text": str(result.get("message", "")), "seconds": 3.5})
	return result


## Pay a bought recruit off from the board that sold him. Host-authoritative like
## every other stop verb, and the inverse of `hire`: the runtime goes, the roster
## row goes (`Warband.dismiss_recruit`) and the body leaves the field on the same
## press (`WorldScene.dismiss_body`). Only a recruit may be dismissed - a sworn
## mercenary is the band's, and a body a human soul is inside is never taken out
## from under it.
func dismiss(merc_id: int) -> Dictionary:
	if _client:
		send_request({"t": "dismiss", "merc": merc_id})
		return {"ok": true, "message": "Sent to the host."}
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ok": false, "message": "The warband is not here."}
	var controller = world.get("controller") if world != null else null
	if controller != null and controller.has_method("possessing_peers"):
		for peer in controller.possessing_peers():
			if int(controller.call("merc_for_peer", peer)) == merc_id:
				return {"ok": false,
					"message": "A soul is inside that body: step out of it first."}
	var result: Dictionary = warband.dismiss_recruit(merc_id)
	if not bool(result.get("ok", false)):
		return result
	# The runtime goes with the name: a body that is no longer in the party must not
	# keep drafting, holding a peer row or feeding the party's own stats.
	players.erase(ALLY_PEER_BASE + maxi(1, merc_id))
	if world.has_method("dismiss_body"):
		world.call("dismiss_body", merc_id)
	_broadcast({"t": "notice", "text": str(result.get("message", "")), "seconds": 3.0})
	return result


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
	var payload := Props.payload_of(prop)
	var contract: Variant = payload.get("contract", {})
	if contract is Dictionary and not (contract as Dictionary).is_empty():
		active_contract = contract
	advance_level(str(payload.get("biome", biome_id)))


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
	if kind == "market":
		_status("LEVEL %d  ·  MARKET  ·  spend, then the road continues" % next, 4.0)
	elif kind == "shop":
		_status("LEVEL %d  ·  SHOP LEVEL  ·  kit up before the boss" % next, 4.0)
	elif kind == "boss":
		_status("LEVEL %d  ·  BOSS  ·  %s" % [next,
			str(StageScript.biome(biome_id).name)], 4.0)
	else:
		var trial_label := str(TRIAL_LABEL.get(
			str(active_contract.get("trial", "")), ""))
		if trial_label != "" and trial_label != "OPEN":
			_status("LEVEL %d  ·  %s  ·  %s" % [next, trial_label,
				str(StageScript.biome(biome_id).name)], 4.0)
		else:
			_status("LEVEL %d  ·  %s" % [next,
				str(StageScript.biome(biome_id).name)], 4.0)


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
	market_level = false
	boss_level = false
	level = 0
	wave = 0
	active_contract.clear()
	_chest_paid.clear()
	_trial_budget_mult = 1.0
	_trial_live_cap_add = 0
	_trial_extra_elites = 0
	# No island is measuring anything now; the next run starts from its depth.
	_earned_cap = 0
	_frame_ms = 0.0
	_budget_clock = 0.0
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	# The chamber's air is the stage's; back in the world the eye takes the sky.
	if world != null and world.get("camera") != null:
		world.camera.environment = null
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		# A run is over; nobody leaves it on the dirt. The roster, the HUD and
		# the world's wipe rule all expect a party that is still standing - except
		# a hireling, who is nobody's to hand back: his ten seconds run on where he
		# fell, so the band loses him on the ground it happened.
		if run.body != null and is_instance_valid(run.body) \
				and _flag(run.body, "downed", false) \
				and not _flag(run.body, "expendable", false):
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
	# Broadhead's point: a point of damage on every shaft, added after the
	# multipliers so a share of the base never dilutes it.
	var flat := maxf(0.0, float(plan.get("damage_add", 0.0)))
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
		var damage := (base * damage_scale + flat) * factor
		var arrow := ArrowScript.new()
		arrow.source_id = int(actor.slot)
		arrow.shooter = actor
		arrow.hit_mask = 1 | 2
		arrow.authoritative_damage = true
		arrow.heal_on_hit = rig.bow_heal_on_hit()
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
## chest is the card, so the drop is a small cache holding one offer per body.
func _drop_card(run, effect: Dictionary) -> void:
	var candidates: Array[String] = []
	for id in run.engine.stacks:
		if int(run.engine.stacks[id]) < Mods.max_stacks(str(id)):
			candidates.append(str(id))
	var at: Vector3 = effect.get("position", Vector3.ZERO)
	var offer := Mods.roll_shelf(_rng, Mods.SOURCE_STALL, stage_index + 1, 1,
		int(run.luck()), candidates, run.carrier_tags())
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
	var card_payload := {"payout": Mods.PAYOUT_CARDS, "style": "mini",
		"offers": table, "label": "A CARD, DROPPED"}
	var card = _spawn_prop("chest", Vector3(at.x, stage.global_position.y, at.z),
		card_payload)
	if card == null:
		return
	draft_offers[int(card.get_meta("serial"))] = table
	_broadcast_prop(card, "chest", card_payload)


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
	var payload := {"payout": Mods.PAYOUT_ROLL, "style": "mini"}
	var chest = _spawn_prop("chest", ground, payload)
	if chest != null:
		_broadcast_prop(chest, "chest", payload)
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
			start_run()
		"sync":
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
		"hire":
			hire(int(request.get("serial", 0)), int(request.get("index", 0)), peer_id)
		"dismiss":
			dismiss(int(request.get("merc", -1)))
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
		"ability":
			_apply_ability_choice(int(event.get("peer", 0)), str(event.get("id", "")))
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
			if run != null and is_instance_valid(run) \
					and not _flag(run.body, "expendable", false):
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
		# A new level on the wire is a new field: the last one's bodies, standing
		# or lying, are replicas of a wave the host has already left behind.
		_free_mobs()
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
	market_level = bool(event.get("market_level", false))
	boss_level = bool(event.get("boss_level", false))
	var contract: Variant = event.get("contract", {})
	if contract is Dictionary and not (contract as Dictionary).is_empty():
		active_contract = contract
	gold_mirror = int(event.get("gold", gold_mirror))
	total_kills = int(event.get("kills", total_kills))
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
			var pair := hand_pair_for(merc)
			var run = PlayerScript.new()
			world.add_child(run)
			run.bind(body, self, peer, merc, str(pair.get("ranged", "")),
				str(pair.get("melee", "")))
			run._active_slot = "ranged" if not str(pair.get("ranged", "")).is_empty() else "melee"
			players[peer] = run
			if body.get("combat") != null:
				body.combat.ammo_gate = Callable()
			_apply_hands(run, str(run._active_slot))


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
	elif kind == "recruiter":
		recruit_board[serial] = payload.get("hires", [])


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


# --- the admin console ------------------------------------------------------
#
# A debug door into the loop, never a run rule. Everything here is the host's
# press, spells its refusal in the party's own line, and moves the same state the
# loop moves: a granted row is the row a chest pays, a re-stood gate is the gate
# `_spawn_gates` builds, a cleared wave is the wave `_clear_wave` books. That is
# the point - the console exists to reach the states the loop reaches slowly, not
# to invent states the loop cannot.

## Every hostile on the field dies at once and the inbound queue is emptied, so
## the level clears on the next tick exactly as a finished wave does.
func admin_kill_all() -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not run_active:
		return {"ok": false, "message": "No run is live."}
	if not wave_active:
		return {"ok": false, "message": "Nothing is fighting: this level is already clear."}
	var killed := 0
	var source := _local_body_slot()
	for mob in _mobs.duplicate():
		if not is_instance_valid(mob) or mob.get("alive") == false:
			continue
		if not (mob as Object).has_method("take_damage"):
			continue
		mob.take_damage(1.0e7, source)
		killed += 1
	var queued := _queue.size()
	queue_clear()
	var line := "ADMIN  ·  %d bodies down  ·  %d inbound emptied" % [killed, queued]
	_status(line, 3.0)
	_broadcast_state()
	return {"ok": true, "killed": killed, "queued": queued, "message": line}


## Hand one peer's run body a row, `count` stacks at a time, up to the row's own
## ceiling. A row the body's hands do not fit is written to the engine anyway:
## a debug switch is the one place a row that no chest would deal can be read,
## and the row's keys act wherever they act.
func admin_grant_mod(peer_id: int, mod_id: String, count: int = 1) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not Mods.has(mod_id):
		return {"ok": false, "message": "That is not an upgrade."}
	var run = players.get(int(peer_id))
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in the run."}
	var cap := Mods.max_stacks(mod_id)
	var granted := 0
	var forced := false
	for _stack in maxi(1, count):
		if int(run.engine.stacks_of(mod_id)) >= cap:
			break
		var answer: Dictionary = run.take_mod(mod_id)
		if not bool(answer.get("ok", false)):
			if not run.engine.add_mod(mod_id):
				break
			run.apply_stats()
			forced = true
		granted += 1
	if granted <= 0:
		var spent := "%s is at its ceiling (%d)." % [Mods.name_of(mod_id), cap]
		_status("ADMIN  ·  " + spent, 2.5)
		return {"ok": false, "message": spent}
	var line := "%s  ·  %d/%d%s" % [Mods.name_of(mod_id),
		int(run.engine.stacks_of(mod_id)), cap, "  ·  forced" if forced else ""]
	_broadcast({"t": "mod", "peer": int(peer_id), "id": mod_id, "message": line})
	_status("ADMIN  ·  " + line, 3.0)
	state_changed.emit()
	return {"ok": true, "count": granted, "stacks": int(run.engine.stacks_of(mod_id)),
		"message": line}


## Open a piece for this player and wear it in the hand it belongs to. In a run
## the body is re-dressed through the warband, exactly as the rack's own press
## does it; in the square the piece is worn on the roster.
func admin_give_weapon(peer_id: int, weapon_id: String) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not Weapons.has(weapon_id):
		return {"ok": false, "message": "That weapon is not in the armory."}
	var warband = world.get("warband") if world != null else null
	if warband == null:
		return {"ok": false, "message": "There is no warband to arm."}
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("grant_weapon"):
		meta.grant_weapon(weapon_id)
	warband.grant_gear(weapon_id)
	var slot := Weapons.slot_of(weapon_id)
	var display := Weapons.display_name(weapon_id)
	var run = players.get(int(peer_id))
	if run != null and is_instance_valid(run):
		var worn: Dictionary = _wear_hand(run, slot, weapon_id)
		var line := "%s  ·  %s hand" % [display, slot]
		if not bool(worn.get("ok", false)):
			line = "%s  ·  %s" % [display, str(worn.get("message", ""))]
		_broadcast({"t": "rebind", "peer": int(peer_id), "slot": slot, "weapon": weapon_id})
		_status("ADMIN  ·  " + line, 3.0)
		_broadcast_state()
		return {"ok": true, "message": line}
	var merc := _merc_for_peer(int(peer_id))
	var line := "%s  ·  in the shared stash" % display
	if merc > 0:
		var worn_town: Dictionary = warband.equip_hand(merc, slot, weapon_id)
		if world != null and world.get("controller") != null:
			world.controller.refresh_gear(merc)
		if bool(worn_town.get("ok", false)):
			line = "%s  ·  %s hand" % [display, slot]
	_status("ADMIN  ·  " + line, 3.0)
	return {"ok": true, "message": line}


## Open a skill for this player and put it on the body's bar. A skill whose
## family the hands do not fit is still granted - the unlock is the player's -
## and the equip's refusal is what the line reports.
func admin_give_ability(peer_id: int, ability_id: String) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	var definition: Dictionary = AbilityRules.by_id(ability_id)
	if definition.is_empty():
		return {"ok": false, "message": "That is not a skill."}
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("grant_ability"):
		meta.grant_ability(ability_id)
	var display := str(definition.get("name", ability_id)).capitalize()
	if AbilityRules.is_automatic(ability_id):
		var always := "%s  ·  always on the bar" % display
		_status("ADMIN  ·  " + always, 2.5)
		return {"ok": true, "message": always}
	var warband = world.get("warband") if world != null else null
	var run = players.get(int(peer_id))
	var merc := int(run.merc_id) if run != null and is_instance_valid(run) \
		else _merc_for_peer(int(peer_id))
	if warband == null or merc <= 0:
		var open := "%s  ·  open in the rack" % display
		_status("ADMIN  ·  " + open, 2.5)
		return {"ok": true, "message": open}
	var equipped: bool = warband.roster.hotbar_order_of(merc).has(ability_id)
	var answer: Dictionary = warband.toggle_ability(merc, ability_id)
	# The bar is drawn at dress time: the body is re-dressed so the key the console
	# just filled is on the next frame's plate, not the next level's.
	if run != null and is_instance_valid(run):
		_apply_hands(run, str(run._active_slot))
	elif world.get("controller") != null:
		world.controller.refresh_gear(merc)
	var line := "%s  ·  %s" % [display, "off the bar" if equipped else "on the bar"]
	if not bool(answer.get("ok", false)):
		line = "%s  ·  open; %s" % [display, str(answer.get("message", ""))]
	_status("ADMIN  ·  " + line, 3.0)
	return {"ok": true, "equipped": not equipped, "message": line}


## Re-stand the three gates of the level the party is standing on. `roll` moves
## the board: the contracts are rolled again from a fresh route seed, so the
## party reads three different promises at three different prices.
func admin_stand_gates(roll: bool = false) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not run_active:
		return {"ok": false, "message": "No run is live."}
	if not (level_cleared or shop_level):
		return {"ok": false, "message": "Only a cleared level stands gates."}
	_clear_props_of("portal")
	if roll:
		_gate_salt += 1
	_spawn_gates(level + 1)
	var line := "%s  ·  %d gates" % ["ADMIN ROLL" if roll else "ADMIN", GATES.size()]
	_status(line, 3.0)
	_broadcast_state()
	return {"ok": true, "gates": GATES.size(), "rolled": roll, "message": line}


## Re-stand the level's boxes. `roll` re-rolls the promise itself - surface and
## tier - and writes it back into the contract, so the level is paid by the chest
## it now shows; a plain re-stand keeps the promise the party was already dealt.
## Either way every box is fresh, with its own three cards, and may be opened
## again.
func admin_stand_chests(roll: bool = false) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not run_active:
		return {"ok": false, "message": "No run is live."}
	if not (level_cleared or shop_level):
		return {"ok": false, "message": "Only a cleared level stands a chest."}
	if stage == null or not is_instance_valid(stage):
		return {"ok": false, "message": "There is no island left to stand a box on."}
	_clear_props_of("chest")
	_clear_chest_books()
	var spec := _active_chest_spec()
	var surface := str(spec.get("surface", ""))
	var tier := str(spec.get("tier", ""))
	var copies := maxi(1, int(spec.get("mult", 1)))
	var payout := Mods.surface_payout(surface)
	var style := "chest"
	if boss_level:
		# A boss keeps its hoard: there is no surface to promise and no card to
		# re-roll, so the console stands the same elite box again.
		surface = ""
		tier = ""
		copies = 1
		payout = Mods.PAYOUT_HOARD
		style = "elite"
	elif roll:
		var promise := Mods.roll_promise(_rng, stage_index + 1, _party_luck(),
			_party_hands())
		surface = str(promise.get("surface", ""))
		tier = str(promise.get("tier", ""))
		payout = Mods.surface_payout(surface)
		active_contract["chest"] = {"surface": surface, "tier": tier, "mult": copies}
	var boxes: Array[Dictionary] = []
	for _copy in copies:
		boxes.append({"main": true, "payout": payout, "style": style})
	_stand_chests(boxes, surface, tier)
	var title := _chest_title(surface, tier, copies)
	var line := "%s  ·  %s" % ["ADMIN ROLL" if roll else "ADMIN",
		title if not title.is_empty() else "THE HOARD"]
	_status(line, 3.0)
	_broadcast_state()
	return {"ok": true, "boxes": boxes.size(), "rolled": roll,
		"surface": surface, "tier": tier, "message": line}


## Stand the party on any floor of the run. The island is rebuilt when the floor
## crosses a depth block, and the level's contract is the one a gate would have
## rolled for it, so a jumped-to level is a level the loop can hold.
func admin_goto_level(target: int) -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not run_active:
		return {"ok": false, "message": "No run is live. Open one at the portal first."}
	if world == null or world.get("controller") == null:
		return {"ok": false, "message": "There is no world to stand a party in."}
	var next := clampi(int(target), 1, 9999)
	var next_island := int((next - 1) / LEVELS_PER_ISLAND)
	wave = int((next - 1) % LEVELS_PER_ISLAND) + 1
	var moved := next_island != stage_index
	stage_index = next_island
	# The contract for the floor landed on: the biome the run is already in, an
	# open trial, and the surface and tier the route rolls for that depth.
	_route_rng.seed = (int(run_seed) ^ (next * 4177) ^ (_gate_salt * 104729)) \
		& 0x7fffffff
	var promise := Mods.roll_promise(_route_rng, next_island + 1, _party_luck(),
		_party_hands())
	if _opens_island(next) and _ability_promise_available():
		# The first chest on a new island is an ABILITY chest, a jump included:
		# the console reaches the loop's states, it does not invent others.
		promise["surface"] = Mods.CHEST_ABILITY
	var chest := {"surface": str(promise.get("surface", "")),
		"tier": str(promise.get("tier", "")), "mult": 1}
	active_contract = {
		"kind": _kind_for_level(next), "biome": biome_id,
		"faction": str(StageScript.biome(biome_id).faction),
		"trial": TRIAL_OPEN, "trial_params": {},
		"chest": chest, "label": _contract_label(chest, TRIAL_OPEN),
		"next_level": next,
	}
	if moved:
		_begin_island(biome_id)
	_begin_level()
	_broadcast_state()
	var line := "ADMIN  ·  LEVEL %d  ·  %s" % [level, str(StageScript.biome(biome_id).name)]
	_status(line, 4.0)
	return {"ok": true, "level": level, "island": stage_index + 1, "message": line}


## Close the run and put the party back on the square. No wipe is booked: the
## ledger records the runs a party loses, and this is not one.
func admin_goto_town() -> Dictionary:
	if _client:
		return {"ok": false, "message": "The admin console is the host's."}
	if not run_active:
		return {"ok": true, "message": "Already in Hearthstead."}
	var reached := level
	# A guest has to be told the run ended, exactly as a wipe tells it, or its
	# island would stand while this machine's party walks the square.
	_broadcast({"t": "end", "won": false, "level": reached})
	_close_run()
	var line := "ADMIN  ·  back to Hearthstead"
	_status(line, 4.0)
	return {"ok": true, "level": reached, "message": line}


## The slot this machine's own body fights under, so a console kill books its
## gold to the body a landing blow would have credited.
func _local_body_slot() -> int:
	if world == null or world.get("controller") == null:
		return 0
	var body = world.controller.body_of(_merc_for_peer(local_peer()))
	if body == null or not is_instance_valid(body):
		return 0
	return int(body.get("slot"))


## Take every prop of one kind off the island, with the books that go with it: a
## re-stood gate and a re-stood chest must not leave a spent serial behind.
func _clear_props_of(kind: String) -> int:
	var removed := 0
	for prop in _props.duplicate():
		if not is_instance_valid(prop) or Props.prop_kind(prop) != kind:
			continue
		var serial := int(prop.get_meta("serial", 0))
		_props.erase(prop)
		_props_by_serial.erase(serial)
		_opened.erase(serial)
		_users.erase(serial)
		_chest_paid.erase(serial)
		draft_offers.erase(serial)
		if _main_chests.has(serial):
			_main_chests.erase(serial)
		_main_open.erase(serial)
		shop_wares.erase(serial)
		recruit_board.erase(serial)
		_broadcast({"t": "prop_gone", "serial": serial})
		(prop as Node).queue_free()
		removed += 1
	return removed


## The chest books a fresh set of boxes starts without: what was paid, who took
## a helping, the drafts the last boxes dealt and the raise they gave.
func _clear_chest_books() -> void:
	_chest_paid.clear()
	_users.clear()
	draft_offers.clear()
	_main_chests.clear()
	_main_open.clear()
	_level_raised = false


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
		"market_level": market_level,
		"contract": active_contract,
		"trial": str(active_contract.get("trial", "")),
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
