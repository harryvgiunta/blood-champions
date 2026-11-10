class_name ProcEngine
extends RefCounted
## The deterministic on-hit modifier engine.
##
## One instance per body. It owns that body's mod stacks, turns them into the
## numbers the firing controllers read, and answers the seven combat events the
## arena loop hangs its triggers on:
##
##   `on_weapon_fire`   a shot leaving the string
##   `on_melee_swing`   a committed cut leaving the hand
##   `on_hit`           a landed ranged or melee blow
##   `on_kill`          a body put down by that blow
##   `on_player_damaged`  a blow landing on this body
##   `on_stage_clear`   an island finished
##   `advance`          the clock the timed rows read
##
## It never touches the scene, never spawns a node and never applies damage. It
## *decides* - and answers with effect requests (`{kind, ...}`) that the player's
## runtime executes. That split is what keeps the whole engine testable without a
## world, and what lets the host replicate an effect to its guests as one small
## dictionary.
##
## A request may also carry `mod`, the catalog row that fired it. Only a trigger
## exactly one row owns names its row: a chance two rows can write (the family
## bleed, a shared stat) stays anonymous rather than guessing. The runtime uses it
## for one thing - the colour its art is drawn in, mixed from that row's rarity -
## so a proc's flash tells the player which upgrade just paid. Nothing in the
## engine reads it back.
##
## Stacking rules, and why they are three rules and not one:
##   * `LINEAR` - damage, fire rate, crit, health, gold, lifesteal. Ten copies of
##     +18% rate is +180%, which is a number a player can read and a design can
##     price.
##   * `HYPERBOLIC` - every *chance*. These approach a cap and never reach it:
##     `cap * n / (n + half)`. The row authors nothing at all - the engine owns
##     the curve, so no stack count deletes the game.
##   * `MAX_KEYS` - caps, ranges, radii and durations. A second copy of Splash
##     Damage widens the spill's share, not its radius. Summing these is the
##     single easiest way to turn a tidy row into a broken one.
##
## Every roll is one call on the instance's own seeded generator, in a fixed
## order, so the same run seed and the same event sequence produce the same
## triggers on the host every time.

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")

## Chance stats and the curve each one rides. `half` is the stack count that
## reaches half the cap. A row that names a chance authors only the key: the
## design table's `cap`/`half` is what is written here, once.
const HYPERBOLIC := {
	"arc_chance": {"cap": 0.55, "half": 3.0},
	"nova_chance": {"cap": 0.55, "half": 3.0},
	"chain_chance": {"cap": 0.70, "half": 3.0},
	"bomb_chance": {"cap": 0.60, "half": 3.0},
	"scatter_chance": {"cap": 0.60, "half": 2.5},
	"chest_chance": {"cap": 0.75, "half": 3.0},
	"dodge_chance": {"cap": 0.60, "half": 4.0},
	"mace_chance": {"cap": 0.55, "half": 3.0},
	"spike_chance": {"cap": 0.70, "half": 4.0},
	"double_chance": {"cap": 0.70, "half": 4.0},
	"mega_crit_chance": {"cap": 0.55, "half": 3.0},
	"drop_chance": {"cap": 0.70, "half": 4.0},
	"throw_burst_chance": {"cap": 0.55, "half": 3.0},
	"triple_throw_chance": {"cap": 0.55, "half": 3.0},
	"double_burst_chance": {"cap": 0.55, "half": 3.0},
	"ability_recast_chance": {"cap": 0.40, "half": 4.0},
}

## Stats that describe a shape rather than an amount. Two copies of a row must
## not double a radius, a duration or a cap.
const MAX_KEYS := {
	"windup_cap": true, "streak_cap": true, "close_range": true, "far_range": true,
	"splash_radius": true, "aura_radius": true, "shot_aura_duration": true,
	"shot_aura_radius": true, "crit_burst_radius": true, "mega_crit_mult": true,
	"shock_radius": true, "explode_radius": true, "regen_window": true,
	"throw_void_radius": true, "throw_spin_radius": true,
	"death_mark_radius": true, "pierce_growth": true,
}

