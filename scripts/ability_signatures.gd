extends RefCounted
## One visual signature per combat skill, drawn on the beat that performs it.
##
## `AbilityRules` authors an ability as data and `AbilityRunner` fires its named
## beats (`shot`, `arc`, `ring`, `cast`, `ward`, …). `AbilityFx` owns the shared
## vocabulary - a crescent, a wake, a burst - and this file is the per-skill
## *sentence* built from it: which shape, at what reach, in whose colour, so a
## long piercing arrow does not read as the same golden crescent as a wide sweep.
##
## The split matters for three reasons:
##
##   * The skill ids are the only place a signature is chosen, so a new skill is
##     one row in `SIGNED` and one branch in `cue`, and nothing else. A skill with
##     no signature is named by `missing_signatures()` and asserted by
##     `tests/ability_fx_regression.gd`, so an ability can never silently ship
##     with no art.
##   * A cue is presentation. Nothing here reads health, spends stamina, spawns a
##     damaging node or touches the rig's state; the owning scene has already
##     resolved the blow by the time it calls `cue`. A peer that misses a
##     signature loses a flash and nothing else.
##   * Every beat is derived from the definition the scene is already running and
##     the direction it already solved, so host and guest draw the same line.
##
## Colours are the family's own, never the skill's: steel for a blade, bow-light
## for an arrow, ember for fire, bone for a staff's dead channel, gold for a
## shield's face, stone for the cord's ward. Two skills in one family may share a
## hue and still read apart, because the shape a signature draws is the skill's
## own - a lance is a line, a bloom is a flower, a flurry is a stutter.
##
## Two rules every helper here obeys, because breaking either one has bitten this
## file before:
##
##   * A node is placed with a *global* position. The FX parent is the world, and
##     the world's dressing nodes carry transforms, so a local `position` would
##     bend a crescent into the island's frame.
##   * One tween owns one property. The rise and the fade of a material's alpha
##     are two sequential steps of `_fade`, never two parallel writers, because
##     the second would overwrite the first and the effect would never appear.

