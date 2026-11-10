class_name RogueliteMeta
extends Node
## Autoload `Roguelite`: the player's ledger of unlocks.
##
## Unlocking is a player's, not a run's: the weapons a player has opened, the key
## balance those weapons are bought with, and the pair bound to the rack all live
## here, in one file of their own (`user://roguelite_meta.json`). A run starts
## every body with the starters and every weapon an earlier run opened is still on
## the rack, so progression survives a wipe.
##
## The file is versioned and read defensively: an id this build no longer has is
## dropped, a loadout slot naming a weapon that is not unlocked falls back to the
## starter, and a newer file is left alone instead of being half-read.
##
## Nothing is lent. Every player unlocks on their own machine, and a guest that
## has never fought a boss fields the starters and nothing else.

signal meta_changed
## One line for the HUD: a key earned, a weapon opened, a slot rebound.
signal announcement(text: String)

const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

const SAVE_VERSION := 3
const DEFAULT_SAVE_PATH := "user://roguelite_meta.json"
const RANGED_SLOT := "ranged"
const MELEE_SLOT := "melee"
const SLOTS := [RANGED_SLOT, MELEE_SLOT]
## What a fresh body walks into Hearthstead holding. These two are never locked:
## the whole point of the arc is that a band starts with a bow and a hatchet and
## earns the rest.
const DEFAULT_RANGED := "bow_twig"
const DEFAULT_MELEE := "hatchet_makeshift"
## A fresh player has no keys and nothing but the starters. The first key is the
## tenth level's boss.
const STARTING_KEYS := 0

var keys := STARTING_KEYS
var unlocked: Array[String] = []
## The combat abilities this player has opened, by `AbilityRules` id. A weapon is
## unlocked once and equipped on the rack; an ability is unlocked once and then
## equipped on a body whose hands fit its family. Neither is ever welded to a
## piece, so a wipe keeps both.
var unlocked_abilities: Array[String] = []
var loadout := {RANGED_SLOT: DEFAULT_RANGED, MELEE_SLOT: DEFAULT_MELEE}
var runs := 0
var best_level := 0
var lifetime_kills := 0
var lifetime_keys := 0
var save_path := DEFAULT_SAVE_PATH


func _ready() -> void:
	# Script regressions must never read or overwrite a player's ledger.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://roguelite_meta_test.json"
	load_meta()


# --- the ledger ------------------------------------------------------------

func reset(persist: bool = true) -> void:
	keys = STARTING_KEYS
	unlocked.clear()
	unlocked_abilities.clear()
	loadout = {RANGED_SLOT: DEFAULT_RANGED, MELEE_SLOT: DEFAULT_MELEE}
	runs = 0
	best_level = 0
	lifetime_kills = 0
	lifetime_keys = 0
	if persist:
		save_meta()
	meta_changed.emit()


## Every weapon id this player can field: the two starters and whatever their
## own keys have opened.
func unlocked_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.default_ids():
		if not out.has(id):
			out.append(id)
	for id in unlocked:
		if Weapons.has(id) and not out.has(id):
			out.append(id)
	return out


func is_unlocked(weapon_id: String) -> bool:
	if Weapons.is_default(weapon_id):
		return true
	return unlocked.has(weapon_id)


