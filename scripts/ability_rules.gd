extends RefCounted
## Ability definitions shared by every mode.
##
## An ability is data: the weapon family it belongs to, the catalog row its
## damage is priced off, its key price, cost, cooldown, duration, travel,
## animation, sound, icon and the effect the owning scene applies. `AbilityRunner`
## owns the lifecycle; controllers only supply authority and the current base
## movement speed. Add a new entry here, an icon beside it, and the same
## HUD/input/network path works for the next ability.
##
## A skill is unlocked once on the player's ledger (`RogueliteMeta`) and then
## equipped on a body. This file owns the two rules that make that work:
## `ABILITY_FAMILIES` tags each ability with the weapon families that can perform
## it, and `fits_rig`/`fits_gear` answer whether the hands a body is holding can
## perform it. A row may carry more than one tag and fits when any of them fits;
## `any` is the wildcard the body skills wear. An equipped skill whose tags do
## not fit the current hands is not on the bar; it stays in the equipped list and
## comes back with the other weapon set.
##
## The bar is five keys. The player assigns a skill to a key from the character
## screen's SKILLS page, and that skill fires from that key; the family starters
## its hands earn (Snap Shot, Quick Cut, Heavy Swing, Quick Stab, Fireball, Shield
## Shove, Charge, Focus) fill the first free keys behind the assigned ones. The
## bandage and the healing potion are not on the bar at all: they are the body's
## own two keys (`Z`/`V`), so medicine never costs a skill a slot. `granted` is the
## one layout every HUD, runner and network replica reads.
##
## A skill is performed with the hands, never the feet: the walk, the sprint and
## the leap stay the player's for its whole duration, on the ground and in the
## air. `travel_seconds` is the one window that commits the owner to a step; for
## the rest of the skill the legs layer the normal locomotion cycle under the
## authored upper body.
##
## A bow skill never follows the bow's own rules: the key is the shot. Its arrows
## leave on the press and the rig performs the bow's *own* release-and-recover,
## solved down the live crosshair and compressed into `BOW_SHOT_SECONDS`, so the
## bow always points at the aim instead of an authored clip's fixed direction.
## There is no wind-up, no nock and no draw to wait for.
##
## `aim` decides where a committed step goes: the dash turns the body onto the
## live crosshair and travels down that line instead of the heading the key was
## pressed from. Every skill that travels (the lunge, the boss shove, the shield
## charge) declares it; a skill that holds its ground needs no direction.

## The hotbar: five keys, fired from the number row (1..5). A run upgrade may buy
## the bar more keys for that session (`MAX_SLOT_COUNT` is the ceiling, keys 6..0),
## and the skills a body may assign are laid exactly on the keys the player chose.
const SLOT_COUNT := 5
## The most keys a bar can ever have: the five it ships with plus five a session's
## legendary upgrade can buy. Nothing past this is drawn, assigned or fired.
const MAX_SLOT_COUNT := 10
const TrinketStats = preload("res://scripts/trinket_stats.gd")
## Temporary testing cost: every weapon skill spends a trivial stamina sliver
## so the effect can be exercised back to back. The legacy unarmed charge keeps
## its original price.
const TEST_STAMINA_COST := 1.0
## Every bow skill plays the bow's own release-and-recover from a full draw
## instead of an authored skill clip: the pose is solved down the live crosshair,
## so the bow always points where the player is aiming. The whole normal shot is
## mapped into this window, which makes it the speed of a snapped shot.
const BOW_SHOT_SECONDS := 0.26
## The free starter skill each weapon family carries. A body with hands that fit
## more than one family - a sword and a board, a one-handed sword - draws each
## fitting starter on its bar; the bare-hand Charge is the unarmed starter. A
## starter is automatic: it is never bought, and it is free with the weapon.
const STARTER_BY_FAMILY := {
	TYPE_BOW: "snap_shot",
	TYPE_SWORD: "quick_cut",
	TYPE_TWO_HAND: "heavy_swing",
	TYPE_DAGGER: "quick_stab",
	TYPE_STAFF: "fireball",
	TYPE_SHIELD: "shield_shove",
	TYPE_UNARMED: "charge",
	TYPE_ANY: "focus",
}
## The marker a player body carries so `granted` lays its family starters. An AI
## body without it gets no starter; the bare-hand Charge is its own fallback.
const STARTER_GRANT := "family"
## The weapon families an ability belongs to. This is the "relevant to what the
## body is holding" layer: an ability is only on the bar while the rig carries a
## piece of one of its tag's families. A row may carry several tags and fits when
## any tag fits; `any` is the wildcard (the dash and the body's own wards), and
## `unarmed` is the bare-hand fallback.
const TYPE_ANY := "any"
const TYPE_UNARMED := "unarmed"
const TYPE_BOW := "bow"
const TYPE_SWORD := "sword"
const TYPE_TWO_HAND := "two_hand"
const TYPE_DAGGER := "dagger"
const TYPE_STAFF := "staff"
const TYPE_SHIELD := "shield"
## Every family tag an ability may wear, in the rack's display order. A row's
## tags are checked against this list; a typo must not silently make a skill
## unusable.
const FAMILIES := [TYPE_ANY, TYPE_UNARMED, TYPE_BOW, TYPE_SWORD, TYPE_TWO_HAND,
	TYPE_DAGGER, TYPE_STAFF, TYPE_SHIELD]
## The `effect.kind`s an AI body may be issued: the shapes it can aim at another
## body and the scene can resolve off its own blow road. A ward (`stone_skin`,
## `energy_shield`, `ember_ward`) is a body state a mob has no pool for, a
## `backstab` needs a crosshair and a blink preflight a mob never runs, and
## `charge`/`dash` are the player's own legs - none of the three is written onto a
## clone's bar (`RangerClone.CASTABLE_KINDS`) or onto a recruit's
## (`RecruitCatalog.skill_for`).
const AI_KINDS := ["melee_arc", "melee_ring", "melee_wave",
	"barrage", "volley", "piercing_shot", "projectile"]