## How much of a max-HP multiplier the greed mods may take away. A stack of
## Glass Cannon at -40% is a real cost; five stacks must not be a corpse.
const MIN_HEALTH_FACTOR := 0.15
## The ceiling on stacked crit chance. A crit is also a doubled proc roll, so a
## guaranteed crit would make every chance mod in the pool guaranteed too.
const CRIT_CAP := 0.85
## Base crit multiplier. Power Punch and Ring Of Precision move it; the engine is
## the one place it is applied to damage.
const CRIT_MULTIPLIER := 2.0
## The floor on attack-rate multipliers: a body always gets to swing.
const MIN_ATTACK_SCALE := 0.25
## The floor on the incoming-damage multiplier: no stack of Hard Target or Ring
## Of Defense takes a blow below a quarter of itself.
const MIN_DAMAGE_TAKEN := 0.25
## Wind Up counts the shafts loosed inside this window; Hot Streak dies when a
## shot has not landed for as long.
const WINDOW_SECONDS := 2.0
## How often a landed blow may pay Leech Shot's heal.
const HEAL_ON_HIT_GATE := 1.0
## The share of its damage a ricocheting shaft keeps on each hop: Ricochet's own
## row says 70%, and this is the one place that number lives.
const HOP_SCALE := 0.7

var run_seed := 0
var peer_id := 1
var stacks: Dictionary = {}
var rng := RandomNumberGenerator.new()
var events := 0
## Seconds since the run began, advanced by `advance`. The engine has no node, so
## its caller is the clock.
var clock := 0.0
var _shot_times: Array[float] = []
var streak := 0
var _last_hit_at := -100.0
var _last_heal_at := -100.0
var _stats: Dictionary = {}
var _dirty := true


func _init(seed_value: int = 0, owner_peer: int = 1) -> void:
	run_seed = seed_value
	peer_id = maxi(1, owner_peer)
	# Two bodies on one seed must not roll identical sequences: a little death
	# per body would hand a four-stack party the same procs on the same frame.
	rng.seed = int(seed_value) * 31 + peer_id * 7919 + 104729


# --- stacks ---------------------------------------------------------------

func add_mod(mod_id: String, count: int = 1) -> bool:
	if not Mods.has(mod_id) or count <= 0:
		return false
	var cap := Mods.max_stacks(mod_id)
	var have := int(stacks.get(mod_id, 0))
	if have >= cap:
		return false
	stacks[mod_id] = mini(cap, have + count)
	_dirty = true
	return true


func stacks_of(mod_id: String) -> int:
	return int(stacks.get(mod_id, 0))


func total_stacks() -> int:
	var sum := 0
	for id in stacks:
		sum += int(stacks[id])
	return sum


func has_flag(flag: String) -> bool:
	for id in stacks:
		if int(stacks[id]) <= 0:
			continue
		var flags: Dictionary = Mods.get_mod(id).get("flags", {})
		if bool(flags.get(flag, false)):
			return true
	return false