const AbilityFx = preload("res://scripts/ability_fx.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Vfx = preload("res://scripts/vfx_library.gd")

const STEEL := Color("e9f2ff")
const STEEL_DIM := Color("8fb4d8")
const TEAL := Color("72cbb6")
const TEAL_DIM := Color("42867e")
const GOLD := Color("e9bf76")
const GOLD_DIM := Color("b89254")
const CREAM := Color("f6f0e1")
const EMBER := Color("ff8a3c")
const EMBER_HOT := Color("ffd9a0")
const BONE := Color("bfe6c8")
const BONE_CORE := Color("e8fff1")
const ASH := Color("a49c92")
const DUST := Color("c9b18a")
const BLOOD := Color("e8503c")
const STONE := Color("b9b09b")

## Every skill id this file dresses. The regression walks `AbilityRules` against
## it, so the list is a contract rather than a note.
const SIGNED := [
	"charge", "dash", "barrage", "triple_volley", "piercing_shot", "snap_shot",
	"rain_of_ash", "skewer", "double_slash", "quick_cut", "butchers_cut",
	"gut_hook", "knife_work", "three_strike", "heavy_swing", "wide_sweep",
	"ground_breaker", "executioner", "lunge_thrust", "spin_slash", "backstab",
	"quick_stab", "shield_shove", "shield_bash", "shield_charge", "shield_slam",
	"rebuke", "fireball", "cinder_lance", "fire_ray", "bone_spear", "grave_bloom",
	"ember_ward", "energy_shield", "focus", "stone_skin",
	# The two consumables are not combat skills and never emit a cue; they are in
	# the list so the one table names every row of the bar the player can press.
	"bandage", "healing_potion",
]


static func signature_ids() -> Array:
	return SIGNED.duplicate()


static func has_signature(id: String) -> bool:
	return SIGNED.has(id)


## The combat abilities that have no signature yet, in catalog order. Always empty
## in a shipped build; the regression fails on a non-empty answer.
static func missing_signatures() -> Array[String]:
	var out: Array[String] = []
	for id in AbilityRules.catalog_ids():
		if not has_signature(str(id)):
			out.append(str(id))
	return out


# --- the entry point -------------------------------------------------------

## Draw the beat. `forward` is the flat aim line the scene already solved for the
## hit, so a signature's light lies on the same line as its damage; `aim` is the
## crosshair point when the scene has one (a bloom has to open where the player
## pointed, not at the horizon). `index` is the cue's ordinal: a two-cut skill
## reads which hand is swinging from it and a six-arrow barrage knows which shaft
## just left.
##
## Answers true when a signature drew something, false for an id this file does
## not dress. The caller does not need the answer; the regression does.
static func cue(parent: Node3D, rig, definition: Dictionary, cue_name: String,
		index: int, forward: Vector3, aim: Vector3 = Vector3.INF) -> bool:
	if not is_instance_valid(parent) or not is_instance_valid(rig):
		return false
	var id := str(definition.get("id", ""))
	if not has_signature(id):
		return false
	var effect: Dictionary = definition.get("effect", {})
	var heading := _flat(forward, _heading(rig))
	match id:
		"charge": _charge(parent, rig, cue_name)
		"dash": _dash(parent, rig, cue_name)
		"barrage": _barrage(parent, rig, definition, cue_name, index, heading)
		"triple_volley": _triple_volley(parent, rig, definition, cue_name, heading)
		"piercing_shot": _piercing_shot(parent, rig, definition, cue_name, heading)
		"snap_shot": _snap_shot(parent, rig, definition, cue_name, heading)
		"rain_of_ash": _rain_of_ash(parent, rig, definition, cue_name, index, heading)
		"skewer": _skewer(parent, rig, definition, cue_name, heading)
		"double_slash": _double_slash(parent, rig, cue_name, index, heading, effect)
		"quick_cut": _quick_cut(parent, rig, cue_name, heading, effect)
		"butchers_cut": _butchers_cut(parent, rig, cue_name, heading, effect)
		"gut_hook": _gut_hook(parent, rig, cue_name, heading, effect)
		"knife_work": _knife_work(parent, rig, cue_name, heading, effect)
		"three_strike": _three_strike(parent, rig, cue_name, index, heading, effect)
		"heavy_swing": _heavy_swing(parent, rig, cue_name, heading, effect)
		"wide_sweep": _wide_sweep(parent, rig, cue_name, heading, effect)
		"ground_breaker": _ground_breaker(parent, rig, cue_name, heading, effect)
		"executioner": _executioner(parent, rig, cue_name, heading, effect)
		"lunge_thrust": _lunge_thrust(parent, rig, cue_name, heading, effect)
		"spin_slash": _spin_slash(parent, rig, cue_name, heading, effect)
		"backstab": _backstab(parent, rig, cue_name, heading)
		"quick_stab": _quick_stab(parent, rig, cue_name, heading, effect)
		"shield_shove": _shield_shove(parent, rig, cue_name, heading, effect)
		"shield_bash": _shield_bash(parent, rig, cue_name, heading, effect)
		"shield_charge": _shield_charge(parent, rig, cue_name, index, heading, effect)
		"shield_slam": _shield_slam(parent, rig, cue_name, heading, effect)
		"rebuke": _rebuke(parent, rig, cue_name, heading, effect)
		"fireball": _fireball(parent, rig, cue_name, heading)
		"cinder_lance": _cinder_lance(parent, rig, cue_name, heading)
		"fire_ray": _fire_ray(parent, rig, cue_name, heading)
		"bone_spear": _bone_spear(parent, rig, cue_name, heading)
		"grave_bloom": _grave_bloom(parent, rig, cue_name, heading, aim, effect)
		"ember_ward": _ember_ward(parent, rig, cue_name)
		"energy_shield": _energy_shield(parent, rig, cue_name)
		"focus": _focus(parent, rig, cue_name)
		"stone_skin": _stone_skin(parent, rig, cue_name)
	return true


# --- body and unarmed ------------------------------------------------------

## Charge: the shoulder goes down and the body eats ground. A wedge of teal
## streaks in front of the chest, a footfall of dust every third of a second and
## a low rumble of grit behind - not the dash's clean sprint line, because a
## charge is weight carried forward rather than a step taken.
static func _charge(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "dash":
		return
	var origin := _feet(rig)
	var forward := _heading(rig)
	_streaks(parent, origin + Vector3.UP * 1.05, forward, 4, 2.2, 0.16, TEAL, 0.0,
		0.72)
	_wedge(parent, origin + Vector3.UP * 1.05, forward, 2.6, 0.9, TEAL_DIM, 0.0)
	for beat in 3:
		_puff(parent, origin + forward * (0.2 + 0.55 * float(beat)) +
			Vector3.UP * 0.04, 0.42, DUST, 0.10 * float(beat))
	_light(parent, origin + Vector3.UP * 1.1 + forward * 1.1, TEAL, 1.1, 2.4, 0.5)


## Dash: the cleanest read in the file. A single bright teal line trailing the
## body, three aftershock streaks that lag behind it, a smear left where the body
## was and a flat dust ring at the takeoff. It must never look like the charge:
## one line, no wedge, no footfalls.
static func _dash(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "dash":
		return
	var origin := _feet(rig)
	var forward := _heading(rig)
	_streaks(parent, origin + Vector3.UP * 0.95, forward, 6, 3.0, 0.11, CREAM, 0.0,
		0.62)
	_streaks(parent, origin + Vector3.UP * 0.55 - forward * 0.5, forward, 5, 2.0,
		0.07, TEAL_DIM, 0.05, 0.5)
	_afterimage(parent, rig, forward, TEAL, 3)
	_ring(parent, origin + Vector3.UP * 0.05, 1.15, TEAL_DIM, 0.34, 0.10, 0.0)
	_light(parent, origin + Vector3.UP * 1.0, TEAL, 0.9, 2.6, 0.4)


# --- bow -------------------------------------------------------------------

## Barrage: a staccato. Each cue is one shaft, and the signature puts a nocked
## spark at the string, a short streak down that shaft's own spread line (the
## same `shot_offsets` the arrow used) and, on the first beat, a gold brush of the
## six lines the skill is about to lay. The fan is drawn once; the streaks are
## what make it read as machine fire rather than as a volley.
static func _barrage(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, index: int, forward: Vector3) -> void:
	if cue_name != "shot":
		return
	var origin := _bow(rig)
	var offsets := AbilityFx.shot_offsets(definition, index)
	var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
	_nock(parent, origin, line, CREAM)
	_streak(parent, origin, line, 1.9, 0.13, CREAM, 0.0, 0.22)
	if index == 0:
		for slot in 6:
			var spread := AbilityFx.shot_offsets(definition, slot)
			var brush := AbilityFx.rotate_direction(forward, spread.x, spread.y)
			_streak(parent, origin, brush, 3.4, 0.05, GOLD_DIM, 0.0, 0.26)
		_light(parent, origin, GOLD, 0.9, 2.0, 0.3)


## Triple Fan Volley: one beat, three arrows. A wide gold fan of three crescents
## opens from the bow hand and a flare sits behind the string, so the volley is
## read as a shape rather than counted from three thin streaks.
static func _triple_volley(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, forward: Vector3) -> void:
	if cue_name != "volley":
		return
	var origin := _bow(rig)
	for slot in 3:
		var offsets := AbilityFx.shot_offsets(definition, slot)
		var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
		_nock(parent, origin, line, GOLD)
		_streak(parent, origin, line, 3.6, 0.10, CREAM, 0.0, 0.24)
		_sweep(parent, origin + Vector3.UP * 0.05, line, 2.2, 26.0, GOLD,
			0.02 * float(slot))
	_flare(parent, origin + Vector3.UP * 0.12 - forward * 0.35, GOLD, 0.42)
	_light(parent, origin, GOLD, 1.3, 2.6, 0.35)


## Snap Shot: the cheapest arrow in the wood, so the smallest read. A pale streak
## with a green venom bead riding the head and a single slow drip that falls
## behind the shot - the poison the starter actually lays, drawn as a promise
## rather than a second effect.
static func _snap_shot(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, forward: Vector3) -> void:
	if cue_name != "shot":
		return
	var origin := _bow(rig)
	var offsets := AbilityFx.shot_offsets(definition, 0)
	var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
	_nock(parent, origin, line, CREAM)
	_streak(parent, origin, line, 2.8, 0.11, CREAM, 0.0, 0.26)
	_spark(parent, origin + line * 1.25, 0.10, TEAL, 0.28, 0.0)
	_drip(parent, origin + line * 0.9, TEAL, 0.45, 0.2)


## Piercing Shot: a long, thin, drilled line. An eighteen-metre lance of bow-light
## with three tightening rings threaded on it and speed dashes either side: the
## shot's whole promise is distance, so the art is length and nothing else.
static func _piercing_shot(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, forward: Vector3) -> void:
	if cue_name != "shot":
		return
	var origin := _bow(rig)
	var offsets := AbilityFx.shot_offsets(definition, 0)
	var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
	_nock(parent, origin, line, STEEL)
	_lance(parent, origin, line, 18.0, 0.10, STEEL, CREAM)
	for index in 3:
		_ring_cross(parent, origin + line * (2.2 + 1.9 * float(index)),
			0.42 - 0.07 * float(index), STEEL, 0.10 * float(index), line)
	for side in [-1.0, 1.0]:
		var offset := line.cross(Vector3.UP).normalized() * 0.36 * float(side)
		_streaks(parent, origin + offset, line, 4, 2.4, 0.03, STEEL_DIM, 0.0, 0.3)
	_light(parent, origin, STEEL, 1.4, 3.4, 0.3)


## Rain of Ash: ash and arrow-fall. The first beat raises a grey veil above the
## aim patch - a soft cloud that sinks - and lays a falling ash field over it;
## every one of the eight shafts adds its own high arcing streak, so the skill
## reads as a curtain dropping rather than a fan fired flat.
static func _rain_of_ash(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, index: int, forward: Vector3) -> void:
	if cue_name != "shot":
		return
	var origin := _bow(rig)
	var patch := origin + forward * 6.0
	if index == 0:
		AbilityFx.smoke_puff(parent, patch + Vector3.UP * 2.6, 1.7, false)
		_ash_curtain(parent, patch + Vector3.UP * 3.2, 4.2, ASH, 18)
		_ring(parent, patch, 2.6, ASH, 0.5, 0.12, 0.2)
		_light(parent, patch + Vector3.UP * 1.4, ASH, 1.0, 4.0, 0.6)
	var offsets := AbilityFx.shot_offsets(definition, index)
	var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
	# The shaft is arced: the streak starts high and falls onto the patch, which
	# is why its light is drawn from the launch point rather than from the bow.
	var launch := origin + Vector3.UP * (0.4 + 0.22 * float(index % 4))
	_streak(parent, launch, line, 4.2, 0.06, ASH, 0.0, 0.4)
	_drip(parent, patch + Vector3.UP * (2.2 - 0.24 * float(index)), ASH, 0.7,
		0.10 * float(index))


## Skewer: one shaft that owns the line. Thicker than the piercing shot, wreathed
## in white heat, with a punched-through ring drawn *at* the shaft and a cone of
## sparks where a body would have been - the difference between "far" and
## "through".
static func _skewer(parent: Node3D, rig, definition: Dictionary,
		cue_name: String, forward: Vector3) -> void:
	if cue_name != "shot":
		return
	var origin := _bow(rig)
	var offsets := AbilityFx.shot_offsets(definition, 0)
	var line := AbilityFx.rotate_direction(forward, offsets.x, offsets.y)
	_nock(parent, origin, line, CREAM)
	_lance(parent, origin, line, 14.0, 0.20, CREAM, STEEL)
	_ring_cross(parent, origin + line * 5.2, 0.55, CREAM, 0.06, line)
	_cone(parent, origin + line * 5.2, line, 0.9, 8, STEEL, 0.10)
	_light(parent, origin + line * 3.0, CREAM, 1.6, 4.5, 0.35)


# --- sword and dagger ------------------------------------------------------

## Double Slash: two cuts, two hands. The first beat draws the right crescent, the
## second its mirror, so the pair crosses in front of the body; a bright glint sits
## at the crossing and the real blade ribbon follows each cut.
static func _double_slash(parent: Node3D, rig, cue_name: String, index: int,
		forward: Vector3, effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 1.9))
	var arc := float(effect.get("arc_degrees", 150.0))
	var side := 1.0 if index % 2 == 0 else -1.0
	AbilityFx.slash_arc(parent, origin, forward.rotated(Vector3.UP, 0.18 * side),
		radius, arc, STEEL, 16.0 * side)
	_glint(parent, origin + Vector3.UP * 1.18, forward.rotated(Vector3.UP,
		0.38 * side), radius, 120.0, STEEL, 0.02)
	AbilityFx.blade_trail(parent, rig, 0.24)
	_streak(parent, origin + Vector3.UP * 1.2,
		forward.rotated(Vector3.UP, 0.5 * side), 1.9, 0.05, STEEL_DIM, 0.02, 0.18)
	if index == 1:
		_spark(parent, origin + forward * radius * 0.55 + Vector3.UP * 1.24, 0.26,
			CREAM, 0.22, 0.0)
		_light(parent, origin + forward * 1.0 + Vector3.UP * 1.2, STEEL, 1.0, 2.2,
			0.24)


## Quick Cut: the plainest sentence in the book. One steel crescent, a short glint
## along the blade and a breath of dust at the feet. If this reads as anything
## clever, it is wrong.
static func _quick_cut(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 1.6))
	AbilityFx.slash_arc(parent, origin, forward, reach,
		float(effect.get("arc_degrees", 90.0)), STEEL, 6.0)
	_glint(parent, origin + Vector3.UP * 1.15, forward, reach * 0.95, 110.0, STEEL)
	AbilityFx.blade_trail(parent, rig, 0.18)
	_streak(parent, origin + Vector3.UP * 1.2, forward, 1.4, 0.09, CREAM, 0.0, 0.24)
	_puff(parent, origin + forward * 0.9 + Vector3.UP * 0.05, 0.3, DUST, 0.0)


## Butcher's Cut: the hook. A red-edged crescent that runs long and low, a heavy
## cleaver ghost turning in behind it and an arterial spray off the leading edge -
## the one sword skill in the file whose light is blood rather than steel.
static func _butchers_cut(parent: Node3D, rig, cue_name: String,
		forward: Vector3, effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.2))
	AbilityFx.slash_arc(parent, origin, forward, radius, 120.0, BLOOD, -12.0)
	_glint(parent, origin + Vector3.UP * 1.12, forward, radius, 140.0, BLOOD)
	AbilityFx.blade_trail(parent, rig, 0.26, BLOOD)
	_cleaver(parent, origin + Vector3.UP * 1.3, forward, 1.5, BLOOD, 0.0)
	_spray(parent, origin + forward * radius * 0.62 + Vector3.UP * 1.1, forward,
		0.8, BLOOD, 0.05)
	_light(parent, origin + forward * 1.1 + Vector3.UP * 1.1, BLOOD, 1.1, 2.4, 0.2)


## Gut Hook: an upward scoop. The blade light rises from the floor to the chest
## instead of sweeping across it, a pale ribcage arc flashes where the hook turns,
## and a thin blood spray runs off the turn.
static func _gut_hook(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.3))
	_scoop(parent, origin, forward, radius, BLOOD)
	_glint(parent, origin + Vector3.UP * 1.0, forward, radius * 0.85, 90.0, BLOOD,
		0.02)
	_ribs(parent, origin + forward * 0.9 + Vector3.UP * 1.15, forward, 0.5, BONE)
	AbilityFx.blade_trail(parent, rig, 0.22)
	_spray(parent, origin + forward * 1.0 + Vector3.UP * 1.0, forward, 0.55, BLOOD,
		0.08)
	_light(parent, origin + forward * 0.8 + Vector3.UP * 1.2, BLOOD, 0.9, 2.0, 0.2)


## Knife Work: three throws from the hip. Each cue is one stab, each stab a short
## bright jab offset from the last, with a spark at the point. The stutter - not
## an arc, not a sweep - is what says "three fast stabs" instead of "one cut".
static func _knife_work(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 1.35))
	for beat in 3:
		var sway := (float(beat) - 1.0) * 0.16
		var line := forward.rotated(Vector3.UP, sway)
		_streak(parent, origin + Vector3.UP * (0.9 + 0.22 * float(beat)), line,
			1.1 + 0.12 * float(beat), 0.09, STEEL, 0.055 * float(beat), 0.2)
		_glint(parent, origin + Vector3.UP * (1.0 + 0.1 * float(beat)),
			line, radius * 0.7, 60.0, STEEL, 0.055 * float(beat))
		_spark(parent, origin + line * (radius * 0.8) +
			Vector3.UP * (0.95 + 0.2 * float(beat)), 0.09, CREAM, 0.16,
			0.05 * float(beat))
	AbilityFx.blade_trail(parent, rig, 0.2)