## Every combat ability's family tags, in catalog order. A row may wear several
## tags; `fits_rig`/`fits_gear` answer yes when any tag fits, so a skill shared by
## two families is usable from either kit. A family is not a grant: the player
## unlocks the ability once, and equips it on a body whose hands fit one of its
## tags.
const ABILITY_FAMILIES := {
	"charge": [TYPE_UNARMED],
	"snap_shot": [TYPE_BOW],
	"quick_cut": [TYPE_SWORD],
	"heavy_swing": [TYPE_TWO_HAND],
	"quick_stab": [TYPE_DAGGER],
	"shield_shove": [TYPE_SHIELD],
	"focus": [TYPE_ANY],
	"barrage": [TYPE_BOW],
	"triple_volley": [TYPE_BOW],
	"piercing_shot": [TYPE_BOW],
	"double_slash": [TYPE_SWORD],
	"lunge_thrust": [TYPE_SWORD],
	"spin_slash": [TYPE_TWO_HAND],
	"backstab": [TYPE_DAGGER],
	"fireball": [TYPE_STAFF],
	"bone_spear": [TYPE_STAFF],
	"shield_bash": [TYPE_SHIELD],
	"shield_charge": [TYPE_SHIELD],
	"shield_slam": [TYPE_SHIELD],
	"dash": [TYPE_ANY],
	"energy_shield": [TYPE_ANY],
	"butchers_cut": [TYPE_SWORD],
	"gut_hook": [TYPE_SWORD],
	"knife_work": [TYPE_DAGGER],
	"ground_breaker": [TYPE_TWO_HAND],
	"wide_sweep": [TYPE_TWO_HAND],
	"executioner": [TYPE_TWO_HAND],
	"rain_of_ash": [TYPE_BOW],
	"skewer": [TYPE_BOW],
	"cinder_lance": [TYPE_STAFF],
	"fire_ray": [TYPE_STAFF],
	"grave_bloom": [TYPE_STAFF],
	"ember_ward": [TYPE_STAFF],
	"rebuke": [TYPE_SHIELD],
	"three_strike": [TYPE_ANY],
	"stone_skin": [TYPE_ANY],
}
## The key price of a permanent, player-level ability unlock. A fresh player
## owns the eight family starters; everything else is bought
## on the rack with the keys bosses pay. The price is the same no matter which
## hand or body will eventually carry it.
const ABILITY_UNLOCK_COSTS := {
	"barrage": 2, "triple_volley": 2, "piercing_shot": 3,
	"rain_of_ash": 4, "skewer": 4,
	"double_slash": 2, "lunge_thrust": 3, "butchers_cut": 3, "gut_hook": 4,
	"spin_slash": 3, "ground_breaker": 4, "wide_sweep": 3, "executioner": 5,
	"backstab": 3, "knife_work": 3,
	"bone_spear": 3, "cinder_lance": 4, "fire_ray": 5, "grave_bloom": 4,
	"ember_ward": 4,
	"shield_bash": 2, "shield_charge": 3, "shield_slam": 4, "rebuke": 3,
	"three_strike": 4, "stone_skin": 4,
	"dash": 3, "energy_shield": 4,
}
## The family tags an ability wears. Definitions without a row - a consumable,
## a test stub - ride every kit. The returned copy is safe for a caller to sort or
## join; the table itself stays untouched.
static func families_of(definition: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = ABILITY_FAMILIES.get(str(definition.get("id", "")), null)
	if raw is Array:
		for family in raw:
			out.append(str(family))
	elif raw != null:
		out.append(str(raw))
	if out.is_empty():
		out.append(TYPE_ANY)
	return out


## The first tag: the family a list sorts by. `families_of` is the fitting answer.
static func type_of(definition: Dictionary) -> String:
	var families := families_of(definition)
	return str(families[0]) if not families.is_empty() else TYPE_ANY


static func type_label(family: String) -> String:
	match family:
		TYPE_BOW: return "BOW"
		TYPE_SWORD: return "SWORD"
		TYPE_TWO_HAND: return "TWO-HAND"
		TYPE_DAGGER: return "DAGGER"
		TYPE_STAFF: return "STAFF"
		TYPE_SHIELD: return "SHIELD"
		TYPE_UNARMED: return "UNARMED"
	return "ANY HAND"


## Every tag on one line, for the rack's row and the paperdoll's card.
static func family_labels(families: Array) -> String:
	var labels := PackedStringArray()
	for family in families:
		labels.append(type_label(str(family)))
	return "  ·  ".join(labels)


static func family_label(definition: Dictionary) -> String:
	return family_labels(families_of(definition))


## The hands the player has to hold to equip this row, for a refusal message:
## "STAFF", "SWORD or SHIELD". A wildcard tag needs no hold.
static func requirement_label(definition: Dictionary) -> String:
	var families := families_of(definition)
	if families.has(TYPE_ANY):
		return "ANY KIT"
	var labels := PackedStringArray()
	for family in families:
		labels.append(type_label(str(family)))
	return " or ".join(labels)


static func is_starter(id: String) -> bool:
	for starter in STARTER_BY_FAMILY.values():
		if str(starter) == id:
			return true
	return false


## The bare-hand fallback and the consumables are automatic; they are not on
## the player's equip list and cannot be locked.
static func is_automatic(id: String) -> bool:
	return is_starter(id) or id == "charge" or CONSUMABLE_IDS.has(id)


static func is_unlockable(id: String) -> bool:
	return not is_automatic(id) and by_id(id).has("id")


static func unlock_cost_of(id: String) -> int:
	return maxi(1, int(ABILITY_UNLOCK_COSTS.get(id, 3)))


## Every combat ability in catalog order, consumables excluded. The starter and
## the bare-hand fallback are in it; the rack and the book mark them automatic.
static func catalog_ids() -> Array[String]:
	var out: Array[String] = []
	for definition in ABILITIES:
		var id := str(definition.get("id", ""))
		if id.is_empty() or CONSUMABLE_IDS.has(id):
			continue
		out.append(id)
	return out


## The ids a player can spend keys on, in catalog order.
static func unlockable_ids() -> Array[String]:
	var out: Array[String] = []
	for id in catalog_ids():
		if is_unlockable(id):
			out.append(id)
	return out


## Does one family tag fit the hands currently on `rig`? The rig is the authority
## in a fight; the roster asks `gear_fits_family` with the catalog rows instead.
static func rig_fits_family(family: String, rig) -> bool:
	if family == TYPE_ANY:
		return true
	if not is_instance_valid(rig):
		return false
	var mode := str(rig.get("weapon"))
	var weapon: String = mode if not mode.is_empty() else "none"
	match family:
		TYPE_UNARMED:
			return weapon == "none"
		TYPE_BOW:
			return weapon == "bow"
		TYPE_DAGGER:
			return weapon == "dagger"
		TYPE_STAFF:
			return bool(rig.get("staff_active"))
		TYPE_SHIELD:
			return bool(rig.get("shield_equipped"))
		TYPE_TWO_HAND:
			return weapon in ["sword", "dual"] and not bool(rig.get("staff_active")) \
				and bool(rig.swings_two_handed())
		TYPE_SWORD:
			return weapon in ["sword", "dual"] and not bool(rig.get("staff_active"))
	return false


## Do any of an ability's family tags fit the rig? Tags are alternatives, so a
## row shared by two families is usable from either kit.
static func fits_rig(definition: Dictionary, rig) -> bool:
	for family in families_of(definition):
		if rig_fits_family(family, rig):
			return true
	return false


## Does one family tag fit a catalog kit? `main` and `off` are the worn item rows
## (`{}` for an empty hand), so a roster record with no body can be judged by the
## same rule the rig uses. A two-hander counts as a sword as well as a two-hander.
static func gear_fits_family(family: String, main: Dictionary, off: Dictionary) -> bool:
	if family == TYPE_ANY:
		return true
	var category := str(main.get("category", ""))
	var kind := str(main.get("kind", ""))
	var is_sword := kind == "sword" and category in ["1h", "2h"]
	match family:
		TYPE_UNARMED:
			return main.is_empty()
		TYPE_BOW:
			return category == "bow"
		TYPE_DAGGER:
			return kind == "dagger"
		TYPE_STAFF:
			return category == "staff"
		TYPE_SHIELD:
			return str(off.get("category", "")) == "shield"
		TYPE_TWO_HAND:
			return is_sword and category == "2h"
		TYPE_SWORD:
			return is_sword
	return false


## The tag set as an answer: true when the gear fits any one of these families.
## `fits_gear` is the catalog row's own tag list passed through here.
static func fits_any_family(families: Array, main: Dictionary, off: Dictionary) -> bool:
	for family in families:
		if gear_fits_family(str(family), main, off):
			return true
	return false


## Does this ability fit a catalog kit? True when any of its tags fits.
static func fits_gear(definition: Dictionary, main: Dictionary, off: Dictionary) -> bool:
	return fits_any_family(families_of(definition), main, off)


## The catalog row an ability's damage is priced off. The weapon is no longer
## the grant, but the authored base (a shortbow's 30, a greatsword's 50, a
## shield's 18) still prices the skill wherever it is equipped.
static func base_item_of(definition: Dictionary) -> String:
	return str(definition.get("item", ""))


## Base damage per catalog item. A definition's `damage_scale` multiplies it.
const ITEM_DAMAGE := {
	"bow_short": 30.0,
	"bow_recurve": 38.0,
	"bow_long": 50.0,
	"sword_short": 30.0,
	"sword_arming": 38.0,
	"sword_great": 50.0,
	"dagger_iron": 14.0,
	"staff_fire": 50.0,
	"staff_bone": 50.0,
	"shield_buckler": 18.0,
	"shield_kite": 18.0,
	"shield_tower": 18.0,
}
const BOW_ITEMS := ["bow_short", "bow_recurve", "bow_long"]
const SWORD_ITEMS := ["sword_short", "sword_arming", "sword_great"]
const STAFF_ITEMS := ["staff_fire", "staff_bone"]
const SHIELD_ITEMS := ["shield_buckler", "shield_kite", "shield_tower"]
## Effect kinds that swing the body's own weapon. They play their authored
## blade clip over the whole skeleton, so the stance has to be upright before
## they start; a cast can layer over a crouch, a cut cannot.
const MELEE_EFFECTS := ["melee_arc", "melee_ring", "melee_wave", "backstab"]
## A blade skill performed with an axe pays double. The hafted head carries
## weight a sword's edge does not, which is the same reason the piece lands for
## double when it is thrown (`ItemPassives.throw_scale`); the class, never the
## catalog id, decides it.
const AXE_ABILITY_SCALE := 2.0
## The melee effect kinds the axe's own weight rides. A backstab is the dagger's
## own lesson and stays dagger-priced however the other hand is filled.
const AXE_EFFECTS := ["melee_arc", "melee_ring", "melee_wave"]

const ABILITIES := [
	{
		"id": "charge",
		"name": "CHARGE",
		"item": "",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": 10.0,
		"cooldown": 2.5,
		"duration": 1.0,
		"travel_seconds": 1.0,
		"speed_scale": 2.0,
		"sound": "charge",
		"animation": "Sprint_Loop",
		"lean": 0.18,
		"icon": "res://assets/ui/abilities/charge.png",
		"description": "Lunge forward at double speed for one second.",
		# A body-only skill: the beat is presentation. The signature reads it as a
		# shoulder-first wedge and a footfall of dust, so a charge is never the
		# dash's clean sprint line.
		"cues": [{"at": 0.0, "cue": "dash"}],
	},
	{
		"id": "barrage",
		"name": "BARRAGE",
		"item": "bow_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": BOW_SHOT_SECONDS,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "barrage",
		"animation": "Bow_Barrage",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/barrage.png",
		"description": "Rapid fire six half-damage arrows with a spread.",
		"effect": {"kind": "barrage", "damage_scale": 0.5, "shots": 6,
			"spread_degrees": 4.0, "vertical_spread_degrees": 1.4,
			"arrow_speed_scale": 1.05},
		"cues": [
			{"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"},
		],
	},
	{
		"id": "triple_volley",
		"name": "TRIPLE FAN VOLLEY",
		"item": "bow_recurve",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.3,
		"duration": BOW_SHOT_SECONDS,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "volley",
		"animation": "Bow_Triple_Volley",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/triple_volley.png",
		"description": "Loose three arrows in one wide fan.",
		"effect": {"kind": "volley", "damage_scale": 0.7, "shots": 3,
			"spread_degrees": 5.0, "vertical_spread_degrees": 0.5,
			"arrow_speed_scale": 1.0},
		"cues": [{"at": 0.0, "cue": "volley"}],
	},
	{
		"id": "piercing_shot",
		"name": "LONG PIERCING SHOT",
		"item": "bow_long",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.6,
		"duration": BOW_SHOT_SECONDS,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "pierce",
		"animation": "Bow_Piercing_Shot",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/piercing_shot.png",
		"description": "A heavy arrow that punches through three bodies.",
		"effect": {"kind": "piercing_shot", "damage_scale": 2.0, "pierce": 3,
			"arrow_speed_scale": 1.5},
		"cues": [{"at": 0.0, "cue": "shot"}],
	},
	{
		"id": "double_slash",
		"name": "DOUBLE SLASH",
		"item": "sword_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.1,
		"duration": 1.0,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slash",
		"animation": "Sword_Double_Slash",
		"lean": 0.05,
		"icon": "res://assets/ui/abilities/double_slash.png",
		"description": "Two fast cuts across the front arc.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.9, "arc_degrees": 150.0,
			"radius": 1.9, "stagger": 0.0},
		"cues": [
			{"at": 0.26, "cue": "arc"},
			{"at": 0.52, "cue": "arc"},
		],
	},
	{
		"id": "lunge_thrust",
		"name": "LUNGING THRUST",
		"item": "sword_arming",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.3,
		"duration": 0.95,
		"travel_seconds": 0.24,
		"speed_scale": 4.05,
		"sound": "lunge",
		"aim": true,
		"animation": "Sword_Lunge_Thrust",
		"lean": 0.12,
		"icon": "res://assets/ui/abilities/lunge_thrust.png",
		"description": "A long dash that cuts through everything in its lane.",
		# The dash sweeps its lane every tick it travels, so a body it passes
		# through is hit once; the thrust at the end measures the old 2.45 m
		# reach with the same shared victim set.
		"effect": {"kind": "melee_arc", "damage_scale": 1.8, "arc_degrees": 55.0,
			"radius": 2.45, "stagger": 0.25, "path_damage": true,
			"path_radius": 1.35, "path_arc_degrees": 170.0,
			"dash_distance": 5.34},
		"cues": [
			{"at": 0.0, "cue": "dash"},
			{"at": 0.42, "cue": "arc"},
		],
	},
	{
		"id": "spin_slash",
		"name": "SPINNING AOE SPIN",
		"item": "sword_great",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.0,
		"duration": 0.3166667,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "spin",
		"animation": "Sword_Spin_Slash",
		"lean": 0.04,
		"spin": 1.0,
		"icon": "res://assets/ui/abilities/spin_slash.png",
		"description": "One full turn that cuts everything around you.",
		"effect": {"kind": "melee_ring", "damage_scale": 1.4, "radius": 2.9,
			"stagger": 0.2},
		# The wind-up gathers the blade before the ring cue spends the hit. The
		# whole turn lasts a third of its old time, so the beats crowd the start.
		"cues": [
			{"at": 0.06, "cue": "wind"},
			{"at": 0.16, "cue": "ring"},
		],
	},
	{
		"id": "backstab",
		"name": "BACKSTAB",
		"item": "dagger_iron",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 0.9,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "backstab",
		"animation": "Dagger_Backstab",
		"lean": 0.16,
		"icon": "res://assets/ui/abilities/backstab.png",
		"description": "Blink behind a foe and drive the dagger through its back.",
		# The owning scene preflights the target before spending the cost; the
		# skill needs a live body under the crosshair to step behind.
		"effect": {"kind": "backstab", "damage_scale": 2.0, "radius": 1.2,
			"stagger": 0.35},
		"cues": [
			{"at": 0.20, "cue": "blink"},
			{"at": 0.50, "cue": "stab"},
		],
	},
	{
		"id": "fireball",
		"name": "FIREBALL",
		"item": "staff_fire",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 10.0,
		"duration": 1.2,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "fire",
		"animation": "Staff_Fireball_Cast",
		"lean": -0.04,
		"icon": "res://assets/ui/abilities/fireball.png",
		"description": "Hurl a burning orb that bursts in a three-metre blast.",
		# The starter spell is priced like every other staff skill: the staff's
		# catalog base times this share, then the rig's spell scale. Forty percent
		# of the Ember Staff's 50 is the authored 20, and a better staff - or a
		# robe channel - takes it above that.
		"effect": {"kind": "projectile", "projectile": "fireball",
			"damage_scale": 0.4, "radius": 3.0, "speed": 22.0, "pierce": 0},
		"cues": [{"at": 0.50, "cue": "cast"}],
	},
	{
		"id": "snap_shot",
		"name": "SNAP SHOT",
		"item": "bow_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": BOW_SHOT_SECONDS,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "barrage",
		"animation": "Bow_Barrage",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/snap_shot.png",
		"description": "The cheapest shot in the wood: one light arrow, loosed at "
			+ "once, whose head keeps working after it lands - 5 damage a second "
			+ "for 5 s.",
		# The starter's one edge is the poison: the shaft is cheap, but the body
		# it opens keeps paying. `warband_abilities` lays the dose on the body the
		# arrow found, so the figure is the body's loss each second.
		"effect": {"kind": "barrage", "damage_scale": 0.35, "shots": 1,
			"spread_degrees": 1.5, "vertical_spread_degrees": 0.0,
			"arrow_speed_scale": 0.9,
			"poison_dps": 5.0, "poison_seconds": 5.0},
		"cues": [{"at": 0.0, "cue": "shot"}],
	},
	{
		"id": "quick_cut",
		"name": "QUICK CUT",
		"item": "sword_short",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 0.9,
		"duration": 0.7,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slash",
		"animation": "Sword_Double_Slash",
		"lean": 0.02,
		"icon": "res://assets/ui/abilities/quick_cut.png",
		"description": "One plain cut across the front arc. The sword's first lesson.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.5,
			"arc_degrees": 90.0, "radius": 1.6, "stagger": 0.0},
		"cues": [{"at": 0.30, "cue": "arc"}],
	},
	{
		"id": "heavy_swing",
		"name": "HEAVY SWING",
		"item": "sword_great",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 0.9,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slam",
		"animation": "Sword_Overhead",
		"lean": -0.04,
		"icon": "res://assets/ui/abilities/heavy_swing.png",
		"description": "The greatsword's first lesson: a slow, wide, honest swing.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.5,
			"arc_degrees": 120.0, "radius": 1.9, "stagger": 0.1},
		"cues": [{"at": 0.38, "cue": "arc"}],
	},
	{
		"id": "quick_stab",
		"name": "QUICK STAB",
		"item": "dagger_iron",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 0.7,
		"duration": 0.55,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "stab",
		"animation": "Dagger_Backstab",
		"lean": 0.05,
		"icon": "res://assets/ui/abilities/quick_stab.png",
		"description": "A short forward stab. The narrow answer a dagger gets for free.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.45,
			"arc_degrees": 55.0, "radius": 1.3, "stagger": 0.0},
		"cues": [{"at": 0.22, "cue": "arc"}],
	},
	{
		"id": "shield_shove",
		"name": "SHIELD SHOVE",
		"item": "shield_buckler",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": 0.7,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "bash",
		"animation": "Shield_Bash",
		"lean": 0.06,
		"icon": "res://assets/ui/abilities/shield_shove.png",
		"description": "The board's free lesson: a short shove that makes room.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.4,
			"arc_degrees": 90.0, "radius": 1.5, "stagger": 0.2},
		"cues": [{"at": 0.30, "cue": "arc"}],
	},
	{
		"id": "focus",
		"name": "FOCUS",
		"item": "",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": 8.0,
		"cooldown": 18.0,
		"duration": 0.5,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "ward",
		"animation": "Staff_Fireball_Cast",
		"lean": -0.02,
		"icon": "res://assets/ui/abilities/focus.png",
		"description": "A small ward every body gets for free: a fifth of each blow paid in stamina.",
		"effect": {"kind": "ward", "absorb": 0.2, "stamina_scale": 1.2,
			"seconds": 4.0},
		"cues": [{"at": 0.20, "cue": "ward"}],
	},
	{
		"id": "bone_spear",
		"name": "BONE SPEAR",
		"item": "staff_bone",
		"slot": 0,
		"key": "SHIFT + 1",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.4,
		"duration": 1.15,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "bone",
		"animation": "Staff_Bone_Spear_Cast",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/bone_spear.png",
		"description": "A spectral bone lance that impales three bodies.",
		"effect": {"kind": "projectile", "projectile": "bone_spear",
			"damage_scale": 1.8, "radius": 0.0, "speed": 28.0, "pierce": 3},
		"cues": [{"at": 0.46, "cue": "cast"}],
	},
	{
		"id": "shield_bash",
		"name": "HEADBUTT",
		"item": "shield_buckler",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.0,
		"duration": 0.8,
		"travel_seconds": 0.16,
		"speed_scale": 0.55,
		"sound": "bash",
		"aim": true,
		"animation": "Shield_Bash",
		"lean": 0.10,
		"icon": "res://assets/ui/abilities/shield_bash.png",
		"description": "A short head-first shove that staggers the front arc.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.5, "arc_degrees": 100.0,
			"radius": 1.7, "stagger": 0.55},
		"cues": [{"at": 0.26, "cue": "arc"}],
	},
	{
		"id": "shield_charge",
		"name": "SHIELD CHARGE",
		"item": "shield_kite",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.2,
		"duration": 1.15,
		"travel_seconds": 0.48,
		"speed_scale": 1.65,
		"aim": true,
		"sound": "charge",
		"animation": "Shield_Charge",
		"lean": 0.14,
		"icon": "res://assets/ui/abilities/shield_charge.png",
		"description": "Drive forward behind the shield face and bowl them over.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.6, "arc_degrees": 130.0,
			"radius": 1.8, "stagger": 0.45},
		"cues": [
			{"at": 0.34, "cue": "arc"},
			{"at": 0.58, "cue": "arc"},
		],
	},
	{
		"id": "shield_slam",
		"name": "GROUND SHIELD SLAM",
		"item": "shield_tower",
		"slot": 1,
		"key": "SHIFT + 2",
		"stamina_cost": TEST_STAMINA_COST,
		"cooldown": 1.5,
		"duration": 1.1,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "slam",
		"animation": "Shield_Ground_Slam",
		"lean": 0.16,
		"icon": "res://assets/ui/abilities/shield_slam.png",
		"description": "Slam the tower shield down and shake everyone nearby.",
		"effect": {"kind": "melee_ring", "damage_scale": 2.2, "radius": 2.9,
			"stagger": 0.65},
		"cues": [{"at": 0.50, "cue": "ring"}],
	},
	{
		# A body skill: the skill is the player's unlock, not a worn piece's, so it
		# fits any weapon loadout once it is on the bar.
		"id": "dash",
		"name": "DASH",
		"item": "",
		"slot": 2,
		"key": "SHIFT + 3",
		"stamina_cost": 10.0,
		"cooldown": 2.5,
		"duration": 1.0,
		"travel_seconds": 1.0,
		"speed_scale": 2.0,
		"aim": true,
		"sound": "charge",
		"animation": "Sprint_Loop",
		"lean": 0.18,
		"icon": "res://assets/ui/abilities/dash.png",
		"description": "Sprint down the crosshair at double speed for one second.",
		# Presentation only, like the charge: the dash's own beat is the sprint
		# line, the afterimage and the takeoff ring.
		"cues": [{"at": 0.0, "cue": "dash"}],
	},
	{
		"id": "energy_shield",
		"name": "ENERGY SHIELD",
		"item": "",
		"slot": 2,
		"key": "SHIFT + 3",
		"stamina_cost": 8.0,
		"cooldown": 30.0,
		"duration": 0.9,
		"travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "ward",
		"animation": "Staff_Fireball_Cast",
		"lean": -0.03,
		"icon": "res://assets/ui/abilities/energy_shield.png",
		"description": "A humming ward for one minute: half of every hit is paid in stamina.",
		# The ward is a timed body state, not a beat of damage: `absorb` is the
		# share of a hit moved onto stamina at `stamina_scale` times the cost.
		"effect": {"kind": "ward", "absorb": 0.5, "stamina_scale": 2.0,
			"seconds": 60.0},
		"cues": [{"at": 0.42, "cue": "ward"}],
	},
	# --- body skills ---------------------------------------------------------
	# Bought from the ability book like every other skill; their `item` row is
	# only the damage profile. Icons fall back to nothing and the animation falls
	# back to the rig's placeholder, so a skill is playable before its art exists.
	{
		"id": "butchers_cut", "name": "BUTCHER'S CUT", "item": "sword_short",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 25.0,
		"cooldown": 6.0, "duration": 0.6, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slash", "animation": "Sword_Double_Slash",
		"lean": 0.04,
		"icon": "res://assets/ui/abilities/butchers_cut.png",
		"description": "A hooked cut that opens the body up.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.9, "arc_degrees": 100.0,
			"radius": 2.2, "stagger": 0.15},
		"cues": [{"at": 0.30, "cue": "arc"}],
	},
	{
		"id": "gut_hook", "name": "GUT HOOK", "item": "sword_short",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 30.0,
		"cooldown": 10.0, "duration": 0.7, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slash", "animation": "Sword_Overhead",
		"lean": 0.02,
		"icon": "res://assets/ui/abilities/gut_hook.png",
		"description": "One narrow cut straight up under the ribs.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.4, "arc_degrees": 45.0,
			"radius": 2.3, "stagger": 0.2},
		"cues": [{"at": 0.34, "cue": "arc"}],
	},
	{
		"id": "knife_work", "name": "KNIFE WORK", "item": "dagger_iron",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 20.0,
		"cooldown": 6.0, "duration": 0.36, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "stab", "animation": "Sword_Double_Slash",
		"lean": 0.03,
		"icon": "res://assets/ui/abilities/knife_work.png",
		"description": "Three fast stabs thrown from the hip.",
		"effect": {"kind": "melee_arc", "damage_scale": 1.1, "arc_degrees": 70.0,
			"radius": 1.35, "stagger": 0.1},
		"cues": [{"at": 0.15, "cue": "arc"}],
	},
	{
		"id": "ground_breaker", "name": "GROUND BREAKER", "item": "sword_great",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 80.0,
		"cooldown": 12.0, "duration": 0.85, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slam", "animation": "Sword_Overhead",
		"lean": -0.08,
		"icon": "res://assets/ui/abilities/ground_breaker.png",
		"description": "The haft comes down on the ground and the ring goes out.",
		"effect": {"kind": "melee_ring", "damage_scale": 1.2, "arc_degrees": 360.0,
			"radius": 3.0, "stagger": 1.5},
		"cues": [{"at": 0.42, "cue": "ring"}],
	},
	{
		"id": "wide_sweep", "name": "WIDE SWEEP", "item": "sword_great",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 40.0,
		"cooldown": 8.0, "duration": 0.75, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slash", "animation": "Sword_Double_Slash",
		"lean": 0.10,
		"icon": "res://assets/ui/abilities/wide_sweep.png",
		"description": "Everything in front of you, all at once.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.8, "arc_degrees": 220.0,
			"radius": 2.7, "stagger": 0.3},
		"cues": [{"at": 0.38, "cue": "arc"}],
	},
	{
		"id": "executioner", "name": "EXECUTIONER", "item": "sword_great",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 60.0,
		"cooldown": 15.0, "duration": 0.9, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slash", "animation": "Sword_Overhead",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/executioner.png",
		"description": "A deliberate overhead that ends a wounded body.",
		"effect": {"kind": "melee_arc", "damage_scale": 2.2, "arc_degrees": 60.0,
			"radius": 2.2, "stagger": 0.4},
		"cues": [{"at": 0.46, "cue": "arc"}],
	},
	{
		"id": "rain_of_ash", "name": "RAIN OF ASH", "item": "bow_short",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 40.0,
		"cooldown": 18.0, "duration": BOW_SHOT_SECONDS, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "barrage", "animation": "Bow_Barrage",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/rain_of_ash.png",
		"description": "Eight arrows arced high and dropped into a patch of ground.",
		"effect": {"kind": "barrage", "damage_scale": 0.4, "shots": 8,
			"spread_degrees": 6.0, "vertical_spread_degrees": 2.0,
			"arrow_speed_scale": 1.1},
		"cues": [
			{"at": 0.0, "cue": "shot"}, {"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"}, {"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"}, {"at": 0.0, "cue": "shot"},
			{"at": 0.0, "cue": "shot"}, {"at": 0.0, "cue": "shot"},
		],
	},
	{
		"id": "skewer", "name": "SKEWER", "item": "bow_long",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 50.0,
		"cooldown": 14.0, "duration": BOW_SHOT_SECONDS, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "pierce", "animation": "Bow_Barrage",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/skewer.png",
		"description": "One shaft down the line, through whoever is standing in it.",
		"effect": {"kind": "piercing_shot", "damage_scale": 0.8, "pierce": 3},
		"cues": [{"at": 0.0, "cue": "shot"}],
	},
	{
		"id": "cinder_lance", "name": "CINDER LANCE", "item": "staff_fire",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 45.0,
		"cooldown": 10.0, "duration": 0.55, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "fire", "animation": "Staff_Fireball_Cast",
		"lean": 0.02,
		"icon": "res://assets/ui/abilities/cinder_lance.png",
		"description": "A lance of fire down the crosshair, straight through a rank.",
		"effect": {"kind": "projectile", "damage_scale": 1.4, "radius": 0.0,
			"speed": 26.0, "pierce": 4, "projectile": "fireball"},
		"cues": [{"at": 0.26, "cue": "cast"}],
	},
	{
		# A held ray, not a bolt: the scene spawns one beam for the length of the
		# cast and it burns every body its line crosses on a fixed tick. The
		# authored `damage_scale` is the share of the staff's base a body loses
		# each **second**, which is why this row's price is read as DPS rather
		# than as one blow - 50 damage a second off the Ember Staff's 50.
		"id": "fire_ray", "name": "FIRE RAY", "item": "staff_fire",
		"slot": 0, "key": "SHIFT + 1", "stamina_cost": 50.0,
		"cooldown": 18.0, "duration": 1.2, "travel_seconds": 0.0,
		"speed_scale": 0.0,
		"sound": "fire", "animation": "Staff_Fireball_Cast",
		"lean": -0.02,
		"icon": "res://assets/ui/abilities/fire_ray.png",
		"description": "A held ray of fire that burns everything in its line.",
		"effect": {"kind": "beam", "damage_scale": 1.0, "range": 16.0,
			"radius": 0.55, "tick_seconds": 0.2, "stagger": 0.0},
		"cues": [{"at": 0.0, "cue": "beam"}],
	},
	{
		"id": "grave_bloom", "name": "GRAVE BLOOM", "item": "staff_bone",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 55.0,
		"cooldown": 14.0, "duration": 0.7, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "bone", "animation": "Staff_Fireball_Cast",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/grave_bloom.png",
		"description": "A bloom of bone that opens where the aim point lands.",
		"effect": {"kind": "projectile", "damage_scale": 1.0, "radius": 4.0,
			"speed": 14.0, "pierce": 0, "projectile": "bone"},
		"cues": [{"at": 0.34, "cue": "cast"}],
	},
	{
		"id": "ember_ward", "name": "EMBER WARD", "item": "staff_fire",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 40.0,
		"cooldown": 20.0, "duration": 0.6, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "ward", "animation": "Staff_Fireball_Cast",
		"lean": -0.03,
		"icon": "res://assets/ui/abilities/ember_ward.png",
		"description": "A short ward: four tenths of every blow paid in stamina.",
		"effect": {"kind": "ward", "absorb": 0.4, "stamina_scale": 2.0, "seconds": 6.0},
		"cues": [{"at": 0.30, "cue": "ward"}],
	},
	{
		"id": "rebuke", "name": "REBUKE", "item": "shield_buckler",
		"hitem": "", "slot": 1, "key": "SHIFT + 2", "stamina_cost": 25.0,
		"cooldown": 10.0, "duration": 0.65, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "bash", "animation": "Shield_Bash",
		"lean": 0.0,
		"icon": "res://assets/ui/abilities/rebuke.png",
		"description": "The board's rim comes round, and the last blow goes back.",
		"effect": {"kind": "melee_arc", "damage_scale": 0.7, "arc_degrees": 90.0,
			"radius": 2.0, "stagger": 0.3},
		"cues": [{"at": 0.32, "cue": "arc"}],
	},
	{
		"id": "three_strike", "name": "THREE STRIKE", "item": "sword_short",
		"hitem": "", "slot": 0, "key": "SHIFT + 1", "stamina_cost": 35.0,
		"cooldown": 8.0, "duration": 0.8, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "slash", "animation": "Sword_Three_Strike",
		# The clip authors its own weight shift and lean, and both of its wrists:
		# `Sword_Three_Strike` is the one clip where a dual pair swings two
		# blades, so the rig must not re-solve the off arm to the carry pose.
		"lean": 0.0, "offhand_authored": true,
		"icon": "res://assets/ui/abilities/three_strike.png",
		"description": "Three sweeping cuts: right blade, left blade, then both together.",
		# One wave per cue, each on the frame its cut lands in the clip (0.20,
		# 0.50 and 0.80 of it). Each wave is its own cut through the front arc and
		# stops at `victims_per_wave` bodies, so the skill reaches at most nine -
		# three waves of three, never one blade re-cutting the same rank. Each
		# wave also sends out its own ripple.
		"effect": {"kind": "melee_wave", "damage_scale": 0.8, "radius": 2.4,
			"arc_degrees": 130.0, "stagger": 0.18, "victims_per_wave": 3,
			"wave_scales": [0.7, 0.7, 1.5], "wave_sides": [1.0, -1.0, 0.0],
			"glow_seconds": 0.8},
		"cues": [
			{"at": 0.16, "cue": "wave"},
			{"at": 0.40, "cue": "wave"},
			{"at": 0.64, "cue": "wave"},
		],
	},
	{
		"id": "stone_skin", "name": "STONE SKIN", "item": "", "hitem": "",
		"slot": 0, "key": "SHIFT + 1", "stamina_cost": 30.0,
		"cooldown": 18.0, "duration": 0.5, "travel_seconds": 0.0, "speed_scale": 0.0,
		"sound": "ward", "animation": "Staff_Fireball_Cast",
		"lean": -0.02,
		"icon": "res://assets/ui/abilities/stone_skin.png",
		"description": "A ward off the cord: a third of every blow is paid in stamina.",
		# `item` is empty on purpose: the cord is the ward, so the skill is the
		# same on a bare body as on a blade and its damage figure is never read.
		"effect": {"kind": "ward", "absorb": 0.33, "stamina_scale": 1.6, "seconds": 5.0},
		"cues": [{"at": 0.20, "cue": "ward"}],
	},
	# The two consumables. They are not the kit's and not on the bar at all:
	# nothing is worn to grant them, so they are fired from the body's own two
	# keys (`Z` and `V`) and never take a hotbar slot from a skill. The body owns
	# the channel; the runner owns the key and the cooldown.
	{
		"id": "bandage",
		"name": "BANDAGE",
		"item": "",
		"slot": 0,
		"key": "Z",
		"stamina_cost": 0.0,
		"cooldown": 9.0,
		"duration": 0.0,
		"consume": "bandage",
		"icon": "res://assets/ui/abilities/bandage.png",
		"description": "Bind a wound: 35 health over three seconds, standing still.",
	},
	{
		"id": "healing_potion",
		"name": "HEALING POTION",
		"item": "",
		"slot": 0,
		"key": "V",
		"stamina_cost": 0.0,
		"cooldown": 12.0,
		"duration": 0.0,
		"consume": "potion",
		"icon": "res://assets/ui/abilities/healing_potion.png",
		"description": "Drink a healing potion: 50 health at once.",
	},
]