func mod_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in stacks:
		if int(stacks[id]) <= 0:
			continue
		out.append({"id": str(id), "stacks": int(stacks[id]),
			"name": Mods.name_of(str(id)), "rarity": Mods.rarity_of(str(id)),
			"family": Mods.family_of(str(id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := Mods.FAMILIES.find(str(a.family))
		var right := Mods.FAMILIES.find(str(b.family))
		if left != right:
			return left < right
		return str(a.id) < str(b.id))
	return out


## The one aggregate every accessor reads. Recomputed when a stack changes, not
## per shot.
func stats() -> Dictionary:
	if not _dirty:
		return _stats
	_dirty = false
	var out := {
		"damage_mult": 0.0, "attack_mult": 0.0, "knockback_mult": 0.0,
		"proc_coeff_mult": 0.0, "currency_mult": 0.0, "max_hp_flat": 0.0,
		"max_hp_mult": 0.0, "crit_chance": 0.0, "crit_mult_flat": 0.0,
		"heal_on_kill": 0.0, "heal_on_clear": 0.0, "heal_on_hit": 0.0,
		"melee_lifesteal": 0.0, "melee_damage_mult": 0.0,
		"melee_attack_mult": 0.0, "melee_reach": 0.0, "melee_delay": 0.0,
		"split_shots": 0.0, "pierce": 0.0, "ricochet": 0.0, "homing": 0.0,
		"wave_damage": 0.0, "standing_drain": 0.0, "enemy_speed_mult": 0.0,
		"enemy_damage_mult": 0.0, "enemy_count_mult": 0.0,
		"enemy_health_mult": 0.0, "damage_taken_mult": 0.0,
		"flat_damage": 0.0, "shot_size": 0.0, "spread_add": 0.0,
		"projectile_speed_mult": 0.0, "drop_mult": 0.0,
		"splash_frac": 0.0, "splash_radius": 2.5, "shot_aura_damage": 0.0,
		"shot_aura_duration": 3.0, "shot_aura_radius": 2.5, "aura_damage": 0.0,
		"aura_radius": 3.5, "mega_crit_mult": 3.0, "crit_burst": 0.0,
		"crit_burst_radius": 2.5, "shock_on_hurt": 0.0, "shock_radius": 4.0,
		"explode_on_kill": 0.0, "explode_radius": 3.0, "gold_on_hit": 0.0,
		"gold_on_hit_taken": 0.0, "luck": 0.0, "shop_offers": 0.0,
		"shop_discount": 0.0, "chest_mods": 0.0, "chest_offers": 0.0,
		"keep_offer": 0.0, "extra_chest_kills": 0.0, "extra_chest_islands": 0.0,
		"levelup_per_island": 0.0, "regen_hp_per_s": 0.0, "regen_window": 60.0,
		"move_mult": 0.0, "roll_distance": 0.0, "roll_speed": 0.0,
		"roll_charges": 0.0, "roll_regen": 0.0,
		"step_distance": 0.0, "step_speed": 0.0, "step_recovery": 0.0,
		"slide_speed": 0.0,
		"slide_duration": 0.0, "damage_high_hp_mult": 0.0,
		"damage_planted_mult": 0.0, "damage_close_mult": 0.0,
		"damage_far_mult": 0.0, "close_range": 6.0, "far_range": 12.0,
		"damage_per_hp": 0.0, "damage_per_gold": 0.0, "damage_per_kill": 0.0,
		"damage_per_island": 0.0, "damage_per_stack": 0.0, "damage_per_mark": 0.0,
		"damage_on_kill": 0.0, "attack_on_kill": 0.0, "attack_per_island": 0.0,
		"windup_per_shot": 0.0, "windup_cap": 15.0, "streak_per_hit": 0.0,
		"streak_cap": 12.0, "pierce_growth": 0.15,
	}
	# Chance stacks are counted first, then curved once. Ten copies of two
	# different chance mods still land on the same cap for their own key.
	var chance_stacks := {}
	for mod_id in stacks:
		var count := int(stacks[mod_id])
		if count <= 0:
			continue
		var row: Dictionary = Mods.get_mod(str(mod_id))
		var row_stats: Dictionary = row.get("stats", {})
		for key in row_stats:
			var name := str(key)
			var value := float(row_stats[key])
			if HYPERBOLIC.has(name):
				chance_stacks[name] = float(chance_stacks.get(name, 0.0)) + count
			elif name == "wave_damage":
				# Crescent Wave pays its authored share on the first stack and
				# widens by its own step on every one after that.
				var step := float(row_stats.get("wave_step", 0.0))
				out["wave_damage"] = value + step * float(maxi(0, count - 1))
			elif name == "wave_step":
				pass
			elif MAX_KEYS.has(name):
				out[name] = maxf(float(out.get(name, 0.0)), value)
			else:
				out[name] = float(out.get(name, 0.0)) + value * float(count)
	for key in chance_stacks:
		var curve: Dictionary = HYPERBOLIC[key]
		var n := float(chance_stacks[key])
		var cap := float(curve.cap)
		var half := maxf(float(curve.half), 0.001)
		out[key] = cap * n / (n + half)
	out["crit_chance"] = clampf(float(out["crit_chance"]), 0.0, CRIT_CAP)
	# Slow Cut hands a slice of its own damage to the clock instead of the blade.
	# The share is what that row contributes to the hand's multiplier, so the
	# contact pays the rest and the wound pays this.
	var deferred := 0.0
	for mod_id in stacks:
		var row: Dictionary = Mods.get_mod(str(mod_id))
		var row_stats: Dictionary = row.get("stats", {})
		if float(row_stats.get("melee_delay", 0.0)) > 0.0:
			deferred += float(row_stats.get("melee_damage_mult", 0.0)) * float(stacks[mod_id])
	var hand_total := 1.0 + float(out["melee_damage_mult"])
	out["melee_delay_share"] = clampf(deferred / maxf(hand_total, 0.001), 0.0, 0.95)
	_stats = out
	return _stats


func stat(key: String) -> float:
	return float(stats().get(key, 0.0))


## A carried row's `tags` decides whose abilities it upgrades. A row tagged
## `any` reaches every family; `melee` reaches the blade, two-hand, dagger,
## shield and bare-hand families; `ranged` reaches bow and staff; a weapon tag
## reaches only itself. Rows with no tags (the original shot/hand/perk/relic
## pool) are global and are not part of this answer.
static func row_matches(family: String, row: Dictionary) -> bool:
	var tags := []
	var raw: Variant = row.get("tags", [])
	if raw is Array:
		tags = raw
	if tags.is_empty():
		return false
	if tags.has("any") or tags.has(family):
		return true
	if tags.has("ranged") and family in ["bow", "staff"]:
		return true
	if tags.has("melee") and family in ["sword", "two_hand", "dagger",
			"shield", "unarmed"]:
		return true
	return false


## The same aggregate as `stat`, filtered to the rows that name this ability
## family. Chance keys ride the same hyperbolic curve; a shape key takes its
## largest value; everything else sums per stack.
func stat_for(family: String, key: String) -> float:
	var total := 0.0
	var chance_stacks := 0.0
	var largest := 0.0
	var found := false
	for mod_id in stacks:
		var count := int(stacks[mod_id])
		if count <= 0:
			continue
		var row: Dictionary = Mods.get_mod(str(mod_id))
		if not row_matches(family, row):
			continue
		var row_stats: Dictionary = row.get("stats", {})
		if not row_stats.has(key):
			continue
		found = true
		var value := float(row_stats[key])
		if HYPERBOLIC.has(key):
			chance_stacks += float(count)
		elif MAX_KEYS.has(key):
			largest = maxf(largest, value)
		else:
			total += value * float(count)
	if HYPERBOLIC.has(key):
		var curve: Dictionary = HYPERBOLIC[key]
		var n := float(chance_stacks)
		var cap := float(curve.cap)
		var half := maxf(float(curve.half), 0.001)
		return cap * n / (n + half)
	return largest if MAX_KEYS.has(key) and found else total


## One tagged chance. The per-stack rows (shield block, bleed, whirlwind, extra
## arrow) add linearly to a cap; the rest ride their hyperbolic curve. A crit
## doubles the chance before the roll.
func chance_for(family: String, key: String, crit: bool = false) -> bool:
	var chance := stat_for(family, key)
	match key:
		"passive_block_chance": chance = minf(0.75, chance)
		"bleed_chance": chance = minf(0.50, chance)
		"whirlwind_chance": chance = minf(0.35, chance)
		"extra_arrow_chance": chance = minf(0.55, chance)
	if crit:
		chance = minf(1.0, chance * 2.0)
	if chance <= 0.0:
		return false
	events += 1
	return rng.randf() < chance


## How many kinds of mark this body's rows can apply. The marks themselves land
## in phase 5; the count is what a HUD or a row's own scale reads.
func mark_kinds() -> int:
	var kinds := {}
	for id in stacks:
		if int(stacks[id]) <= 0:
			continue
		for key in (Mods.get_mod(str(id)).get("stats", {})):
			var name := str(key)
			if name.begins_with("mark_stacks."):
				kinds[name.get_slice(".", 1).get_slice(".", 0)] = true
	return kinds.size()


# --- the numbers the controllers read -------------------------------------

## Weapon damage as a multiplier over the profile's own base. Heavy Caliber,
## Glass Cannon, Cursed Arsenal and any future `damage_mult` stack additively.
func damage_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("damage_mult"))


## The hand's own multiplier, which the bow never reads: Sharp Claws and Iron
## Claws buy the hatchet, not the shot.
func melee_damage_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("melee_damage_mult"))


func attack_scale() -> float:
	return maxf(MIN_ATTACK_SCALE, 1.0 + stat("attack_mult"))


## The rate a body's *hand* swings at: the global rate plus the hand's own, so
## Blender never speeds the bow up.
func melee_attack_scale() -> float:
	return maxf(MIN_ATTACK_SCALE,
		1.0 + stat("attack_mult") + stat("melee_attack_mult"))


func knockback_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("knockback_mult"))


