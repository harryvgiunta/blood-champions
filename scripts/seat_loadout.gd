extends RefCounted
## Seat loadouts arrive over the wire, so only real catalog ids that are legal
## for the requested hand may be applied. Both the arena and the open world use
## this one validator; a malformed kit leaves the existing presentation alone.

const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

const TRINKET_SLOTS := ["off"]

static func hand(value: Variant, slot: String) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var id := str(value)
	var item: Dictionary = State.ITEMS.get(id,{})
	if item.is_empty() or not Rules.allowed(item,slot):
		return ""
	return id

## Every unlocked combat skill whose family fits the kit, in catalog order, capped
## at the keys a body's bar has. Used only for a body with no player's list behind
## it.
static func _default_abilities(loadout: Dictionary) -> Array[String]:
	var main: Dictionary = State.ITEMS.get(str(loadout.get("main", "")), {})
	var off: Dictionary = State.ITEMS.get(str(loadout.get("off", "")), {})
	var out: Array[String] = []
	for id in AbilityRules.unlockable_ids():
		var definition := AbilityRules.by_id(id)
		if definition.is_empty() or not AbilityRules.fits_gear(definition, main, off):
			continue
		out.append(id)
		if out.size() >= AbilityRules.SLOT_COUNT:
			break
	return out


## Whether a bar assignment names any skill at all. A row of empty keys is no
## assignment, and a body nobody is inside gets one laid out for it.
static func _has_skills(assigned: Array[String]) -> bool:
	for id in assigned:
		if not str(id).is_empty():
			return true
	return false


## The worn kit travels beside the hands. Each id must be a real catalog item
## legal in its slot; anything else becomes an empty slot.
static func trinkets(value: Variant) -> Dictionary:
	var kit := {"off":""}
	if typeof(value) != TYPE_DICTIONARY:
		return kit
	var source: Dictionary = value
	for slot in TRINKET_SLOTS:
		kit[slot] = hand(source.get(slot,""),slot)
	return kit

## `ability_loadout` is the player's equipped ability ids for this
## body, read off the mercenary's record; `gain` shows only the families its
## current hands fit. `starter_ability` is the caller's reading of whether a
## player is inside the body being dressed: only then is it given the starter
## spell, so a squadmate never gains a caster it never had.
static func apply(rig, loadout: Dictionary,
		ability_loadout: Array = [], starter_ability: bool = false) -> void:
	if rig == null or loadout.is_empty():
		return
	var equipped := AbilityRules.equipped_ids(ability_loadout)
	# A warband body nobody is inside - a squadmate, a borrowed seat - has no
	# player to lay out its keys. Give it every skill its own hands fit, so the
	# band fights with its kit instead of standing on the starter alone. A bar of
	# empty keys is still no assignment: the AI body is dressed outright.
	if not _has_skills(equipped) and not starter_ability:
		equipped = _default_abilities(loadout)
	rig.set("ability_loadout", equipped)
	var bow: Variant = loadout.get("bow")
	var sword: Variant = loadout.get("sword")
	var armor: Variant = loadout.get("armor")
	var bow_ok := typeof(bow) == TYPE_INT and int(bow) >= 0 and int(bow) <= 2
	var sword_ok := typeof(sword) == TYPE_INT and int(sword) >= 0 and int(sword) <= 2
	var armor_ok := typeof(armor) == TYPE_INT and int(armor) >= 0 and int(armor) <= ArmorData.PIECE_MASK
	var main_raw: Variant = loadout.get("main")
	var off_raw: Variant = loadout.get("off")
	var main := hand(main_raw,"main")
	var off := hand(off_raw,"off")
	var worn := trinkets(loadout.get("trinkets"))
	worn["off"] = off
	var hands_present := loadout.has("main") or loadout.has("off")
	var main_ok := not loadout.has("main") or (typeof(main_raw) == TYPE_STRING and (str(main_raw).is_empty() or not main.is_empty()))
	var off_ok := not loadout.has("off") or (typeof(off_raw) == TYPE_STRING and (str(off_raw).is_empty() or not off.is_empty()))
	if hands_present and main_ok and off_ok:
		# Hub kits carry the whole paperdoll; the state script derives the
		# weapon mode, staff, focus, shield and off-hand from the validated ids.
		# Explicitly empty hands are deliberate (unarmed); a malformed non-empty
		# hand falls through instead of wiping a valid seat. `starter_ability` is
		# the caller's own reading of whether a *player* is inside this body: the
		# starter spell is the player's key, not a squadmate's.
		var pieces: Dictionary = ArmorData.unpack(int(armor) & ArmorData.PIECE_MASK) if armor_ok else rig.armor_pieces.duplicate()
		rig.apply_loadout(State.build_loadout(main,off,pieces,worn,
			starter_ability))
		return
	# A kit that omits the hands still carries its worn trinkets.
	rig.apply_trinkets(worn)
	if bow_ok:
		rig.set_bow(int(bow))
	if sword_ok:
		rig.set_sword(int(sword))
	if armor_ok:
		rig.set_armor_bits(int(armor))