static var _icon_cache: Dictionary = {}
static var _starter_grants_cache: Dictionary = {}
static var _by_id: Dictionary = {}


static func _static_init() -> void:
	for ability: Dictionary in ABILITIES:
		_by_id[str(ability.id)] = ability


static func by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


## A melee skill swings the equipped blade, so it can only be performed
## standing: the crouch overlay would replace the authored clip's arms.
static func is_melee(definition: Dictionary) -> bool:
	return MELEE_EFFECTS.has(str(definition.get("effect", {}).get("kind", "")))


## Skills that cannot be performed from a crouch. A blade swings over the whole
## skeleton, and a committed dash would slide a folded-over body along the
## floor; only the casts keep the crouch layer.
static func needs_standing(definition: Dictionary) -> bool:
	return is_melee(definition) or float(definition.get("speed_scale", 0.0)) > 0.0


## A committed step travels down the crosshair instead of the body's heading.
static func follows_aim(definition: Dictionary) -> bool:
	return bool(definition.get("aim", false))


## Compact wire code for the animation/replication scalars. Index 0 is the
## first authored ability, so a packed zero never means a real ability.
static func index_of(id: String) -> int:
	for index in ABILITIES.size():
		if str(ABILITIES[index].id) == id:
			return index
	return -1


static func by_index(index: int) -> Dictionary:
	if index < 0 or index >= ABILITIES.size():
		return {}
	return ABILITIES[index]