## The weapons a slot can be set to right now, in registry order.
func pool_for(slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.ids_for_slot(slot):
		if is_unlocked(id):
			out.append(id)
	return out


func loadout_for(slot: String) -> String:
	var id := str(loadout.get(slot, ""))
	if id.is_empty() or not is_unlocked(id) or Weapons.slot_of(id) != slot:
		return DEFAULT_RANGED if slot == RANGED_SLOT else DEFAULT_MELEE
	return id


## Bind a slot to an unlocked weapon. Refuses a locked piece, a piece that
## belongs in the other slot, and the same piece in both hands.
func set_loadout_slot(slot: String, weapon_id: String) -> Dictionary:
	if not SLOTS.has(slot):
		return {"ok": false, "message": "That is not a loadout slot."}
	if not Weapons.has(weapon_id):
		return {"ok": false, "message": "That weapon is not in the armory."}
	var weapon_slot := Weapons.slot_of(weapon_id)
	if weapon_slot != slot:
		return {"ok": false, "message": "%s belongs in the %s slot." % [
			Weapons.display_name(weapon_id), weapon_slot]}
	if not is_unlocked(weapon_id):
		return {"ok": false, "message": "%s is still locked. Open it on the rack." % [
			Weapons.display_name(weapon_id)]}
	var other := MELEE_SLOT if slot == RANGED_SLOT else RANGED_SLOT
	if loadout_for(other) == weapon_id:
		return {"ok": false, "message": "%s is already in the other hand." % [
			Weapons.display_name(weapon_id)]}
	loadout[slot] = weapon_id
	save_meta()
	meta_changed.emit()
	return {"ok": true, "message": "%s takes the %s slot." % [
		Weapons.display_name(weapon_id), slot]}


# --- keys and unlocks ------------------------------------------------------

func award_keys(amount: int, reason: String = "") -> int:
	var gained := maxi(0, amount)
	if gained <= 0:
		return 0
	keys += gained
	lifetime_keys += gained
	save_meta()
	meta_changed.emit()
	var line := "+%d KEY%s" % [gained, "" if gained == 1 else "S"]
	if not reason.is_empty():
		line += "  ·  %s" % reason
	announcement.emit(line)
	return gained


func spend_keys(amount: int) -> bool:
	var price := maxi(0, amount)
	if price <= 0:
		return true
	if keys < price:
		return false
	keys -= price
	save_meta()
	meta_changed.emit()
	return true


## The weapons that are still locked, cheapest first. A pool that only ever
## offered the dearest piece would make the first keys feel like a tax.
func locked_ids() -> Array[String]:
	var out: Array[String] = []
	for id in Weapons.all_ids():
		if not is_unlocked(id):
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var cost_a := int(Weapons.get_weapon(a).get("unlock_cost", 3))
		var cost_b := int(Weapons.get_weapon(b).get("unlock_cost", 3))
		if cost_a == cost_b:
			return a < b
		return cost_a < cost_b)
	return out


## Open one named weapon for this player, at the price on its row. The rack calls
## this for a locked piece; there is no roll and no pool to draw from.
func unlock_cost_of(weapon_id: String) -> int:
	return maxi(1, int(Weapons.get_weapon(weapon_id).get("unlock_cost", 3)))


## The starter spell and the bare-hand fallback are the body's own; they are
## never bought and never need a key.
func is_ability_unlocked(ability_id: String) -> bool:
	if AbilityRules.is_automatic(ability_id):
		return true
	if AbilityRules.by_id(ability_id).is_empty():
		return false
	return unlocked_abilities.has(ability_id)


## Open one named ability for this player, at the price on its row. The rack calls
## this for a locked row; the ability is then equippable on every body whose hands
## fit its family. There is no pool and no roll.
func ability_unlock_cost(ability_id: String) -> int:
	return AbilityRules.unlock_cost_of(ability_id)


func unlock_ability(ability_id: String) -> Dictionary:
	var definition := AbilityRules.by_id(ability_id)
	if definition.is_empty() or AbilityRules.is_automatic(ability_id):
		return {"ok": false, "message": "That skill cannot be unlocked."}
	var display := str(definition.get("name", ability_id)).capitalize()
	if unlocked_abilities.has(ability_id):
		return {"ok": false, "message": "%s is already open." % display}
	var price := ability_unlock_cost(ability_id)
	if keys < price:
		return {"ok": false, "message": "%s wants %d keys. You carry %d." % [
			display, price, keys]}
	spend_keys(price)
	unlocked_abilities.append(ability_id)
	save_meta()
	meta_changed.emit()
	var text := "%s is open. Equip it on the rack." % display
	announcement.emit(text)
	return {"ok": true, "id": ability_id, "name": display, "message": text}


