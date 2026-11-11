extends CharacterBody3D
## Host-authoritative ranger clone: a crimson-black mirror of the player that
## fights with a random paperdoll kit. The body keeps the player rig and combat
## clocks, so it draws, cuts, guards and parries exactly like a ranger; the AI is
## the arena bot's range discipline plus a guard reaction and a sidestep.
##
## The frontier and the delve both own it:
## - frontier: `attack_mode = "scene"` routes melee through `attacked`, so the
##   controller resolves the live ranger's guard and damage;
## - delve: `attack_mode = "direct"` strikes the delve actor and reports the
##   outcome through `struck`, on the same contract as every other mob.

signal defeated(enemy: Node3D, reward: int)
signal attacked(attacker: CharacterBody3D, amount: float, victim: Node3D)
signal arrow_fired(origin: Vector3, direction: Vector3, speed: float, damage: float)
signal died(clone)
signal struck(target, amount: float, position: Vector3, outcome)

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const NetReplication = preload("res://scripts/net_replication.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const CorpseHold = preload("res://scripts/corpse_hold.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const DodgeStep = preload("res://scripts/dodge_step.gd")
const CoverMovement = preload("res://scripts/cover_movement.gd")
const Stamina = preload("res://scripts/stamina.gd")
const State = preload("res://scripts/player_state.gd")
const MobSenses = preload("res://scripts/mob_senses.gd")
const MobSteering = preload("res://scripts/mob_steering.gd")
const MobWander = preload("res://scripts/mob_wander.gd")
const MobLod = preload("res://scripts/mob_lod.gd")
const CloneAi = preload("res://scripts/clone_ai.gd")
const AbilityRunner = preload("res://scripts/ability_runner.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilityFx = preload("res://scripts/ability_fx.gd")
const AbilitySignatures = preload("res://scripts/ability_signatures.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")

const MAX_HEALTH := 100.0
const GOLD := 14
const KIND := 8
const BODY_RADIUS := 0.30
const BODY_HEIGHT := 1.80
const STRIKE_PROGRESS := 0.38
## Inside this distance the clone puts the bow away and closes to blade reach,
## so a party is never kept at arm's length by a circling archer.
const BLADE_RANGE := 11.0
## The bow only fires backwards of this: closer than that the clone advances
## through its own shot lane instead of backing off.
const BOW_MIN_RANGE := 6.0
## The brain's own clocks - swing cadence, guard share, reaction delay, sidestep
## cadence, pace, turn, sight, bow lead and blow weight - are `CloneAi`'s: this
## body reads one tier and spends it, so the pit can be retuned without touching a
## clock. The rig's telegraph and strike are its clip's and stay as authored.

## The item skills a clone may roll for itself. A clone is a duellist with a
## ranger's kit, so it performs the beats that are a blade, a bow or a staff: the
## shapes this body can aim and the scene can resolve from its own `attacked`
## road. The list itself is the shared table's (`AbilityRules.AI_KINDS`) - a
## recruit rolls from the same one - and a `const` alias keeps this module's own
## name for it.
const CASTABLE_KINDS := AbilityRules.AI_KINDS
## One beat's reach for a ground skill is its radius; an aimed one is allowed to
## pick a body out of the middle distance.
const CAST_ARROW_REACH := 28.0
const CAST_SPELL_REACH := 26.0
## Bodies one clone beat may reach, on top of what the definition asks for: a pit
## of four bodies does not need a skill that sweeps a crowd of twelve.
const CAST_MAX_VICTIMS := 6
## How long a clone that has decided to cast holds its hands off its blade. A cut
## is performed from a whole stance, so the brain reserves the body: no new swing
## starts until the clip it is already inside has finished, and if the stance never
## comes the hold expires and the fight carries on.
const CAST_HOLD := 1.2

## What a clone is issued, one rung per depth block - one block is ten levels,
## `stage_index + 1` in the director - so the kit steps on the same beat the run
## does and never mid-block. A body in the first block carries what an unblooded
## ranger can lift: a short bow, a plain blade, a dagger, leather or cloth. Mail
## arrives in the second block, plate in the third, the long bow and the great
## sword in the fourth, and the fire staff at the fifth and every block after.
## `armor` indexes `ArmorData.SET_IDS` (0 leather, 1 mail, 2 plate, 3 cloth).
const DEPTH_KIT := [
	{  # depth 1 - levels 1..10
		"main": ["bow_short", "sword_short", "dagger_iron"],
		"armor": [0, 3],
	},
	{  # depth 2 - levels 11..20: the recurve, the arming sword, the bone staff
		"main": ["bow_short", "bow_recurve", "sword_short", "sword_arming",
			"dagger_iron", "staff_bone"],
		"armor": [0, 1, 3],
	},
	{  # depth 3 - levels 21..30: the great sword, and plate on the body
		"main": ["bow_short", "bow_recurve", "sword_short", "sword_arming",
			"sword_great", "dagger_iron", "staff_bone"],
		"armor": [0, 1, 2, 3],
	},
	{  # depth 4 - levels 31..40: the long bow
		"main": ["bow_short", "bow_recurve", "bow_long", "sword_short",
			"sword_arming", "sword_great", "dagger_iron", "staff_bone"],
		"armor": [0, 1, 2, 3],
	},
	{  # depth 5 - levels 41 and on: the fire staff
		"main": ["bow_short", "bow_recurve", "bow_long", "sword_short",
			"sword_arming", "sword_great", "dagger_iron", "staff_fire",
			"staff_bone"],
		"armor": [0, 1, 2, 3],
	},
]
const OFF_POOL := ["shield_buckler","shield_kite","shield_tower"]
const FOCUS_POOL := ["focus_tome","focus_skull"]

var kind := KIND
var clone_id := 0
## How deep the body stands, and the only thing its kit is picked by: a shallow
## clone is issued a short bow or a plain blade, a deep one the great weapons and
## the plate. The run's own curve scales the pool, so depth is not a second pool.
var depth := 1
## What one of its blows is worth against a ranger's own. A clone carries a real
## kit and hits with it; the island sets this so a wave of them is a fight and not
## a firing squad.
var damage_scale := 1.0
## Which `CloneAi` tier this body fights on. `-1` takes the session's tier when
## `configure` runs; a spawner that wants a body of its own writes it first.
var ai_tier := -1
## The resolved knobs, read every tick. A clone is born on `Hard` and is never
## left with an empty table, so a body built without `configure` still fights.
var _ai: Dictionary = CloneAi.profile(CloneAi.DEFAULT_TIER)
## The item skill this body rolled for itself when its kit was issued (empty
## below `Medium`, where the tier performs nothing), and the runner that owns the
## beat: the cooldown, the stamina, the committed pose and the cue clock.
var ability_id := ""
var ability
## The brain's own wait between performances, beside the skill's cooldown.
var _cast_wait := 0.0
## Seconds left on a decided performance: while it runs the hands keep off the
## blade so the stance the skill needs can arrive.
var _cast_intent := 0.0
var _cast_aim := Vector3.ZERO
var authoritative := true
var replica := false
var auto_ai := true
var attack_mode := "scene"
var bounds := 143.0
var alive := true
var _impact_force := Vector3.ZERO
var health := MAX_HEALTH
var max_health := MAX_HEALTH
## Slot of the ranger whose damage landed last.
var last_hitter := -1
var stamina := Stamina.MAX
var state := "IDLE"
var targets: Array = []
var fallback_target
var home := Vector3.ZERO
var aggro_range := 30.0
var leash := 42.0
var rig
var combat
var dodge

var _main_item := "sword_short"
var _target
var _retarget := 0.0
var _guard_hold := 0.0
var _guard_cooldown := 0.0
## Set once this blow has had its one guard answer rolled, so the decision is not
## re-asked every frame the attacker's swing is in the air: a fifth of a chance
## polled sixty times a second is a certainty.
var _guard_answered_swing := false
## The same, for the sidestep: a share polled every frame is a certainty too.
var _step_answered_swing := false
## How long this attacker's wind-up has been in the air, against the tier's
## `reaction`: a clone slower to notice never answers a short one at all.
var _threat_clock := 0.0
var _step_cooldown := 0.0
var _attack_cooldown := 0.0
var _state_time := 0.0
var _swing_pending := false
var _swing_count := 0
var _move_intent := Vector3.ZERO
var _move_speed := 0.0
var _net_position := Vector3.ZERO
var _received_pose := false
## Buffered server states for the replica's delayed render.
var _timeline = NetReplication.mob_timeline()
var _death_handled := false
var _body: Node3D
var _collider: CollisionShape3D
var _shape: CapsuleShape3D
var _query := PhysicsRayQueryParameters3D.new()
var _floor_query := PhysicsRayQueryParameters3D.new()
var _steering := MobSteering.new()
## The cry the pack raised or the blow that named its striker. The clone hunts
## those bodies past its aggro range and leash until the clocks run out.
var _senses := MobSenses.new()
## The stretch of trail this clone patrols when nothing is in sight.
var _wander := MobWander.new()
## Tick budget: the further from the nearest ranger, the rarer the tick.
var _lod := MobLod.new()
## Presentation band last applied (0 shadowed, 1 animate-only, 2 resting).
var _present_band := -1
## Distance to the eye this machine draws through (`MobCuller.view_distance`), or
## -1 while nothing has measured it: what a body is drawn at is that camera's
## business, what it is simulated at is every soul's.
var _view_distance := -1.0
## Parked by `MobCuller`: no tick, no draw, no state change while it is true.
var dormant := false
## Whether this clone has already called the pack to the fight.
var _woke := false


func _ready() -> void:
	name = "RangerClone"
	collision_layer = 2
	collision_mask = 1
	# One slide per move: the clone steers its own lane.
	max_slides = 2
	# A body on a slope must keep its horizontal motion: the default stop
	# cancels it the moment the ground tilts, which read as crawling.
	floor_stop_on_slope = false
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(46.0)
	_shape = CapsuleShape3D.new()
	_shape.radius = BODY_RADIUS
	_shape.height = BODY_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	_collider.position.y = BODY_HEIGHT * 0.5
	add_child(_collider)
	_body = Node3D.new()
	_body.name = "CloneBody"
	add_child(_body)
	rig = Archer.new()
	rig.name = "RangerRig"
	_body.add_child(rig)
	rig.set_ground_sampler(_floor_height)
	combat = Combat.new()
	add_child(combat)
	combat.setup(rig, global_position + Vector3(0,1.2,0))
	combat.actor = self
	# The clone's damage is resolved by its owner scene, never by the shared
	# sweep: the frontier player body is not a Combat actor.
	combat.damage_enabled = false
	combat.target_mask = 0
	combat.shot.connect(_on_bow_released)
	# The skill runner is the shared one, on the same contract as a ranger's: it
	# owns *when* a beat happens and this body owns *what* it does, because a
	# clone's beats land on rangers and not on the wood's mobs.
	ability = AbilityRunner.new()
	ability.name = "CloneAbility"
	add_child(ability)
	ability.setup(self, rig, combat, 5.8)
	ability.cue.connect(_on_ability_cue)
	var cover := CoverMovement.new()
	add_child(cover)
	cover.setup(self,_collider)
	combat.cover = cover
	dodge = DodgeStep.new()
	add_child(dodge)
	_query.collision_mask = 1
	_floor_query.collision_mask = 1
	# Clones answer and raise the same pack alarm as every other wilderness
	# body, so a woken wave fights together.
	add_to_group(MobSenses.GROUP)


## `mode` is `"scene"` for the frontier and `"direct"` for the delve.
func configure(id: int, next_depth: int, is_authoritative: bool, mode: String = "scene") -> void:
	clone_id = maxi(0,id)
	depth = maxi(1,next_depth)
	authoritative = is_authoritative
	replica = not is_authoritative
	attack_mode = mode
	auto_ai = mode == "scene"
	# The session's tier unless the spawner named one before configuring: a run
	# that wants a body of its own writes `ai_tier` first, and everything else
	# follows the dial `CloneAi.set_tier` turns.
	if ai_tier < 0:
		ai_tier = CloneAi.current_tier
	ai_tier = CloneAi.clamp_tier(ai_tier)
	_ai = CloneAi.profile(ai_tier)
	_steering.bias = 1.0 if clone_id % 2 == 0 else -1.0
	_lod = MobLod.new(clone_id * 3)
	aggro_range = 40.0 if mode == "direct" else 30.0
	leash = 60.0 if mode == "direct" else 42.0
	_roll_loadout()
	max_health = _pool_health()
	health = max_health
	stamina = Stamina.MAX
	alive = true
	state = "IDLE"
	_state_time = 0.0
	_death_handled = false
	_impact_force = Vector3.ZERO
	_swing_pending = false
	_swing_count = 0
	_target = null
	_retarget = 0.0
	_guard_answered_swing = false
	_step_answered_swing = false
	_threat_clock = 0.0
	_attack_cooldown = 0.0
	_step_cooldown = 0.0
	_cast_wait = 0.0
	_cast_intent = 0.0
	_cast_aim = Vector3.ZERO
	ability.cancel()
	ability.cooldowns.fill(0.0)
	combat.source_id = 400 + clone_id
	combat.damage_enabled = false
	combat.target_mask = 0
	combat.stop()
	combat.attack_progress = 1.0
	rig.set_hit_react(0.0)
	rig.set_roll(-1.0,Vector3.FORWARD)
	rig.set_step(-1.0,Vector3.FORWARD)
	rig.set_slide(-1.0,Vector3.FORWARD)
	rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	_net_position = global_position
	_received_pose = false
	_steering.reset()
	_senses.clear()
	_wander.reset()
	_woke = false
	_body.rotation = Vector3.ZERO
	_body.position = Vector3.ZERO
	_body.visible = true


## Move this body onto another `CloneAi` tier, in place. A live body keeps its
## pool, kit and health - only its brain is retuned - so a menu or a lab can walk
## the ladder while the pit is fighting. Returns the tier now in force.
func set_ai_tier(tier: int) -> int:
	ai_tier = CloneAi.clamp_tier(tier)
	_ai = CloneAi.profile(ai_tier)
	return ai_tier


## The name of the tier this body fights on, for a plate or a log line.
func ai_tier_name() -> String:
	return CloneAi.name_of(ai_tier)


func spawn_at(point: Vector3, facing: Vector3 = Vector3.ZERO) -> void:
	global_position = point
	home = point
	_net_position = point
	_received_pose = true
	velocity = Vector3.ZERO
	alive = true
	health = max_health
	stamina = Stamina.MAX
	_death_handled = false
	_impact_force = Vector3.ZERO
	_swing_pending = false
	_threat_clock = 0.0
	_step_answered_swing = false
	_guard_answered_swing = false
	_cast_wait = 0.0
	_cast_intent = 0.0
	_cast_aim = Vector3.ZERO
	ability.cancel()
	state = "IDLE"
	_state_time = 0.0
	collision_layer = 2
	collision_mask = 1
	_target = null
	_steering.reset()
	_senses.clear()
	_wander.reset()
	_woke = false
	var flat := Vector3(facing.x,0.0,facing.z)
	if flat.length_squared() > 0.0001:
		rotation.y = atan2(-flat.x,-flat.z)


func get_display_name() -> String:
	return "Ranger clone"


func role() -> String:
	return "ranger"


func get_aim_position() -> Vector3:
	return global_position + Vector3(0,1.2,0)


func head_hitbox_center() -> Vector3:
	return rig.head_hitbox_center() if is_instance_valid(rig) else get_aim_position()


func head_hit_profile() -> Vector2:
	return rig.head_hit_profile() if is_instance_valid(rig) else Vector2(0.16,0.12)


func blood_rig() -> Node3D:
	return _body if is_instance_valid(_body) else self


func blood_scale() -> float:
	return 1.0


func blood_strike_point() -> Vector3:
	if is_instance_valid(rig):
		return rig.global_position + Vector3(0,1.25,0) - rig.global_basis.z * 0.45
	return get_aim_position()


func blood_weapon_anchor(_hand: String = "") -> Node3D:
	if is_instance_valid(rig) and rig.has_method("active_weapon_node"):
		return rig.active_weapon_node()
	return null


## The catalog id the clone would leave behind: its main-hand piece.
func held_weapon_id() -> String:
	return _main_item


## A patrol is one ranger, not a band: two clones never share a patch.
func wanders_packed() -> bool:
	return false


## How far the patrol strays from the spot it was posted to.
func wander_radius() -> float:
	return 15.0


func pack_family() -> String:
	return "ranger"


## Distance to the closest ranger, for the tick budget.
func _nearest_ranger() -> float:
	var best := INF
	if is_instance_valid(fallback_target):
		best = global_position.distance_squared_to(fallback_target.global_position)
	for candidate in targets:
		if is_instance_valid(candidate):
			best = minf(best, global_position.distance_squared_to(candidate.global_position))
	if best == INF:
		return INF
	return sqrt(best)


## Far clones stop sampling the player rig; it keeps its last pose.
func _cull_presentation(nearest: float) -> void:
	var band := MobLod.band(nearest)
	if band == _present_band:
		return
	_present_band = band
	if not is_instance_valid(rig):
		return
	# The rig is the heaviest body in the world: stop sampling it and stop its
	# shadow pass at range instead of hiding it, which would pop.
	rig.set_physics_process(band < 2)
	rig.set_process(band < 2)
	if rig.has_method("set_shadow_casting"):
		rig.set_shadow_casting(band == 0)


## The culler's only call into a parked body: one distance check per sweep.
## The pursuit, the bow ladder, the rig sampling and the swept move are all
## behind the physics process `mob_sleep` turns off.
##
## `eye_distance` is measured from every body a soul could be inside - the tick
## budget follows the fight, whoever is in it. `view_distance` is measured from
## this machine's own camera, and is the only one the presentation bands read.
func mob_lod_sweep(eye_distance: float = -1.0, view_distance: float = -1.0) -> void:
	if not alive:
		return
	if view_distance >= 0.0:
		_view_distance = view_distance
	var nearest := eye_distance if eye_distance >= 0.0 else _nearest_ranger()
	_cull_presentation(_present_distance(nearest))
	if not MobLod.dormant(nearest, dormant):
		if dormant:
			mob_wake()
		return
	if dormant:
		return
	if replica or _may_sleep():
		mob_sleep()


## How far this body is from the eye that draws it: the camera on this machine
## when the culler has measured one, and the nearest ranger as the fallback for a
## clone swept without a scene behind it.
func _present_distance(nearest: float) -> float:
	return _view_distance if _view_distance >= 0.0 else nearest


## Only a calm body with its feet down may park. A clone that is hunting has to
## keep running, and one parked mid-air would hang there. A replica runs no AI
## at all, so it parks on distance alone.
func _may_sleep() -> bool:
	return not _senses.aggressive() and is_on_floor()


## Parked: the clone keeps its loadout, health, patrol and corpse, and loses its
## physics process and its draw call. Nothing outside `MobSenses` can see it
## from here, and the frontier's fog is opaque well before it.
func mob_sleep() -> void:
	if dormant:
		return
	dormant = true
	if not replica:
		# Nothing banked from before the sleep; the first frame back is granted.
		_lod.resume()
		set_physics_process(false)
	visible = false


func mob_wake() -> void:
	if not dormant:
		return
	dormant = false
	_lod.resume()
	set_physics_process(true)
	visible = true
	# Re-apply the presentation band for the distance it woke at.
	_present_band = -1


func assign_territory(shared, ring_slot: int, pack_group: String) -> void:
	_wander.assign(shared, ring_slot, pack_group)


## The pool this body is born with, before any scene's own scale. One place for
## the formula, because `configure` and `apply_difficulty` both set it and two
## copies of the curve are two curves that can drift apart. Depth is *not* in it:
## it already picks the kit, and the run's `life` carries how deep the party is -
## counting depth twice made a level-two clone worth two wardens.
func _pool_health(life: float = 1.0) -> float:
	return maxf(1.0, MAX_HEALTH * maxf(0.01, life))


## The run's floor applied to the body: `life` multiplies the pool its depth gave
## it, and the verb sets from the depth rather than compounding, so a body scaled
## twice is the floor's body, not its square. `rate` is accepted for the shared
## dialect with the devils and spent on nothing: a clone's step and swing clocks
## are its `CloneAi` tier's, and a floor that scaled both would be two hands on
## one dial.
func apply_difficulty(life: float, _rate: float = 1.0) -> void:
	if not alive:
		return
	max_health = _pool_health(life)
	health = max_health


## Commit to a body. A clone's own rule is proximity (`aggro_range`), so a scene
## that hands it a quarry seats it in the roster the brain walks and wakes the
## body: from there the chase, the guard and the swing are the brain's own.
func hunt(target: Node3D) -> void:
	if not alive or not is_instance_valid(target) or target.get("alive") == false:
		return
	mob_wake()
	fallback_target = target
	if not targets.has(target):
		targets.append(target)
	_target = target
	# The brain re-picks its quarry on a timer; a body that has just been handed
	# one takes it on its next tick instead of finishing the old interval.
	_retarget = 0.0


## True while this body is fighting somebody. `squad_drive.retarget` asks before
## re-arming a hunt, exactly as it does of the watchers and the devils.
func hunting() -> bool:
	return alive and _engaged(_target)


func _roll_loadout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + clone_id * 7919 + depth * 131
	# The kit is the depth block's, not the die's and not the level's: a body in
	# the first ten levels is issued what an unblooded clone can lift, and the
	# great blades and the plate only come out in the blocks that follow.
	var rung: Dictionary = DEPTH_KIT[clampi(depth - 1, 0, DEPTH_KIT.size() - 1)]
	var kit: Array = rung.get("main", ["sword_short"])
	var sets: Array = rung.get("armor", [0])
	_main_item = str(kit[rng.randi_range(0,kit.size() - 1)])
	var off := ""
	if _main_item in ["sword_short","sword_arming","dagger_iron"]:
		var roll := rng.randf()
		if roll < 0.35:
			off = str(OFF_POOL[rng.randi_range(0,OFF_POOL.size() - 1)])
		elif roll < 0.45:
			off = str(FOCUS_POOL[rng.randi_range(0,FOCUS_POOL.size() - 1)])
	var pieces := {}
	for slot in ["head","chest","hands","legs","feet"]:
		pieces[slot] = int(sets[rng.randi_range(0,sets.size() - 1)])
	rig.apply_loadout(State.build_loadout(_main_item,off,pieces))
	_roll_ability(rng)
	_tint_rig()


## The one item skill this body performs, rolled off the same seed as its kit so
## a replica, a reload and a re-configure all name the same beat. Only the tiers
## from `Medium` up issue one, and only a skill this body's hands can actually
## perform: the grants table fits a skill to the hand that holds it, so a bow
## clone rolls a bow's beats and a greatsword clone rolls the great blade's.
func _roll_ability(rng: RandomNumberGenerator) -> void:
	ability_id = ""
	rig.set_ability_loadout([])
	if not bool(_ai.get("casts", false)):
		return
	var pool: Array[String] = []
	for definition in AbilityRules.ABILITIES:
		var effect: Dictionary = definition.get("effect", {})
		if not CASTABLE_KINDS.has(str(effect.get("kind", ""))):
			continue
		# A skill that sweeps its own lane only reaches it by moving the body
		# (the lunge's dash); this brain commits its beat on the spot, so a
		# travelling skill would cut the air it never crossed.
		if bool(effect.get("path_damage", false)):
			continue
		if not AbilityRules.fits_rig(definition, rig):
			continue
		pool.append(str(definition.get("id", "")))
	if pool.is_empty():
		return
	ability_id = pool[rng.randi_range(0,pool.size() - 1)]
	rig.set_ability_loadout([ability_id])


## Heavy crimson-black: every mesh under the rig gets its own duplicated
## material, so one clone never recolours another ranger or another clone.
func _tint_rig() -> void:
	var red := 0.30 + 0.05 * float(clone_id % 3)
	var black := 0.015 + 0.008 * float(clone_id % 2)
	for node in rig.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var tuned := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				tuned.albedo_color = Color(red,black,black,1.0)
				tuned.emission_enabled = true
				tuned.emission = Color(0.55,0.02,0.02)
				tuned.emission_energy_multiplier = 0.35
				mesh.set_surface_override_material(surface,tuned)


func _physics_process(delta: float) -> void:
	if dormant:
		return
	if not alive:
		if authoritative and not replica:
			CorpsePhysics.settle_root(self, delta)
		return
	if replica or not authoritative or not auto_ai:
		return
	var nearest := _nearest_ranger()
	_cull_presentation(nearest)
	var budget := _lod.slice(nearest, delta, not _senses.aggressive())
	if budget <= 0.0:
		return
	delta = budget
	dodge.advance(delta,is_on_floor())
	_step_ai(delta,targets)


## The delve drives wave members through this entry point.
func step(delta: float, actors: Array = [], _peers: Array = []) -> void:
	if not authoritative or replica or not alive:
		return
	dodge.advance(delta,is_on_floor())
	_step_ai(delta,actors)


func _step_ai(delta: float, candidates: Array) -> void:
	_state_time += delta
	_attack_cooldown = maxf(0.0,_attack_cooldown - delta)
	_guard_cooldown = maxf(0.0,_guard_cooldown - delta)
	_step_cooldown = maxf(0.0,_step_cooldown - delta)
	_retarget -= delta
	_senses.age(delta)
	stamina = minf(Stamina.MAX,stamina + Stamina.REGEN_PER_SECOND * delta)
	combat.advance(delta)
	# A body with no skill has nothing for the runner to clock: `advance` rebuilds
	# the grant row every tick, and a pit of eight of them is eight rows a frame
	# spent on a bar nobody will press.
	if not ability_id.is_empty():
		ability.advance(delta)
	_cast_wait = maxf(0.0,_cast_wait - delta)
	if _cast_intent > 0.0:
		_cast_intent = maxf(0.0,_cast_intent - delta)
		if _cast_intent <= 0.0:
			# The stance never came. The fight is not owed a longer wait: swing,
			# and decide again once this exchange has been paid for.
			_cast_wait = maxf(_cast_wait,1.0)
	if _swing_pending and combat.attack_progress >= STRIKE_PROGRESS:
		_swing_pending = false
		_resolve_melee()
	if ability.active:
		# A skill is a committed beat: the feet stand, the guard and the blade
		# wait, and the runner's own clock finishes it. Nothing else may move the
		# body while its signature is being performed.
		state = "CAST"
		_move_intent = Vector3.ZERO
		_move_speed = 0.0
		_apply_motion(delta,Vector3.ZERO)
		return
	var roster: Array = candidates
	if roster.is_empty() and is_instance_valid(fallback_target):
		roster = [fallback_target]
	if _retarget <= 0.0 or not _engaged(_target):
		_target = _nearest(roster)
		_retarget = 0.35
	if _engaged(_target):
		if not _woke:
			_woke = true
			MobSenses.alert_pack(self,_target,_target.global_position)
			MobSenses.alert_packmates(self,_target,_target.global_position,_wander.group)
	else:
		_woke = false
	_move_intent = Vector3.ZERO
	_move_speed = 0.0
	if not _engaged(_target):
		_target = null
		if combat.blocking:
			combat.stop_block()
		# A calm clone walks its patrol: the trail it was posted to, not a
		# statue on one spot.
		var outside: bool = _wander.outside(self)
		var patrol: Vector3 = _wander.step(self)
		state = "RETURN" if outside else "IDLE"
		if patrol.length_squared() > 0.0001:
			_move_intent = _steer(patrol)
			_move_speed = _pace(4.2 if outside else 2.6)
			_apply_motion(delta,_move_intent)
		else:
			_apply_motion(delta,Vector3.ZERO)
		return
	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()
	var direction := to_target.normalized() if distance > 0.001 else Vector3.FORWARD
	combat.set_aim(_aim_point(_target,distance))
	combat.face_block(direction)
	var threat: bool = _target_attacking(_target) and distance <= float(rig.melee_reach("right")) + 0.9
	if not threat:
		_guard_answered_swing = false
		_step_answered_swing = false
		_threat_clock = 0.0
	else:
		_threat_clock += delta
	# A clone that is slower to notice simply never answers a short wind-up: the
	# tier's `reaction` is how much of one has to pass before its hands move.
	var answerable: bool = threat and _threat_clock >= float(_ai.reaction)
	if combat.blocking:
		_guard_hold -= delta
		if _guard_hold <= 0.0 and not threat:
			combat.stop_block()
	elif answerable and not _guard_answered_swing and _guard_cooldown <= 0.0 \
			and combat.attack_progress >= 0.999:
		# One answer per blow, and only the tier's share of wind-ups earn it: the
		# roll is spent the moment the swing is seen, never again while it is in
		# the air.
		_guard_answered_swing = true
		if randf() < float(_ai.guard_answer) and combat.start_block(direction):
			_guard_hold = 0.30
			_guard_cooldown = 0.9
	if answerable and not combat.blocking and not _step_answered_swing \
			and _step_cooldown <= 0.0 and dodge.can_step(is_on_floor(),false):
		# The same one roll, on the feet instead of the guard.
		_step_answered_swing = true
		if randf() < float(_ai.step_chance):
			var tangent := Vector3(-direction.z,0.0,direction.x)
			if clone_id % 2 != 0:
				tangent = -tangent
			if dodge.try_step(tangent,is_on_floor(),false):
				_step_cooldown = float(_ai.step_gap)
	var want_bow := distance > BLADE_RANGE
	if _try_ability(distance):
		state = "CAST"
		_move_intent = Vector3.ZERO
		_move_speed = 0.0
		_apply_motion(delta,Vector3.ZERO)
		return
	if combat.attack_progress >= 0.999 and not combat.blocking and _cast_intent <= 0.0:
		if want_bow and rig.weapon != "bow":
			rig.set_weapon("bow")
		elif not want_bow and rig.weapon == "bow":
			rig.set_weapon("sword")
	if rig.weapon == "bow":
		state = "SHOOT" if rig.draw_amount > 0.0 else "CIRCLE"
		_bow_step(distance,direction)
	else:
		state = "STRIKE" if _swing_pending else "CIRCLE"
		_blade_step(distance,direction)
	_apply_motion(delta,direction)


func _apply_motion(delta: float, facing_direction: Vector3) -> void:
	var desired := _move_intent * _move_speed
	if dodge.active:
		var step_velocity: Vector3 = dodge.velocity()
		velocity.x = step_velocity.x
		velocity.z = step_velocity.z
	else:
		var control := 26.0 if is_on_floor() else 8.0
		velocity.x = move_toward(velocity.x,desired.x,control * delta)
		velocity.z = move_toward(velocity.z,desired.z,control * delta)
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= 18.0 * delta
	if facing_direction.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y,atan2(-facing_direction.x,-facing_direction.z),
			minf(delta * 10.0 * float(_ai.turn),1.0))
	var before := global_position
	MobLod.move(self)
	position.x = clampf(position.x,-bounds,bounds)
	position.z = clampf(position.z,-bounds,bounds)
	var actual := (global_position - before) / maxf(delta,0.0001)
	_present(actual)


func _present(actual: Vector3) -> void:
	rig.set_step(dodge.progress if dodge.active else -1.0,dodge.direction)
	rig.set_roll(-1.0,Vector3.FORWARD)
	rig.set_slide(-1.0,Vector3.FORWARD)
	rig.set_cover(false,Vector3.ZERO,0.0,false,Vector3.ZERO)
	# The rig turns onto the walk this clone meant to make, never onto the ground
	# a stopped blow shoved it across: a facing read from the shove leaves the
	# clone's back to the body whose blow its guard just stopped.
	rig.set_locomotion(actual,is_on_floor(),_move_intent)
	combat.set_motion(actual,actual.length() > 0.4,is_on_floor())


## Every pace this brain keeps, on the tier's own speed: the closing run, the
## circling walk, the shot lane and the patrol.
func _pace(base: float) -> float:
	return base * float(_ai.speed)


## The bow is a walking weapon here: the clone closes the gap between shots
## instead of orbiting at range, and only plants its feet while the string is
## drawn. A ranger who holds a corridor cannot be circled forever.
func _bow_step(distance: float, direction: Vector3) -> void:
	if distance < BOW_MIN_RANGE:
		_move_intent = -direction
		_move_speed = _pace(5.4)
	elif rig.draw_amount > 0.0 or rig.phase in ["DRAWING","HOLDING"]:
		var tangent := Vector3(-direction.z,0.0,direction.x) * 0.35
		if clone_id % 2 != 0:
			tangent = -tangent
		_move_intent = _steer(tangent)
		_move_speed = _pace(1.4)
	else:
		_move_intent = _steer(direction)
		_move_speed = _pace(4.6)
	if combat.can_draw() and _cast_intent <= 0.0 and _has_sight(_target):
		combat.begin_draw()
	elif rig.draw_amount >= 0.92 and rig.phase in ["DRAWING","HOLDING"]:
		combat.release_draw()


func _blade_step(distance: float, direction: Vector3) -> void:
	var reach: float = rig.melee_reach("right")
	if distance > reach * 0.80:
		_move_intent = _steer(direction)
		_move_speed = _pace(5.8)
	else:
		var tangent := Vector3(-direction.z,0.0,direction.x) * 0.55
		if clone_id % 2 != 0:
			tangent = -tangent
		_move_intent = tangent
		_move_speed = _pace(2.6)
		if _attack_cooldown <= 0.0 and _cast_intent <= 0.0 \
				and combat.attack_progress >= 0.999 and not combat.blocking \
				and _has_sight(_target):
			var swing := "diagonal_right" if (clone_id + _swing_count) % 2 == 0 else "diagonal_left"
			if combat.begin_melee("right",swing):
				_swing_count += 1
				_swing_pending = true
				# The tier's own cadence. The telegraph and the strike are the
				# rig's clip and stay as authored; this is the wait after it.
				_attack_cooldown = float(_ai.swing_gap)


func _resolve_melee() -> void:
	if not _target_alive(_target):
		return
	var to_target: Vector3 = _target.global_position - global_position
	to_target.y = 0.0
	if to_target.length() > rig.melee_reach("right") + 0.45:
		return
	if to_target.length_squared() > 0.0001 and (-global_basis.z).dot(to_target.normalized()) < 0.15:
		return
	var damage := _melee_damage()
	if damage <= 0.0:
		return
	if attack_mode == "scene":
		attacked.emit(self,damage,_target)
		return
	var outcome := Combat.DEFENSE_NONE
	if _target.has_method("receive_melee"):
		outcome = int(_target.receive_melee(damage,combat.source_id,global_position,false))
	elif _target.has_method("take_damage"):
		_target.take_damage(damage,combat.source_id)
	if outcome == Combat.DEFENSE_PARRY:
		stagger(Combat.PARRY_STAGGER)
	struck.emit(_target,damage,global_position,outcome)


func _melee_damage() -> float:
	if rig.weapon == "bow":
		return 0.0
	return float(rig.melee_base_damage("right")) * damage_scale * float(_ai.blow)


# --- the skill it rolled ---------------------------------------------------
#
# `AbilityRunner` owns *when*: the cooldown, the stamina, the committed pose, the
# rig's own clip and the cue clock. This body owns *what a beat does*, exactly as
# `WarbandAbilities` does for a ranger - but with the pit's targets and the pit's
# roads. A blade beat is announced through `attacked`, so the ranger's guard,
# armour, blood and damage numbers stay the world's business on the same contract
# the clone's sword already uses; an arrow is a real shaft and a spell a real orb,
# both authoritative, on the mask the clone's own bow already fires down.

## Attempt the rolled skill. The tier's willingness, the hand that must hold the
## piece, the stance and the sight are all asked before the runner is touched: a
## refused key costs a fraction of a second, never a swing.
func _try_ability(distance: float) -> bool:
	if ability_id.is_empty() or _cast_wait > 0.0:
		return false
	if ability == null or ability.active:
		return false
	if not _engaged(_target):
		return false
	var definition := AbilityRules.by_id(ability_id)
	if definition.is_empty() or distance > _cast_reach(definition):
		return false
	if not _has_sight(_target):
		return false
	var slot := _cast_slot()
	if slot < 0:
		# The hands do not hold the piece this skill is fired from right now - a
		# bow skill while the blade is out. Wait rather than re-asking every frame.
		_cast_wait = 0.5
		return false
	if combat.blocking:
		return false
	# A skill still on its own clock is not worth a stance: the reserve below holds
	# the blade still, and a spent piece would park the fight for its whole
	# cooldown. Wait out what is left of it and swing in the meantime.
	if slot < ability.cooldowns.size() and float(ability.cooldowns[slot]) > 0.0:
		_cast_wait = minf(3.0, float(ability.cooldowns[slot]))
		return false
	# The aim is committed before the key, not after: a bow skill's first cue fires
	# inside `activate` itself, and a beat aimed at nothing is a shot into the dirt.
	_cast_aim = _aim_point(_target,distance)
	_cast_intent = CAST_HOLD
	var answer: Dictionary = ability.activate(slot)
	if bool(answer.get("ok", false)):
		_cast_intent = 0.0
		_cast_wait = float(_ai.cast_gap)
		return true
	if str(rig.phase) == "READY":
		# A whole stance and still refused: it is the skill's own clock or a spent
		# pool, and neither is bought by holding the blade still.
		_cast_intent = 0.0
		_cast_wait = 0.75
	return false


## How far out the body commits to what it rolled: a ground beat reaches its own
## radius, a spell or an arrow is aimed at whatever the eye can see.
func _cast_reach(definition: Dictionary) -> float:
	var effect: Dictionary = definition.get("effect", {})
	match str(effect.get("kind", "")):
		"melee_arc", "melee_ring", "melee_wave":
			# The decision and the cut are the same measure: a clone that committed
			# a metre outside its own reach would whiff a skill it paid for.
			return _beat_radius(effect)
		"projectile":
			return CAST_SPELL_REACH
	return CAST_ARROW_REACH


## Where the rolled skill sits on the bar the hands grant right now, or -1 when
## nothing on that bar is this skill.
func _cast_slot() -> int:
	var grants := AbilityRules.granted(rig)
	for slot in grants.size():
		var definition = grants[slot]
		if definition is Dictionary and str(definition.get("id", "")) == ability_id:
			return slot
	return -1


## One performed beat, resolved from the definition the runner is holding so a
## hand swapped mid-skill can never leave the wrong effect behind.
func _on_ability_cue(id: String, cue: String, index: int) -> void:
	if not alive or replica or ability == null or not ability.active:
		return
	if str(ability.active_id) != id:
		return
	var definition: Dictionary = ability.active_definition
	if definition.is_empty():
		return
	var effect: Dictionary = definition.get("effect", {})
	var aim: Vector3 = _cast_aim if _cast_aim != Vector3.ZERO \
		else rig.global_position - rig.global_basis.z
	AbilitySignatures.cue(_fx_parent(), rig, definition, cue, index,
		_cast_forward(), aim)
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot":
			_cast_arrows(definition, index)
		"projectile":
			_cast_spell(definition)
		"melee_arc", "melee_ring":
			_cast_blade(definition, cue)
		"melee_wave":
			_cast_wave(definition, cue, index)


## Every activation keeps the point it was committed to: a beat's cues may fire
## inside `activate` itself, before the caller sees the answer, so the aim is set
## by the brain before the key is pressed and cleared by nothing else.


## The line a beat is drawn and thrown down: the aim point it committed to, or
## the body's own facing when there was nobody to aim at.
func _cast_forward() -> Vector3:
	var forward := _cast_aim - global_position if _cast_aim != Vector3.ZERO \
		else -global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


## The world a beat's art is drawn into: the scene's own root, never the body, so
## a crescent stays where it was cut.
func _fx_parent() -> Node3D:
	var world = get_parent()
	return world if world is Node3D else self


## What one beat is worth: the definition's own price, in the clone's hand.
func _cast_damage(definition: Dictionary) -> float:
	return AbilityRules.damage_for(definition, rig) * damage_scale * float(_ai.blow)


## A blade beat: an arc in front or a ring around, whoever the roster has inside
## it. The wind-up and the dash are presentation - the ring and the thrust cut.
func _cast_blade(definition: Dictionary, cue: String) -> void:
	if cue == "wind" or cue == "dash":
		return
	var effect: Dictionary = definition.get("effect", {})
	var radius := _beat_radius(effect)
	var arc := float(effect.get("arc_degrees", 360.0))
	var ring := str(effect.get("kind", "")) == "melee_ring" or arc >= 359.0
	var damage := _cast_damage(definition)
	for victim in _beat_victims(global_position, radius, arc, ring):
		_land_beat(victim, damage)


## The reach of a ground beat. The definition authors the shape, but a skill is
## performed with the blade the body already holds: a shove's own 1.7 m would cut
## short of where this clone's arm ends, and every cast would be thrown from a
## metre the sword cannot reach.
func _beat_radius(effect: Dictionary) -> float:
	return maxf(float(effect.get("radius", 1.7)), float(rig.melee_reach("right")))


## One wave of a three-strike necklace: its own share of the damage, its own
## reach across the rank, and its own victim count.
func _cast_wave(definition: Dictionary, cue: String, index: int) -> void:
	if cue != "wave":
		return
	var effect: Dictionary = definition.get("effect", {})
	var scales: Array = effect.get("wave_scales", [])
	var share := float(scales[index]) if index < scales.size() else 1.0
	var radius := _beat_radius(effect)
	var arc := float(effect.get("arc_degrees", 130.0))
	var per_wave := maxi(1, int(effect.get("victims_per_wave", 3)))
	var damage := _cast_damage(definition) * share
	var struck := 0
	for victim in _beat_victims(global_position, radius, arc, false):
		if struck >= per_wave:
			break
		_land_beat(victim, damage)
		struck += 1


## Barrage / fan volley / piercing shot: a real shaft per beat, down the line the
## body committed to, with the authored spread and the arrow's own pierce.
func _cast_arrows(definition: Dictionary, index: int) -> void:
	if rig.weapon != "bow":
		return
	var effect: Dictionary = definition.get("effect", {})
	var kind := str(effect.get("kind", ""))
	rig.aim_at(_cast_aim if _cast_aim != Vector3.ZERO else rig.global_position - rig.global_basis.z)
	rig.refresh_bow_pose()
	var origin: Vector3 = rig.get_arrow_origin()
	var base := _cast_aim - origin
	if base.length_squared() < 0.0001:
		base = -rig.global_basis.z
	var profile: Dictionary = Archer.BOW_DATA[
		clampi(int(rig.bow_index),0,Archer.BOW_DATA.size() - 1)]
	var speed := float(profile.speed) * float(effect.get("arrow_speed_scale", 1.0))
	var pierce := int(effect.get("pierce", 0))
	var shots := maxi(1, int(effect.get("shots", 1))) if kind == "volley" else 1
	var damage := _cast_damage(definition)
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(rig.active_shield):
		excluded.append(rig.active_shield.get_rid())
	for shot in shots:
		var pattern := index if kind == "barrage" else shot
		var offsets: Vector2 = AbilityFx.shot_offsets(definition, pattern)
		var direction := AbilityFx.rotate_direction(base, offsets.x, offsets.y).normalized()
		var arrow := Arrow.new()
		arrow.source_id = combat.source_id
		arrow.shooter = self
		# Layer 8 is the shield: a raised or carried shield takes the shaft first.
		arrow.hit_mask = 1 | 4 | 8
		arrow.authoritative_damage = true
		get_parent().add_child(arrow)
		arrow.launch(origin, direction, speed, damage, excluded, origin, pierce)
		arrow_fired.emit(origin, direction, speed, damage)


## Fireball / bone spear / lance: a real orb, authoritative, and its blast is
## resolved here because a clone's `Combat` owns no target set of its own.
func _cast_spell(definition: Dictionary) -> void:
	var effect: Dictionary = definition.get("effect", {})
	var origin: Vector3 = rig.cast_origin()
	var direction := _cast_aim - origin
	if direction.length_squared() < 0.0001:
		direction = -rig.global_basis.z
	var damage := _cast_damage(definition)
	var mask := 1 | 4 | 8
	var spell := SpellProjectile.new()
	spell.kind = str(effect.get("projectile", "fireball"))
	spell.hit_mask = mask
	spell.shooter = self
	spell.source_id = combat.source_id
	spell.authoritative_damage = true
	get_parent().add_child(spell)
	spell.launch(origin, direction.normalized(), float(effect.get("speed", 22.0)),
		damage, [get_rid()], mask, true, global_position,
		float(effect.get("radius", 3.0)), int(effect.get("pierce", 0)))
	spell.set_meta("clone_blast_damage", damage)
	spell.detonated.connect(_on_clone_spell_detonated.bind(spell))


## The burst owns the space it fills: everything of the roster inside the radius
## takes the authored blow, on the same road a swing does.
func _on_clone_spell_detonated(centre: Vector3, _direction: Vector3, spell) -> void:
	if not is_instance_valid(spell):
		return
	var radius := float(spell.blast_radius)
	var damage := float(spell.get_meta("clone_blast_damage", 0.0))
	if radius <= 0.0 or damage <= 0.0:
		return
	for victim in _beat_victims(centre, radius, 360.0, true):
		_land_beat(victim, damage)


## Who one beat reaches: the roster this body is already fighting, filtered by the
## shape around `centre`. A beat is a swing's cousin, so it reads the same roster
## the blade does instead of sweeping the world for bodies it never engaged.
func _beat_victims(centre: Vector3, radius: float, arc: float, ring: bool) -> Array:
	var out: Array = []
	var seen := {}
	var forward := _cast_forward()
	var right := forward.cross(Vector3.UP)
	var half := deg_to_rad(clampf(arc,0.0,360.0)) * 0.5
	for candidate in targets:
		if out.size() >= CAST_MAX_VICTIMS:
			break
		if not _target_alive(candidate) or candidate == self:
			continue
		var key: int = candidate.get_instance_id()
		if seen.has(key):
			continue
		var offset: Vector3 = candidate.global_position - centre
		offset.y = 0.0
		if offset.length() > radius:
			continue
		if not ring and half < PI - 0.01 and offset.length_squared() > 0.0001:
			if absf(atan2(offset.dot(right),offset.dot(forward))) > half:
				continue
		seen[key] = true
		out.append(candidate)
	return out


## Put one beat's damage on one body, down the road this clone already uses: the
## frontier and the pit resolve the live ranger's guard and armour from `attacked`,
## the delve's direct mode strikes the actor and reports through `struck`.
func _land_beat(victim, damage: float) -> void:
	if damage <= 0.0 or not _target_alive(victim):
		return
	if attack_mode == "scene":
		attacked.emit(self, damage, victim)
		return
	var outcome := Combat.DEFENSE_NONE
	if victim.has_method("receive_melee"):
		outcome = int(victim.receive_melee(damage, combat.source_id, global_position, false))
	elif victim.has_method("take_damage"):
		victim.take_damage(damage, combat.source_id)
	struck.emit(victim, damage, global_position, outcome)


func _on_bow_released(origin: Vector3, direction: Vector3, speed: float, charge: float) -> void:
	if not authoritative or not alive:
		return
	if not direction.is_finite() or direction.length_squared() < 0.01:
		return
	var damage := Combat.damage_for(rig.bow_index,charge) * damage_scale * float(_ai.blow)
	var arrow := Arrow.new()
	arrow.source_id = combat.source_id
	arrow.shooter = self
	# Layer 8 is the shield: a raised or carried shield takes the shaft first.
	arrow.hit_mask = 1 | 4 | 8
	arrow.authoritative_damage = true
	get_parent().add_child(arrow)
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(rig.active_shield):
		excluded.append(rig.active_shield.get_rid())
	arrow.launch(origin,direction.normalized(),speed,damage,excluded)
	arrow_fired.emit(origin,direction,speed,damage)


func note_impact(force: Vector3) -> void:
	_impact_force = Vector3(force.x, 0.0, force.z)


func take_damage(amount: float, source_id: int, headshot: bool = false, _react: bool = true) -> void:
	if not alive or replica:
		return
	# Being hit is not something a parked body can miss: it wakes and turns.
	mob_wake()
	last_hitter = source_id
	var applied: float = amount * Hitbox.damage_multiplier(headshot) * (1.0 - rig.damage_reduction(headshot))
	health = maxf(0.0,health - applied)
	DamageNumbers.spawn(get_parent(),get_aim_position(),applied,"hit",headshot,health <= 0.0)
	BloodFx.wound(self,blood_rig(),get_aim_position(),applied,headshot,health <= 0.0,blood_scale())
	if health <= 0.0:
		_die(true)


## Swords, daggers and staves meet the clone's guard here; arrows use take_damage.
func receive_melee(amount: float, source_id: int, attacker_position: Vector3, headshot: bool = false) -> int:
	if not alive or replica:
		return Combat.DEFENSE_NONE
	mob_wake()
	var outcome: int = combat.resolve_melee_defense(attacker_position)
	if outcome == Combat.DEFENSE_PARRY:
		return outcome
	if outcome == Combat.DEFENSE_BLOCK or outcome == Combat.DEFENSE_WEAK_BLOCK:
		stamina = maxf(0.0,stamina - combat.block_stamina_cost())
		var push := global_position - attacker_position
		push.y = 0.0
		if push.length_squared() > 0.000001:
			push = push.normalized() * Combat.BLOCK_PUSH_SPEED
			velocity.x = push.x
			velocity.z = push.z
		# The guard stays up: a clone's blade meets every blow it can pay for, and
		# its own `_guard_hold` clock is what finally lowers it.
		if outcome == Combat.DEFENSE_WEAK_BLOCK:
			take_damage(amount * Combat.WEAK_BLOCK_DAMAGE_SCALE,source_id,headshot,false)
		return outcome
	take_damage(amount,source_id,headshot)
	return Combat.DEFENSE_NONE


func stagger(seconds: float) -> void:
	if not alive:
		return
	mob_wake()
	combat.stagger(seconds)
	rig.set_hit_react(seconds)
	dodge.reset()
	velocity.x = 0.0
	velocity.z = 0.0


func snapshot() -> Dictionary:
	var rig_state: Array = rig.pack_animation_state(rig.get_animation_state()) if is_instance_valid(rig) else []
	if attack_mode == "direct":
		return {"kind":KIND,"id":clone_id,"role":"ranger","pos":global_position,"yaw":rotation.y,
			"state":state,"time":_state_time,"health":health,"alive":alive,
			"weapon":str(rig.weapon),"depth":depth,"max_health":max_health,"anim":rig_state}
	return {"kind":KIND,"id":clone_id,"max_health":max_health,"weapon":str(rig.weapon),
		"p":global_position,"y":rotation.y,"v":velocity,"g":is_on_floor(),
		"s":state,"t":_state_time,"h":health,"a":alive,"x":Vector4(-1,0,0,-1),
		"anim":rig_state}


func apply_snapshot(snapshot_state: Dictionary, tick: int = -1) -> void:
	authoritative = false
	replica = true
	auto_ai = false
	var had_pose := _received_pose
	var previous_health := health
	clone_id = int(snapshot_state.get("id",clone_id))
	var next_position: Vector3 = snapshot_state.get("pos",snapshot_state.get("p",_net_position))
	_net_position = next_position
	var next_velocity: Vector3 = snapshot_state.get("v",velocity)
	var yaw := float(snapshot_state.get("yaw",snapshot_state.get("y",rotation.y)))
	var at := tick if tick >= 0 else _timeline.newest_tick() + 1
	var now := Time.get_ticks_msec()/1000.0
	if not had_pose:
		_timeline.reset_to(next_position,next_velocity,yaw,at,now)
		position = next_position
		rotation.y = yaw
		_received_pose = true
	else:
		_timeline.push(at,next_position,next_velocity,yaw,now)
		rotation.y = _timeline.sample().yaw
	velocity = snapshot_state.get("v",velocity)
	max_health = float(snapshot_state.get("max_health",max_health))
	health = float(snapshot_state.get("health",snapshot_state.get("h",health)))
	alive = bool(snapshot_state.get("alive",snapshot_state.get("a",alive)))
	state = str(snapshot_state.get("state",snapshot_state.get("s",state)))
	_state_time = float(snapshot_state.get("time",snapshot_state.get("t",_state_time)))
	var weapon := str(snapshot_state.get("weapon",""))
	if weapon in ["bow","sword","dagger"] and str(rig.weapon) != weapon:
		rig.set_weapon(weapon)
	if snapshot_state.has("anim") and typeof(snapshot_state.anim) in [TYPE_DICTIONARY,TYPE_ARRAY]:
		rig.apply_animation_state(snapshot_state.anim)
	if had_pose and previous_health - health > 0.01:
		BloodFx.wound(self,blood_rig(),get_aim_position(),previous_health - health,
			false,health <= 0.0,blood_scale())
	if not alive and not _death_handled:
		_die(false)
	elif alive and _death_handled:
		alive = true


func _process(delta: float) -> void:
	if not replica or not alive or not _received_pose:
		return
	var before := position
	_timeline.advance(delta)
	var sample: Dictionary = _timeline.sample()
	position = sample.pos
	if is_instance_valid(rig):
		rig.set_locomotion((position - before)/maxf(delta,0.0001),true)


func _die(announce: bool) -> void:
	if _death_handled:
		return
	_death_handled = true
	alive = false
	state = "DEAD"
	var fall_dir := _impact_force if _impact_force.length_squared() > 0.0001 \
		else CorpsePhysics.fall_direction(self, velocity)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 1
	combat.stop()
	ability.cancel()
	dodge.reset()
	if is_instance_valid(rig):
		rig.set_step(-1.0,Vector3.FORWARD)
		rig.set_hit_react(0.0)
		# Stop the Archer's physics-clock animation and hide its loose props
		# before its skeleton is handed to the ragdoll; snapshots only mirror
		# state on dead replicas.
		rig.enter_corpse_pose()
	var limp = CorpsePhysics.start_limp(_body, fall_dir) if is_instance_valid(_body) else null
	var fall: Tween
	if limp != null:
		fall = create_tween()
		fall.tween_interval(0.5)
		CorpseHold.append(fall,self,_body)
	elif is_instance_valid(_body):
		fall = create_tween()
		fall.tween_property(_body,"rotation:z",PI * 0.47,0.5)
		CorpseHold.append(fall,self,_body)
	if announce:
		defeated.emit(self,GOLD)
		died.emit(self)


func _nearest(candidates: Array):
	var nearest = null
	var best := INF
	for candidate in candidates:
		if candidate == self or not _target_alive(candidate) or not _within_aggro(candidate):
			continue
		var offset: Vector3 = candidate.global_position - global_position
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < best:
			best = distance
			nearest = candidate
	return nearest


func _within_aggro(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	# A landed blow is a fight the clone cannot lose by distance: it walks the
	# whole way to whoever hit it, past the aggro range and past its leash.
	if _senses.aggressive() and candidate == _senses.target:
		return true
	# The tier's own eyes: a shallow clone notices a ranger later. The leash is
	# the scene's and is never scaled - how far a body may be led is a place's
	# rule, not a brain's.
	if global_position.distance_to(candidate.global_position) > aggro_range * float(_ai.sight):
		return false
	return global_position.distance_to(home) <= leash


func _engaged(candidate) -> bool:
	return _target_alive(candidate) and _within_aggro(candidate)


func _target_alive(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	if candidate.has_method("is_downed"):
		return not candidate.is_downed()
	var flag = candidate.get("alive")
	if flag == null:
		return true
	return bool(flag)


func _target_attacking(candidate) -> bool:
	var unit = candidate
	if is_instance_valid(candidate) and candidate.has_meta("ironwood_damage_target"):
		unit = candidate.get_meta("ironwood_damage_target")
	if not is_instance_valid(unit):
		return false
	var other = unit.get("combat")
	if other == null:
		return false
	var progress = other.get("attack_progress")
	if progress == null:
		return false
	return float(progress) < 0.999


func _aim_point(candidate, distance: float) -> Vector3:
	var point: Vector3 = candidate.global_position + Vector3(0,1.0,0)
	var speed := float(Archer.BOW_DATA[rig.bow_index].speed)
	var travel := distance / maxf(speed,1.0)
	var target_velocity = candidate.get("velocity")
	if typeof(target_velocity) == TYPE_VECTOR3:
		point += target_velocity * travel * float(_ai.lead)
	return point


func _has_sight(candidate) -> bool:
	if not is_instance_valid(candidate):
		return false
	_query.from = global_position + Vector3(0,1.35,0)
	_query.to = candidate.global_position + Vector3(0,1.1,0)
	return get_world_3d().direct_space_state.intersect_ray(_query).is_empty()


func _steer(direction: Vector3) -> Vector3:
	return _steering.steer(self,direction,0.9)


## A landed blow names its striker before it applies damage. The clone takes up
## the fight wherever the ranger runs to, exactly like every wilderness mob.
func note_attacker(attacker: Node3D) -> void:
	if not alive or replica or not is_instance_valid(attacker):
		return
	_senses.notice(attacker,attacker.global_position)
	_target = attacker
	_retarget = 0.0
	_woke = true
	MobSenses.alert_pack(self,attacker,attacker.global_position)


## A neighbour woke or was struck within earshot: take up the same hunt.
func hear_alert(attacker: Node3D, at: Vector3) -> void:
	if not alive or replica:
		return
	mob_wake()
	if is_instance_valid(attacker) and attacker is CharacterBody3D:
		_target = attacker
		_senses.hear(attacker, at)
		if _target_alive(_target):
			_woke = true


func _floor_height(point: Vector3) -> float:
	_floor_query.from = point + Vector3(0,1.2,0)
	_floor_query.to = point - Vector3(0,2.6,0)
	var hit := get_world_3d().direct_space_state.intersect_ray(_floor_query)
	return float(hit.position.y) if not hit.is_empty() else global_position.y