## The item the rig is visibly holding in the main hand. Session weapon keys
## change the held mode, so the granted skill follows the hands, not the
## paperdoll's stowed kit.
static func main_item(rig) -> String:
	if not is_instance_valid(rig):
		return ""
	match str(rig.weapon):
		"bow":
			return BOW_ITEMS[clampi(int(rig.bow_index), 0, BOW_ITEMS.size() - 1)]
		"dagger":
			return "dagger_iron"
		"sword":
			if bool(rig.staff_active):
				return STAFF_ITEMS[clampi(int(rig.staff_index), 0, STAFF_ITEMS.size() - 1)]
			return SWORD_ITEMS[clampi(int(rig.sword_index), 0, SWORD_ITEMS.size() - 1)]
		"dual":
			return SWORD_ITEMS[clampi(int(rig.sword_index), 0, 1)]
	return ""



## The two consumables a body carries beside the bar: a bandage and a healing
## potion are worn by nobody and unlocked by nothing, so they cannot come from a
## piece and the player never assigns them. Each fires from its own body key
## (`Z`, `V`) - the bar is for skills alone.
const CONSUMABLE_IDS := ["bandage", "healing_potion"]


## The starter skills a body's hands earn. A family starter is automatic and
## free: the player never buys it, and a bow body that has never opened a skill
## still has Snap Shot. A body with a board and a one-handed sword wears three
## starters (sword, shield, the any-hand Focus); a greatsword earns only the
## two-hand starter, not the sword one as well.
static func starter_families(rig) -> Array[String]:
	var out: Array[String] = []
	if not is_instance_valid(rig):
		return out
	var weapon := str(rig.get("weapon"))
	if weapon.is_empty() or weapon == "none":
		out.append(TYPE_UNARMED)
	elif weapon == "bow":
		out.append(TYPE_BOW)
	elif weapon == "dagger":
		out.append(TYPE_DAGGER)
	elif bool(rig.get("staff_active")):
		out.append(TYPE_STAFF)
	elif weapon in ["sword", "dual"]:
		if rig.has_method("swings_two_handed") and bool(rig.swings_two_handed()):
			out.append(TYPE_TWO_HAND)
		else:
			out.append(TYPE_SWORD)
	if bool(rig.get("shield_equipped")) and not out.has(TYPE_SHIELD):
		out.append(TYPE_SHIELD)
	if not out.has(TYPE_ANY):
		out.append(TYPE_ANY)
	return out