func proc_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("proc_coeff_mult"))


func move_scale() -> float:
	return maxf(0.2, 1.0 + stat("move_mult"))


## Health after the plate and the greed. Floored so a stack of Glass Cannon can
## put a body on its last legs but never on the ground.
func health_factor() -> float:
	var factor := 1.0 + stat("max_hp_mult")
	return maxf(MIN_HEALTH_FACTOR, factor)


## The incoming-damage multiplier, floored: no defensive stack takes a blow below
## a quarter of itself.
func damage_taken_multiplier() -> float:
	return maxf(MIN_DAMAGE_TAKEN, 1.0 + stat("damage_taken_mult"))


func crit_multiplier() -> float:
	return maxf(1.0, CRIT_MULTIPLIER + stat("crit_mult_flat"))


func crit_roll() -> bool:
	events += 1
	return rng.randf() < stat("crit_chance")


## A crit, and whether it went mega. One roll each, in a fixed order.
func roll_crit() -> Dictionary:
	var crit := crit_roll()
	var mult := crit_multiplier()
	if crit and chance_roll("mega_crit_chance"):
		mult = maxf(mult, stat("mega_crit_mult"))
	return {"crit": crit, "mult": mult if crit else 1.0}


## One hyperbolic chance roll. `crit` doubles the proc chance, which is the
## engine's own reading of Crit Sharpshooter.
func chance_roll(key: String, crit: bool = false) -> bool:
	var chance := stat(key)
	if crit:
		chance = minf(1.0, chance * 2.0)
	if chance <= 0.0:
		return false
	events += 1
	return rng.randf() < chance