## Three Strike: the necklace's waves. Each cue sweeps the arc its own way - right
## blade, left blade, then both driven in - and the third beat adds a gold ring
## because the finisher is the only one of the three that pays full.
static func _three_strike(parent: Node3D, rig, cue_name: String, index: int,
		forward: Vector3, effect: Dictionary) -> void:
	if cue_name != "wave":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.4))
	var arc := float(effect.get("arc_degrees", 130.0))
	var sides: Array = effect.get("wave_sides", [1.0, -1.0, 0.0])
	var side := float(sides[index]) if index < sides.size() else 1.0
	var tint := GOLD if is_zero_approx(side) else STEEL
	AbilityFx.wave_ripple(parent, origin, forward, radius, arc, side, tint)
	_glint(parent, origin + Vector3.UP * 1.15,
		forward.rotated(Vector3.UP, 0.24 * side), radius * 0.95, 120.0, tint)
	var hands: Array = ["right", "left"] if is_zero_approx(side) else \
		["right" if side > 0.0 else "left"]
	# A rig with no weapons query (a harness, a replica mid-build) simply gets no
	# ribbon: the wave still reads, and no signature may assume the rig's API.
	if rig.has_method("swing_weapon_class"):
		for hand in hands:
			if str(rig.swing_weapon_class(str(hand))).is_empty():
				continue
			AbilityFx.blade_trail(parent, rig, 0.2, tint, str(hand))
	if index == 2:
		_ring(parent, origin + Vector3.UP * 0.06, radius * 0.9, GOLD, 0.42, 0.14, 0.0)
		_light(parent, origin + Vector3.UP * 1.2, GOLD, 1.6, radius * 1.2, 0.35)


## Heavy Swing: the greatsword's first lesson, and it should feel like the first
## lesson. A fat gold crescent, an air dome punched forward, dust off the floor and
## a slow, unsubtle glow. Nothing here is fast.
static func _heavy_swing(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 1.9))
	AbilityFx.slash_arc(parent, origin, forward, radius,
		float(effect.get("arc_degrees", 120.0)), GOLD, 10.0)
	_glint(parent, origin + Vector3.UP * 1.2, forward, radius, 150.0, GOLD)
	_dome(parent, origin + forward * 0.7 + Vector3.UP * 0.85, forward, radius,
		GOLD_DIM)
	AbilityFx.blade_trail(parent, rig, 0.3, GOLD)
	for side in [-1.0, 1.0]:
		_puff(parent, origin + forward * 0.6 + Vector3.UP * 0.05 +
			forward.cross(Vector3.UP).normalized() * 0.5 * float(side), 0.46, DUST,
			0.05)
	_light(parent, origin + forward * 1.2 + Vector3.UP * 1.1, GOLD, 1.2, 2.6, 0.3)


## Wide Sweep: one cut that is really four. Three ghost crescents fan across the
## whole 220 degrees, a dust band runs along the floor edge of the arc, and the
## real blade ribbon trails behind all of it. The fan, not the crescent, is the
## read.
static func _wide_sweep(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.7))
	var arc := float(effect.get("arc_degrees", 220.0))
	for slot in 3:
		var turn := (float(slot) - 1.0) * 0.22
		var tint := STEEL if slot == 1 else STEEL_DIM
		AbilityFx.slash_arc(parent, origin, forward.rotated(Vector3.UP, turn),
			radius * (1.0 - 0.12 * float(slot)), arc, tint, 4.0 * float(slot))
		_glint(parent, origin + Vector3.UP * 1.1,
			forward.rotated(Vector3.UP, turn), radius * (1.0 - 0.1 * float(slot)),
			120.0, tint)
	_band(parent, origin + Vector3.UP * 0.05, forward, radius, arc, DUST)
	AbilityFx.blade_trail(parent, rig, 0.28)
	_light(parent, origin + Vector3.UP * 1.1, STEEL, 1.0, radius * 1.1, 0.28)


## Ground Breaker: the haft comes down and the floor loses. Radiating ground
## cracks, four chunks of turf thrown up at the compass points, two columns of dust
## and a hard ring - a weight-and-fracture read with no blade light at all.
static func _ground_breaker(parent: Node3D, rig, cue_name: String,
		forward: Vector3, effect: Dictionary) -> void:
	if cue_name != "ring":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 3.0))
	_cracks(parent, origin + Vector3.UP * 0.04, radius, GOLD_DIM, 7)
	_ring(parent, origin + Vector3.UP * 0.03, radius * 0.92, DUST, 0.5, 0.16, 0.0)
	for slot in 4:
		var angle := TAU * float(slot) / 4.0 + 0.4
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_debris(parent, origin + outward * radius * 0.55 + Vector3.UP * 0.1,
			outward, 0.42, GOLD_DIM, 0.04 * float(slot))
		_column(parent, origin + outward * radius * 0.72 + Vector3.UP * 0.05,
			DUST, 0.55 + 0.1 * float(slot), 0.06 * float(slot))
	_light(parent, origin + Vector3.UP * 0.4, GOLD, 2.0, radius * 1.6, 0.4)


## Executioner: a verdict. A narrow blade ghost falls from above onto the aim line
## - the only downward read in the file - a red sigil is stamped flat on the
## ground beneath it and a thin chop-line runs out to the blade's reach. No sweep.
static func _executioner(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 2.2))
	_falling_blade(parent, origin + forward * reach * 0.62, forward, 2.6, 0.26,
		STEEL, 0.26)
	_glint(parent, origin + Vector3.UP * 1.25, forward, reach, 60.0, STEEL, 0.2)
	_sigil(parent, origin + forward * reach * 0.5 + Vector3.UP * 0.04, 0.9, BLOOD)
	_streak(parent, origin + forward * 0.3 + Vector3.UP * 0.95, forward, reach, 0.07,
		CREAM, 0.22, 0.16)
	_cone(parent, origin + forward * reach * 0.7 + Vector3.UP * 0.2, Vector3.UP, 0.7,
		6, BLOOD, 0.26)
	_light(parent, origin + forward * reach * 0.6 + Vector3.UP * 1.4, BLOOD, 1.6,
		3.0, 0.36)


## Quick Stab: one jab. A short bright line at chest height and a pinpoint spark,
## with the blade ribbon held to the length of the thrust. The line is the whole
## icon, as on the art.
static func _quick_stab(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 1.3))
	_streak(parent, origin + Vector3.UP * 1.12, forward, reach * 0.9, 0.10, STEEL,
		0.0, 0.22)
	_glint(parent, origin + Vector3.UP * 1.05, forward, reach * 0.8, 45.0, STEEL)
	_spark(parent, origin + forward * reach * 0.88 + Vector3.UP * 1.12, 0.16,
		CREAM, 0.18, 0.0)
	AbilityFx.blade_trail(parent, rig, 0.16)


## Lunge Thrust: two beats, two stories. The dash beat is the wake the body drags
## behind it; the arc beat is the thrust itself - a long lance down the lane with
## the blade ribbon still running and dust kicked off the passed floor.
static func _lunge_thrust(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name == "dash":
		AbilityFx.lunge_wake(parent, rig, 0.40)
		_streaks(parent, _feet(rig) + Vector3.UP * 1.0, forward, 3, 2.4, 0.09,
			STEEL_DIM, 0.0, 0.3)
		return
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 2.45))
	_lance(parent, origin + Vector3.UP * 1.15, forward, reach, 0.13, STEEL, CREAM)
	_glint(parent, origin + Vector3.UP * 1.15, forward, reach * 0.9, 45.0, STEEL)
	AbilityFx.blade_trail(parent, rig, 0.18)
	_streaks(parent, origin + Vector3.UP * 0.16, forward, 5, reach * 0.8, 0.04,
		DUST, 0.02, 0.22)
	_light(parent, origin + forward * reach * 0.7 + Vector3.UP * 1.1, STEEL, 1.3,
		3.0, 0.24)


## Spinning Cut: the wind-up gathers the blade before the ring is spent, so the
## first beat draws light turning inward, and the ring beat throws the existing
## low dust ring plus two counter-rotating crescents and the blade's own ribbon.
static func _spin_slash(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.9))
	if cue_name == "wind":
		_gather(parent, origin + Vector3.UP * 1.05, radius * 0.8, GOLD, 0.34)
		AbilityFx.blade_trail(parent, rig, 0.34, GOLD)
		return
	if cue_name != "ring":
		return
	AbilityFx.spin_burst(parent, origin, radius)
	for side in [1.0, -1.0]:
		AbilityFx.slash_arc(parent, origin, forward.rotated(Vector3.UP,
			1.4 * float(side)), radius * 0.92, 150.0, CREAM, 24.0 * float(side))
	AbilityFx.blade_trail(parent, rig, 0.3, CREAM)


## Backstab: the blink swallows the body, the stab opens it. The blink is the
## existing near-black engulfing cloud; the stab is the warm flash behind the body
## plus a green-black venom bead, because the dagger's own lesson is the wound that
## keeps working.
static func _backstab(parent: Node3D, rig, cue_name: String, forward: Vector3) -> void:
	var origin := _feet(rig)
	if cue_name == "blink":
		AbilityFx.smoke_puff(parent, origin, 1.0, true)
		return
	if cue_name != "stab":
		return
	AbilityFx.backstab_flash(parent, origin + forward * 0.35 + Vector3.UP * 1.15,
		forward)
	_spark(parent, origin + forward * 0.5 + Vector3.UP * 0.9, 0.2, TEAL_DIM, 0.3, 0.06)
	_drip(parent, origin + forward * 0.6 + Vector3.UP * 0.85, TEAL_DIM, 0.8, 0.1)


# --- shield ----------------------------------------------------------------

## Shield Shove: the board makes room. A flat pressure wave off the shield face, a
## small gold ring at the rim and a short shove streak - deliberately the cheapest
## shield read, because it is the free one every board earns.
static func _shield_shove(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 1.5))
	_shield_face(parent, origin + forward * 0.75 + Vector3.UP * 1.05, forward, 0.7,
		GOLD)
	_pressure(parent, origin + forward * (0.75 + reach * 0.4) + Vector3.UP * 1.0,
		forward, 0.8, GOLD_DIM)
	_ring(parent, origin + Vector3.UP * 0.05, reach * 0.85, GOLD_DIM, 0.3, 0.08, 0.02)
	_light(parent, origin + forward * 0.9 + Vector3.UP * 1.05, GOLD, 0.7, 1.8, 0.2)