## The same answer for a roster record with no body: the catalog rows.
static func starter_ids_for_gear(main: Dictionary, off: Dictionary) -> Array[String]:
	var families: Array[String] = []
	var category := str(main.get("category", ""))
	var kind := str(main.get("kind", ""))
	if main.is_empty():
		families.append(TYPE_UNARMED)
	elif category == "bow":
		families.append(TYPE_BOW)
	elif kind == "dagger":
		families.append(TYPE_DAGGER)
	elif category == "staff":
		families.append(TYPE_STAFF)
	elif kind == "sword":
		families.append(TYPE_TWO_HAND if category == "2h" else TYPE_SWORD)
	if str(off.get("category", "")) == "shield":
		families.append(TYPE_SHIELD)
	families.append(TYPE_ANY)
	return starter_ids_for_families(families)


static func starter_ids_for_families(families: Array) -> Array[String]:
	var out: Array[String] = []
	for family in families:
		var id := str(STARTER_BY_FAMILY.get(str(family), ""))
		if not id.is_empty() and not out.has(id):
			out.append(id)
	return out


## A player body carries the marker `PlayerState.build_loadout` writes; an AI
## body dressed without it gets no starter and keeps only the bare-hand fallback.
static func starter_enabled(rig) -> bool:
	if not is_instance_valid(rig):
		return false
	var id: Variant = rig.get("starter_ability")
	return id != null and not str(id).is_empty()


