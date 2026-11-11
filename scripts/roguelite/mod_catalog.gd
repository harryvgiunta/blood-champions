class_name RogueliteModCatalog
extends RefCounted
## The upgrade pool: 161 rows over five families and four tiers, and the ladder
## that decides which tier a surface may offer.
##
## Every row is data. The proc engine reads `stats` and `flags`, so a new mod is
## one dictionary here and nothing else - no branch in the engine, no scene code,
## no per-mod class. Values are *per stack* unless the field is a cap, a radius or
## a duration, which the engine takes at their largest rather than their sum
## (`ProcEngine.MAX_KEYS`); chance rows carry no number at all, only the key,
## because their curve is the engine's (`ProcEngine.HYPERBOLIC`).
##
## The tier is not power. It is where the row arrives: a reward chest carries
## commons, a boss's hoard and the stall carry legendaries.
## The ladder is the part of a loot system a player learns by playing, so it lives
## here, next to the rows it prices.
##
## The design this implements is `docs/upgrade-pool.md`. `ready: false` marks a row
## whose keys belong to a subsystem that has not landed yet (the mark ledger, phase
## 5, and the kit verbs' roll / parry / guard hooks, phase 4): the row is in the
## pool and in the design record, and it is never offered until its keys are read.

const RARITY_COMMON := "common"
const RARITY_EPIC := "epic"
const RARITY_LEGENDARY := "legendary"
const RARITY_GREED := "greed"
const RARITIES := [RARITY_COMMON, RARITY_EPIC, RARITY_LEGENDARY, RARITY_GREED]

const RARITY_COLOUR := {
	RARITY_COMMON: Color("cfd8c4"),
	RARITY_EPIC: Color("9fd0ff"),
	RARITY_LEGENDARY: Color("f2c862"),
	RARITY_GREED: Color("e0624f"),
}

## The families, in the order the plate and the card list them. The source's
## Weapon / Ability / Melee / Perk / Relic shape, re-cut to our verbs: a shot, a
## swing, an ability button, a body-wide passive and a rule.
const FAMILY_SHOT := "shot"
const FAMILY_HAND := "hand"
const FAMILY_ABILITY := "ability"
const FAMILY_PERK := "perk"
const FAMILY_RELIC := "relic"
const FAMILIES := [FAMILY_SHOT, FAMILY_HAND, FAMILY_ABILITY, FAMILY_PERK, FAMILY_RELIC]
const FAMILY_LABEL := {
	FAMILY_SHOT: "SHOT", FAMILY_HAND: "HAND", FAMILY_ABILITY: "ABILITY",
	FAMILY_PERK: "PERK", FAMILY_RELIC: "RELIC",
}

## What a gate promises: a **chest surface** — the category — and a tier. The
## source system's surfaces table, re-cut to our keys. A surface is a tag set, not
## a family: a row belongs to every surface it acts on, so Glass Cannon is a
## Damage chest's and a Health chest's at once, and a weapon row is a Weapons
## chest's wherever it sits in the pool.
##
## Eight surfaces hold a **shelf** of cards; `key` and `gear` are promises too,
## but they pay on the open and lay out no card at all, so they are the payout
## surfaces and never asked for a shelf. A gate promises one surface at one tier,
## and that tier is absolute: the chest lays out the tier on the label, or the
## gate does not make the promise.
const CHEST_WEAPONS := "weapons"
const CHEST_DAMAGE := "damage"
const CHEST_HEALTH := "health"
const CHEST_STAMINA := "stamina"
const CHEST_SPEED := "speed"
const CHEST_LUCK := "luck"
const CHEST_CRITICAL := "critical"
const CHEST_ABILITY := "ability"
const CHEST_ATTACK := "attack"
const CHEST_KEY := "key"
const CHEST_GEAR := "gear"
## The eight that own a shelf of **mod** cards: every row-bearing rule reads
## these. `ability` is not one of them any more - an ABILITY chest pays skills
## out of `ability_rules.gd`, not rows out of this pool.
const CARD_SURFACES := [CHEST_WEAPONS, CHEST_DAMAGE, CHEST_HEALTH,
	CHEST_STAMINA, CHEST_SPEED, CHEST_LUCK, CHEST_CRITICAL, CHEST_ATTACK]
## The two that pay without a card.
const PAYOUT_SURFACES := [CHEST_KEY, CHEST_GEAR]
## The one that pays something other than this catalog's rows: a player's skill.
const SKILL_SURFACES := [CHEST_ABILITY]
const CHEST_SURFACES := [CHEST_WEAPONS, CHEST_DAMAGE, CHEST_HEALTH,
	CHEST_STAMINA, CHEST_SPEED, CHEST_LUCK, CHEST_CRITICAL, CHEST_ABILITY,
	CHEST_ATTACK, CHEST_KEY, CHEST_GEAR]
const CHEST_SURFACE_LABEL := {
	CHEST_WEAPONS: "WEAPONS", CHEST_DAMAGE: "DAMAGE", CHEST_HEALTH: "HEALTH",
	CHEST_STAMINA: "STAMINA", CHEST_SPEED: "SPEED", CHEST_LUCK: "LUCK",
	CHEST_CRITICAL: "CRITICAL", CHEST_ABILITY: "ABILITY", CHEST_ATTACK: "ATTACK",
	CHEST_KEY: "KEY", CHEST_GEAR: "GEAR",
}

## A chest's payout: what a surface pays, and the two chests that carry no
## surface at all - a cache that auto-rolls one row, and a boss's hoard.
const PAYOUT_CARDS := "cards"
const PAYOUT_KEYS := "keys"
const PAYOUT_GEAR := "gear"
const PAYOUT_ROLL := "roll"
const PAYOUT_HOARD := "hoard"
## A skill, permanently, for one player: the ABILITY chest's own payout. The
## chest lays out three and the soul keeps one.
const PAYOUT_SKILLS := "skills"
const CHEST_SURFACE_PAYOUT := {
	CHEST_WEAPONS: PAYOUT_CARDS, CHEST_DAMAGE: PAYOUT_CARDS,
	CHEST_HEALTH: PAYOUT_CARDS, CHEST_STAMINA: PAYOUT_CARDS,
	CHEST_SPEED: PAYOUT_CARDS, CHEST_LUCK: PAYOUT_CARDS,
	CHEST_CRITICAL: PAYOUT_CARDS, CHEST_ABILITY: PAYOUT_SKILLS,
	CHEST_ATTACK: PAYOUT_CARDS, CHEST_KEY: PAYOUT_KEYS, CHEST_GEAR: PAYOUT_GEAR,
}
## How often the route promises a surface. A key buys a weapon for the rest of
## the player's life and a skill is that player's for as long as they play, so
## the two unlock surfaces are the rarest promises on the board - and the first
## chest of every island is an ability chest whatever the board rolled.
const CHEST_SURFACE_WEIGHT := {CHEST_KEY: 0.5, CHEST_ABILITY: 0.5, CHEST_GEAR: 0.8}

## What a key chest and a gear chest pay, by tier: the promise's own rank.
const PAYOUT_BY_TIER := {
	RARITY_COMMON: 1, RARITY_EPIC: 2, RARITY_LEGENDARY: 3,
}

## The weapon families a Weapons chest reads: the tags the ability kit rows carry.
const WEAPON_TAGS := ["bow", "staff", "sword", "two_hand", "dagger", "shield",
	"melee", "ranged"]

## The keys each stat surface reads, exactly as `proc_engine.stats()` names them.
## A row is on the surface when it writes one of these keys.
const CHEST_KEYS := {
	CHEST_DAMAGE: ["damage_mult", "melee_damage_mult", "flat_damage",
		"wave_damage", "spell_damage_mult", "throw_damage_mult",
		"ability_damage_mult", "damage_high_hp_mult", "damage_planted_mult",
		"damage_close_mult", "damage_far_mult", "damage_per_hp",
		"damage_per_gold", "damage_per_kill", "damage_per_island",
		"damage_per_stack", "damage_per_mark", "damage_on_kill", "aura_damage",
		"splash_frac", "explode_on_kill", "shock_on_hurt"],
	CHEST_HEALTH: ["max_hp_mult", "max_hp_flat", "max_hp_flat_on_hit",
		"heal_on_kill", "heal_on_clear", "heal_on_hit", "melee_lifesteal",
		"regen_hp_per_s", "regen_window", "damage_taken_mult",
		"mark_damage_taken_mult", "dodge_chance", "passive_block_chance",
		"guard_cost_mult"],
	# Stamina is the pool and what spends it: the ability buttons' cooldowns and
	# recasts, the guard's price, the roll's charges and the throw's own kit. It
	# is the widest shelf of the card surfaces because our run body spends stamina
	# on every verb it has.
	CHEST_STAMINA: ["ability_stamina_mult", "ability_cooldown_mult",
		"ability_recast_chance", "guard_cost_mult", "roll_charges", "roll_regen",
		"roll_refund_throw", "roll_repel", "roll_blades", "roll_blade_scale",
		"roll_distance", "move_mult", "parry_refund", "parry_window_add",
		"throw_charges_flat", "throw_regen_mult", "throw_delay",
		"throw_damage_mult", "throw_speed_mult", "throw_fan", "throw_fan_scale",
		"throw_burst_chance", "throw_stagger", "throw_spin", "throw_spin_radius",
		"throw_homing", "throw_void", "throw_void_radius", "triple_throw_chance",
		"double_burst_chance", "blast_radius"],
	# Speed is the body's own travel: the walk it crosses the island at, the roll,
	# the grounded side step and the sprint slide. It reads the three movement
	# state machines' own keys, so a movement row is a Speed card wherever its
	# family sits - `speed_demon` is a Perk and `ring_of_swiftness` a Relic, and
	# both are on this shelf.
	CHEST_SPEED: ["move_mult", "roll_distance", "roll_speed", "roll_charges",
		"roll_regen", "step_distance", "step_speed", "step_recovery",
		"slide_speed", "slide_duration"],
	CHEST_LUCK: ["luck", "drop_chance", "drop_mult", "chest_chance",
		"chest_offers", "chest_mods", "keep_offer", "extra_chest_kills",
		"extra_chest_islands", "shop_offers", "shop_discount", "currency_mult",
		"gold_on_hit", "gold_on_hit_taken", "levelup_per_island"],
	CHEST_CRITICAL: ["crit_chance", "crit_mult_flat", "mega_crit_chance",
		"mega_crit_mult", "crit_burst", "crit_burst_radius"],
	CHEST_ATTACK: ["attack_mult", "melee_attack_mult", "attack_on_kill",
		"attack_per_island", "proc_coeff_mult", "melee_reach", "melee_delay",
		"knockback_mult", "shot_size", "spread_add", "projectile_speed_mult",
		"projectile_bounce", "split_shots", "pierce", "pierce_growth",
		"ricochet", "homing", "arrow_split", "arrow_homing",
		"extra_arrow_chance", "bow_draw_mult", "bow_no_nock", "bow_spiral",
		"windup_per_shot", "windup_cap", "streak_per_hit", "streak_cap",
		"bleed_chance", "chain_chance", "arc_chance", "nova_chance",
		"scatter_chance", "mace_chance", "spike_chance", "double_chance",
		"bomb_chance", "whirlwind_chance"],
}
## Prefix rows: every mark a shaft or a claw applies is a basic attack's business.
const CHEST_PREFIX_KEYS := {CHEST_ATTACK: ["mark_", "death_mark_"]}
## Tag rows: a row carries the tag, the surface reads it.
const CHEST_TAG_KEYS := {CHEST_WEAPONS: WEAPON_TAGS}
## Family rows: basic attacks are the shot and hand families. The ability family
## - the throw/roll/guard/parry kit and the weapon kit - is not a surface any
## more: it arrives off a cache, the stall and the hoard, and the ABILITY chest
## belongs to `AbilityRules`.
const CHEST_FAMILY_KEYS := {
	CHEST_ATTACK: [FAMILY_SHOT, FAMILY_HAND],
}