## Headbutt: the shield's real hit. A white-hot helm crack at the face of the
## target, a red-white star behind it and a hard short cone of sparks. The impact
## star, not a crescent, is what makes it read as a head and not a cut.
static func _shield_bash(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 1.7))
	var at := origin + forward * reach * 0.72 + Vector3.UP * 1.35
	AbilityFx.shield_impact(parent, at, forward, reach, false)
	_star(parent, at, forward, 0.7, 10, CREAM, 0.0)
	_cone(parent, at, forward, 0.55, 8, GOLD, 0.02)
	_star(parent, at, forward, 0.45, 6, BLOOD, 0.05)


## Shield Charge: the run behind the board. The first beat is the ram itself - a
## gold wedge in front of the shield face and three face streaks - and the second
## beat is the contact, a shield impact sized to the arc's own radius.
static func _shield_charge(parent: Node3D, rig, cue_name: String, index: int,
		forward: Vector3, effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 1.8))
	if index == 0:
		_wedge(parent, origin + forward * 1.0 + Vector3.UP * 1.1, forward, 1.8, 0.8,
			GOLD, 0.0)
		for slot in 3:
			_streak(parent, origin + Vector3.UP * (0.85 + 0.28 * float(slot)),
				forward, 2.0 + 0.3 * float(slot), 0.06, GOLD_DIM,
				0.02 * float(slot), 0.24)
		_shield_face(parent, origin + forward * 0.7 + Vector3.UP * 1.05, forward,
			0.85, GOLD)
		return
	AbilityFx.shield_impact(parent, origin + forward * reach * 0.75 +
		Vector3.UP * 1.05, forward, reach, true)
	_star(parent, origin + forward * reach * 0.75 + Vector3.UP * 1.05, forward, 0.6,
		8, GOLD, 0.02)


## Ground Shield Slam: the board goes down and the floor answers. The existing
## shield impact plus a floor crack ring, two tall dust columns and a heavy ring
## out at the hit volume - the weight and the fracture, no blade light.
static func _shield_slam(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "ring":
		return
	var origin := _feet(rig)
	var radius := float(effect.get("radius", 2.9))
	AbilityFx.shield_impact(parent, origin + forward * 0.9 + Vector3.UP * 0.55,
		forward, radius, true)
	_cracks(parent, origin + forward * 0.6 + Vector3.UP * 0.03, radius * 0.8,
		GOLD_DIM, 6)
	_ring(parent, origin + Vector3.UP * 0.04, radius * 0.95, GOLD, 0.45, 0.15, 0.0)
	for side in [-1.0, 1.0]:
		_column(parent, origin + forward * 0.7 +
			forward.cross(Vector3.UP).normalized() * 0.6 * float(side) +
			Vector3.UP * 0.05, DUST, 0.7, 0.05)
	_light(parent, origin + Vector3.UP * 0.5, GOLD, 2.2, radius * 1.5, 0.4)


## Rebuke: the rim comes round and the last blow goes back. A bright arc on the
## shield's own rim, a returning streak that runs back down the incoming line and
## a gold counter-crescent - light that moves *outward from* the board rather than
## from the body.
static func _rebuke(parent: Node3D, rig, cue_name: String, forward: Vector3,
		effect: Dictionary) -> void:
	if cue_name != "arc":
		return
	var origin := _feet(rig)
	var reach := float(effect.get("radius", 2.0))
	var board := origin + forward * 0.65 + Vector3.UP * 1.05
	_shield_face(parent, board, forward, 0.9, CREAM)
	_sweep(parent, board, forward, 0.85, 130.0, GOLD, 0.0)
	_streak(parent, board, -forward, 1.6, 0.10, CREAM, 0.04, 0.2)
	AbilityFx.slash_arc(parent, origin, forward, reach, 90.0, GOLD, -8.0)
	_light(parent, board, GOLD, 1.5, 2.4, 0.24)


# --- fire and bone ---------------------------------------------------------

## Fireball: the staff lights before the orb does. A bright ignition knot at the
## staff head, a heat ring and a small spray of embers - the flight itself belongs
## to `spell_projectile.gd`, so this beat only has to say "it is lit".
static func _fireball(parent: Node3D, rig, cue_name: String, forward: Vector3) -> void:
	if cue_name != "cast":
		return
	var origin := _staff(rig)
	_orb(parent, origin, 0.26, EMBER, EMBER_HOT, 0.0)
	_ring_cross(parent, origin + forward * 0.2, 0.5, EMBER, 0.02, forward)
	_cone(parent, origin, forward, 0.5, 7, EMBER_HOT, 0.0)
	_light(parent, origin, EMBER, 2.0, 3.4, 0.4)


## Cinder Lance: a beam, not a ball. A tapered line of fire from the staff to the
## aim point, embers shed along its length, and a hot bloom where it would land.
## The only staff skill whose light is continuous.
static func _cinder_lance(parent: Node3D, rig, cue_name: String,
		forward: Vector3) -> void:
	if cue_name != "cast":
		return
	var origin := _staff(rig)
	var reach := 14.0
	_lance(parent, origin, forward, reach, 0.16, EMBER, EMBER_HOT)
	for slot in 5:
		_spark(parent, origin + forward * (1.4 + 2.2 * float(slot)) +
			Vector3.UP * 0.08 * float(slot), 0.10, EMBER_HOT, 0.5,
			0.03 * float(slot))
	_flare(parent, origin + forward * reach * 0.85, EMBER, 0.7)
	_light(parent, origin, EMBER, 2.4, 4.0, 0.5)


## Fire Ray: the ignition of a held line. The ray itself is a standing node
## (`fire_ray.gd`) because it outlives its cue; this beat only lights the mouth -
## a hot knot on the staff head, a pressure ring around it, the first spray of
## fire down the line and the light that paints the caster's arms.
static func _fire_ray(parent: Node3D, rig, cue_name: String,
		forward: Vector3) -> void:
	if cue_name != "beam":
		return
	var origin := _staff(rig)
	var dir := _flat(forward, _heading(rig))
	_orb(parent, origin, 0.24, EMBER, EMBER_HOT, 0.0)
	_ring_cross(parent, origin + dir * 0.14, 0.44, EMBER, 0.0, dir)
	_cone(parent, origin, dir, 0.8, 9, EMBER_HOT, 0.0)
	_flare(parent, origin + dir * 0.32, EMBER, 0.82)
	_light(parent, origin, EMBER, 2.6, 4.5, 0.5)


## Bone Spear: the dead channel. Bone shards converge on the staff, a spectral ring
## snaps in behind them and a pale lance points down the line - cold, thin and
## colourless next to the fire staff's read.
static func _bone_spear(parent: Node3D, rig, cue_name: String,
		forward: Vector3) -> void:
	if cue_name != "cast":
		return
	var origin := _staff(rig)
	_converge(parent, origin + forward * 0.4, 0.9, BONE, 7)
	_ring_cross(parent, origin + forward * 0.55, 0.55, BONE, 0.0, forward)
	_lance(parent, origin, forward, 7.0, 0.09, BONE, BONE_CORE)
	_spark(parent, origin, 0.18, BONE_CORE, 0.3, 0.0)
	_light(parent, origin, BONE, 1.4, 3.0, 0.35)


## Grave Bloom: a flower of bone opens where the aim lands. Six petals unfold
## outward from a bright core, four thorn spikes rise under them, and a pale ring
## holds the ground - the one staff read that is a shape rather than a line.
static func _grave_bloom(parent: Node3D, rig, cue_name: String, forward: Vector3,
		aim: Vector3, effect: Dictionary) -> void:
	if cue_name != "cast":
		return
	var radius := float(effect.get("radius", 4.0))
	var at := _aim_point(rig, forward, aim) + Vector3.UP * 0.9
	_bloom(parent, at, radius * 0.45, BONE, BONE_CORE)
	for slot in 4:
		var angle := TAU * float(slot) / 4.0 + 0.6
		_spike(parent, at - Vector3.UP * 0.8 +
			Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.3,
			Vector3.UP + Vector3(cos(angle), 0.0, sin(angle)) * 0.24, 1.1, 0.09, BONE,
			0.06 * float(slot))
	_ring(parent, at - Vector3.UP * 0.88, radius * 0.62, BONE, 0.5, 0.12, 0.04)
	_light(parent, at, BONE, 1.8, radius, 0.5)


# --- wards -----------------------------------------------------------------

## Ember Ward: the ward's own fire. A ring of licking ember notches turns around
## the body, a warm shell breathes once, and three cinders rise. The staff's ward
## is fire held in a circle, not a bubble.
static func _ember_ward(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "ward":
		return
	var origin := _feet(rig)
	_rune_ring(parent, origin + Vector3.UP * 0.08, 1.25, EMBER, 1.0, 9)
	for slot in 3:
		_cinder(parent, origin + Vector3.UP * (0.4 + 0.5 * float(slot)), EMBER_HOT,
			0.05 * float(slot))
	_shell(parent, origin + Vector3.UP * 1.0, 1.05, EMBER, 0.32)
	_light(parent, origin + Vector3.UP * 1.1, EMBER, 1.4, 2.6, 0.5)


## Energy Shield: the tuned ward. A gold bubble breathes out from the body, a ring
## of even notches spins up its face and a hard core glint sits at the chest. This
## is the only ward whose light is a closed shell, because it is the only one that
## lasts a minute.
static func _energy_shield(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "ward":
		return
	var origin := _feet(rig)
	_shell(parent, origin + Vector3.UP * 1.0, 1.2, GOLD, 0.3)
	_rune_ring(parent, origin + Vector3.UP * 0.1, 1.35, GOLD, 1.2, 12)
	_spark(parent, origin + Vector3.UP * 1.15, 0.3, CREAM, 0.4, 0.0)
	_light(parent, origin + Vector3.UP * 1.2, GOLD, 1.6, 3.2, 0.55)


## Focus: the free ward, and the calmest read in the file. Two still concentric
## rings and a slow lift of pale motes. No shell, no spin, no strong colour: the
## cord's ward is attention, so the art is symmetry.
static func _focus(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "ward":
		return
	var origin := _feet(rig)
	_ring(parent, origin + Vector3.UP * 0.06, 0.85, TEAL_DIM, 0.7, 0.06, 0.0)
	_ring(parent, origin + Vector3.UP * 0.5, 0.55, TEAL, 0.8, 0.05, 0.08)
	_motes(parent, origin + Vector3.UP * 0.2, 1.0, TEAL, 6, 0.9)
	_spark(parent, origin + Vector3.UP * 1.1, 0.22, TEAL, 0.4, 0.05)


## Stone Skin: the cord turns a body to rock. Four slabs rise out of the ground
## around the feet, grit falls, and a flat grey ring spreads - weight and stone
## rather than light.
static func _stone_skin(parent: Node3D, rig, cue_name: String) -> void:
	if cue_name != "ward":
		return
	var origin := _feet(rig)
	for slot in 4:
		var angle := TAU * float(slot) / 4.0 + 0.78
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_slab(parent, origin + outward * 0.72 + Vector3.UP * 0.05, outward, 0.9,
			STONE, 0.05 * float(slot))
	_ring(parent, origin + Vector3.UP * 0.04, 1.15, STONE, 0.55, 0.14, 0.0)
	for slot in 2:
		_puff(parent, origin + Vector3.UP * (0.2 + 0.3 * float(slot)), 0.5, DUST,
			0.08 * float(slot))
	_light(parent, origin + Vector3.UP * 0.8, STONE, 0.8, 2.2, 0.4)


# --- consumables -----------------------------------------------------------

## A consumable's own beat, when the body finishes binding or drinking. The
## two are not combat skills - they have no cue of their own and the body owns
## the channel - so the scene calls this from the channel's last tick. A bandage
## is cloth and patience: still green rings and a slow lift of motes. A potion is
## a swallow: red light twisting up out of the chest and a gold glint as it
## closes. Distinct on purpose; a player must be able to tell which one just
## finished without looking at the bar.
static func consume(parent: Node3D, rig, kind: String) -> bool:
	if not is_instance_valid(parent) or not is_instance_valid(rig):
		return false
	var origin := _feet(rig)
	match kind:
		"bandage":
			_ring(parent, origin + Vector3.UP * 0.05, 0.6, TEAL_DIM, 0.7, 0.05, 0.0)
			_ring(parent, origin + Vector3.UP * 0.05, 0.95, TEAL, 0.9, 0.04, 0.18)
			_motes(parent, origin + Vector3.UP * 0.15, 0.7, TEAL, 8, 1.1)
			_spark(parent, origin + Vector3.UP * 1.15, 0.2, TEAL, 0.45, 0.0)
			_light(parent, origin + Vector3.UP * 1.1, TEAL, 1.0, 2.2, 0.5)
			return true
		"potion":
			_ring(parent, origin + Vector3.UP * 0.05, 0.55, GOLD, 0.6, 0.06, 0.0)
			# The swallow is a twist, not a column: three staggered embers climb
			# the chest on their own arcs while a warm core blooms behind them.
			for slot in 3:
				_cinder(parent, origin + Vector3(
					(float(slot) - 1.0) * 0.16, 0.5 + 0.2 * float(slot),
					(float(slot) - 1.0) * 0.1), BLOOD, 0.06 * float(slot))
			_shell(parent, origin + Vector3.UP * 1.0, 0.7, BLOOD, 0.34)
			_flare(parent, origin + Vector3.UP * 1.1, BLOOD, 0.34)
			_light(parent, origin + Vector3.UP * 1.1, BLOOD, 1.4, 2.6, 0.45)
			return true
	return false


# --- shared shapes ---------------------------------------------------------
#
# Everything below is a shape, not a skill: a streak is a line, a sweep is a
# narrow crescent, a star is a burst. Skills compose them above. Each helper adds
# its own nodes under `parent`, places them in world space and frees them on their
# own tween clocks, so a signature never tracks a node it made.
#
# `_fade` is the one writer of a material's alpha. It rises to `peak` over `rise`
# and falls to nothing over `hold`, in that order and in one tween chain; every
# caller then adds its own motion as a parallel step *after* the fade's last step,
# which is the only way two properties animate together without one of them
# overwriting the other.

## Rise then fade one material's alpha, then leave the tween for the caller to
## hang motion on. Returns the tween whose last step is the fade.
static func _fade(node: Node, material: StandardMaterial3D, colour: Color,
		peak: float, rise: float, hold: float, delay: float = 0.0) -> Tween:
	var tween := node.create_tween()
	tween.tween_interval(maxf(delay, 0.0))
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, peak), maxf(rise, 0.01))
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), maxf(hold, 0.02))
	return tween


