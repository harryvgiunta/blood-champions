extends RefCounted
## The blood clone's brain on a dial: six tiers of *how* a clone fights, not how
## much of it there is.
##
## A clone's body is the run's: `ranger_clone` issues the kit by depth block, the
## gate's `life` sets the pool, and the rig, reach and guard are a ranger's. What
## a tier changes is every clock and every instinct the brain spends *inside* that
## body - how long it waits between swings, how often it answers a wind-up with
## its guard or a sidestep, how late it notices one, how fast it turns onto a
## body that has walked around it, how hard it crowds, how far it sees and how
## well it leads a moving target - plus what one of its landed blows is worth.
##
## The knobs, and where each one lands in `ranger_clone`:
##
##   swing_gap     seconds between committed melee swings (`_blade_step`). The
##                 telegraph and the strike are the rig's own clip and stay as
##                 authored: this is the wait *between* blows, so a slower clone
##                 is still a readable duellist, just a rarer one.
##   blow          x on what a landed blow takes off, on top of the scene's own
##                 `damage_scale` (`_melee_damage`, the bow's release). The kit
##                 is still the damage: this only weights the hand that holds it.
##   guard_answer  share of telegraphed blows answered with the guard, rolled once
##                 per wind-up and never again while that swing is in the air.
##   reaction      seconds of an attacker's wind-up before the clone may answer it
##                 at all - its guard or its step. A clone that is slower to
##                 notice simply eats the blows whose telegraph is shorter than
##                 this, which is what a heavy hand does to a slow opponent.
##   step_gap      seconds between sidelong steps, once one is spent.
##   step_chance   share of the threats it does answer that it answers by moving
##                 its feet rather than standing its ground.
##   speed         x on every pace it keeps: the closing run, the circling walk,
##                 the shot lane and the patrol (`_pace`).
##   turn          x on how fast the body turns onto the direction it meant to
##                 walk. A slow turn is a slow guard: the blade arrives before the
##                 facing does.
##   sight         x on `aggro_range`. It never touches the scene's own leash.
##   lead          share of a moving target's travel the bow leads. A shallow
##                 clone drops its arrows where the body *was*.
##   casts         whether the body performs an item skill at all. Every clone
##                 from `Medium` up rolls one when its kit is issued (see
##                 `ranger_clone._roll_ability`); `Very Easy` and `Easy` never do,
##                 so the shallow half of the pit is a plain duellist's fight.
##   cast_gap      seconds between performances, on top of the skill's own
##                 cooldown. The skill is the one the clone rolled, so this is how
##                 *willing* the brain is, not how often the piece can fire.
##
## `Hard` is the authored body and the one the pit shipped with, except for
## `swing_gap`, which is a quarter longer than the old fixed 0.85 s: four bodies
## on that clock were the hardest melee in the game, and the owner asked for the
## pit to be a duellist's fight rather than a blender's.

## Every tier, shallowest first. Its index is the tier's number and nothing else
## keys off it, so a tier may be re-tuned or renamed without touching a caller.
const TIERS := [
	{
		"name": "Very Easy",
		"swing_gap": 1.90, "blow": 0.55, "guard_answer": 0.04, "reaction": 0.45,
		"step_gap": 3.20, "step_chance": 0.20, "speed": 0.82, "turn": 0.55,
		"sight": 0.70, "lead": 0.20, "casts": false, "cast_gap": 0.0,
	},
	{
		"name": "Easy",
		"swing_gap": 1.55, "blow": 0.72, "guard_answer": 0.08, "reaction": 0.30,
		"step_gap": 2.60, "step_chance": 0.45, "speed": 0.90, "turn": 0.70,
		"sight": 0.85, "lead": 0.32, "casts": false, "cast_gap": 0.0,
	},
	{
		"name": "Medium",
		"swing_gap": 1.28, "blow": 0.86, "guard_answer": 0.14, "reaction": 0.18,
		"step_gap": 2.00, "step_chance": 0.72, "speed": 0.95, "turn": 0.85,
		"sight": 0.92, "lead": 0.44, "casts": true, "cast_gap": 11.0,
	},
	{
		"name": "Hard",
		"swing_gap": 1.05, "blow": 1.00, "guard_answer": 0.20, "reaction": 0.10,
		"step_gap": 1.60, "step_chance": 1.00, "speed": 1.00, "turn": 1.00,
		"sight": 1.00, "lead": 0.55, "casts": true, "cast_gap": 8.0,
	},
	{
		"name": "Very Hard",
		"swing_gap": 0.86, "blow": 1.12, "guard_answer": 0.30, "reaction": 0.05,
		"step_gap": 1.25, "step_chance": 1.00, "speed": 1.06, "turn": 1.15,
		"sight": 1.10, "lead": 0.68, "casts": true, "cast_gap": 6.0,
	},
	{
		"name": "Fuck you",
		"swing_gap": 0.68, "blow": 1.30, "guard_answer": 0.45, "reaction": 0.00,
		"step_gap": 0.90, "step_chance": 1.00, "speed": 1.12, "turn": 1.30,
		"sight": 1.25, "lead": 0.85, "casts": true, "cast_gap": 4.5,
	},
]

## The tier every clone is born on unless its spawner or the session says
## otherwise: `Hard`, the body the owner named as the pit's current fight.
const DEFAULT_TIER := 3

## The session's tier. A clone takes it at `configure` unless its spawner has
## already written `ai_tier`; `set_tier` retunes every body spawned afterwards,
## which is what a menu, a cheat line or a lab would drive.
static var current_tier := DEFAULT_TIER


## `tier` forced into the table. A negative or absurd index is `DEFAULT_TIER`,
## never a crash: a save from a build with a different ladder has to land
## somewhere sane.
static func clamp_tier(tier: int) -> int:
	if tier < 0 or tier >= TIERS.size():
		return DEFAULT_TIER
	return tier


## The knobs of one tier, read-only (a `const` dictionary is Godot's own). Every
## key the brain reads is always present: `ranger_clone` does not defend against a
## hole in the table, so a tier is edited by changing a number, never by adding or
## dropping a key.
static func profile(tier: int) -> Dictionary:
	return TIERS[clamp_tier(tier)]


static func name_of(tier: int) -> String:
	return str(profile(tier)["name"])


## Every tier by name, shallowest first, for a menu or a lab to list.
static func labels() -> Array[String]:
	var out: Array[String] = []
	for tier in TIERS:
		out.append(str(tier["name"]))
	return out


## Put the session on `tier`. Returns the tier in force, which is the one asked
## for or `DEFAULT_TIER` when the ask was outside the ladder.
static func set_tier(tier: int) -> int:
	current_tier = clamp_tier(tier)
	return current_tier


## Step to the next tier in the ladder and round again, which is what a single
## key bound to "harder" would call.
static func cycle_tier() -> int:
	return set_tier((clamp_tier(current_tier) + 1) % TIERS.size())
