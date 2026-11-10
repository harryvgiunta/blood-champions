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
## The tier is not power. It is where the row arrives: a pedestal carries commons,
## a boss's hoard and the stall carry legendaries, a totem carries greed. The
## ladder is the part of a loot system a player learns by playing, so it lives
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


## The surfaces. A surface's ladder row is the only thing that decides whether a
## tier can appear at all, which is what stops luck from opening a tier the
## surface does not sell.
const SURFACE_PEDESTAL := "pedestal"
const SURFACE_SHOP_PEDESTAL := "shop_pedestal"
const SURFACE_CHEST := "chest"
const SURFACE_HOARD := "hoard"
const SURFACE_STALL := "stall"
const SURFACE_TOTEM := "totem"

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
## A reward chest is one mod with no choice, so its legendary weight is a quarter
## of the ladder's: 4% on island 4, 5.5% on island 5+.
const CHEST_LEGENDARY_SCALE := 0.25
## The greed share a surface that carries greed carves out of the roll, from
## island 2 on. The source's greed is 6.1% of its pool; ours is the totem's six
## levels in ten, so a chest is the only place greed arrives without a bargain.
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
		"description": "The bow no longer has to be drawn: arrows leave at once.",
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
		"description": "+25% gold from every kill, chest and totem.",
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
		"description": "The pedestal lays out one more card.",
		"stats": {"pedestal_offers": 1.0}, "flags": {},
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
		"id": "rare_treasure", "name": "Rare Treasure", "family": FAMILY_PERK,
		"rarity": RARITY_LEGENDARY, "max_stacks": 3,
		"description": "A body has a 3% chance a stack to leave an upgrade card on " +
"the ground, for whoever reaches it.",
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
		"description": "A pedestal card you did not take stays on the ground as a " +
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
		"description": "An extra chest every island, but the pedestal only lays " +
"out two cards from now on.",
		"stats": {"extra_chest_islands": 1.0, "pedestal_offers": -1.0},
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
static var _built := false


static func _ensure() -> void:
	if _built:
		return
	_built = true
	_by_id.clear()
	for row in MODS:
		_by_id[str(row.id)] = row


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

## The tier roll an island stands on, before luck or a surface's own gate.
static func ladder_for(island: int) -> Dictionary:
	return LADDER[clampi(island, 1, LADDER.size()) - 1]


## Which tiers a surface may sell at all. This is the one rule luck cannot bend:
## a pedestal never carries a legendary, whatever the body's luck.
static func surface_tiers(surface: String, island: int) -> Array[String]:
	var out: Array[String] = []
	match surface:
		SURFACE_TOTEM:
			out.append(RARITY_GREED)
			return out
		SURFACE_PEDESTAL:
			out.append(RARITY_COMMON)
			if island >= 2:
				out.append(RARITY_EPIC)
			return out
		SURFACE_SHOP_PEDESTAL:
			out.append(RARITY_COMMON)
			out.append(RARITY_EPIC)
			return out
		SURFACE_STALL:
			out.append(RARITY_COMMON)
			out.append(RARITY_EPIC)
			if island >= 3:
				out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out
		SURFACE_HOARD:
			out.append(RARITY_EPIC)
			out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out
		_:
			# The reward chest: commons and epics always, a legendary from island
			# 4 at a quarter weight, greed from island 2.
			out.append(RARITY_COMMON)
			out.append(RARITY_EPIC)
			if island >= 4:
				out.append(RARITY_LEGENDARY)
			if island >= 2:
				out.append(RARITY_GREED)
			return out