## The body's feet, so a ground read starts on the floor the body stands on.
static func _feet(rig) -> Vector3:
	if not is_instance_valid(rig) or not (rig is Node3D):
		return Vector3.ZERO
	return (rig as Node3D).global_position


## The flat heading the body is facing. A signature with no aim line (a ward, a
## turn) still needs a direction to bias its shapes.
static func _heading(rig) -> Vector3:
	if not is_instance_valid(rig) or not (rig is Node3D):
		return Vector3.FORWARD
	return _flat(-(rig as Node3D).global_basis.z, Vector3.FORWARD)


## A flat unit vector, or `fallback` when the input is vertical or degenerate.
static func _flat(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	if flat.length_squared() < 0.000001:
		return fallback
	return flat.normalized()


## The bow's own muzzle, so arrow light leaves the string instead of the chest.
static func _bow(rig) -> Vector3:
	if is_instance_valid(rig) and rig.has_method("get_arrow_origin"):
		return rig.get_arrow_origin()
	return _feet(rig) + Vector3.UP * 1.2


## The staff's own head, for the same reason.
static func _staff(rig) -> Vector3:
	if is_instance_valid(rig) and rig.has_method("cast_origin"):
		return rig.cast_origin()
	return _feet(rig) + Vector3.UP * 1.2


## Where the crosshair actually is, bounded to the skill's own reach: a bloom must
## open on the ground the player pointed at, not at the horizon. `aim` is the
## scene's own solution when it has one; otherwise the line is projected.
static func _aim_point(rig, forward: Vector3, aim: Vector3) -> Vector3:
	var origin := _feet(rig)
	if aim != Vector3.INF:
		var flat := Vector3(aim.x, origin.y, aim.z)
		if flat.distance_to(origin) < 12.0:
			return flat
	return origin + forward * 5.0


## A weighted pseudo-random in 0..1 from an index and a salt. Fixed arithmetic, so
## two peers draw the same puff pattern.
static func _hash(index: int, salt: int) -> float:
	var value := (index + 1) * 2654435761 + (salt + 3) * 40503
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xFFFF) / 65535.0


## A basis whose local Y points along `direction`, with a stable side vector even
## when the direction is (nearly) vertical. Used by every elongated mesh, because
## `Basis.looking_at` fails on a parallel up vector.
static func _basis_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	if y.length_squared() < 0.000001:
		y = Vector3.UP
	var up := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.94 else Vector3.FORWARD
	var x := y.cross(up).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## A glow streak lying along `direction`. The soft dot is stretched so the streak
## has a bright head and a soft tail, and the quad's plane contains the line rather
## than facing along it (a billboard would vanish edge-on at the shoulder camera).
## `delay` staggers beats inside one cue.
static func _streak(parent: Node3D, at: Vector3, direction: Vector3, length: float,
		width: float, colour: Color, delay: float = 0.0, life: float = 0.2) -> void:
	if not is_instance_valid(parent) or length <= 0.001:
		return
	var dir := direction.normalized()
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(maxf(width, 0.01), length)
	var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
		Color(colour.r, colour.g, colour.b, 0.0))
	material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureStreak"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_basis = Basis(right, dir, right.cross(dir))
	node.global_position = at + dir * length * 0.5
	var tween := _fade(node, material, colour, 0.85, 0.05, life, delay)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3(1.0, 1.12, 1.0), life)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## Several streaks fanned around a forward line: the generic motion read.
static func _streaks(parent: Node3D, at: Vector3, forward: Vector3, count: int,
		length: float, width: float, colour: Color, delay: float,
		spread_seconds: float) -> void:
	for index in count:
		var h := _hash(index, 17)
		var side := (h - 0.5) * 0.7
		var lift := (_hash(index, 31) - 0.5) * 0.5
		var line := forward.rotated(Vector3.UP, side) + Vector3.UP * lift * 0.3
		_streak(parent, at + Vector3.UP * lift * 0.25, line.normalized(),
			length * (0.6 + 0.6 * _hash(index, 47)), width, colour,
			delay + spread_seconds * float(index) / float(maxi(count, 1)),
			0.16 + 0.12 * _hash(index, 53))


## A flat ground ring that opens from `radius` to `radius * 2.2`. A torus in a
## horizontal plane: no billboard, so it reads as a ring on the floor at any camera
## pitch.
static func _ring(parent: Node3D, at: Vector3, radius: float, colour: Color,
		hold: float, thickness: float = 0.1, delay: float = 0.0) -> void:
	if not is_instance_valid(parent):
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0
	mesh.outer_radius = 1.0 + maxf(thickness, 0.02)
	mesh.rings = 48
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureRing"
	node.mesh = mesh
	# A TorusMesh is generated around its own Y axis, so it is already a ring lying
	# on the floor: rotating it would stand it on edge, which is how a ground ring
	# turns into a hoop nobody asked for.
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_position = at
	node.scale = Vector3.ONE * maxf(radius, 0.1)
	var span := maxf(hold, 0.08)
	var tween := _fade(node, material, colour, 0.7, 0.06, span, delay)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE * maxf(radius, 0.1) * 2.2,
		span).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A ring standing across the line of travel: the "punched through" read. The torus
## faces along `direction` and snaps outward, so it reads as the shaft passing
## through a hole it just made.
static func _ring_cross(parent: Node3D, at: Vector3, radius: float, colour: Color,
		delay: float, direction: Vector3) -> void:
	if not is_instance_valid(parent):
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.0
	mesh.outer_radius = 1.08
	mesh.rings = 40
	mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureCross"
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	# The ring stands across the line of travel: the torus's own axis is its Y, so
	# that axis is pointed down the direction and the hole faces the shooter.
	node.global_basis = _basis_y(direction)
	node.global_position = at
	node.scale = Vector3.ONE * maxf(radius, 0.05)
	var tween := _fade(node, material, colour, 0.75, 0.05, 0.26, delay)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE * maxf(radius, 0.05) * 1.9,
		0.26).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A long taper of light lying on a line: the lance, the beam and the drill. Built
