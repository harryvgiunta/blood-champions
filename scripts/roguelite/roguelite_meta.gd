class_name RogueliteMeta
extends Node
## Autoload `Roguelite`: the player's ledger of unlocks.
##
## Unlocking is a player's, not a run's: the weapons and skills a player has
## opened and the keys they were bought with live here, in one file of their own
## (`user://roguelite_meta.json`, a sealed container - `scripts/save_file.gd` - so
## a key count is not a number in a text file), so progression survives a wipe. The
## *pair* is not here: what a body carries is its own worn kit, in the warband's
## inventory.
## The rack opens a piece and the warband forges it into the shared stash; the
## stash is the only place a carried weapon can come from.
##
## The file is versioned and read defensively: an id this build no longer has is
## dropped, and a newer file is left alone instead of being half-read.
##
## Nothing is lent. Every player unlocks on their own machine.

signal meta_changed
## One line for the HUD: a key earned, a weapon opened, a skill opened.
signal announcement(text: String)

const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
## The sealed save container: AES-256 over a binary payload with an HMAC tail.
const SaveFileScript = preload("res://scripts/save_file.gd")

const SAVE_VERSION := 4
const DEFAULT_SAVE_PATH := "user://roguelite_meta.json"
## A fresh player has no keys and nothing but the starters. The first key is the
## tenth level's boss.
const STARTING_KEYS := 0

var keys := STARTING_KEYS
var unlocked: Array[String] = []
## The combat abilities this player has opened, by `AbilityRules` id. An ability
## is unlocked once and then equipped on a body whose hands fit its family; a
## weapon is unlocked once and the warband forges it into the shared stash.
var unlocked_abilities: Array[String] = []
## The opened pieces the warband has already forged a copy of. The forge is a
## ledger fact, not a stash one: a piece the player has worn and sold must not be
## re-minted by pressing its open row again.
var forged: Array[String] = []
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
	# A fresh warband is seeded with the starters' copies: they owe no forge.
	forged.clear()
	for id in Weapons.default_ids():
		forged.append(str(id))
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


## Whether an opened piece still owes the warband its one copy. True until the
## forge has booked it, so a sold weapon is not re-minted by the rack.
func needs_forge(weapon_id: String) -> bool:
	return is_unlocked(weapon_id) and not forged.has(weapon_id)


## Book one piece as forged into the shared stash.
func mark_forged(weapon_id: String) -> void:
	if weapon_id.is_empty() or forged.has(weapon_id):
		return
	forged.append(weapon_id)
	save_meta()
	meta_changed.emit()


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
	var text := "%s is open. It is forged into the stash." % Weapons.display_name(weapon_id)
	announcement.emit(text)
	return {"ok": true, "id": weapon_id, "name": Weapons.display_name(weapon_id),
		"message": text}


## The admin console's grant, and nothing else's: the piece becomes this
## player's own without a key changing hands, so the rack lists it as worn kit
## from then on. `unlock_weapon` stays the one path a purchase spends through.
func grant_weapon(weapon_id: String) -> Dictionary:
	if not Weapons.has(weapon_id):
		return {"ok": false, "message": "That weapon is not in the armory."}
	if is_unlocked(weapon_id):
		return {"ok": true, "id": weapon_id, "message": "%s is already open."
			% Weapons.display_name(weapon_id)}
	unlocked.append(weapon_id)
	save_meta()
	meta_changed.emit()
	var text := "%s is open  ·  ADMIN" % Weapons.display_name(weapon_id)
	announcement.emit(text)
	return {"ok": true, "id": weapon_id, "message": text}


## The admin console's ability grant: the skill is this player's without a key,
## and the rack's book can then equip it on any body whose hands fit it.
func grant_ability(ability_id: String) -> Dictionary:
	var definition := AbilityRules.by_id(ability_id)
	if definition.is_empty():
		return {"ok": false, "message": "No such skill."}
	if AbilityRules.is_automatic(ability_id) or unlocked_abilities.has(ability_id):
		return {"ok": true, "id": ability_id, "message": "%s is already open."
			% str(definition.get("name", ability_id)).capitalize()}
	unlocked_abilities.append(ability_id)
	save_meta()
	meta_changed.emit()
	var text := "%s is open  ·  ADMIN" % str(definition.get("name", ability_id)).capitalize()
	announcement.emit(text)
	return {"ok": true, "id": ability_id, "message": text}


func note_run(level_reached: int, kills: int = 0) -> void:
	runs += 1
	best_level = maxi(best_level, level_reached)
	lifetime_kills += maxi(0, kills)
	save_meta()
	meta_changed.emit()


# --- persistence -----------------------------------------------------------

func save_meta() -> void:
	if not SaveFileScript.write(save_path, {
		"version": SAVE_VERSION,
		"keys": keys,
		"unlocked": unlocked,
		"abilities": unlocked_abilities,
		"forged": forged,
		"runs": runs,
		"best_level": best_level,
		"lifetime_kills": lifetime_kills,
		"lifetime_keys": lifetime_keys,
	}):
		push_warning("Roguelite: cannot write %s" % save_path)


func load_meta() -> void:
	var opened: Dictionary = SaveFileScript.inspect(save_path)
	if not bool(opened.get("ok", false)):
		var problem := str(opened.get("problem", ""))
		if problem != "missing":
			push_warning("Roguelite: ignoring %s ledger at %s" % [problem, save_path])
		_ensure_defaults()
		return
	var data: Dictionary = opened.get("data", {})
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
	# A v3 file also carried the rack's bound pair. It is dropped: the pair is the
	# warband's inventory now, and a saved id here would be a second truth.
	forged.clear()
	var raw_forged: Variant = data.get("forged", [])
	if raw_forged is Array:
		for entry in raw_forged:
			var id := str(entry)
			if Weapons.has(id) and not forged.has(id):
				forged.append(id)
	_ensure_defaults()


func _ensure_defaults() -> void:
	if not Weapons.has(Weapons.STARTER_RANGED) or not Weapons.has(Weapons.STARTER_MELEE):
		push_error("Roguelite: the starter weapons are missing from the registry")
		return
	# The starters are seeded into a fresh warband's stash: they owe no forge.
	for id in Weapons.default_ids():
		if not forged.has(id):
			forged.append(str(id))


func describe() -> String:
	return "%d key%s  ·  %d/%d weapons open  ·  %d/%d skills open  ·  best level %d" % [
		keys, "" if keys == 1 else "s", unlocked_ids().size(), Weapons.all_ids().size(),
		unlocked_abilities.size(), AbilityRules.unlockable_ids().size(), best_level]