## The surfaces a row belongs to, most specific first. Computed once with the
## catalog, so a chest never has to scan 161 rows to ask a question.
static func chest_surfaces_of(mod_id: String) -> Array[String]:
	_ensure()
	var cached: Variant = _surfaces.get(mod_id)
	if cached is Array:
		return cached
	return []


## One row's surfaces, from the three rules that define them: a family, a tag,
## or a key it writes. A row is on every surface it acts on.
static func _surfaces_for(row: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var family := str(row.get("family", ""))
	var row_tags: Array = row.get("tags", [])
	var stats: Dictionary = row.get("stats", {})
	for surface in CARD_SURFACES:
		if (CHEST_FAMILY_KEYS.get(surface, []) as Array).has(family):
			out.append(surface)
			continue
		var matched := false
		for tag in CHEST_TAG_KEYS.get(surface, []):
			if row_tags.has(str(tag)):
				matched = true
				break
		if not matched:
			for key in stats:
				var name := str(key)
				if (CHEST_KEYS.get(surface, []) as Array).has(name):
					matched = true
					break
				for prefix in CHEST_PREFIX_KEYS.get(surface, []):
					if name.begins_with(str(prefix)):
						matched = true
						break
				if matched:
					break
		if matched:
			out.append(surface)
	return out


## Whether a row is one a surface may lay out. An empty surface is the
## surfaceless cache, which takes whatever the ladder gives it.
static func in_chest_surface(mod_id: String, surface: String) -> bool:
	if surface.is_empty():
		return true
	return chest_surfaces_of(mod_id).has(surface)


# --- the shelf --------------------------------------------------------------

## The rows a surface holds at one tier that one hand can still take.
## `carrier_tags` narrows the shelf to the rows the body's hands fit and `taken`
## drops the rows it has already spent, because a chest deals its cards per body.
## Empty arguments ask the catalog's own question: the whole surface.
static func shelf(surface: String, tier: String,
		carrier_tags: Array = [], taken: Array = []) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for row in MODS:
		var id := str(row.id)
		if str(row.rarity) != tier or not ready_of(id):
			continue
		if taken.has(id):
			continue
		if not in_chest_surface(id, surface):
			continue
		if not row_fits_carrier(id, carrier_tags):
			continue
		out.append(id)
	return out


## A promise is a whole hand, not a card with a gate in front of it: a surface is
## only promised at a tier where it can lay out this many cards.
const SURFACE_MIN_ROWS := 3


# --- promises ---------------------------------------------------------------

## A gate's promise: a surface and the one tier the chest lays out. The pair is
## absolute - nothing downstream rolls the tier again - and the label the player
## reads is built from it.
static func promise(surface: String, tier: String) -> Dictionary:
	return {"surface": surface, "tier": tier}


## Whether a promise can be kept: it names a surface that holds a shelf at all,
## and every hand the chest is dealt to can still lay out a whole hand of it.
## `hands` is one `{"tags": ..., "taken": ...}` per body; empty asks the
## party-wide question. A party-wide row count once promised an Ability chest to a
## dagger body whose own epic shelf was bare, and a shelf a body had spent to its
## ceiling was promised just as blindly: both stood a chest with nothing in it.
static func keeps_promise(pr: Dictionary, hands: Array = []) -> bool:
	var surface := str(pr.get("surface", ""))
	var tier := str(pr.get("tier", ""))
	# A skill promise is kept by the catalog, not by this pool: the skills a body
	# may still be offered are the ledger's fact, so the per-body check happens
	# when the chest deals (the director's `_ability_offers`).
	if surface_payout(surface) == PAYOUT_SKILLS:
		return true
	if not CARD_SURFACES.has(surface):
		return not surface.is_empty() and surface_payout(surface) != ""
	if tier.is_empty():
		return false
	if hands.is_empty():
		return shelf(surface, tier).size() >= SURFACE_MIN_ROWS
	for hand in hands:
		var spec: Dictionary = hand
		if shelf(surface, tier, spec.get("tags", []),
				spec.get("taken", [])).size() < SURFACE_MIN_ROWS:
			return false
	return true


## The promise a gate rolls: the island's own tier, the rung an elite trial buys,
## and then the surface that can still keep it for every body in the party. The
## raise happens here and nowhere else, so the shelf a surface is checked against
## and the tier its chest lays out cannot drift apart.
##
## Greed is never a promise - it is the boss's hoard and the stall's bargain - and
## `taken` surfaces are only repeated once the rest of the board is spent.
static func roll_promise(rng: RandomNumberGenerator, island: int, luck: int,
		hands: Array = [], elite: bool = false,
		taken: Array = []) -> Dictionary:
	var tier := _roll_tier(rng, tier_weights(
		[RARITY_COMMON, RARITY_EPIC, RARITY_LEGENDARY], luck, island))
	if tier.is_empty():
		tier = RARITY_COMMON
	if elite:
		tier = raise_tier(tier)
	return promise(_roll_surface(rng, tier, hands, taken), tier)


## One step up the ladder: the elite trial's premium on a promise it priced.
static func raise_tier(tier: String) -> String:
	return RARITY_EPIC if tier == RARITY_COMMON else RARITY_LEGENDARY


## Which surface a gate promises at a tier: every surface that can keep that
## promise, weighted, and never one the board already carries while another is
## left. A repeat beats a promise the chest cannot keep.
static func _roll_surface(rng: RandomNumberGenerator, tier: String,
		hands: Array, taken: Array) -> String:
	var pool: Array[String] = []
	var weights: Array[float] = []
	for surface in CHEST_SURFACES:
		if taken.has(surface) or not keeps_promise(promise(surface, tier), hands):
			continue
		pool.append(surface)
		weights.append(float(CHEST_SURFACE_WEIGHT.get(surface, 1.0)))
	if pool.is_empty():
		for surface in CHEST_SURFACES:
			if keeps_promise(promise(surface, tier), hands):
				pool.append(surface)
				weights.append(float(CHEST_SURFACE_WEIGHT.get(surface, 1.0)))
	if pool.is_empty():
		return CHEST_ATTACK
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := rng.randf_range(0.0, total)
	var walked := 0.0
	for index in pool.size():
		walked += weights[index]
		if roll <= walked:
			return str(pool[index])
	return str(pool[pool.size() - 1])


## The cards a promise stands in front of one body: the promised surface's own
## shelf first, then the same tier across the pool until there are `count` of
## them. A chest never stands with one card in it, or none. The top-up only
## happens when the body's own shelf is short - rows it has spent to their
## ceiling, or a hand it swapped into after the gate was priced - and it keeps the
## part of the promise the player is owed: the tier on the label.
static func deal(rng: RandomNumberGenerator, pr: Dictionary, count: int = 3,
		exclude: Array = [], carrier_tags: Array = []) -> Array[String]:
	var tier := str(pr.get("tier", ""))
	var taken: Dictionary = {}
	for id in exclude:
		taken[str(id)] = true
	var out := _take_rows(rng, str(pr.get("surface", "")), tier, count, taken,
		carrier_tags)
	if out.size() >= count:
		return out
	out.append_array(_take_rows(rng, "", tier, count - out.size(), taken,
		carrier_tags))
	return out


## What a key chest or a gear chest pays on the open.
static func payout_count(tier: String) -> int:
	return maxi(1, int(PAYOUT_BY_TIER.get(tier, 1)))


## The piece-count a lower tier pays, and the set floor a higher one welds on.
static func tier_rank(tier: String) -> int:
	var index := [RARITY_COMMON, RARITY_EPIC, RARITY_LEGENDARY].find(tier)
	return maxi(0, index)


static func surface_label(surface: String) -> String:
	return str(CHEST_SURFACE_LABEL.get(surface, surface.to_upper()))


static func surface_payout(surface: String) -> String:
	return str(CHEST_SURFACE_PAYOUT.get(surface, ""))


## The ability family is not the active ability catalog: its rows are run upgrades
## to the throw, roll, guard and parry buttons, plus the weapon-family upgrades
## below. This is the verb each of the verb rows modifies, so an upgrade card, the
## ability index and the design record all name the same category. A verb row with
## no entry here is a catalog bug.
const VERB_TAGS := {
	"fleet_roll": "roll",
	"heavy_throw": "throw", "sticky_throw": "throw", "wide_burst": "throw",
	"braced_guard": "guard",
	"throw_shove": "throw", "throw_burst": "throw", "throw_ring": "throw",
	"grenadier": "throw", "triple_throw": "throw", "layered_throw": "throw",
	"repulsion": "roll", "black_hole": "throw", "ability_ring": "throw",
	"ammo_ring": "throw", "dagger_dash": "roll", "parry_master": "parry",
	"spinning_blade": "throw", "homing_blades": "throw",
}
## The verbs in display order.
const VERB_ORDER := ["throw", "roll", "guard", "parry"]

## Whether a row may be offered to a body carrying `carrier_tags` (the ability
## families its hands fit plus their groups). A row with no tags belongs to the
## original pool and is always legal; an ability row must share a tag with the
## carrier. An empty carrier list means "do not filter" (a party-wide shelf).
static func row_fits_carrier(mod_id: String, carrier_tags: Array) -> bool:
	if carrier_tags.is_empty():
		return true
	var row_tags := tags_of(mod_id)
	if row_tags.is_empty():
		return true
	for tag in row_tags:
		if carrier_tags.has(tag):
			return true
	return false


## The unpromised sources: where a row nobody promised comes from. Each one's
## tier list is the only thing that decides whether a tier can appear at all,
## which is what stops luck from opening a tier the source does not sell. A
## source is not a surface - a surface is what a gate promises.
const SOURCE_WELD := "weld"
const SOURCE_CACHE := "cache"
const SOURCE_HOARD := "hoard"
const SOURCE_STALL := "stall"

## The tier roll by island: `common / epic / legendary` out of 100, before luck.
## Island 5 and beyond holds the fifth row, so a run that never leaves the first
## island still sees a legendary once it earns one.
const LADDER := [
	{"common": 78.0, "epic": 22.0, "legendary": 0.0},
	{"common": 62.0, "epic": 34.0, "legendary": 4.0},
	{"common": 52.0, "epic": 38.0, "legendary": 10.0},
	{"common": 44.0, "epic": 40.0, "legendary": 16.0},
	{"common": 38.0, "epic": 40.0, "legendary": 22.0},
]
## One stack of luck moves six points from common into epic and four from epic
## into legendary. Legendary is floored at zero and capped, because a run that
## takes Streamer Loot four times must still see commons.
const LUCK_COMMON_TO_EPIC := 6.0
const LUCK_EPIC_TO_LEGENDARY := 4.0
const LUCK_LEGENDARY_CAP := 35.0
## The greed share a surface that carries greed carves out of the roll, from
## island 2 on: the boss's hoard and the stall are the two surfaces that sell it,
## so greed is a bargain the party buys and never a gate's promise.
const GREED_SHARE := 6.0

## The stall's price: `22 + 5 x level` for a common, and a flat surcharge by tier.
const SHOP_BASE := 22.0
const SHOP_STEP := 5.0
const TIER_SURCHARGE := {
	RARITY_COMMON: 0.0, RARITY_EPIC: 35.0, RARITY_LEGENDARY: 70.0, RARITY_GREED: 45.0,
}

## The whole pool. Rows are grouped by family, then tier, then the order the
## design table lists them.
const MODS := [
	# --- shot: the ranged hand ----------------------------------------------
	{
		"id": "broadhead", "name": "Broadhead", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "Each shaft carries a heavier point: +1 flat damage. Flat " +
"damage is what a light bow lacks most.",
		"stats": {"flat_damage": 1.0}, "flags": {},
	},
	{
		"id": "steady_draw", "name": "Steady Draw", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "A planted shot lands true: +12% shot damage while both " +
"feet are still.",
		"stats": {"damage_planted_mult": 0.12}, "flags": {},
	},
	{
		"id": "big_shot", "name": "Big Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "A fatter arrow: +40% size, +15% damage, and it flies 25% " +
"slower.",
		"stats": {"shot_size": 0.4, "damage_mult": 0.15,
			"projectile_speed_mult": -0.25}, "flags": {},
	},
	{
		"id": "blind_fire", "name": "Blind Fire", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Loosed without a sightline: +20% shot damage, but the fan " +
"opens by 9 degrees.",
		"stats": {"damage_mult": 0.2, "spread_add": 9.0}, "flags": {},
	},
	{
		"id": "wind_up", "name": "Wind Up", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "A hand that keeps working: +3% damage per shaft loosed in " +
"the last two seconds, up to fifteen.",
		"stats": {"windup_per_shot": 0.03, "windup_cap": 15.0}, "flags": {},
	},
	{
		"id": "streak", "name": "Hot Streak", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "Hit after hit: +4% damage per body struck in a row, up to " +
"twelve, and a miss wipes it.",
		"stats": {"streak_per_hit": 0.04, "streak_cap": 12.0}, "flags": {},
	},
	{
		"id": "ricochet", "name": "Ricochet", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "A shaft that lands begins again: it hops to one more body " +
"within 12 m at 70% damage, plus one hop a stack.",
		"stats": {"ricochet": 1.0}, "flags": {},
	},
	{
		"id": "fast_shot", "name": "Fast Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "A flat trajectory: +25% arrow speed and a quarter less " +
"drop over distance.",
		"stats": {"projectile_speed_mult": 0.25, "drop_mult": -0.25}, "flags": {},
	},
	{
		"id": "rapid_fire", "name": "Berserk Rate", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 10,
		"description": "+18% ranged fire rate and melee attack speed per stack.",
		"stats": {"attack_mult": 0.18}, "flags": {},
	},
	{
		"id": "heavy_caliber", "name": "Heavy Caliber", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+35% weapon damage and +40% knockback, but -10% fire " +
"rate.",
		"stats": {"damage_mult": 0.35, "knockback_mult": 0.4, "attack_mult": -0.1},
		"flags": {},
	},
	{
		"id": "bleed_shot", "name": "Sanguine Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5, "ready": false,
		"description": "The point opens a vein: hits apply 10 Bleed.",
		"stats": {"mark_stacks.bleed": 10.0}, "flags": {},
	},
	{
		"id": "burn_shot", "name": "Cinder Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5, "ready": false,
		"description": "The point carries an ember: hits apply 10 Burn.",
		"stats": {"mark_stacks.burn": 10.0}, "flags": {},
	},
	{
		"id": "chill_shot", "name": "Rime Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5, "ready": false,
		"description": "The point is cold enough to hurt: hits apply 10 Chill.",
		"stats": {"mark_stacks.chill": 10.0}, "flags": {},
	},
	{
		"id": "storm_shot", "name": "Wardens' Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5, "ready": false,
		"description": "The shaft carries the Watchers' charge: hits apply 10 " +
"Storm.",
		"stats": {"mark_stacks.storm": 10.0}, "flags": {},
	},
	{
		"id": "hex_shot", "name": "Hexed Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_COMMON, "max_stacks": 5, "ready": false,
		"description": "The shaft is cut with a curse: hits apply 10 Hex.",
		"stats": {"mark_stacks.hex": 10.0}, "flags": {},
	},
	{
		"id": "dagger_arc", "name": "Hatchet Arc", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 6,
		"description": "Chance on any landed blow to spin a throwing blade at a " +
"nearby body for 140% weapon damage.",
		"stats": {"arc_chance": 1.0}, "flags": {},
	},
	{
		"id": "arrow_nova", "name": "Thorn Nova", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "A landed shaft bursts a ring of eight splinters, and a " +
"kill does it outright, at 55% weapon damage.",
		"stats": {"nova_chance": 1.0}, "flags": {},
	},
	{
		"id": "aura_shot", "name": "Aura Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "The shaft drags a field of thorns: any body it passes " +
"takes 45% weapon damage a second for 3 s.",
		"stats": {"shot_aura_damage": 0.45, "shot_aura_duration": 3.0},
		"flags": {},
	},
	{
		"id": "chain_lightning", "name": "Blood Arc", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 6,
		"description": "Chance on hit to arc to three bodies for 40% weapon " +
"damage each; a stack adds a body.",
		"stats": {"chain_chance": 1.0}, "flags": {},
	},
	{
		"id": "scatter_shot", "name": "Scatter Burst", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "On impact the shaft splits into three smaller ones behind " +
"the body, each at 60% damage.",
		"stats": {"scatter_chance": 1.0}, "flags": {},
	},
	{
		"id": "piercing_wave", "name": "Piercing Wave", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "A slow crescent of wind follows the shot's line: the " +
"shaft passes through one more body a stack, and every body behind the first " +
"takes 15% more.",
		"stats": {"pierce": 1.0, "pierce_growth": 0.15}, "flags": {},
	},
	{
		"id": "mace_shot", "name": "Mace Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "Chance to loose a hafted head instead: 120% damage in a " +
"1.8 m burst and a committed stagger.",
		"stats": {"mace_chance": 1.0}, "flags": {},
	},
	{
		"id": "money_shot", "name": "Coin Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "Every landed blow pays: +1 gold, flat, whatever the body " +
"was worth.",
		"stats": {"gold_on_hit": 1.0}, "flags": {},
	},
	{
		"id": "health_shot", "name": "Leech Shot", "family": FAMILY_SHOT,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "A wound for a wound: the first landed blow each second " +
"restores 2 HP.",
		"stats": {"heal_on_hit": 2.0}, "flags": {},
	},
	{
		"id": "homing_bolts", "name": "Homing Bolts", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "The shaft turns in the air toward the nearest body inside " +
"the aim cone; each stack turns harder.",
		"stats": {"homing": 1.0}, "flags": {},
	},
	{
		"id": "sticky_charge", "name": "Blood Charge", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "A landed shaft plants a charge that detonates after 1.2 s " +
"for 120% weapon damage in a 3 m gore burst.",
		"stats": {"bomb_chance": 1.0}, "flags": {},
	},
	{
		"id": "split_shot", "name": "Arc Split", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 6,
		"description": "Every shot looses +1 shaft in a tight fan; the first is " +
"whole, each extra pays 85%.",
		"stats": {"split_shots": 1.0}, "flags": {},
	},
	{
		"id": "splash_shot", "name": "Splash Damage", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "What the point does not open, the pressure does: +40% of " +
"the blow in a 2.5 m spill.",
		"stats": {"splash_frac": 0.4, "splash_radius": 2.5}, "flags": {},
	},
	{
		"id": "spike_strike", "name": "Spike Strike", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "The ground answers the arrow: thorns erupt under the body " +
"for 70% weapon damage in 3 m.",
		"stats": {"spike_chance": 1.0}, "flags": {},
	},
	{
		"id": "double_tap", "name": "Double Tap", "family": FAMILY_SHOT,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "Chance a landed blow is booked twice: the whole hit again, " +
"procs and all.",
		"stats": {"double_chance": 1.0}, "flags": {},
	},

	# --- hand: the melee hand ------------------------------------------------
	{
		"id": "grim_harvest", "name": "Grim Harvest", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "Killing or gibbing a body restores 1 + stack HP.",
		"stats": {"heal_on_kill": 1.0}, "flags": {},
	},
	{
		"id": "blender", "name": "Blender", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "The arm keeps turning: +15% melee attack speed only, the " +
"bow is untouched.",
		"stats": {"melee_attack_mult": 0.15}, "flags": {},
	},
	{
		"id": "sharp_claws", "name": "Sharp Claws", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+15% melee damage. The hatchet's answer to a warden's " +
"reach.",
		"stats": {"melee_damage_mult": 0.15}, "flags": {},
	},
	{
		"id": "iron_claws", "name": "Iron Claws", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "+30% melee damage, but every swing takes 20% longer to " +
"come back around.",
		"stats": {"melee_damage_mult": 0.3, "melee_attack_mult": -0.2},
		"flags": {},
	},
	{
		"id": "big_claws", "name": "Big Claws", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "The cut reaches further: +0.35 m of melee reach, so a " +
"roll-back can still be answered.",
		"stats": {"melee_reach": 0.35}, "flags": {},
	},
	{
		"id": "time_claws", "name": "Slow Cut", "family": FAMILY_HAND,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "+45% melee damage, but the wound pays out over 1.2 s " +
"instead of on contact.",
		"stats": {"melee_damage_mult": 0.45, "melee_delay": 1.2}, "flags": {},
	},
	{
		"id": "bleed_claws", "name": "Flaying Edge", "family": FAMILY_HAND,
		"rarity": RARITY_EPIC, "max_stacks": 5, "ready": false,
		"description": "The blade is meant to open, not to close: melee hits " +
"apply 18 Bleed.",
		"stats": {"mark_stacks.bleed": 18.0}, "flags": {}, "scope": "melee",
	},
	{
		"id": "burn_claws", "name": "Ember Edge", "family": FAMILY_HAND,
		"rarity": RARITY_EPIC, "max_stacks": 5, "ready": false,
		"description": "A blade kept in the brazier: melee hits apply 18 Burn.",
		"stats": {"mark_stacks.burn": 18.0}, "flags": {}, "scope": "melee",
	},
	{
		"id": "storm_claws", "name": "Storm Edge", "family": FAMILY_HAND,
		"rarity": RARITY_EPIC, "max_stacks": 5, "ready": false,
		"description": "A blade that carries the wardens' charge: melee hits " +
"apply 18 Storm.",
		"stats": {"mark_stacks.storm": 18.0}, "flags": {}, "scope": "melee",
	},
	{
		"id": "melee_shockwave", "name": "Crescent Wave", "family": FAMILY_HAND,
		"rarity": RARITY_LEGENDARY, "max_stacks": 4,
		"description": "Every swing throws a short piercing crescent of wind and " +
"blood: 45% weapon damage, +15 points a stack.",
		"stats": {"wave_damage": 0.45, "wave_step": 0.15}, "flags": {},
	},
	{
		"id": "brawler", "name": "Brawler", "family": FAMILY_HAND,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "Both hands on the haft: +60% melee damage, -35% shot " +
"damage.",
		"stats": {"melee_damage_mult": 0.6, "damage_mult": -0.35}, "flags": {},
	},

	# --- kit: the throw, the guard, the roll, the bandage --------------------
	{
		"id": "fleet_roll", "name": "Fleet Roll", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 3, "ready": false,
		"description": "One more roll before the ground claims you: +1 roll " +
"charge on a 1.6 s regen.",
		"stats": {"roll_charges": 1.0, "roll_regen": 1.6}, "flags": {},
	},
	{
		"id": "heavy_throw", "name": "Heavy Throw", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "+25% thrown damage, but the piece travels 20% slower and " +
"drops harder.",
		"stats": {"throw_damage_mult": 0.25, "throw_speed_mult": -0.2},
		"flags": {},
	},
	{
		"id": "sticky_throw", "name": "Sticky Throw", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "The piece bites and waits: +45% throw damage, paid 0.6 s " +
"after it lands.",
		"stats": {"throw_damage_mult": 0.45, "throw_delay": 0.6}, "flags": {},
	},
	{
		"id": "wide_burst", "name": "Wide Burst", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "+0.7 m of blast radius on every thrown piece and every " +
"burst it leaves.",
		"stats": {"blast_radius": 0.7}, "flags": {},
	},
	{
		"id": "braced_guard", "name": "Braced Guard", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "The arm is set before the blow: guard costs 25% less " +
"stamina a second.",
		"stats": {"guard_cost_mult": -0.25}, "flags": {},
	},
	{
		"id": "throw_shove", "name": "Throw Shove", "family": FAMILY_ABILITY,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "A thrown piece parts the crowd: +40% knockback and a " +
"0.25 s stagger on every body it hits.",
		"stats": {"knockback_mult": 0.4, "throw_stagger": 0.25}, "flags": {},
	},
	{
		"id": "throw_burst", "name": "Burst Throw", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 4, "ready": false,
		"description": "The landing throws sparks: an eight-splinter ring at 55% " +
"weapon damage.",
		"stats": {"throw_burst_chance": 1.0}, "flags": {},
	},
	{
		"id": "throw_ring", "name": "Ring of Daggers", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 3, "ready": false,
		"description": "The piece comes apart into six blades fanned forward, 70% " +
"weapon damage each.",
		"stats": {"throw_fan": 6.0, "throw_fan_scale": 0.7}, "flags": {},
	},
	{
		"id": "grenadier", "name": "Grenadier", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 4, "ready": false,
		"description": "A deeper belt: +2 throw charges.",
		"stats": {"throw_charges_flat": 2.0}, "flags": {},
	},
	{
		"id": "triple_throw", "name": "Triple Throw", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 3, "ready": false,
		"description": "Chance to loose three pieces in one motion, the extras " +
"paying 70%.",
		"stats": {"triple_throw_chance": 1.0}, "flags": {},
	},
	{
		"id": "layered_throw", "name": "Layered Throw", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 3, "ready": false,
		"description": "Chance the landing bursts a second time for half the " +
"first.",
		"stats": {"double_burst_chance": 1.0}, "flags": {},
	},
	{
		"id": "repulsion", "name": "Repulsion", "family": FAMILY_ABILITY,
		"rarity": RARITY_EPIC, "max_stacks": 3, "ready": false,
		"description": "The roll turns arrows aside: enemy shafts inside 3 m are " +
"knocked off their line.",
		"stats": {"roll_repel": 3.0}, "flags": {},
	},
	{
		"id": "black_hole", "name": "Black Hole", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "The piece opens a 2.5 m void for 1.2 s that drags bodies " +
"in and deals 30% weapon damage every 0.25 s.",
		"stats": {"throw_void": 0.3, "throw_void_radius": 2.5}, "flags": {},
	},
	{
		"id": "ability_ring", "name": "Ability Ring", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "The belt refills itself: throw regen 40% faster.",
		"stats": {"throw_regen_mult": 0.4}, "flags": {},
	},
	{
		"id": "ammo_ring", "name": "Ammo Ring", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "A roll returns a piece to the hand: every roll restores " +
"one throw charge.",
		"stats": {"roll_refund_throw": 1.0}, "flags": {},
	},
	{
		"id": "dagger_dash", "name": "Dagger Dash", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "The roll throws a fan of five blades in the look " +
"direction, 60% weapon damage each.",
		"stats": {"roll_blades": 5.0, "roll_blade_scale": 0.6}, "flags": {},
	},
	{
		"id": "parry_master", "name": "Parry Master", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "The parry window widens by 0.06 s, and a parry returns a " +
"throw charge and 15 stamina.",
		"stats": {"parry_window_add": 0.06, "parry_refund": 1.0}, "flags": {},
	},
	{
		"id": "spinning_blade", "name": "Spinning Blade", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "A thrown piece that does not come down: it spins in place " +
"for 3 s, cutting 45% weapon damage a second in 2 m.",
		"stats": {"throw_spin": 0.45, "throw_spin_radius": 2.0}, "flags": {},
	},
	{
		"id": "homing_blades", "name": "Homing Blades", "family": FAMILY_ABILITY,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2, "ready": false,
		"description": "The thrown piece decides for itself: it curves to the " +
"nearest body and strikes for 130%.",
		"stats": {"throw_homing": 1.0, "throw_damage_mult": 0.3}, "flags": {},
	},

	# --- ability: the weapon-family upgrades --------------------------------
	# Every row here writes a key the ability runtime reads. `tags` says which
	# ability family carries it; a group tag - melee, ranged - is the shared
	# reading between its families. None of these is a passive body perk.
	{
		"id": "echo_cast", "name": "Echo Cast", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "A cast sometimes repeats itself: a chance for any " +
"ability to activate a second time.",
		"stats": {"ability_recast_chance": 1.0}, "flags": {},
	},
	{
		"id": "quickening", "name": "Quickening", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "Ability cooldowns 7% shorter a stack.",
		"stats": {"ability_cooldown_mult": -0.07}, "flags": {},
	},
	{
		"id": "focused_force", "name": "Focused Force", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+10% ability damage.",
		"stats": {"ability_damage_mult": 0.1}, "flags": {},
	},
	{
		"id": "light_hands", "name": "Light Hands", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Abilities cost 10% less stamina.",
		"stats": {"ability_stamina_mult": -0.1}, "flags": {},
	},
	{
		"id": "broad_arc", "name": "Broad Arc", "family": FAMILY_ABILITY,
		"tags": ["melee"], "rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "A melee ability reaches one more body.",
		"stats": {"ability_cleave": 1.0}, "flags": {},
	},
	{
		"id": "bloodletting", "name": "Bloodletting", "family": FAMILY_ABILITY,
		"tags": ["melee"], "rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "Melee hits have a chance to open a bleed.",
		"stats": {"bleed_chance": 0.05}, "flags": {},
	},
	{
		"id": "duelists_grace", "name": "Duelist's Grace", "family": FAMILY_ABILITY,
		"tags": ["sword"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Sword cooldowns 6% shorter a stack.",
		"stats": {"ability_cooldown_mult": -0.06}, "flags": {},
	},
	{
		"id": "serrated_edge", "name": "Serrated Edge", "family": FAMILY_ABILITY,
		"tags": ["sword"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Sword hits have a chance to bleed.",
		"stats": {"bleed_chance": 0.05}, "flags": {},
	},
	{
		"id": "opening_vein", "name": "Opening Vein", "family": FAMILY_ABILITY,
		"tags": ["dagger"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Dagger hits have a chance to bleed.",
		"stats": {"bleed_chance": 0.05}, "flags": {},
	},
	{
		"id": "quick_hands", "name": "Quick Hands", "family": FAMILY_ABILITY,
		"tags": ["dagger"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "Dagger cooldowns 7% shorter a stack.",
		"stats": {"ability_cooldown_mult": -0.07}, "flags": {},
	},
	{
		"id": "arcane_focus", "name": "Arcane Focus", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+10% spell damage.",
		"stats": {"spell_damage_mult": 0.1}, "flags": {},
	},
	{
		"id": "guardians_instinct", "name": "Guardian's Instinct",
		"family": FAMILY_ABILITY, "tags": ["shield"], "rarity": RARITY_COMMON,
		"max_stacks": 5,
		"description": "A shield blocks attacks even when not raised, up to 75%.",
		"stats": {"passive_block_chance": 0.05}, "flags": {},
	},
	{
		"id": "double_nock", "name": "Double Nock", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "A chance to loose an extra arrow on the draw.",
		"stats": {"extra_arrow_chance": 0.1}, "flags": {},
	},
	{
		"id": "quick_draw", "name": "Quick Draw", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "Bow draw time 10% shorter a stack.",
		"stats": {"bow_draw_mult": 0.1}, "flags": {},
	},
	{
		"id": "piercing_points", "name": "Piercing Points", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "Bow shots pass through one more body.",
		"stats": {"ability_pierce": 1.0}, "flags": {},
	},
	{
		"id": "long_flight", "name": "Long Flight", "family": FAMILY_ABILITY,
		"tags": ["ranged"], "rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "Ranged projectiles fly 15% faster.",
		"stats": {"ability_speed_mult": 0.15}, "flags": {},
	},
	{
		"id": "whirling_fury", "name": "Whirling Fury", "family": FAMILY_ABILITY,
		"tags": ["two_hand"], "rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "A landed two-hand hit has a chance to whirlwind.",
		"stats": {"whirlwind_chance": 0.05}, "flags": {},
	},
	{
		"id": "cleaving_steel", "name": "Cleaving Steel", "family": FAMILY_ABILITY,
		"tags": ["sword"], "rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "A melee ability reaches one more body a stack.",
		"stats": {"ability_cleave": 1.0}, "flags": {},
	},
	{
		"id": "heavy_arc", "name": "Heavy Arc", "family": FAMILY_ABILITY,
		"tags": ["two_hand"], "rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "A two-hand ability reaches one more body a stack.",
		"stats": {"ability_cleave": 1.0}, "flags": {},
	},
	{
		"id": "momentum", "name": "Momentum", "family": FAMILY_ABILITY,
		"tags": ["two_hand"], "rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "+18% two-hand ability damage.",
		"stats": {"ability_damage_mult": 0.18}, "flags": {},
	},
	{
		"id": "heavy_robes", "name": "Heavy Robes", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "The robe is a trade: -25% melee damage, +10% spell damage.",
		"stats": {"melee_damage_mult": -0.25, "spell_damage_mult": 0.1},
		"flags": {},
	},
	{
		"id": "spell_siphon", "name": "Spell Siphon", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Staff casts have a chance to repeat.",
		"stats": {"ability_recast_chance": 1.0}, "flags": {},
	},
	{
		"id": "piercing_hex", "name": "Piercing Hex", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Spells pierce one more body.",
		"stats": {"ability_pierce": 1.0}, "flags": {},
	},
	{
		"id": "ember_spread", "name": "Ember Spread", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "Spell blasts are 0.35 m wider a stack.",
		"stats": {"ability_radius": 0.35}, "flags": {},
	},
	{
		"id": "bulwark", "name": "Bulwark", "family": FAMILY_ABILITY,
		"tags": ["shield"], "rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "A stronger passive block chance, still capped at 75%.",
		"stats": {"passive_block_chance": 0.05}, "flags": {},
	},
	{
		"id": "shield_force", "name": "Shield Force", "family": FAMILY_ABILITY,
		"tags": ["shield"], "rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "+15% shield ability damage.",
		"stats": {"ability_damage_mult": 0.15}, "flags": {},
	},
	{
		"id": "spiral_shot", "name": "Spiral Shot", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "Arrows corkscrew in flight and hit 15% harder.",
		"stats": {"bow_spiral": 1.0, "ability_damage_mult": 0.15}, "flags": {},
	},
	{
		"id": "split_fletching", "name": "Split Fletching", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Each shot looses an extra arrow at 25% damage.",
		"stats": {"arrow_split": 1.0}, "flags": {},
	},
	{
		"id": "bouncing_arrows", "name": "Bouncing Arrows", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Arrows fold to another body after the first.",
		"stats": {"projectile_bounce": 1.0}, "flags": {},
	},
	{
		"id": "homing_fletching", "name": "Homing Fletching", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Arrows steer toward the nearest body.",
		"stats": {"arrow_homing": 1.0}, "flags": {},
	},
	{
		"id": "ricochet_rounds", "name": "Ricochet Rounds", "family": FAMILY_ABILITY,
		"tags": ["ranged"], "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "Ranged projectiles fold to a second body.",
		"stats": {"projectile_bounce": 1.0}, "flags": {},
	},
	{
		"id": "overcharge", "name": "Overcharge", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "+30% ability damage.",
		"stats": {"ability_damage_mult": 0.3}, "flags": {},
	},
	{
		"id": "chain_cast", "name": "Chain Cast", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_LEGENDARY, "max_stacks": 4,
		"description": "A much greater chance for an ability to activate twice.",
		"stats": {"ability_recast_chance": 1.0}, "flags": {},
	},
	{
		"id": "battle_trance", "name": "Battle Trance", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "Ability cooldowns 12% shorter a stack.",
		"stats": {"ability_cooldown_mult": -0.12}, "flags": {},
	},
	{
		"id": "arcane_surge", "name": "Arcane Surge", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_LEGENDARY, "max_stacks": 4,
		"description": "+22% spell damage.",
		"stats": {"spell_damage_mult": 0.22}, "flags": {},
	},
	{
		"id": "shield_wall", "name": "Shield Wall", "family": FAMILY_ABILITY,
		"tags": ["shield"], "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "A large passive block chance, capped at 75%.",
		"stats": {"passive_block_chance": 0.05}, "flags": {},
	},
	{
		"id": "whirlwind_edge", "name": "Whirlwind Edge", "family": FAMILY_ABILITY,
		"tags": ["two_hand"], "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "A large chance for a two-hand hit to whirlwind.",
		"stats": {"whirlwind_chance": 0.05}, "flags": {},
	},
	{
		"id": "magical_nock", "name": "Magical Nock", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_LEGENDARY, "max_stacks": 1,
		"description": "Arrows nock themselves: no reach for the quiver, no " +
"re-nock. The string still has to be drawn.",
		"stats": {"bow_no_nock": 1.0}, "flags": {},
	},
	{
		"id": "bloodstorm", "name": "Bloodstorm", "family": FAMILY_ABILITY,
		"tags": ["melee"], "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "Melee hits bleed and can whirlwind in the same breath.",
		"stats": {"bleed_chance": 0.05, "whirlwind_chance": 0.05}, "flags": {},
	},
	{
		"id": "spellstorm", "name": "Spellstorm", "family": FAMILY_ABILITY,
		"tags": ["staff"], "rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "Staff casts repeat and hit 15% harder.",
		"stats": {"ability_recast_chance": 1.0, "spell_damage_mult": 0.15},
		"flags": {},
	},
	{
		"id": "hunters_focus", "name": "Hunter's Focus", "family": FAMILY_ABILITY,
		"tags": ["bow"], "rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "An extra arrow and a chance for one more.",
		"stats": {"arrow_split": 1.0, "extra_arrow_chance": 0.1}, "flags": {},
	},
	# The bar's own upgrade: one more skill key for this run, held open as a
	# placeholder until a skill is put on it. Five cards take the bar from its five
	# keys to ten, and the ceiling is the run's, not the card's - `hotbar_slots` is
	# clamped by `AbilityRules.MAX_SLOT_COUNT` on the rig that fires it.
	{
		"id": "widened_bar", "name": "Widened Bar", "family": FAMILY_ABILITY,
		"tags": ["any"], "rarity": RARITY_LEGENDARY, "max_stacks": 5,
		"description": "One more skill key for this run, up to ten. The key waits " +
"empty until a skill is put on it.",
		"stats": {"hotbar_slots": 1.0}, "flags": {},
	},

	# --- perk: the body ------------------------------------------------------
	{
		"id": "vitality", "name": "Vitality", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "+10 max HP. A quarter of the pool of a body that has " +
"taken four.",
		"stats": {"max_hp_flat": 10.0}, "flags": {},
	},
	{
		"id": "thick_blood", "name": "Thick Blood", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "+8% max HP multiplier, which also scales the flat HP a " +
"plate gave you.",
		"stats": {"max_hp_mult": 0.08}, "flags": {},
	},
	{
		"id": "fortified_plate", "name": "Fortified Plate", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "+25 max HP, and 10% of the pool comes back when the " +
"island is cleared.",
		"stats": {"max_hp_flat": 25.0, "heal_on_clear": 0.1}, "flags": {},
	},
	{
		"id": "field_dressing", "name": "Field Dressing", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "A bandage between islands instead of a prayer: heal 6% of " +
"the pool on every clear.",
		"stats": {"heal_on_clear": 0.06}, "flags": {},
	},
	{
		"id": "blood_high", "name": "Blood High", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "+20% damage while above 75% health. Reward for a body " +
"that is not being hit.",
		"stats": {"damage_high_hp_mult": 0.2}, "flags": {},
	},
	{
		"id": "regenerator", "name": "Regenerator", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "0.4 HP a second while a wave is live, for the first 60 s " +
"of it.",
		"stats": {"regen_hp_per_s": 0.4, "regen_window": 60.0}, "flags": {},
	},
	{
		"id": "hard_target", "name": "Hard Target", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "Incoming damage -5% a stack, toward a floor of a quarter " +
"of the blow.",
		"stats": {"damage_taken_mult": -0.05}, "flags": {},
	},
	{
		"id": "speed_demon", "name": "Speed Demon", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "+5% movement speed.",
		"stats": {"move_mult": 0.05}, "flags": {},
	},
	{
		"id": "crit_sharpshooter", "name": "Critical Sharpshooter",
		"family": FAMILY_PERK, "rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+12% crit chance; a crit deals 2.0x and rolls its procs " +
"twice.",
		"stats": {"crit_chance": 0.12}, "flags": {},
	},
	{
		"id": "anti_crit", "name": "Anti Crit", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "+18% damage and -10% crit chance: the trade for a body " +
"that never liked dice.",
		"stats": {"damage_mult": 0.18, "crit_chance": -0.1}, "flags": {},
	},
	{
		"id": "power_punch", "name": "Power Punch", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 6,
		"description": "+0.20 to the crit multiplier, so a crit pays 2.2x and " +
"then 2.4x.",
		"stats": {"crit_mult_flat": 0.2}, "flags": {},
	},
	{
		"id": "collectors_bounty", "name": "Collector's Bounty",
		"family": FAMILY_PERK, "rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "+25% gold from every kill and chest.",
		"stats": {"currency_mult": 0.25}, "flags": {},
	},
	{
		"id": "special_delivery", "name": "Special Delivery", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 2,
		"description": "The stall lays out one more ware.",
		"stats": {"shop_offers": 1.0}, "flags": {},
	},
	{
		"id": "streamer_loot", "name": "Streamer Loot", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "+1 luck: the tier roll leans away from common and toward " +
"epic, and epic toward legendary.",
		"stats": {"luck": 1.0}, "flags": {},
	},
	{
		"id": "danger_close", "name": "Danger Close", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "+15% damage to bodies inside 6 m. The hatchet's whole " +
"world.",
		"stats": {"damage_close_mult": 0.15, "close_range": 6.0}, "flags": {},
	},
	{
		"id": "eagle_eye", "name": "Eagle Eye", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "+12% damage to bodies beyond 12 m. The bow's whole world.",
		"stats": {"damage_far_mult": 0.12, "far_range": 12.0}, "flags": {},
	},
	{
		"id": "mark_expert", "name": "Elemental Expert", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 4, "ready": false,
		"description": "+8% damage per different mark on the body, up to four.",
		"stats": {"damage_per_mark": 0.08}, "flags": {},
	},
	{
		"id": "featherstep", "name": "Featherstep", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 8,
		"description": "A step that is never quite where the blow lands: +10% " +
"dodge, hyperbolic toward 60%.",
		"stats": {"dodge_chance": 1.0}, "flags": {},
	},
	{
		"id": "lightfoot", "name": "Lightfoot", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 4,
		"description": "The side step carries a half pace further: +0.30 m of " +
"travel on every step.",
		"stats": {"step_distance": 0.30}, "flags": {},
	},
	{
		"id": "spring_step", "name": "Spring Step", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "The step comes back sooner: 15% off its recovery, so it " +
"chains a beat earlier.",
		"stats": {"step_recovery": 0.15}, "flags": {},
	},
	{
		"id": "quick_heel", "name": "Quick Heel", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "The same step, taken quicker: +15% side step speed, same " +
"distance off the same floor.",
		"stats": {"step_speed": 0.15}, "flags": {},
	},
	{
		"id": "skirmish_legs", "name": "Skirmish Legs", "family": FAMILY_PERK,
		"rarity": RARITY_COMMON, "max_stacks": 5,
		"description": "The walk keeps up with the fight: +4% movement speed and " +
"0.10 m more on every side step.",
		"stats": {"move_mult": 0.04, "step_distance": 0.10}, "flags": {},
	},
	{
		"id": "health_is_power", "name": "Health Is Power", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "+1% damage per 10 HP you are carrying.",
		"stats": {"damage_per_hp": 0.01}, "flags": {},
	},
	{
		"id": "money_is_power", "name": "Money Is Power", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "+1% damage per 100 gold in the purse.",
		"stats": {"damage_per_gold": 0.01}, "flags": {},
	},
	{
		"id": "checklist", "name": "Checklist", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "+1% damage per 20 bodies put down this run.",
		"stats": {"damage_per_kill": 0.01}, "flags": {},
	},
	{
		"id": "gemstone", "name": "Gemstone", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "+10% damage for each island already cleared. A run's own " +
"momentum.",
		"stats": {"damage_per_island": 0.1}, "flags": {},
	},
	{
		"id": "collector", "name": "Collector", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "+2% damage per upgrade stack you carry, whatever its " +
"family.",
		"stats": {"damage_per_stack": 0.02}, "flags": {},
	},
	{
		"id": "damage_aura", "name": "Damage Aura", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 5,
		"description": "A standing field of blood: 6 damage a second to " +
"everything inside 3.5 m.",
		"stats": {"aura_damage": 6.0, "aura_radius": 3.5}, "flags": {},
	},
	{
		"id": "shockwave", "name": "Shockwave", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "A blow landed on you answers with a ring: 80% weapon " +
"damage in 4 m, through cover.",
		"stats": {"shock_on_hurt": 0.8, "shock_radius": 4.0}, "flags": {},
	},
	{
		"id": "exploding_enemies", "name": "Exploding Enemies",
		"family": FAMILY_PERK, "rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "A dying body bursts for 25% of its own max HP in a 3 m " +
"circle.",
		"stats": {"explode_on_kill": 0.25, "explode_radius": 3.0}, "flags": {},
	},
	{
		"id": "big_chests", "name": "Big Chests", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "The reward chest lays out one more card.",
		"stats": {"chest_offers": 1.0}, "flags": {},
	},
	{
		"id": "crit_blast", "name": "Critical Blast", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "A crit bursts for 60% of the blow in 2.5 m.",
		"stats": {"crit_burst": 0.6, "crit_burst_radius": 2.5}, "flags": {},
	},
	{
		"id": "mega_crit", "name": "Mega Crit", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "12% chance a crit becomes a mega crit at 3.0x instead of " +
"2.0x.",
		"stats": {"mega_crit_chance": 1.0, "mega_crit_mult": 3.0}, "flags": {},
	},
	{
		"id": "bonus_chest", "name": "Buried Cache", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 6,
		"description": "15% chance per stack that clearing a level buries a " +
"mini-chest beside the reward.",
		"stats": {"chest_chance": 1.0}, "flags": {},
	},
	{
		"id": "rolling_start", "name": "Rolling Start", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 4,
		"description": "The roll leaves the ground faster: +12% roll speed, and " +
"the same clock carries it further.",
		"stats": {"roll_speed": 0.12}, "flags": {},
	},
	{
		"id": "hunter_pace", "name": "Hunter's Pace", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "A long stride that keeps: +10% movement speed, walk and " +
"sprint alike.",
		"stats": {"move_mult": 0.10}, "flags": {},
	},
	{
		"id": "low_slide", "name": "Low Slide", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "The sprint slide runs a fifth longer: +18% of its own " +
"length, same low profile.",
		"stats": {"slide_duration": 0.18}, "flags": {},
	},
	{
		"id": "slipstream", "name": "Slipstream", "family": FAMILY_PERK,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "The slide starts and ends quicker: +12% slide speed.",
		"stats": {"slide_speed": 0.12}, "flags": {},
	},
	{
		"id": "rare_treasure", "name": "Rare Treasure", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "A body has a 3% chance a stack to leave a small cache " +
"holding one upgrade card, for whoever reaches it.",
		"stats": {"drop_chance": 1.0}, "flags": {},
	},
	{
		"id": "level_up", "name": "Level Up", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "After every island, two carried upgrades gain a stack. " +
"The cheapest power in the pool.",
		"stats": {"levelup_per_island": 2.0}, "flags": {},
	},
	{
		"id": "bonus_chests", "name": "Bonus Chests", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "A reward chest every 25 kills, on top of the level's own.",
		"stats": {"extra_chest_kills": 25.0}, "flags": {},
	},
	{
		"id": "care_package", "name": "Care Package", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 1,
		"description": "An extra chest after every third island.",
		"stats": {"extra_chest_islands": 3.0}, "flags": {},
	},
	{
		"id": "faulty_chests", "name": "Faulty Chests", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "A chest card you did not take stays on the ground as a " +
"pickup, once a card a stack.",
		"stats": {"keep_offer": 1.0}, "flags": {},
	},
	{
		"id": "conducting_bodies", "name": "Conducting Bodies",
		"family": FAMILY_PERK, "rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"ready": false,
		"description": "A body put down discharges 25 Storm into everything within " +
"5 m.",
		"stats": {"death_marks.storm": 25.0, "death_mark_radius": 5.0},
		"flags": {},
	},
	{
		"id": "long_roll", "name": "Long Roll", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "The roll becomes a dive: +1.5 m of travel on every one, " +
"on the roll's own clock.",
		"stats": {"roll_distance": 1.5}, "flags": {},
	},
	{
		"id": "thoroughbred", "name": "Thoroughbred", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "The island is crossed at a canter: +22% movement speed.",
		"stats": {"move_mult": 0.22}, "flags": {},
	},
	{
		"id": "ground_skimmer", "name": "Ground Skimmer", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 2,
		"description": "The slide skims further and faster: +25% of its speed and " +
"of its length together.",
		"stats": {"slide_speed": 0.25, "slide_duration": 0.25}, "flags": {},
	},
	{
		"id": "glass_cannon", "name": "Glass Cannon", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 5,
		"description": "Deal +100% all damage and lose 40% of your max HP.",
		"stats": {"damage_mult": 1.0, "max_hp_mult": -0.4}, "flags": {},
	},
	{
		"id": "rising_star", "name": "Rising Star", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+75% gold, and a fifth again as many bodies on every " +
"level.",
		"stats": {"currency_mult": 0.75, "enemy_count_mult": 0.2}, "flags": {},
	},
	{
		"id": "juggernaut", "name": "Juggernaut", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+35% max HP, and the wave comes heavier: +25% bodies.",
		"stats": {"max_hp_mult": 0.35, "enemy_count_mult": 0.25}, "flags": {},
	},
	{
		"id": "up_the_ante", "name": "Up The Ante", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+45% damage, +30% bodies, and the wave moves 15% faster.",
		"stats": {"damage_mult": 0.45, "enemy_count_mult": 0.3,
			"enemy_speed_mult": 0.15}, "flags": {},
	},
	{
		"id": "double_trouble", "name": "Double Trouble", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+40% max HP, and every body arrives with +30% HP of its " +
"own.",
		"stats": {"max_hp_mult": 0.4, "enemy_health_mult": 0.3}, "flags": {},
	},
	{
		"id": "bribe", "name": "Bribe", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+50% max HP, but a landed blow costs you 8 gold.",
		"stats": {"max_hp_mult": 0.5, "gold_on_hit_taken": 8.0}, "flags": {},
	},
	{
		"id": "damage_seeker", "name": "Damage Seeker", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+60% damage, but a landed blow costs you 3 max HP for " +
"the rest of the run.",
		"stats": {"damage_mult": 0.6, "max_hp_flat_on_hit": -3.0}, "flags": {},
	},
	{
		"id": "brute_force", "name": "Brute Force", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+50% damage out and +30% damage in. The pool and the " +
"purse both run hotter.",
		"stats": {"damage_mult": 0.5, "damage_taken_mult": 0.3}, "flags": {},
	},
	{
		"id": "slippery_slope", "name": "Slippery Slope", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 3,
		"description": "+100% gold, but you bleed 2% of your max HP a second " +
"while standing still in a live wave.",
		"stats": {"currency_mult": 1.0, "standing_drain": 0.02}, "flags": {},
	},
	{
		"id": "hoarder", "name": "Hoarder", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 2,
		"description": "An extra chest every island, but the reward chest lays " +
"out two cards from now on.",
		"stats": {"extra_chest_islands": 1.0, "chest_offers": -1.0},
		"flags": {},
	},
	{
		"id": "bloodthirst", "name": "Bloodthirst", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 2,
		"description": "No more breathing between islands: passive heals stop and " +
"+300% melee lifesteal replaces them.",
		"stats": {"melee_lifesteal": 3.0}, "flags": {"bloodthirst": true},
	},
	{
		"id": "cursed_arsenal", "name": "Cursed Arsenal", "family": FAMILY_PERK,
		"rarity": RARITY_GREED, "max_stacks": 2,
		"description": "The hands lock for the run: +150% weapon damage and +50% " +
"proc coefficient on what you hold.",
		"stats": {"damage_mult": 1.5, "proc_coeff_mult": 0.5},
		"flags": {"hands_locked": true},
	},

	# --- relic: one unique rule each -----------------------------------------
	{
		"id": "coral_amulet", "name": "Coral Amulet", "family": FAMILY_RELIC,
		"rarity": RARITY_COMMON, "max_stacks": 2,
		"description": "The reward chest gives one more upgrade card, not one " +
"more choice.",
		"stats": {"chest_mods": 1.0}, "flags": {},
	},
	{
		"id": "adrenaline_amulet", "name": "Adrenaline Amulet",
		"family": FAMILY_RELIC, "rarity": RARITY_COMMON, "max_stacks": 3,
		"description": "+25% attack rate for 4 s after every kill.",
		"stats": {"attack_on_kill": 0.25}, "flags": {},
	},
	{
		"id": "ring_of_defense", "name": "Ring Of Defense", "family": FAMILY_RELIC,
		"rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "Incoming damage -18%, stacking to a floor of a quarter of " +
"the blow.",
		"stats": {"damage_taken_mult": -0.18}, "flags": {},
	},
	{
		"id": "turbo_ring", "name": "Turbo Ring", "family": FAMILY_RELIC,
		"rarity": RARITY_EPIC, "max_stacks": 3,
		"description": "+3% attack rate for every island cleared, kept for the " +
"run.",
		"stats": {"attack_per_island": 0.03}, "flags": {},
	},
	{
		"id": "ring_of_fury", "name": "Ring Of Fury", "family": FAMILY_RELIC,
		"rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "+40% weapon damage for 4 s after every kill.",
		"stats": {"damage_on_kill": 0.4}, "flags": {},
	},
	{
		"id": "ring_of_precision", "name": "Ring Of Precision",
		"family": FAMILY_RELIC, "rarity": RARITY_EPIC, "max_stacks": 2,
		"description": "+0.75 crit multiplier.",
		"stats": {"crit_mult_flat": 0.75}, "flags": {},
	},
	{
		"id": "fire_ring", "name": "Fire Ring", "family": FAMILY_RELIC,
		"rarity": RARITY_EPIC, "max_stacks": 1, "ready": false,
		"description": "Burn is 150% stronger, and Chill no longer applies to " +
"anything you touch.",
		"stats": {"mark_potency.burn": 1.5, "mark_lockout.chill": 1.0},
		"flags": {},
	},
	{
		"id": "ring_of_value", "name": "Ring Of Value", "family": FAMILY_RELIC,
		"rarity": RARITY_EPIC, "max_stacks": 1,
		"description": "The shop always keeps one ware at half price.",
		"stats": {"shop_discount": 0.5}, "flags": {},
	},
	{
		"id": "ring_of_protection", "name": "Ring Of Protection",
		"family": FAMILY_RELIC, "rarity": RARITY_LEGENDARY, "max_stacks": 1,
		"ready": false,
		"description": "Damage from marks lands on you at a quarter of its value.",
		"stats": {"mark_damage_taken_mult": -0.75}, "flags": {},
	},
	{
		"id": "ring_of_swiftness", "name": "Ring Of Swiftness",
		"family": FAMILY_RELIC, "rarity": RARITY_LEGENDARY, "max_stacks": 1,
		"description": "+35% movement speed, and the roll covers 2 m further.",
		"stats": {"move_mult": 0.35, "roll_distance": 2.0}, "flags": {},
	},
	{
		"id": "ring_of_luck", "name": "Ring Of Luck", "family": FAMILY_RELIC,
		"rarity": RARITY_LEGENDARY, "max_stacks": 1,
		"description": "+2 luck, and every chance in the pool rolls 20% kinder.",
		"stats": {"luck": 2.0, "proc_coeff_mult": 0.2}, "flags": {},
	},
	{
		"id": "ring_of_tankiness", "name": "Ring Of Tankiness",
		"family": FAMILY_RELIC, "rarity": RARITY_GREED, "max_stacks": 1,
		"description": "+120% max HP and -35% movement speed. A door, not a body.",
		"stats": {"max_hp_mult": 1.2, "move_mult": -0.35}, "flags": {},
	},
]

static var _by_id: Dictionary = {}
static var _surfaces: Dictionary = {}   # mod id -> Array[String] of chest surfaces
static var _built := false


static func _ensure() -> void:
	if _built:
		return
	_built = true
	_by_id.clear()
	_surfaces.clear()
	for row in MODS:
		var id := str(row.id)
		_by_id[id] = row
		_surfaces[id] = _surfaces_for(row)


static func all() -> Array:
	_ensure()
	return MODS


static func get_mod(mod_id: String) -> Dictionary:
	_ensure()
	return _by_id.get(mod_id, {})


static func has(mod_id: String) -> bool:
	_ensure()
	return _by_id.has(mod_id)


## A row whose keys no subsystem reads yet is in the pool and never offered. The
## design's phases 4 and 5 are the two that turn these on, and a card that cannot
## act is a bug the player would have to debug.
static func ready_of(mod_id: String) -> bool:
	return bool(get_mod(mod_id).get("ready", true))


static func family_of(mod_id: String) -> String:
	return str(get_mod(mod_id).get("family", FAMILY_PERK))


## The verb a kit row upgrades - throw, roll, guard, parry - or "" for a row in
## another family. The active ability catalog is `ability_rules.gd`; this is the
## category its kit upgrades belong to.
static func verb_of(mod_id: String) -> String:
	if family_of(mod_id) != FAMILY_ABILITY:
		return ""
	return str(VERB_TAGS.get(mod_id, ""))


## The ability-family tags a row applies to: bow, sword, two_hand, dagger,
## staff, shield, any, melee, ranged, or a verb for the old throw/roll rows.
## Rows outside the ability family have no tags and are not carrier-specific.
static func tags_of(mod_id: String) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = get_mod(mod_id).get("tags", [])
	if raw is Array:
		for tag in raw:
			out.append(str(tag))
	return out


static func family_label_of(mod_id: String) -> String:
	var family := family_of(mod_id)
	var label := str(FAMILY_LABEL.get(family, "PERK"))
	if family != FAMILY_ABILITY:
		return label
	var verb := verb_of(mod_id)
	if not verb.is_empty():
		return "%s  ·  %s" % [label, verb.to_upper()]
	var tags := tags_of(mod_id)
	if not tags.is_empty():
		var shown := PackedStringArray()
		for tag in tags:
			shown.append(tag.to_upper())
		return "%s  ·  %s" % [label, " / ".join(shown)]
	return label


static func rarity_of(mod_id: String) -> String:
	return str(get_mod(mod_id).get("rarity", RARITY_COMMON))


static func name_of(mod_id: String) -> String:
	return str(get_mod(mod_id).get("name", mod_id))


static func max_stacks(mod_id: String) -> int:
	return maxi(1, int(get_mod(mod_id).get("max_stacks", 1)))


# --- the ladder -------------------------------------------------------------

## The tier roll an island stands on, before luck or a source's own gate.
static func ladder_for(island: int) -> Dictionary:
	return LADDER[clampi(island, 1, LADDER.size()) - 1]


## Which tiers a *source* may sell at all - the cache, the stall, the weld or the
## hoard - whatever the luck. This is the one rule luck cannot bend:
## a weld never carries a legendary, whatever the body's luck.
##
## A source is not a surface: a surface is what a gate promises, a source is where
## an unpromised row comes from.
static func source_tiers(source: String, island: int) -> Array[String]:
	var out: Array[String] = []
	match source:
		SOURCE_WELD:
			# The modifiers a chest's piece welds on: commons, epics from the
			# second island, and never the ceiling.
			out.append(RARITY_COMMON)
			if island >= 2:
				out.append(RARITY_EPIC)
			return out
		SOURCE_STALL:
			out.append(RARITY_COMMON)
			out.append(RARITY_EPIC)
			if island >= 3:
				out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out
		SOURCE_HOARD:
			out.append(RARITY_EPIC)
			out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out
		_:
			# The cache: commons and epics always, a legendary from island 4, greed
			# from island 2. A gate's chest never rolls this - it promises one
			# surface at one tier and lays out exactly that.
			out.append(RARITY_COMMON)
			out.append(RARITY_EPIC)
			if island >= 4:
				out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out


## The weights one source's roll uses inside the tiers it sells: the island's
## ladder row, bent by luck. Mass the ladder puts outside the band is never
## invented, and a band the ladder cannot price at all is priced evenly rather
## than left empty - that empty band was what stood a legendary chest on island
## one with nothing in it. The result sums to 100.
static func tier_weights(tiers: Array, luck: int, island: int,
		greedy: bool = false) -> Dictionary:
	var row := ladder_for(island)
	var shift := float(maxi(0, luck))
	var common := maxf(0.0, float(row.common) - LUCK_COMMON_TO_EPIC * shift)
	var epic := maxf(0.0, float(row.epic) + LUCK_COMMON_TO_EPIC * shift
		- LUCK_EPIC_TO_LEGENDARY * shift)
	var unluck := float(row.legendary) + LUCK_EPIC_TO_LEGENDARY * shift
	var legendary := clampf(unluck, 0.0, LUCK_LEGENDARY_CAP)
	# A source that quarters the legendary's weight gives the difference back to
	# the epics: the design's 4% is a share of a hundred, not of eighty-eight.
	epic += maxf(0.0, unluck - legendary)
	# The greed share is carved out of the commons and epics, never out of the
	# legendary: the chest's 4% is the design's own figure and it stays 4%.
	if greedy and common + epic > 0.0:
		var take := minf(GREED_SHARE, common + epic)
		var pool := common + epic
		common -= take * (common / pool)
		epic -= take * (epic / pool)
	var raw := {
		RARITY_COMMON: common,
		RARITY_EPIC: epic,
		RARITY_LEGENDARY: legendary,
		RARITY_GREED: GREED_SHARE if greedy else 0.0,
	}
	var out: Dictionary = {}
	for tier in tiers:
		var weight := float(raw.get(str(tier), 0.0))
		if weight > 0.0:
			out[str(tier)] = weight
	if out.is_empty():
		for tier in tiers:
			out[str(tier)] = 100.0 / float(maxi(1, tiers.size()))
		return out
	out = _normalise(out)
	# The cap is a share of the finished roll, so it is applied after the roll is
	# a hundred: four stacks of luck must still leave commons to find. The mass it
	# frees goes to another tier the band actually sells - a band of the ceiling
	# alone has nowhere to put it, and the promise is the ceiling.
	var held := float(out.get(RARITY_LEGENDARY, 0.0))
	if held > LUCK_LEGENDARY_CAP:
		for other in [RARITY_EPIC, RARITY_COMMON, RARITY_GREED]:
			if out.has(other):
				out[RARITY_LEGENDARY] = LUCK_LEGENDARY_CAP
				out[other] = float(out[other]) + held - LUCK_LEGENDARY_CAP
				break
	return out


static func _normalise(weights: Dictionary) -> Dictionary:
	var total := 0.0
	for tier in weights:
		total += float(weights[tier])
	if total <= 0.0:
		return {}
	var out: Dictionary = {}
	for tier in weights:
		out[str(tier)] = float(weights[tier]) * 100.0 / total
	return out


## One offer count a surface lays out, after the rows that move it.
static func stall_price(tier: String, level: int) -> int:
	return int(round(SHOP_BASE + SHOP_STEP * float(maxi(1, level))
		+ float(TIER_SURCHARGE.get(tier, 0.0))))


# --- one unpromised shelf ---------------------------------------------------

## `count` distinct rows off a source nobody promised, for one body: the island's
## ladder picks the tier among the ones the source sells, luck bends the weights,
## and `exclude` drops the rows the body has spent. This is the cache, the stall,
## the weld and the hoard - every roll that is *not* a promise.
##
## A gate's chest never comes through here: its tier is settled on the label.
static func roll_shelf(rng: RandomNumberGenerator, source: String, island: int,
		count: int = 3, luck: int = 0, exclude: Array = [],
		carrier_tags: Array = []) -> Array[String]:
	_ensure()
	var allowed := source_tiers(source, island)
	var out: Array[String] = []
	if allowed.is_empty() or count <= 0:
		return out
	var weights := tier_weights(allowed, luck, island, allowed.has(RARITY_GREED))
	var taken: Dictionary = {}
	for id in exclude:
		taken[str(id)] = true
	while out.size() < count and not weights.is_empty():
		var tier := _roll_tier(rng, weights)
		if tier.is_empty():
			break
		var id := _pick_in_tier(rng, tier, taken, carrier_tags)
		if id.is_empty():
			# That tier has nothing left to offer this body: drop it and roll the
			# rest rather than spend the count on a dead card.
			weights.erase(tier)
			weights = _normalise(weights)
			continue
		out.append(id)
		taken[id] = true
	return out


## `count` distinct rows of one tier and one surface off a fixed `taken` set: the
## only way a card chest deals. A fixed tier is a promise, so no ladder is read.
static func _take_rows(rng: RandomNumberGenerator, surface: String, tier: String,
		count: int, taken: Dictionary, carrier_tags: Array = []) -> Array[String]:
	var out: Array[String] = []
	while out.size() < count:
		var id := _pick_in_tier(rng, tier, taken, carrier_tags, surface)
		if id.is_empty():
			break
		out.append(id)
		taken[id] = true
	return out


static func _roll_tier(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for tier in weights:
		total += float(weights[tier])
	if total <= 0.0:
		return ""
	var roll := rng.randf_range(0.0, total)
	var walked := 0.0
	var last := ""
	for tier in weights:
		last = str(tier)
		walked += float(weights[tier])
		if roll <= walked:
			return str(tier)
	return last


static func _pick_in_tier(rng: RandomNumberGenerator, tier: String,
		taken: Dictionary, carrier_tags: Array = [],
		chest_surface: String = "") -> String:
	var pool: Array[String] = []
	for row in MODS:
		var id := str(row.id)
		if str(row.rarity) != tier or taken.has(id) or not ready_of(id):
			continue
		if not in_chest_surface(id, chest_surface):
			continue
		if not row_fits_carrier(id, carrier_tags):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]


## A boss's hoard: `count` mods with one legendary guaranteed. The guarantee is
## not a roll - the ladder prices the rest, the boss pays the ceiling. So the
## ladder rolls `count - 1` and the legendary is the row that is written down.
static func hoard(rng: RandomNumberGenerator, count: int, luck: int, island: int,
		exclude: Array = [], carrier_tags: Array = []) -> Array[String]:
	var out := roll_shelf(rng, SOURCE_HOARD, island, maxi(0, count - 1), luck,
		exclude, carrier_tags)
	var taken: Array = exclude.duplicate()
	for id in out:
		taken.append(id)
	var forced := pick_of_tier(rng, RARITY_LEGENDARY, taken, carrier_tags)
	if not forced.is_empty():
		out.append(forced)
	return out


## One ready row of a named tier, for the surfaces that guarantee one: a boss's
## hoard always carries a legendary, and that guarantee is not a roll.
static func pick_of_tier(rng: RandomNumberGenerator, tier: String,
		taken: Array = [], carrier_tags: Array = []) -> String:
	_ensure()
	var exclude: Dictionary = {}
	for id in taken:
		exclude[str(id)] = true
	return _pick_in_tier(rng, tier, exclude, carrier_tags)