## from three stretched soft sprites, so the middle stays solid and both ends fade,
## with a hot core laid on top.
static func _lance(parent: Node3D, origin: Vector3, direction: Vector3,
		length: float, width: float, colour: Color, core: Color) -> void:
	var dir := direction.normalized()
	_streak(parent, origin, dir, length, width * 2.4, colour, 0.0, 0.22)
	_streak(parent, origin + dir * length * 0.08, dir, length * 0.92, width, core,
		0.0, 0.18)
	_streak(parent, origin, dir, length * 0.55, width * 5.0, colour, 0.02, 0.3)
	_light(parent, origin + dir * length * 0.45, colour, 1.4,
		clampf(length * 0.35, 2.0, 6.0), 0.28)


## A vertical crescent of blade light, standing in the plane the swing travels
## in. `AbilityFx.slash_arc` lays its ribbon flat, which is the right read from
## above but nearly edge-on from the shoulder camera - the game's actual view - so
## every blade skill also draws this: the same swing, seen as the arc a player
## expects. `arc_degrees` spans the cut and the ribbon opens upward.
static func _glint(parent: Node3D, at: Vector3, forward: Vector3, radius: float,
		arc_degrees: float, colour: Color, delay: float = 0.0) -> void:
	if not is_instance_valid(parent):
		return
	var dir := _flat(forward, Vector3.FORWARD)
	var size := clampf(radius * 0.62, 0.8, 1.5)
	# The painted swing streak: one quad facing the camera, stretched along the
	# line of the cut. A camera-facing streak is what reads from behind the
	# shoulder, and the texture carries the taper and the hot core.
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size * 1.45, size * 0.95)
	var material := Vfx.quad_material(Vfx.texture(Vfx.GLINT), Color(colour.r,
		colour.g, colour.b, 0.0), true, false)
	mesh.material = material
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(quad)
	quad.global_position = at + Vector3.UP * 0.12
	quad.global_basis = Basis.looking_at(dir, Vector3.UP)
	# The streak's own plane is the cut's: local X is the sweep, local Y is up.
	quad.rotate_object_local(Vector3.FORWARD, deg_to_rad(-32.0))
	var hold := 0.26
	var tween := quad.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.5), 0.05)
	tween.set_parallel(true)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), hold).set_delay(0.06)
	tween.tween_property(quad, "scale", Vector3.ONE * 1.22, hold)
	tween.set_parallel(false)
	tween.tween_callback(quad.queue_free)


## A narrow crescent of light: used where `slash_arc`'s full ribbon would read as a
## weapon swing. `radius` is the arc's own radius at this point.
static func _sweep(parent: Node3D, at: Vector3, direction: Vector3, radius: float,
		arc: float, colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureSweep"
	parent.add_child(root)
	root.global_basis = Basis.looking_at(_flat(direction, Vector3.FORWARD), Vector3.UP)
	root.global_position = at
	var material := AbilityFx.ribbon_material(Color(colour.r, colour.g, colour.b, 0.0))
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = AbilityFx.arc_ribbon_mesh(arc, 20)
	ribbon.material_override = material
	ribbon.scale = Vector3.ONE * maxf(radius, 0.1)
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ribbon)
	var tween := _fade(root, material, colour, 0.62, 0.05, 0.24, delay)
	tween.set_parallel(true)
	tween.tween_property(ribbon, "scale", Vector3.ONE * maxf(radius, 0.1) * 1.3,
		0.24).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A wedge of light in front of the body - the shoulder's own shape. Unlike a
## crescent it is solid through the middle, so it reads as mass moving forward.
static func _wedge(parent: Node3D, at: Vector3, forward: Vector3, length: float,
		width: float, colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var dir := forward.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var normal := right.cross(dir)
	for slot in 3:
		var taper := 1.0 - 0.3 * float(slot)
		var mesh := QuadMesh.new()
		mesh.size = Vector2(width * taper, length * (1.0 - 0.14 * float(slot)))
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis(right, dir, normal)
		node.global_position = at + dir * (length * 0.5) - normal * (0.12 * float(slot))
		var end := at + dir * (length * 1.1) - normal * (0.12 * float(slot))
		var tween := _fade(node, material, colour, 0.42 - 0.1 * float(slot), 0.06,
			0.34, delay + 0.02 * float(slot))
		tween.set_parallel(true)
		tween.tween_property(node, "global_position", end, 0.34) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)


## Light gathering inward: the wind-up before a spin. Three arcs close on the body
## and fade as they touch it, so the beat reads as stored motion.
static func _gather(parent: Node3D, at: Vector3, radius: float, colour: Color,
		seconds: float) -> void:
	if not is_instance_valid(parent):
		return
	for slot in 3:
		var root := Node3D.new()
		root.name = "SignatureGather"
		parent.add_child(root)
		root.global_position = at
		root.global_rotation = Vector3(0.0, TAU * float(slot) / 3.0, 0.0)
		var material := AbilityFx.ribbon_material(Color(colour.r, colour.g, colour.b,
			0.0))
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = AbilityFx.arc_ribbon_mesh(150.0, 22)
		ribbon.material_override = material
		ribbon.scale = Vector3.ONE * radius * 1.5
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ribbon)
		var spin := root.global_rotation.y + PI * 0.6
		var tween := _fade(root, material, colour, 0.5, 0.08, seconds * 0.42, 0.0)
		tween.set_parallel(true)
		tween.tween_property(ribbon, "scale", Vector3.ONE * radius * 0.55, seconds) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(root, "global_rotation:y", spin, seconds)
		tween.set_parallel(false)
		tween.tween_callback(root.queue_free)


## A dome punched forward: the heavy swing's displaced air. A flattened sphere is
## the one shape here that still reads from behind the shoulder, where the camera
## is.
static func _dome(parent: Node3D, at: Vector3, forward: Vector3, radius: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	sphere.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureDome"
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD), Vector3.UP)
	node.global_position = at
	node.scale = Vector3(radius * 0.4, radius * 0.5, radius * 0.4)
	var tween := _fade(node, material, colour, 0.30, 0.06, 0.30, 0.0)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3(radius * 1.1, radius * 0.4,
		radius * 1.1), 0.34).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## Radiating floor cracks: `count` thin warm lines running out from a point, each
## stamped a beat apart. The ground break, without a ring to soften it.
static func _cracks(parent: Node3D, at: Vector3, radius: float, colour: Color,
		count: int) -> void:
	for index in count:
		var angle := TAU * float(index) / float(count) + _hash(index, 13) * 0.35
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var reach := radius * (0.55 + 0.45 * _hash(index, 23))
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.07, reach)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis(outward.cross(Vector3.UP).normalized(), outward,
			Vector3.UP)
		node.global_position = at + outward * reach * 0.5 + Vector3.UP * 0.015
		var tween := _fade(node, material, colour, 0.6, 0.05, 0.45,
			0.03 * float(index))
		tween.set_parallel(true)
		tween.tween_property(node, "scale", Vector3(1.0, 1.0, 1.4), 0.45) \
			.set_delay(0.1)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)


## A chunk of ground thrown up on an arc: the breaker's debris.
static func _debris(parent: Node3D, at: Vector3, direction: Vector3, size: float,
		colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var box := BoxMesh.new()
	box.size = Vector3(size, size * 0.7, size * 0.8)
	var material := AbilityFx.glow_material(colour, 0.0, 0.0)
	box.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureDebris"
	node.mesh = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_position = at
	var outward := direction.normalized()
	var peak := at + outward * 1.1 + Vector3.UP * 1.3
	var rest := at + outward * 1.5 + Vector3.UP * 0.1
	var tween := node.create_tween()
	tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.tween_property(node, "global_position", peak, 0.24) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "rotation", Vector3(_hash(3, 7) * TAU,
		_hash(5, 11) * TAU, 0.0), 0.5)
	tween.set_parallel(false)
	tween.tween_property(node, "global_position", rest, 0.26) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(true)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.85), 0.05)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.4).set_delay(0.2)
	tween.tween_property(node, "scale", Vector3.ONE * 0.4, 0.3)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A column of rising dust: the slam's weight. Stretched soft sprites rather than
## particles, so the column keeps its shape at the shoulder camera.
static func _column(parent: Node3D, at: Vector3, colour: Color, seconds: float,
		delay: float) -> void:
	if not is_instance_valid(parent):
		return
	for slot in 4:
		var h := _hash(slot, 61)
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.5 + 0.2 * h, 1.5 + 0.7 * h)
		var material := AbilityFx.sprite_material(AbilityFx.smoke_texture(), false,
			Color(colour.r, colour.g, colour.b, 0.0))
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		var start := at + Vector3((h - 0.5) * 0.42, 0.1, (h - 0.5) * 0.3)
		node.global_position = start
		var end := start + Vector3.UP * (1.2 + h)
		var tween := _fade(node, material, colour, 0.35, 0.1, seconds,
			delay + 0.03 * float(slot))
		tween.set_parallel(true)
		tween.tween_property(node, "global_position", end, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "scale", Vector3(1.7, 1.9, 1.0), seconds)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)


## A soft ground band along an arc's own reach: the wide sweep's floor shadow,
## which is what tells a 220-degree cut from a 90-degree one when the camera is
## close.
static func _band(parent: Node3D, at: Vector3, forward: Vector3, radius: float,
		arc: float, colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureBand"
	parent.add_child(root)
	root.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD), Vector3.UP)
	root.global_position = at
	var material := AbilityFx.ribbon_material(Color(colour.r, colour.g, colour.b, 0.0))
	var band := MeshInstance3D.new()
	band.mesh = AbilityFx.arc_ribbon_mesh(arc, 40, 0.7)
	band.material_override = material
	band.scale = Vector3.ONE * radius * 0.8
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(band)
	var tween := _fade(root, material, colour, 0.26, 0.1, 0.5, 0.0)
	tween.set_parallel(true)
	tween.tween_property(band, "scale", Vector3.ONE * radius, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A blade ghost: a hafted head thrown in a short turn. The butcher's cleaver and
## the executioner's verdict share the shape and differ only in the arc they travel.
static func _cleaver(parent: Node3D, at: Vector3, forward: Vector3, size: float,
		colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureCleaver"
	parent.add_child(root)
	root.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD), Vector3.UP)
	root.global_position = at
	var material := AbilityFx.glow_material(colour, 1.6, 0.0)
	var edge := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size * 0.12, size * 0.72, size * 0.06)
	box.material = material
	edge.mesh = box
	edge.position = Vector3(0.0, 0.0, -size * 0.2)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)
	var hook := MeshInstance3D.new()
	var hook_mesh := BoxMesh.new()
	hook_mesh.size = Vector3(size * 0.34, size * 0.16, size * 0.06)
	hook_mesh.material = material
	hook.mesh = hook_mesh
	hook.position = Vector3(size * 0.16, size * 0.32, -size * 0.2)
	hook.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hook)
	root.scale = Vector3.ONE * 0.4
	var turn := root.global_rotation.y - 1.1
	var tween := _fade(root, material, colour, 0.85, 0.06, 0.3, delay)
	tween.set_parallel(true)
	tween.tween_property(root, "scale", Vector3.ONE * 1.2, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(root, "global_rotation:y", turn, 0.3) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A downward blade ghost: the executioner's falling verdict, drawn as a narrow
## edge that drops along the aim line and stops at chest height.
static func _falling_blade(parent: Node3D, at: Vector3, forward: Vector3,
		height: float, size: float, colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureVerdict"
	parent.add_child(root)
	root.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD), Vector3.UP)
	root.global_position = at + Vector3.UP * height
	var material := AbilityFx.glow_material(colour, 2.2, 0.0)
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size * 0.34, size * 1.5, size * 0.05)
	box.material = material
	blade.mesh = box
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(blade)
	var floor_at := at + Vector3.UP * 1.1
	var tween := _fade(root, material, colour, 0.9, 0.05, 0.2, delay)
	tween.set_parallel(true)
	tween.tween_property(root, "global_position", floor_at, 0.13) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## An upward scoop: the gut hook's rising cut, built from three staggered sprites