## The weights a surface's roll uses: the island's ladder row, luck's shift,
## the chest's quarter legendary, the greed share, and then only the tiers the
## surface sells. The result sums to 100 unless nothing is left.
static func tier_weights(tiers: Array, luck: int, island: int,
		legendary_scale: float = 1.0, greedy: bool = false) -> Dictionary:
	var row := ladder_for(island)
	var shift := float(maxi(0, luck))
	var common := maxf(0.0, float(row.common) - LUCK_COMMON_TO_EPIC * shift)
	var epic := maxf(0.0, float(row.epic) + LUCK_COMMON_TO_EPIC * shift
		- LUCK_EPIC_TO_LEGENDARY * shift)
	var unluck := float(row.legendary) + LUCK_EPIC_TO_LEGENDARY * shift
	var legendary := clampf(unluck * legendary_scale, 0.0, LUCK_LEGENDARY_CAP)
	# A surface that quarters the legendary's weight gives the difference back to
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
	out = _normalise(out)
	# The cap is a share of the finished roll, so it is applied after the roll is
	# a hundred: four stacks of luck must still leave commons to find.
	var held := float(out.get(RARITY_LEGENDARY, 0.0))
	if held > LUCK_LEGENDARY_CAP:
		out[RARITY_LEGENDARY] = LUCK_LEGENDARY_CAP
		out[RARITY_EPIC] = float(out.get(RARITY_EPIC, 0.0)) + held - LUCK_LEGENDARY_CAP
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


# --- drafting ---------------------------------------------------------------

## One draft of `count` distinct offers. `tiers` is the surface's own ladder row
## (an Array of tier names) or, for the old call shape, a boolean gate: `false`
## is the pedestal's ladder and `true` lets every tier in, greed included.
##
## `luck` only ever shifts weight between the tiers the surface already sells,
## and `island` is 1-based. The roll happens here so every surface - pedestal,
## chest, hoard and stall - answers the same rules.
static func draft(rng: RandomNumberGenerator, count: int = 3, tiers: Variant = null,
		luck: int = 0, island: int = 1, exclude: Array = [],
		carrier_tags: Array = []) -> Array[String]:
	_ensure()
	var allowed := _resolve_tiers(tiers, island)
	var out: Array[String] = []
	if allowed.is_empty() or count <= 0:
		return out
	var taken: Dictionary = {}
	for id in exclude:
		taken[str(id)] = true
	var weights := tier_weights(allowed,
		luck, island, 1.0, allowed.has(RARITY_GREED))
	# A surface whose roll is all greed (the totem's own row) needs the share,
	# not the ladder: one tier means one tier.
	if weights.size() == 1:
		var only := str(weights.keys()[0])
		weights = {only: 100.0}
	var misses := 0
	while out.size() < count and not weights.is_empty():
		var tier := _roll_tier(rng, weights)
		var id := _pick_in_tier(rng, tier, taken, carrier_tags)
		if id.is_empty():
			# That tier has nothing left to offer this body: drop it and roll the
			# rest rather than spend the draft on a dead card.
			misses += 1
			weights.erase(tier)
			weights = _normalise(weights)
			if misses > RARITIES.size() * 2:
				break
			continue
		out.append(id)
		taken[id] = true
	return out


static func _resolve_tiers(tiers: Variant, island: int) -> Array[String]:
	if tiers is bool:
		# The old call shape: `false` is the pedestal, `true` lets greed in.
		return surface_tiers(SURFACE_STALL if tiers else SURFACE_PEDESTAL, island)
	var out: Array[String] = []
	if tiers is Array:
		for tier in tiers:
			out.append(str(tier))
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
		taken: Dictionary, carrier_tags: Array = []) -> String:
	var pool: Array[String] = []
	for row in MODS:
		var id := str(row.id)
		if str(row.rarity) != tier or taken.has(id) or not ready_of(id):
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
	var out := draft(rng, maxi(0, count - 1),
		surface_tiers(SURFACE_HOARD, island), luck, island, exclude, carrier_tags)
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


## A greed totem's own offer: always a greed mod, never one already maxed out.
static func greed_offer(rng: RandomNumberGenerator, stacks: Dictionary) -> String:
	_ensure()
	var pool: Array[String] = []
	for row in MODS:
		if str(row.rarity) != RARITY_GREED:
			continue
		var id := str(row.id)
		if not ready_of(id) or int(stacks.get(id, 0)) >= max_stacks(id):
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	return pool[rng.randi_range(0, pool.size() - 1)]