## The starter definitions the bar carries, each a copy marked `ai_cast: false`:
## the key is the player's, and an ally that casts it spends its own swing on a
## blast, which is a cadence nobody asked a squad to take up. Built once per id.
static func starter_grants(rig) -> Array:
	var out: Array = []
	if not starter_enabled(rig):
		return out
	for id in starter_ids_for_families(starter_families(rig)):
		var definition := by_id(id)
		if definition.is_empty():
			continue
		if not _starter_grants_cache.has(id):
			var copy := definition.duplicate(true)
			copy["ai_cast"] = false
			_starter_grants_cache[id] = copy
		out.append(_starter_grants_cache[id])
	return out


## How many keys this body's bar has: the five the game ships with, plus what the
## run's own upgrades bought it this session (`rig.ability_extra_slots`), never
## past `MAX_SLOT_COUNT`. The screen that draws the bar reads the same number, so
## a placeholder it shows is a key the fight can fire.
static func slots_for(rig) -> int:
	var extra := 0
	if is_instance_valid(rig):
		var raw: Variant = rig.get("ability_extra_slots")
		if raw is int or raw is float:
			extra = clampi(int(raw), 0, MAX_SLOT_COUNT - SLOT_COUNT)
	return SLOT_COUNT + extra


## The bar this body fires: one grant per key, and a skill sits on the key the
## player put it on. A key the player left empty stays empty, the family starters
## its hands earn fill the first free keys behind them, and the bare-hand charge
## takes the first free key when no starter did. A skill whose family tags do not
## fit the hands the body is holding right now is not drawn - switching a weapon
## set swaps the visible row without forgetting what the player assigned.
##
## The bandage and the potion are not on this bar: they have their own two keys on
## the body (`Z`/`V`), so a skill never has to share a key with medicine.
static func granted(rig) -> Array:
	if not is_instance_valid(rig):
		return []
	var out: Array = []
	for _slot in slots_for(rig):
		out.append({})
	var seen: Dictionary = {}
	var assigned := equipped_ids(rig.get("ability_loadout"))
	for index in mini(assigned.size(), out.size()):
		var id := str(assigned[index])
		if id.is_empty() or seen.has(id):
			continue
		var definition := by_id(id)
		if definition.is_empty() or not fits_rig(definition, rig):
			continue
		seen[id] = true
		out[index] = definition
	for starter in starter_grants(rig):
		var id := str(starter.get("id", ""))
		if id.is_empty() or seen.has(id) or not fits_rig(starter, rig):
			continue
		var free := _first_free(out)
		if free < 0:
			break
		seen[id] = true
		out[free] = starter
	# No main hand and no starter grant: the bare-handed charge is the one thing
	# an AI body has left to do.
	if main_item(rig).is_empty():
		var charge := by_id("charge")
		if not charge.is_empty() and not seen.has("charge"):
			var free := _first_free(out)
			if free >= 0:
				seen["charge"] = true
				out[free] = charge
	return out