## that climb from the floor and lean forward at the top.
static func _scoop(parent: Node3D, at: Vector3, forward: Vector3, radius: float,
		colour: Color) -> void:
	var dir := forward.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	for slot in 3:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.12 + 0.03 * float(slot), 0.9 + 0.3 * float(slot))
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis(right, Vector3.UP, right.cross(Vector3.UP))
		node.global_position = at + dir * (0.5 + 0.2 * float(slot)) + Vector3.UP * 0.1
		var end := at + dir * (0.5 + 0.55 * float(slot)) + \
			Vector3.UP * (1.0 + 0.12 * float(slot))
		var tween := _fade(node, material, colour, 0.55, 0.06, 0.3,
			0.03 * float(slot))
		tween.set_parallel(true)
		tween.tween_property(node, "global_position", end, 0.22) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)
	# The scoop's reach is the skill's, so its floor mark uses the same number.
	_ring(parent, at + Vector3.UP * 0.03, maxf(radius * 0.55, 0.4), colour, 0.3,
		0.05, 0.02)


## A pale ribcage arc: three short horizontal bands stacked over the chest. The hook
## turns here, so the art names the body it is turning in.
static func _ribs(parent: Node3D, at: Vector3, forward: Vector3, radius: float,
		colour: Color) -> void:
	var right := forward.normalized().cross(Vector3.UP).normalized()
	for slot in 3:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(radius * 2.0 * (1.0 - 0.18 * float(slot)), 0.07)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis(right, Vector3.UP, right.cross(Vector3.UP))
		node.global_position = at + Vector3.UP * (0.16 * float(slot))
		var tween := _fade(node, material, colour, 0.5, 0.05, 0.34,
			0.04 * float(slot))
		tween.tween_callback(node.queue_free)


## A shield face: an upright rounded plate at the board's own position. The
## shield's skills read from *this*, never from a blade crescent.
static func _shield_face(parent: Node3D, at: Vector3, forward: Vector3, size: float,
		colour: Color) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureShieldFace"
	parent.add_child(root)
	root.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD), Vector3.UP)
	root.global_position = at
	var material := AbilityFx.glow_material(colour, 1.4, 0.0)
	var plate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size * 0.62, size * 0.86, size * 0.08)
	box.material = material
	plate.mesh = box
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plate)
	var boss := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = size * 0.16
	sphere.height = size * 0.26
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = AbilityFx.glow_material(colour, 2.4, 0.0)
	boss.mesh = sphere
	boss.position = Vector3(0.0, 0.0, -size * 0.06)
	boss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(boss)
	var tween := _fade(root, material, colour, 0.42, 0.05, 0.26, 0.0)
	tween.tween_callback(root.queue_free)


## A flat pressure wave off a surface: a thin outward ring plus three short shove
## streaks. The shove's read, and the only shield beat that is quiet.
static func _pressure(parent: Node3D, at: Vector3, forward: Vector3, size: float,
		colour: Color) -> void:
	_ring_cross(parent, at, size * 0.55, colour, 0.0, forward)
	var right := forward.cross(Vector3.UP).normalized()
	for slot in 3:
		var offset := right * (float(slot) - 1.0) * 0.18
		_streak(parent, at + offset, forward, size * 1.4, 0.06, colour,
			0.02 * float(slot), 0.18)


## A star impact: `count` thin spikes radiating from a point, with a white core. The
## headbutt's and the rebuke's hard contact.
static func _star(parent: Node3D, at: Vector3, forward: Vector3, size: float,
		count: int, colour: Color, delay: float) -> void:
	for index in count:
		var angle := TAU * float(index) / float(count) + _hash(index, 37) * 0.4
		var outward := forward.rotated(Vector3.UP, angle) + Vector3.UP * 0.25
		_streak(parent, at, outward.normalized(), size * (0.6 + 0.5 *
			_hash(index, 41)), 0.05, colour, delay + 0.01 * float(index), 0.12)
	_spark(parent, at, size * 0.5, CREAM, 0.2, delay)


## A cone of sparks thrown forward from a point: the impact's debris.
static func _cone(parent: Node3D, at: Vector3, direction: Vector3, size: float,
		count: int, colour: Color, delay: float) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.000001:
		dir = Vector3.FORWARD
	for index in count:
		var h := _hash(index, 67)
		var spray := dir.rotated(Vector3.UP, (h - 0.5) * 0.9) + Vector3.UP * \
			(0.1 + 0.35 * _hash(index, 71))
		_streak(parent, at, spray.normalized(), size * (0.5 + 0.7 * h), 0.05,
			colour, delay + 0.015 * float(index), 0.16)


## Shards converging on a point: the bone staff's gather, the reverse of a burst.
static func _converge(parent: Node3D, at: Vector3, radius: float, colour: Color,
		count: int) -> void:
	for index in count:
		var h := _hash(index, 83)
		var angle := TAU * float(index) / float(count) + h * 0.3
		var outward := Vector3(cos(angle), 0.25 + 0.3 * h, sin(angle)) * radius
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.07, 0.34)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis.looking_at(-outward.normalized(), Vector3.UP)
		node.global_position = at + outward
		var tween := _fade(node, material, colour, 0.7, 0.06, 0.2, 0.0)
		tween.set_parallel(true)
		tween.tween_property(node, "global_position", at, 0.22) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)


## Petals opening from a core: the grave bloom. Each petal is a stretched soft
## sprite that swings out and up, with a bright core left behind.
static func _bloom(parent: Node3D, at: Vector3, radius: float, colour: Color,
		core: Color) -> void:
	for index in 6:
		var angle := TAU * float(index) / 6.0 + 0.3
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var mesh := QuadMesh.new()
		mesh.size = Vector2(radius * 0.55, radius * 1.1)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis(outward.cross(Vector3.UP).normalized(), outward,
			Vector3.UP)
		node.global_position = at
		node.scale = Vector3.ONE * 0.2
		var end := at + outward * radius * 0.9 + Vector3.UP * radius * 0.25
		var tween := _fade(node, material, colour, 0.75, 0.08, 0.5,
			0.02 * float(index))
		tween.set_parallel(true)
		tween.tween_property(node, "scale", Vector3.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(node, "global_position", end, 0.42) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)
		tween.tween_callback(node.queue_free)
	_spark(parent, at, radius * 0.42, core, 0.4, 0.0)
	_light(parent, at, colour, 1.4, radius * 2.0, 0.45)


## A ground sigil: two crossed thin quads on the floor, stamped. The executioner's
## verdict mark and any future mark a skill leaves behind.
static func _sigil(parent: Node3D, at: Vector3, radius: float, colour: Color) -> void:
	for slot in 2:
		var mesh := QuadMesh.new()
		mesh.size = Vector2(radius * 2.0, 0.08)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.rotation = Vector3(0.0, PI * 0.25 * float(slot), 0.0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_position = at
		var tween := _fade(node, material, colour, 0.55, 0.08, 0.6, 0.0)
		tween.tween_callback(node.queue_free)
	_ring(parent, at, radius, colour, 0.5, 0.06, 0.05)


## A ring of notches that turns around the body and fades: the ward's own clock.
## `seconds` is how long the flare is meant to read - the *state* lives on the
## rig's bubble, never here.
static func _rune_ring(parent: Node3D, at: Vector3, radius: float, colour: Color,
		seconds: float, count: int) -> void:
	if not is_instance_valid(parent):
		return
	# The painted rune circle, turning slowly on its own axis. The notch boxes it
	# replaced read as a fence; a painted circle reads as a ward.
	var decal := Vfx.decal(parent, at + Vector3.UP * 0.03, Vfx.RUNES,
		Vector2.ONE * radius * 2.1, Color(colour.r, colour.g, colour.b, 0.95),
		maxf(seconds, 0.4), true, 0.0)
	if decal != null:
		decal.create_tween().tween_property(decal, "rotation:y", TAU * 0.5,
			maxf(seconds, 0.4))
	_ring(parent, at + Vector3.UP * 0.02, radius * 0.95, colour, maxf(seconds, 0.3),
		0.05, 0.0)


## One breath of a shell: a transparency-only sphere that expands and dies. Used by
## the wards that need a closed surface rather than a ring.
static func _shell(parent: Node3D, at: Vector3, radius: float, colour: Color,
		seconds: float) -> void:
	if not is_instance_valid(parent):
		return
	var material := AbilityFx.glow_material(colour, 1.1, 0.0)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.9
	sphere.radial_segments = 18
	sphere.rings = 10
	sphere.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureShell"
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_position = at
	node.scale = Vector3.ONE * radius * 0.65
	var hold := maxf(seconds, 0.2)
	var tween := _fade(node, material, colour, 0.26, 0.08, hold, 0.0)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE * radius * 1.15, hold) \
		.set_delay(0.06)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A stone slab rising out of the floor: the cord's ward. Flat, grey and heavy, with