func dodge_roll() -> bool:
	return chance_roll("dodge_chance")


func luck() -> int:
	return maxi(0, int(round(stat("luck"))))


## The share a ricochet keeps. The director hands it to the arrow so a run's hop
## pays Ricochet's own figure and a campaign shot keeps the world's.
func hop_scale() -> float:
	return HOP_SCALE


# --- the clock ------------------------------------------------------------

## Called every physics frame by the body's runtime. Wind Up counts the shafts
## inside its window, and a shot that has not landed in `WINDOW_SECONDS` takes the
## streak with it - the one miss this engine can see.
func advance(delta: float) -> void:
	clock += maxf(0.0, delta)
	while not _shot_times.is_empty() and clock - float(_shot_times[0]) > WINDOW_SECONDS:
		_shot_times.pop_front()
	if streak > 0 and clock - _last_hit_at > WINDOW_SECONDS:
		streak = 0


## The wind-up bonus as it stands: per-shaft, capped at the row's own ceiling.
func windup_multiplier() -> float:
	var per := stat("windup_per_shot")
	if per <= 0.0:
		return 1.0
	var shots := mini(_shot_times.size(), int(round(stat("windup_cap"))))
	return 1.0 + per * float(shots)


## Hot Streak's bonus as it stands, wiped by a miss or by the clock.
func streak_multiplier() -> float:
	var per := stat("streak_per_hit")
	if per <= 0.0:
		return 1.0
	return 1.0 + per * float(mini(streak, int(round(stat("streak_cap")))))