func unlock_weapon(weapon_id: String) -> Dictionary:
	if not Weapons.has(weapon_id):
		return {"ok": false, "message": "That weapon is not in the armory."}
	if is_unlocked(weapon_id):
		return {"ok": false, "message": "%s is already open." % Weapons.display_name(weapon_id)}
	var price := unlock_cost_of(weapon_id)
	if keys < price:
		return {"ok": false, "message": "%s wants %d keys. You carry %d." % [
			Weapons.display_name(weapon_id), price, keys]}
	spend_keys(price)
	unlocked.append(weapon_id)
	save_meta()
	meta_changed.emit()
	var text := "%s is open. It stands on the rack." % Weapons.display_name(weapon_id)
	announcement.emit(text)
	return {"ok": true, "id": weapon_id, "name": Weapons.display_name(weapon_id),
		"message": text}


func note_run(level_reached: int, kills: int = 0) -> void:
	runs += 1
	best_level = maxi(best_level, level_reached)
	lifetime_kills += maxi(0, kills)
	save_meta()
	meta_changed.emit()


# --- persistence -----------------------------------------------------------

func save_meta() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Roguelite: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"keys": keys,
		"unlocked": unlocked,
		"abilities": unlocked_abilities,
		"loadout": loadout,
		"runs": runs,
		"best_level": best_level,
		"lifetime_kills": lifetime_kills,
		"lifetime_keys": lifetime_keys,
	}, "\t"))
	file.close()


func load_meta() -> void:
	if not FileAccess.file_exists(save_path):
		_ensure_defaults()
		return
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		_ensure_defaults()
		return
	var raw := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_ensure_defaults()
		return
	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		# A ledger from a newer build is left as it stands; reading half of it
		# would quietly spend a player's keys on a weapon this build cannot hold.
		_ensure_defaults()
		return
	keys = maxi(0, int(data.get("keys", 0)))
	runs = maxi(0, int(data.get("runs", 0)))
	best_level = maxi(0, int(data.get("best_level", data.get("best_stage", 0))))
	lifetime_kills = maxi(0, int(data.get("lifetime_kills", 0)))
	lifetime_keys = maxi(0, int(data.get("lifetime_keys", 0)))
	unlocked.clear()
	var raw_unlocked: Variant = data.get("unlocked", [])
	if raw_unlocked is Array:
		for entry in raw_unlocked:
			var id := str(entry)
			if Weapons.has(id) and not Weapons.is_default(id) and not unlocked.has(id):
				unlocked.append(id)
	unlocked_abilities.clear()
	var raw_abilities: Variant = data.get("abilities", [])
	if raw_abilities is Array:
		for entry in raw_abilities:
			var id := str(entry)
			if AbilityRules.by_id(id).is_empty() or AbilityRules.is_automatic(id):
				continue
			if not unlocked_abilities.has(id):
				unlocked_abilities.append(id)
	var raw_loadout: Variant = data.get("loadout", {})
	if raw_loadout is Dictionary:
		var saved: Dictionary = raw_loadout
		for slot in SLOTS:
			var id := str(saved.get(slot, ""))
			if not id.is_empty() and Weapons.slot_of(id) == slot and (Weapons.is_default(id) or unlocked.has(id)):
				loadout[slot] = id
	_ensure_defaults()


func _ensure_defaults() -> void:
	if not Weapons.has(DEFAULT_RANGED) or not Weapons.has(DEFAULT_MELEE):
		push_error("Roguelite: the starter weapons are missing from the registry")
		return
	if not is_unlocked(str(loadout.get(RANGED_SLOT, ""))) or Weapons.slot_of(str(loadout.get(RANGED_SLOT, ""))) != RANGED_SLOT:
		loadout[RANGED_SLOT] = DEFAULT_RANGED
	if not is_unlocked(str(loadout.get(MELEE_SLOT, ""))) or Weapons.slot_of(str(loadout.get(MELEE_SLOT, ""))) != MELEE_SLOT:
		loadout[MELEE_SLOT] = DEFAULT_MELEE


func describe() -> String:
	return "%d key%s  ·  %d/%d weapons open  ·  %d/%d skills open  ·  best level %d" % [
		keys, "" if keys == 1 else "s", unlocked_ids().size(), Weapons.all_ids().size(),
		unlocked_abilities.size(), AbilityRules.unlockable_ids().size(), best_level]