## rock casting a real shadow.
static func _slab(parent: Node3D, at: Vector3, outward: Vector3, size: float,
		colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var box := BoxMesh.new()
	box.size = Vector3(size * 0.55, size * 1.1, size * 0.18)
	var material := AbilityFx.glow_material(colour, 0.0, 0.92)
	box.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureSlab"
	node.mesh = box
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	node.global_basis = Basis.looking_at(_flat(outward, Vector3.FORWARD), Vector3.UP)
	node.global_position = at - Vector3.UP * size * 0.55
	var tween := node.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(node, "global_position", at + Vector3.UP * size * 0.4,
		0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.9), 0.05)
	tween.tween_property(material, "albedo_color",
		Color(colour.r, colour.g, colour.b, 0.0), 0.4).set_delay(0.5)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A single thorn or bone spear rising: the bloom's undergrowth.
static func _spike(parent: Node3D, at: Vector3, direction: Vector3, length: float,
		width: float, colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var cone := CylinderMesh.new()
	cone.top_radius = 0.001
	cone.bottom_radius = maxf(width, 0.01)
	cone.height = length
	cone.radial_segments = 6
	cone.rings = 1
	var material := AbilityFx.glow_material(colour, 0.8, 0.0)
	cone.material = material
	var node := MeshInstance3D.new()
	node.name = "SignatureSpike"
	node.mesh = cone
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	node.global_basis = _basis_y(direction)
	node.global_position = at
	node.scale = Vector3.ONE * 0.2
	var tween := _fade(node, material, colour, 0.85, 0.06, 0.34, delay)
	tween.set_parallel(true)
	tween.tween_property(node, "scale", Vector3.ONE, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(node.queue_free)


## A glow orb with a hot core: the fireball's ignition knot.
static func _orb(parent: Node3D, at: Vector3, radius: float, colour: Color,
		core: Color, delay: float) -> void:
	_spark(parent, at, radius, core, 0.45, delay)
	_flare(parent, at, colour, radius * 1.6)


## A single bright point that swells and dies. Returns the sprite so a caller can
## chain another read on the same node's clock.
static func _spark(parent: Node3D, at: Vector3, size: float, colour: Color,
		life: float, delay: float) -> MeshInstance3D:
	if not is_instance_valid(parent):
		return null
	var sprite := AbilityFx.sprite_flash(parent, Vector3.ZERO,
		Vector2.ONE * maxf(size, 0.02) * 2.4, Color(colour.r, colour.g, colour.b, 0.0))
	sprite.global_position = at
	var material := AbilityFx.sprite_tint(sprite)
	var hold := maxf(life, 0.06)
	var tween := _fade(sprite, material, colour, 0.95, 0.04, hold, delay)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector3.ONE * 1.6, hold)
	tween.set_parallel(false)
	tween.tween_callback(sprite.queue_free)
	return sprite


## A soft flare of light and a light source: a general beat.
static func _flare(parent: Node3D, at: Vector3, colour: Color, size: float) -> void:
	if not is_instance_valid(parent):
		return
	_spark(parent, at, size, colour, 0.3, 0.0)
	_light(parent, at, colour, 1.6, size * 4.0, 0.3)


## A short-lived omni light: the only thing here that paints the world rather than
## adding a sprite. Every signature that fires a big light uses this, so the fade is
## consistent and the node is always freed.
static func _light(parent: Node3D, at: Vector3, colour: Color, energy: float,
		reach: float, seconds: float) -> void:
	if not is_instance_valid(parent):
		return
	var light := AbilityFx.flash_light(colour, energy, reach)
	parent.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, maxf(seconds, 0.05))
	tween.tween_callback(light.queue_free)


## A dust puff on the floor: the footstep, the landing, the shove.
static func _puff(parent: Node3D, at: Vector3, size: float, colour: Color,
		delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureDust"
	parent.add_child(root)
	root.global_position = at
	root.scale = Vector3.ONE * maxf(size, 0.05) * 0.1
	var sprite := AbilityFx.sprite_flash(root, Vector3.UP * 0.1,
		Vector2.ONE * maxf(size, 0.05) * 2.0, Color(colour.r, colour.g, colour.b, 0.0))
	var material := AbilityFx.sprite_tint(sprite)
	var tween := _fade(root, material, colour, 0.4, 0.08, 0.55, delay)
	tween.set_parallel(true)
	tween.tween_property(root, "scale", Vector3.ONE * maxf(size, 0.05), 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position", Vector3.UP * (0.3 + 0.4 * size), 0.5)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A burst of spray in a direction: blood, ash or grit thrown off a blow. Short
## streaks give it a direction rather than making it a sphere.
static func _spray(parent: Node3D, at: Vector3, direction: Vector3, size: float,
		colour: Color, delay: float) -> void:
	var dir := direction.normalized()
	if dir.length_squared() < 0.000001:
		dir = Vector3.FORWARD
	for index in 7:
		var h := _hash(index, 91)
		var spray := dir.rotated(Vector3.UP, (h - 0.5) * 1.1) + Vector3.UP * \
			(0.15 + 0.5 * _hash(index, 97))
		_streak(parent, at, spray.normalized(), size * (0.4 + 0.8 * h),
			0.045 + 0.03 * h, colour, delay + 0.012 * float(index),
			0.18 + 0.1 * h)


## A bead that falls: the venom drop behind a snap shot, the drip under a wound.
static func _drip(parent: Node3D, at: Vector3, colour: Color, seconds: float,
		delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureDrip"
	parent.add_child(root)
	root.global_position = at
	var sprite := AbilityFx.sprite_flash(root, Vector3.ZERO, Vector2.ONE * 0.09,
		Color(colour.r, colour.g, colour.b, 0.0))
	var material := AbilityFx.sprite_tint(sprite)
	var tween := _fade(root, material, colour, 0.85, 0.06, seconds * 0.4, delay)
	tween.set_parallel(true)
	tween.tween_property(root, "global_position", at + Vector3.DOWN * 0.5, seconds)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A rising ember: the ward's fire and the ash curtain's flakes.
static func _cinder(parent: Node3D, at: Vector3, colour: Color, delay: float) -> void:
	if not is_instance_valid(parent):
		return
	var root := Node3D.new()
	root.name = "SignatureCinder"
	parent.add_child(root)
	root.global_position = at
	var sprite := AbilityFx.sprite_flash(root, Vector3.ZERO, Vector2.ONE * 0.07,
		Color(colour.r, colour.g, colour.b, 0.0))
	var material := AbilityFx.sprite_tint(sprite)
	var end := at + Vector3.UP * 1.3 + Vector3(_hash(7, 3) - 0.5, 0.0,
		_hash(9, 5) - 0.5) * 0.4
	var tween := _fade(root, material, colour, 0.9, 0.08, 0.5, delay)
	tween.set_parallel(true)
	tween.tween_property(root, "global_position", end, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)


## A veil of falling ash: a curtain of slowly sinking flakes over a patch.
static func _ash_curtain(parent: Node3D, at: Vector3, radius: float, colour: Color,
		count: int) -> void:
	for index in count:
		var h1 := _hash(index, 101)
		var h2 := _hash(index, 103)
		var start := at + Vector3(cos(TAU * h1) * radius * h2, 0.0,
			sin(TAU * h1) * radius * h2)
		var root := Node3D.new()
		root.name = "SignatureAsh"
		parent.add_child(root)
		root.global_position = start
		var sprite := AbilityFx.sprite_flash(root, Vector3.ZERO,
			Vector2.ONE * (0.06 + 0.06 * h2), Color(colour.r, colour.g, colour.b, 0.0))
		var material := AbilityFx.sprite_tint(sprite)
		var tween := _fade(root, material, colour, 0.55, 0.2, 1.1,
			0.1 + 0.5 * h1)
		tween.set_parallel(true)
		tween.tween_property(root, "global_position", start + Vector3.DOWN * 2.6,
			1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.set_parallel(false)
		tween.tween_callback(root.queue_free)


## Motes lifting around the body: the calm ward's slow attention.
static func _motes(parent: Node3D, at: Vector3, radius: float, colour: Color,
		count: int, seconds: float) -> void:
	for index in count:
		var h := _hash(index, 107)
		var angle := TAU * float(index) / float(count)
		var start := at + Vector3(cos(angle) * radius * 0.6, 0.0,
			sin(angle) * radius * 0.6)
		var root := Node3D.new()
		root.name = "SignatureMote"
		parent.add_child(root)
		root.global_position = start
		var sprite := AbilityFx.sprite_flash(root, Vector3.ZERO,
			Vector2.ONE * (0.04 + 0.03 * h), Color(colour.r, colour.g, colour.b, 0.0))
		var material := AbilityFx.sprite_tint(sprite)
		var end := start + Vector3.UP * 1.2 + Vector3(cos(angle) * 0.2, 0.0,
			sin(angle) * 0.2)
		var tween := _fade(root, material, colour, 0.8, 0.2, seconds * 0.6,
			0.08 * float(index))
		tween.set_parallel(true)
		tween.tween_property(root, "global_position", end, seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.set_parallel(false)
		tween.tween_callback(root.queue_free)


## Three ghost afterimages of the body's own shape, left behind on a dash. The rig
## cannot be cloned cheaply, so this is a body-sized vertical smear per step: the
## read of "it passed here" without a second skeleton.
static func _afterimage(parent: Node3D, rig, forward: Vector3, colour: Color,
		count: int) -> void:
	var origin := _feet(rig)
	for index in count:
		var at := origin - forward * (0.6 + 0.7 * float(index))
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.8, 1.7)
		var material := AbilityFx.sprite_material(AbilityFx.soft_dot_texture(), true,
			Color(colour.r, colour.g, colour.b, 0.0))
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		mesh.material = material
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
		node.global_basis = Basis.looking_at(_flat(forward, Vector3.FORWARD),
			Vector3.UP)
		node.global_position = at + Vector3.UP * 0.9
		var tween := _fade(node, material, colour,
			0.30 - 0.06 * float(index), 0.06, 0.34, 0.03 * float(index))
		tween.tween_callback(node.queue_free)


## A nocked spark at the string with two whiskers of string-light: the tell that a
## shaft just left. Drawn at the bow's own muzzle.
static func _nock(parent: Node3D, origin: Vector3, direction: Vector3,
		colour: Color) -> void:
	var right := direction.normalized().cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	_spark(parent, origin, 0.20, colour, 0.18, 0.0)
	for side in [-1.0, 1.0]:
		_streak(parent, origin + right * 0.1 * float(side), direction, 0.6, 0.05,
			colour, 0.0, 0.16)