func note_hit() -> void:
	streak += 1
	_last_hit_at = clock


func note_miss() -> void:
	streak = 0


# --- events ----------------------------------------------------------------

## A shot leaving the string. Answers the firing controllers with the whole shot
## plan: how many projectiles, how far off-axis, how big, how fast, and what each
## one carries.
func on_weapon_fire(profile: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	_shot_times.append(clock)
	while _shot_times.size() > maxi(1, int(round(stat("windup_cap")))):
		_shot_times.pop_front()
	var rolled := roll_crit()
	var crit := bool(rolled.crit)
	var plan := {
		"shots": 1 + int(round(stat("split_shots"))),
		"scatter": false,
		"spread": float(profile.get("spread", 0.0)) + stat("spread_add"),
		"size": maxf(0.1, 1.0 + stat("shot_size")),
		"speed": maxf(0.2, 1.0 + stat("projectile_speed_mult")),
		"drop": maxf(0.0, 1.0 + stat("drop_mult")),
		"damage_scale": damage_multiplier() * windup_multiplier() * streak_multiplier(),
		# Flat damage is added to each shaft's number after the multipliers rather
		# than folded into them: Broadhead's point is a point, not a share.
		"damage_add": stat("flat_damage"),
		"crit": crit,
		"crit_mult": float(rolled.mult),
		"pierce": int(profile.get("pierce", 0)) + int(round(stat("pierce"))),
		"ricochet": int(profile.get("ricochet", 0)) + int(round(stat("ricochet"))),
		"homing": float(profile.get("homing", 0.0)) + stat("homing") * 18.0,
		"knockback": float(profile.get("knockback", 1.0)) * knockback_multiplier(),
		"gore": float(profile.get("gore", 1.0)),
		"proc": float(profile.get("proc", 1.0)) * proc_multiplier(),
	}
	# Scatter: a chance to turn one trigger into a burst of three. It rides on
	# top of the split count rather than replacing it.
	if chance_roll("scatter_chance", crit):
		plan["scatter"] = true
		plan["shots"] = int(plan["shots"]) + 2
		# Scatter pays 60% a bolt, exactly as its row says; Split Shot's own fan
		# is a separate budget and keeps the first arrow whole.
		plan["damage_scale"] = float(plan["damage_scale"]) * 0.6
	plan["origin"] = origin
	plan["direction"] = direction
	return plan


## A committed cut. Answers the melee-swing effects (the crescent) and the crit
## the blow carries, and lets the caller scale the swing's damage.
func on_melee_swing(profile: Dictionary, forward: Vector3) -> Dictionary:
	var rolled := roll_crit()
	var crit := bool(rolled.crit)
	var requests: Array = []
	if stat("wave_damage") > 0.0:
		requests.append({
			"kind": "shockwave", "forward": forward, "mod": "melee_shockwave",
			"damage_scale": stat("wave_damage"),
			"pierce": 1 + int(round(stat("pierce"))),
			"crit": crit, "crit_mult": float(rolled.mult),
			"proc": float(profile.get("proc", 1.0)) * proc_multiplier(),
		})
	return {
		"crit": crit,
		"crit_mult": float(rolled.mult),
		# A crit is a bigger blow, exactly as it is for a shot: the controller
		# scales the cut here and carries the flag on to the proc roll. The slice
		# Slow Cut deferred is taken out of the contact and paid in `on_hit`.
		"damage_scale": melee_damage_multiplier()
			* maxf(0.0, 1.0 - stat("melee_delay_share")) * float(rolled.mult),
		"knockback": knockback_multiplier(),
		"reach": stat("melee_reach"),
		"requests": requests,
	}


## A landed blow. `ctx`:
## `{kind, target, position, damage, crit, proc, profile, hand, is_melee}`.
## Answers the trigger requests that blow earned.
func on_hit(ctx: Dictionary) -> Array:
	var out: Array = []
	var target = ctx.get("target")
	if target == null or not is_instance_valid(target):
		return out
	var crit := bool(ctx.get("crit", false))
	var damage := float(ctx.get("damage", 0.0))
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	var proc := maxf(0.0, float(ctx.get("proc", 1.0)))
	note_hit()
	if stat("arc_chance") > 0.0 and chance_roll("arc_chance", crit):
		out.append({"kind": "arc", "target": target, "position": position,
			"mod": "dagger_arc",
			"damage": damage * 1.4, "proc": proc * 0.5, "crit": false})
	if stat("nova_chance") > 0.0 and chance_roll("nova_chance", crit):
		out.append({"kind": "nova", "target": target, "position": position,
			"mod": "arrow_nova",
			"damage": damage * 0.55, "proc": proc * 0.4, "count": 8})
	if stat("chain_chance") > 0.0 and chance_roll("chain_chance", crit):
		out.append({"kind": "chain", "target": target, "position": position,
			"mod": "chain_lightning",
			"damage": damage * 0.4, "proc": proc * 0.4,
			"targets": 3 + stacks_of("chain_lightning")})
	if stat("bomb_chance") > 0.0 and chance_roll("bomb_chance", crit):
		out.append({"kind": "bomb", "target": target, "position": position,
			"mod": "sticky_charge",
			"damage": damage * 1.2, "proc": proc * 0.5, "radius": 3.0,
			"delay": 1.2})
	if stat("mace_chance") > 0.0 and chance_roll("mace_chance", crit):
		out.append({"kind": "blast", "target": target, "position": position,
			"mod": "mace_shot",
			"damage": damage * 1.2, "radius": 1.8, "stagger": 0.5,
			"proc": proc * 0.5})
	if stat("spike_chance") > 0.0 and chance_roll("spike_chance", crit):
		out.append({"kind": "spike", "target": target, "position": position,
			"mod": "spike_strike",
			"damage": damage * 0.7, "radius": 3.0, "proc": proc * 0.4})
	if stat("double_chance") > 0.0 and chance_roll("double_chance", crit):
		# The whole blow again, procs and all - the one effect that spends its
		# own budget rather than a fraction of it. It never rolls another proc:
		# the fan-out is one deep by construction.
		out.append({"kind": "double", "target": target, "position": position,
			"mod": "double_tap",
			"damage": damage, "crit": crit, "proc": 0.0})
	if stat("splash_frac") > 0.0:
		out.append({"kind": "splash", "target": target, "position": position,
			"mod": "splash_shot",
			"damage": damage * stat("splash_frac"),
			"radius": stat("splash_radius"), "proc": 0.0})
	if crit and stat("crit_burst") > 0.0:
		out.append({"kind": "splash", "target": target, "position": position,
			"mod": "crit_blast",
			"damage": damage * stat("crit_burst"),
			"radius": stat("crit_burst_radius"), "proc": 0.0})
	if stat("shot_aura_damage") > 0.0 and not bool(ctx.get("is_melee", false)):
		out.append({"kind": "zone", "position": position, "mod": "aura_shot",
			"damage": damage * stat("shot_aura_damage"),
			"radius": stat("shot_aura_radius"),
			"duration": stat("shot_aura_duration"), "target": target})
	if stat("gold_on_hit") > 0.0:
		out.append({"kind": "currency", "amount": stat("gold_on_hit"),
			"mod": "money_shot"})
	if stat("heal_on_hit") > 0.0 and clock - _last_heal_at >= HEAL_ON_HIT_GATE:
		_last_heal_at = clock
		out.append({"kind": "heal", "amount": stat("heal_on_hit"),
			"mod": "health_shot", "source": "shot"})
	if bool(ctx.get("is_melee", false)) and stat("melee_lifesteal") > 0.0:
		out.append({"kind": "heal", "amount": damage * stat("melee_lifesteal"),
			"mod": "bloodthirst", "source": "melee"})
	if bool(ctx.get("is_melee", false)) and stat("melee_delay_share") > 0.0:
		# Slow Cut's share: the contact paid the rest, and this is paid over the
		# row's own delayed clock.
		var share := stat("melee_delay_share")
		out.append({"kind": "wound", "target": target,
			"mod": "time_claws",
			"damage": damage * share / maxf(0.05, 1.0 - share),
			"delay": stat("melee_delay")})
	if bool(ctx.get("is_melee", false)):
		var family := str(ctx.get("family", ""))
		if not family.is_empty():
			if chance_for(family, "bleed_chance", crit):
				out.append({"kind": "bleed", "target": target,
					"position": position, "damage": damage * 0.2,
					"seconds": 3.0})
			if chance_for(family, "whirlwind_chance", crit):
				out.append({"kind": "whirlwind", "position": position,
					"damage": damage * 0.8, "radius": 2.5, "target": target})
	return out


## A body this blow put down.
func on_kill(ctx: Dictionary) -> Array:
	var out: Array = []
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	var damage := float(ctx.get("damage", 0.0))
	var proc := maxf(0.0, float(ctx.get("proc", 1.0)))
	var gibbed := bool(ctx.get("gibbed", false))
	var harvest: float = float(stats().get("heal_on_kill", 0.0))
	if harvest > 0.0:
		# Grim Harvest restores `1 + stack`: one point for the kill itself and
		# one per copy of the mod, doubled when the body came apart.
		out.append({"kind": "heal", "amount": (1.0 + harvest) * (2.0 if gibbed else 1.0),
			"mod": "grim_harvest", "source": "harvest"})
	if stat("nova_chance") > 0.0:
		# A kill is a guaranteed nova, which is the whole appeal of the mod.
		out.append({"kind": "nova", "target": ctx.get("target"), "position": position,
			"mod": "arrow_nova",
			"damage": damage * 0.55, "proc": proc * 0.4, "count": 8})
	if stat("explode_on_kill") > 0.0:
		var pool := 0.0
		var target = ctx.get("target")
		if target != null and is_instance_valid(target):
			pool = float(target.get("max_health")) if target.get("max_health") != null else 0.0
		out.append({"kind": "blast", "target": target, "position": position,
			"mod": "exploding_enemies",
			"damage": pool * stat("explode_on_kill"),
			"radius": stat("explode_radius"), "proc": 0.0})
	if stat("drop_chance") > 0.0 and chance_roll("drop_chance"):
		out.append({"kind": "drop_card", "position": position,
			"mod": "rare_treasure"})
	return out


## A blow landing on this body. Answers the dodge, the incoming multiplier, and
## the ring a Shockwave sends back.
func on_player_damaged(amount: float, _source_id: int) -> Dictionary:
	var dodged := dodge_roll()
	var taken := amount * damage_taken_multiplier()
	var requests: Array = []
	if not dodged and stat("shock_on_hurt") > 0.0:
		requests.append({"kind": "blast", "target": null, "position": Vector3.ZERO,
			"mod": "shockwave",
			"damage": taken * stat("shock_on_hurt"),
			"radius": stat("shock_radius"), "proc": 0.0, "from_body": true})
	if stat("gold_on_hit_taken") > 0.0 and not dodged:
		requests.append({"kind": "currency", "amount": -stat("gold_on_hit_taken"),
			"mod": "bribe"})
	return {"dodged": dodged, "damage": taken, "requests": requests}


## An island cleared. Answers the per-clear heals and the upgrade that pays a
## stack to two rows every island.
func on_stage_clear(max_health: float, allow_heal: bool = true) -> Array:
	var out: Array = []
	if stat("heal_on_clear") > 0.0 and allow_heal:
		out.append({"kind": "heal", "amount": max_health * stat("heal_on_clear"),
			"mod": "field_dressing", "source": "clear"})
	if stat("levelup_per_island") > 0.0:
		out.append({"kind": "level_up", "mod": "level_up",
			"count": int(round(stat("levelup_per_island")))})
	return out