## The first key in `out` that fires nothing, `-1` when the bar is full.
static func _first_free(out: Array) -> int:
	for index in out.size():
		if (out[index] as Dictionary).is_empty():
			return index
	return -1


## Sanitise an ability-id list: strings or arrays, duplicates and unknown ids
## dropped, order preserved.
static func skill_ids(value: Variant) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = []
	if value is String:
		raw = [value]
	elif value is Array:
		raw = value
	for item in raw:
		var id := str(item)
		if id.is_empty() or out.has(id) or by_id(id).is_empty():
			continue
		out.append(id)
	return out


## The ids a player has assigned to the bar, one per key: real catalog skills
## with the starter, the bare-hand fallback and the consumables removed, and an
## empty string for a key the player left empty - the *position* is the
## assignment, so a hole in the middle of the row is a deliberate empty key and
## never a reason for the skills behind it to slide forward.
static func equipped_ids(value: Variant) -> Array[String]:
	var out: Array[String] = []
	var raw: Array = []
	if value is String:
		raw = [value]
	elif value is Array:
		raw = value
	for item in raw:
		if out.size() >= MAX_SLOT_COUNT:
			break
		var id := str(item)
		if id.is_empty():
			out.append("")
			continue
		if is_automatic(id) or out.has(id) or by_id(id).is_empty():
			# A refused id keeps its key's position: dropping it would move the
			# skills behind it onto keys the player never chose.
			out.append("")
			continue
		out.append(id)
	while not out.is_empty() and out[out.size() - 1].is_empty():
		out.resize(out.size() - 1)
	return out


