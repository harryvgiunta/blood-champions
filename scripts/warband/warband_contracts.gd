class_name WarbandContracts
extends RefCounted
## GHOST OF THE WARBAND — the shared contract every parallel worktree reads.
##
## This file is Phase 0 of the overhaul and is deliberately pure vocabulary plus
## arithmetic: no scene, no node, no autoload. Six isolated branches cannot
## invent two spellings of the same slot, state, essence tier, bubble radius or
## overkill rule because they all land here.
##
## Existing vocabulary this maps onto, and must never replace:
##   * `EquipmentRules.SLOTS`  -> head/chest/hands/legs/feet/neck/ring1/ring2/main/off
##   * `PlayerState.ITEMS`     -> category 1h/2h/bow/staff/shield/focus/armor/jewelry
##   * `ArenaActor.MAX_HEALTH` -> 100.0 (every mercenary has identical base stats)
##   * `Stamina.MAX`           -> 1000.0 (identical for every mercenary)

# --- equipment -------------------------------------------------------------

## The ten worn slots, in paperdoll order. `BOOTS` is the existing `feet` id and
## `MAIN_HAND`/`OFF_HAND` are the existing `main`/`off` ids: the enum names are
## the design vocabulary, `SLOT_IDS` is the wire and save vocabulary.
##
## Steel first, then the armour, then the trinkets - the order a body is armed in
## (`Warband.DRESS_SLOTS`), so the rows of the page and the kit order the hotbar
## keys are laid out in are the same order the body is first dressed.
enum SlotType { HEAD, CHEST, HANDS, LEGS, BOOTS, NECK, RING1, RING2, MAIN_HAND, OFF_HAND }

const SLOT_ORDER: Array[int] = [
	SlotType.MAIN_HAND, SlotType.OFF_HAND,
	SlotType.HEAD, SlotType.CHEST, SlotType.HANDS, SlotType.LEGS, SlotType.BOOTS,
	SlotType.NECK, SlotType.RING1, SlotType.RING2,
]

const SLOT_IDS := {
	SlotType.HEAD: "head",
	SlotType.CHEST: "chest",
	SlotType.HANDS: "hands",
	SlotType.LEGS: "legs",
	SlotType.BOOTS: "feet",
	SlotType.NECK: "neck",
	SlotType.RING1: "ring1",
	SlotType.RING2: "ring2",
	SlotType.MAIN_HAND: "main",
	SlotType.OFF_HAND: "off",
}

const SLOT_LABELS := {
	SlotType.HEAD: "Head",
	SlotType.CHEST: "Chest",
	SlotType.HANDS: "Hands",
	SlotType.LEGS: "Legs",
	SlotType.BOOTS: "Boots",
	SlotType.NECK: "Neck",
	SlotType.RING1: "Ring 1",
	SlotType.RING2: "Ring 2",
	SlotType.MAIN_HAND: "Main Hand",
	SlotType.OFF_HAND: "Off-Hand",
}

## What a held item is, as the paperdoll and the brand system care about it.
## `PlayerState.ITEMS` says `category`/`focus`; this says what the item *does*.
enum WeaponSubType { NONE, ONE_HAND, TWO_HAND, BOW, STAFF, SHIELD, SKULL, TOME }

const WEAPON_LABELS := {
	WeaponSubType.NONE: "Armor",
	WeaponSubType.ONE_HAND: "One-Handed",
	WeaponSubType.TWO_HAND: "Two-Handed",
	WeaponSubType.BOW: "Bow",
	WeaponSubType.STAFF: "Staff",
	WeaponSubType.SHIELD: "Shield",
	WeaponSubType.SKULL: "Skull",
	WeaponSubType.TOME: "Tome",
}

const SKULL_FOCUS := ["skull", "skull_life", "skull_death"]

# --- slot helpers ----------------------------------------------------------

static func slot_id(slot: int) -> String:
	return str(SLOT_IDS.get(slot, ""))

## '' when the id is not a worn slot.
static func slot_from_id(id: String) -> int:
	for slot in SLOT_IDS:
		if SLOT_IDS[slot] == id:
			return slot
	return -1

static func slot_label(slot: int) -> String:
	return str(SLOT_LABELS.get(slot, "Slot"))

static func slot_id_label(id: String) -> String:
	return slot_label(slot_from_id(id))

## The item's combat identity, mapped from the catalog's category/focus pair.
static func weapon_subtype(item: Dictionary) -> int:
	if item.is_empty():
		return WeaponSubType.NONE
	match str(item.get("category", "")):
		"1h":
			return WeaponSubType.ONE_HAND
		"2h":
			return WeaponSubType.TWO_HAND
		"bow":
			return WeaponSubType.BOW
		"staff":
			return WeaponSubType.STAFF
		"shield":
			return WeaponSubType.SHIELD
		"focus":
			return WeaponSubType.SKULL if str(item.get("focus", "")) in SKULL_FOCUS else WeaponSubType.TOME
	return WeaponSubType.NONE

## True for items that leave no off hand: 2H, bows and staves.
static func two_handed_item(item: Dictionary) -> bool:
	return weapon_subtype(item) in [WeaponSubType.TWO_HAND, WeaponSubType.BOW, WeaponSubType.STAFF]

## Off-hand-only pieces: shields, skulls and tomes.
static func off_hand_only(item: Dictionary) -> bool:
	return weapon_subtype(item) in [WeaponSubType.SHIELD, WeaponSubType.SKULL, WeaponSubType.TOME]

# --- combat helpers --------------------------------------------------------

static func state_name(state: int) -> String:
	match state:
		HealthState.DOWNED:
			return "Downed"
		HealthState.DEAD:
			return "Dead"
	return "Alive"

## Resolve one hit against a living body. The single authority for the 10%
## overkill rule: a lethal hit that does not overkill by more than 10% of max
## health leaves the body DOWNED at zero health, anything heavier kills it.
##
## Returns `{ok, state, health, damage, overkill, downed, died}`.
static func resolve_damage(health: float, max_health: float, amount: float) -> Dictionary:
	var max_hp := maxf(0.0, max_health)
	var hit := maxf(0.0, amount)
	if hit <= 0.0:
		return {"ok": false, "state": HealthState.ALIVE, "health": health,
			"damage": 0.0, "overkill": 0.0, "downed": false, "died": false}
	var remaining := health - hit
	if remaining > 0.0:
		return {"ok": true, "state": HealthState.ALIVE, "health": remaining,
			"damage": hit, "overkill": 0.0, "downed": false, "died": false}
	var overkill := -remaining
	if overkill <= max_hp * OVERKILL_THRESHOLD:
		return {"ok": true, "state": HealthState.DOWNED, "health": 0.0,
			"damage": hit, "overkill": overkill, "downed": true, "died": false}
	return {"ok": true, "state": HealthState.DEAD, "health": 0.0,
		"damage": hit, "overkill": overkill, "downed": false, "died": true}

## A blow on an already-downed body. The same 10% threshold is a finisher: a
## heavy strike ends it, a light one (including passive 10% chip) does not.
## Returns true when the body dies.
static func finishes_downed(max_health: float, amount: float) -> bool:
	return amount > maxf(0.0, max_health) * OVERKILL_THRESHOLD

## Health a revive restores, as a fraction of max health.
## What a body stands up with. A revived mercenary comes back with a twentieth of
## its own pool: enough to walk, not enough to trade blows, so a rescue buys a
## withdrawal rather than a second life.
const REVIVE_HEALTH_FRACTION := 0.05