## The hand a catalog piece occupies when the altar labels it: a shield's is the
## off hand's, every other weapon's the main hand's.
static func hand_slot(entry: Dictionary) -> int:
	return 1 if str(entry.get("category", "")) == "shield" else 0


static func definition_for(rig, slot: int) -> Dictionary:
	var grants := granted(rig)
	if slot < 0 or slot >= grants.size():
		return {}
	return grants[slot]


static func damage_for(definition: Dictionary, rig) -> float:
	var item := str(definition.get("item", ""))
	if item.is_empty():
		# Unarmed charge does no damage; fall back to the held weapon so a
		# malformed definition cannot become a free heavy hit.
		item = main_item(rig)
	var effect: Dictionary = definition.get("effect", {})
	# A definition may author its own damage instead of a share of the item's, for
	# a skill whose price is not the piece it is fired from. Every ability in the
	# kit prices off its item: the base times `damage_scale`, then the rig's
	# channel (ranged, melee or spell) scales the result.
	var base := float(effect.get("damage", ITEM_DAMAGE.get(item, 0.0)))
	var damage := base * float(effect.get("damage_scale", 1.0))
	if not is_instance_valid(rig):
		return damage
	# Ranged trinkets scale arrows; melee trinkets scale blade skills and the
	# backstab; robe trinkets scale the staff's spells. The *item* the skill is
	# fired from decides which of the two ranged channels it rides, because a
	# bow's damage and a spell's damage are separate pools of modifiers. Every
	# scene reads this one function, so the frontier, the arena and the delve
	# cannot drift apart.
	match str(effect.get("kind", "")):
		"barrage", "volley", "piercing_shot", "projectile", "beam":
			if STAFF_ITEMS.has(item):
				return damage * spell_scale(rig)
			return damage * ranged_scale(rig) + flat_bonus(rig, "flat_ranged")
		"melee_arc", "melee_ring", "melee_wave", "backstab":
			var melee := damage * melee_scale(rig) + flat_bonus(rig, "flat_melee")
			if AXE_EFFECTS.has(str(effect.get("kind", ""))) and swings_an_axe(rig):
				melee *= AXE_ABILITY_SCALE
			return melee
	return damage


## True when the swinging hand holds an axe. The class is the rig's own answer -
## `swing_weapon_class` is the level every replica knows from the wire - so a
## skin that swaps the mesh keeps the rule, exactly as the throw's multiplier
## reads it.
static func swings_an_axe(rig) -> bool:
	if not is_instance_valid(rig) or not rig.has_method("swing_weapon_class"):
		return false
	return str(rig.swing_weapon_class("right")) == "axe"


## The echo trinkets shorten every skill's cooldown.
static func cooldown_scale(rig) -> float:
	if not is_instance_valid(rig):
		return 1.0
	var stats: Variant = rig.get("trinket_stats")
	if stats is Dictionary:
		return TrinketStats.cooldown_scale(stats)
	return 1.0


static func ranged_scale(rig) -> float:
	if not is_instance_valid(rig) or not rig.has_method("ranged_scale"):
		return 1.0
	return float(rig.ranged_scale())


static func melee_scale(rig) -> float:
	if not is_instance_valid(rig) or not rig.has_method("melee_scale"):
		return 1.0
	return float(rig.melee_scale())


## The robe channel: a staff's spells scale with `spell_damage` and with nothing
## the bow wears.
static func spell_scale(rig) -> float:
	if not is_instance_valid(rig) or not rig.has_method("spell_scale"):
		return 1.0
	return float(rig.spell_scale())


## Flat damage, additive after every multiplier, in the weapon's own class.
static func flat_bonus(rig, key: String) -> float:
	if not is_instance_valid(rig) or not rig.has_method("flat_bonus"):
		return 0.0
	var value: Variant = rig.flat_bonus(key)
	return float(value) if value != null else 0.0


## The ward block of a definition, or {} for every other skill.
static func ward(definition: Dictionary) -> Dictionary:
	var effect: Dictionary = definition.get("effect", {})
	if str(effect.get("kind", "")) != "ward":
		return {}
	return effect


static func icon_texture(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var path := str(by_id(id).get("icon", ""))
	var texture: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[id] = texture
	return texture
