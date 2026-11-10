extends SceneTree
## Ability unlocks and the equipped bar.
##
## A skill is opened once on the player's ledger, then equipped on a body. The
## body's hands decide which equipped skills actually reach the ten keys: a bow
## skill waits while the sword is out and comes back with the bow. The starter
## spell and the two consumables are automatic; the player's list holds the rest.
## This walks the catalog layer, the player unlock ledger, the rig's grant, the
## warband's per-body list, its save round-trip, the paperdoll row and the co-op
## refusal.

const Actor = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")

const ARMOR := {"head": 0, "chest": 0, "hands": 0, "legs": 0, "feet": 0}
const TEST_SAVE := "user://hotbar_regression_state.json"
const TEST_META := "user://hotbar_regression_meta.json"

var checks := 0
var failures := 0
var warband
var meta

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("HOTBAR_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _on_watchdog() -> void:
	check(false, "the regression did not finish in time")
	print("HOTBAR_REGRESSION checks=", checks, " failures=", failures)
	quit(1)

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _same(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in actual.size():
		if str(actual[index]) != str(expected[index]):
			return false
	return true

func _ids(definitions: Array) -> Array:
	var out := []
	for definition in definitions:
		var id := str(definition.get("id", ""))
		if not id.is_empty():
			out.append(id)
	return out

func tile_id(tile) -> String:
	var definition = tile.get("_definition")
	return str(definition.get("id", "")) if definition is Dictionary else ""

func tile_key(tile) -> String:
	var label = tile.get("_key")
	return str(label.text) if label != null else ""

func fighter(parent: Node3D, index: int, at: Vector3) -> Node3D:
	var actor := Actor.new()
	actor.slot = index
	actor.authoritative = true
	parent.add_child(actor)
	actor.configure(index + 1, "Probe", at)
	actor.set_process(false)
	actor.rig.set_physics_process(false)
	actor.set_physics_process(false)
	actor.combat.set_motion(Vector3.ZERO, false, true)
	actor.combat.grounded = true
	return actor


func run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(_on_watchdog)
	_remove(TEST_SAVE)
	_remove(TEST_META)
	warband = root.get_node("Warband")
	warband.save_path = TEST_SAVE
	warband.reset_state()
	meta = root.get_node("Roguelite")
	meta.save_path = TEST_META
	meta.reset(false)
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	_check_catalog()
	_check_unlocks()
	_check_rig(world)
	_check_warband()
	_check_move_and_save()
	_check_paperdoll()
	world.queue_free()
	warband.reset_state()
	meta.reset(false)
	_remove(TEST_SAVE)
	_remove(TEST_META)
	print("HOTBAR_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


## The layer above the definitions: every combat ability names a family, a
## family has one fitting answer, and only the real skills are for sale.
func _check_catalog() -> void:
	check(AbilityRules.type_of(AbilityRules.by_id("barrage")) == AbilityRules.TYPE_BOW,
		"barrage is a bow skill")
	check(AbilityRules.type_of(AbilityRules.by_id("double_slash")) == AbilityRules.TYPE_SWORD,
		"double slash is a sword skill")
	check(AbilityRules.type_of(AbilityRules.by_id("executioner")) == AbilityRules.TYPE_TWO_HAND,
		"executioner is a two-hand skill")
	check(AbilityRules.type_of(AbilityRules.by_id("backstab")) == AbilityRules.TYPE_DAGGER,
		"backstab is a dagger skill")
	check(_same(AbilityRules.families_of(AbilityRules.by_id("fireball")),
		[AbilityRules.TYPE_STAFF]), "the starter spell is a staff skill")
	var untagged: Array[String] = []
	for id in AbilityRules.catalog_ids():
		var tags := AbilityRules.families_of(AbilityRules.by_id(id))
		if not AbilityRules.ABILITY_FAMILIES.has(id) or tags.is_empty():
			untagged.append(id)
			continue
		for family in tags:
			if not AbilityRules.FAMILIES.has(family):
				untagged.append("%s:%s" % [id, family])
	check(untagged.is_empty(), "every combat ability wears a known family tag (%s)"
		% str(untagged))
	var bow: Dictionary = State.ITEMS["bow_short"]
	var sword: Dictionary = State.ITEMS["sword_short"]
	var great: Dictionary = State.ITEMS["sword_great"]
	var staff: Dictionary = State.ITEMS["staff_fire"]
	var shield: Dictionary = State.ITEMS["shield_kite"]
	var bare := {}
	check(AbilityRules.fits_gear(AbilityRules.by_id("barrage"), bow, {}),
		"a bow carries barrage")
	check(not AbilityRules.fits_gear(AbilityRules.by_id("barrage"), sword, {}),
		"a sword does not carry barrage")
	check(AbilityRules.fits_gear(AbilityRules.by_id("double_slash"), great, {}),
		"a greatsword is still a sword")
	check(AbilityRules.fits_gear(AbilityRules.by_id("executioner"), great, {}),
		"a two-hand skill fits a greatsword")
	check(not AbilityRules.fits_gear(AbilityRules.by_id("executioner"), sword, {}),
		"a one-hander does not fit a two-hand skill")
	check(AbilityRules.fits_gear(AbilityRules.by_id("cinder_lance"), staff, {}),
		"a staff carries its lance")
	check(AbilityRules.fits_gear(AbilityRules.by_id("fireball"), staff, {}),
		"a staff carries the starter spell")
	check(not AbilityRules.fits_gear(AbilityRules.by_id("fireball"), bow, {})
			and not AbilityRules.fits_gear(AbilityRules.by_id("fireball"), sword, {})
			and not AbilityRules.fits_gear(AbilityRules.by_id("fireball"), bare, {}),
		"the starter is not carried by a bow, a sword or an empty hand")
	# Two tags are alternatives: a row that wears both is usable from either kit.
	var shared := [AbilityRules.TYPE_SWORD, AbilityRules.TYPE_SHIELD]
	check(AbilityRules.fits_any_family(shared, sword, {}),
		"a shared row fits its sword tag")
	check(AbilityRules.fits_any_family(shared, bow, shield),
		"and its shield tag")
	check(not AbilityRules.fits_any_family(shared, bow, {}),
		"but not a kit whose hands fit neither tag")
	check(AbilityRules.requirement_label(AbilityRules.by_id("fireball")) == "STAFF"
			and AbilityRules.family_label(AbilityRules.by_id("fireball")) == "STAFF",
		"the rack names the starter's family")
	check(AbilityRules.fits_gear(AbilityRules.by_id("shield_charge"), sword, shield),
		"a shield skill fits the board in the off hand")
	check(AbilityRules.fits_gear(AbilityRules.by_id("charge"), bare, {}),
		"the bare hand carries the charge")
	check(not AbilityRules.fits_gear(AbilityRules.by_id("charge"), sword, {}),
		"a sword does not carry the bare-hand charge")
	check(AbilityRules.unlockable_ids().has("barrage")
			and AbilityRules.unlockable_ids().has("dash")
			and not AbilityRules.unlockable_ids().has("fireball")
			and not AbilityRules.unlockable_ids().has("charge")
			and not AbilityRules.unlockable_ids().has("bandage"),
		"the starter, fallback and consumables are not for sale")
	check(AbilityRules.unlockable_ids().size() == 27,
		"there are 27 purchasable combat skills, got %d"
		% AbilityRules.unlockable_ids().size())
	check(AbilityRules.unlock_cost_of("barrage") == 2
			and AbilityRules.unlock_cost_of("executioner") == 5,
		"the authored prices are read")
	check(AbilityRules.is_automatic("fireball")
			and AbilityRules.is_automatic("charge")
			and AbilityRules.is_automatic("bandage"),
		"starter, fallback and consumables are automatic")
	check(not AbilityRules.is_automatic("barrage"), "barrage is the player's to equip")


## The unlock is the player's, bought with boss keys and kept across a reload.
func _check_unlocks() -> void:
	check(meta.is_ability_unlocked("fireball") and meta.is_ability_unlocked("charge"),
		"a fresh player owns the starter and the bare-hand fallback")
	check(not meta.is_ability_unlocked("barrage"), "a fresh player has not opened barrage")
	var broke: Dictionary = meta.unlock_ability("barrage")
	check(not bool(broke.get("ok", true)) and int(meta.keys) == 0,
		"the rack refuses a skill the keys cannot cover")
	meta.award_keys(6)
	var opened: Dictionary = meta.unlock_ability("barrage")
	check(bool(opened.get("ok", false)) and meta.is_ability_unlocked("barrage"),
		"a paid press opens the skill (%s)" % str(opened.get("message", "")))
	check(int(meta.keys) == 4, "barrage takes its two keys, got %d" % int(meta.keys))
	var again: Dictionary = meta.unlock_ability("barrage")
	check(not bool(again.get("ok", true)), "the same skill cannot be bought twice")
	meta.save_meta()
	meta.unlocked_abilities.clear()
	meta.load_meta()
	check(meta.is_ability_unlocked("barrage"),
		"the opened skill survives a reload")
	check(not meta.is_ability_unlocked("dash"),
		"and nothing the player did not buy is open")


## The rig: equipped ids filtered by the hands, then the starter, the fallback
## and the consumables; a weapon swap changes the visible row, not the list.
func _check_rig(world: Node3D) -> void:
	var actor := fighter(world, 0, Vector3.ZERO)
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, true))
	actor.rig.set_ability_loadout(["barrage", "triple_volley", "double_slash",
		"dash"])
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["barrage", "triple_volley", "dash", "snap_shot", "focus", "bandage", "healing_potion"]),
		"a bow shows its bow skills, the any-hand dash and the consumables, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.SLOT_COUNT,
		"the hotbar is always ten slots wide")
	check(str(AbilityRules.definition_for(actor.rig, 8).get("id", "")) == "bandage"
			and str(AbilityRules.definition_for(actor.rig, 9).get("id", "")) == "healing_potion",
		"the bandage keeps key 9 and the potion key 0")

	var hud := HudScript.new()
	hud.name = "Hud"
	world.add_child(hud)
	hud.set_body(actor, "Probe", 1)
	var tiles: Array = hud.ability_tiles()
	check(tile_id(tiles[0]) == "barrage", "the HUD draws the first equipped skill")
	check(tile_key(tiles[0]) == "1", "the tile numbers stay the keys")
	hud.queue_free()

	# A sword hand: the bow skills wait, the sword skill and the any-hand skill
	# ride, and the stored list is untouched.
	actor.rig.apply_loadout(State.build_loadout("sword_short", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["double_slash", "dash", "quick_cut", "focus", "bandage", "healing_potion"]),
		"a sword shows its own skill and hides the bow rows, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))
	check(_same(Array(actor.rig.ability_loadout),
		["barrage", "triple_volley", "double_slash", "dash"]),
		"the equipped list survives the swap")

	# Back to the bow: the two bow skills return in their stored places.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["barrage", "triple_volley", "dash", "snap_shot", "focus", "bandage", "healing_potion"]),
		"the bow brings its rows back")

	# Bare hands: only the any-hand rows and the automatic charge.
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["dash", "charge", "focus", "bandage", "healing_potion"]),
		"an empty main hand shows the fallback charge, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))

	# A staff is a staff, not a greatsword: a two-hand skill does not slip in
	# through the staff's sword-index two.
	actor.rig.apply_loadout(State.build_loadout("staff_fire", "", ARMOR, {}, true))
	actor.rig.set_ability_loadout(["executioner", "cinder_lance", "dash"])
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["cinder_lance", "dash", "fireball", "focus", "bandage", "healing_potion"]),
		"a staff carries its lance and not a two-hand blade, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))

	# A moved skill keeps its cooldown: the timer belongs to the skill id, not
	# the key the player laid it on.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, true))
	actor.rig.set_ability_loadout(["barrage", "triple_volley", "dash"])
	actor.ability.setup(actor, actor.rig, actor.combat, 5.5)
	actor.ability._refresh_grants()
	actor.ability.cooldowns[0] = 3.0
	actor.rig.set_ability_loadout(["triple_volley", "barrage", "dash"])
	actor.ability._refresh_grants()
	check(is_equal_approx(actor.ability.cooldowns[1], 3.0),
		"a moved skill carries its cooldown to its new key, got %.2f"
		% actor.ability.cooldowns[1])
	check(is_equal_approx(actor.ability.cooldowns[0], 0.0),
		"the skill that took the old key starts ready")

	# The seat hand-off carries the list beside the kit.
	SeatLoadout.apply(actor.rig, State.build_loadout("bow_short", "", ARMOR, {}, true),
		{}, ["barrage", "dash"], true)
	check(_same(Array(actor.rig.ability_loadout), ["barrage", "dash"]),
		"a dressing puts the body's equipped list on the rig")


## The warband owns the equipped list and filters it by the body's current hands.
func _check_warband() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Keys")
	for item_id in ["bow_short", "sword_short", "shield_kite", "neck_shield",
			"staff_fire"]:
		warband.stash.add(item_id, 1)
	check(bool(warband.equip_merc(merc, "main", "bow_short").get("ok", false)),
		"the body holds a bow")
	var started: Array = warband.hotbar_layout(merc)
	check(_same(started, ["snap_shot", "focus", "", "", "", "", "", "", "bandage", "healing_potion"]),
		"a bow carries no starter spell; the two consumables keep their keys, got %s"
		% str(started))

	var bow_skill: Dictionary = warband.toggle_ability(merc, "barrage")
	check(bool(bow_skill.get("ok", false)), "a bow skill equips on a bow: %s"
		% str(bow_skill.get("message", "")))
	var sword_skill: Dictionary = warband.toggle_ability(merc, "double_slash")
	check(not bool(sword_skill.get("ok", true)),
		"a sword skill refuses while a bow is held (%s)" % str(sword_skill.get("message", "")))
	var any_skill: Dictionary = warband.toggle_ability(merc, "dash")
	check(bool(any_skill.get("ok", false)), "an any-hand skill equips on a bow")
	check(_same(warband.hotbar_layout(merc),
		["barrage", "dash", "snap_shot", "focus", "", "", "", "", "bandage", "healing_potion"]),
		"the equipped rows draw in order, got %s" % str(warband.hotbar_layout(merc)))

	# The sword set: the bow row waits, the sword row can now be equipped, and
	# the bow row is still in the stored list.
	warband.equip_merc(merc, "main", "sword_short")
	check(_same(warband.hotbar_layout(merc),
		["dash", "quick_cut", "focus", "", "", "", "", "", "bandage", "healing_potion"]),
		"the sword hides the bow row and the staff starter, got %s"
		% str(warband.hotbar_layout(merc)))
	check(bool(warband.toggle_ability(merc, "double_slash").get("ok", false)),
		"the sword skill equips on the sword")
	check(_same(warband.hotbar_layout(merc),
		["dash", "double_slash", "quick_cut", "focus", "", "", "", "", "bandage", "healing_potion"]),
		"the sword's own row joins the visible keys")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["barrage", "dash", "double_slash"]),
		"the waiting bow row is still stored, in its place")

	# Seven is the cap; an eighth refuses. The starter is not an equip and does
	# not count, but it is only drawn when the hands fit the staff family.
	for id in ["lunge_thrust", "butchers_cut", "gut_hook", "energy_shield"]:
		warband.toggle_ability(merc, id)
	check(warband.roster.hotbar_order_of(merc).size() == AbilityRules.MAX_EQUIPPED,
		"the bar reaches seven equipped skills")
	var overflow: Dictionary = warband.toggle_ability(merc, "three_strike")
	check(not bool(overflow.get("ok", true)),
		"the eighth equipped skill is refused")
	warband.equip_merc(merc, "main", "staff_fire")
	warband.reset_hotbar(merc)
	check(warband.roster.hotbar_order_of(merc).is_empty(),
		"UNEQUIP ALL clears the player's list")
	check(_same(warband.hotbar_layout(merc),
		["fireball", "focus", "", "", "", "", "", "", "bandage", "healing_potion"]),
		"and a staff draws the starter beside the consumables")

	# A locked skill is still just an id to the state; the rack UI is what gates
	# the press. The book tells the page what the player owns.
	var book: Array = warband.ability_book(merc)
	var barrage_row: Dictionary = {}
	for row in book:
		if str(row.get("id", "")) == "barrage":
			barrage_row = row
	check(str(barrage_row.get("type", "")) == AbilityRules.TYPE_BOW,
		"the book names barrage's family")
	check(_same(barrage_row.get("types", []), [AbilityRules.TYPE_BOW]),
		"and carries its tag list")
	check(bool(barrage_row.get("unlocked", false)),
		"the book reads the player's unlock ledger")


## The equipped order keeps hidden rows; the save round-trip and the co-op
## refusal are the same as the rest of the warband's gear.
func _check_move_and_save() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Moves")
	for item_id in ["bow_short", "sword_short", "staff_fire"]:
		warband.stash.add(item_id, 1)
	warband.equip_merc(merc, "main", "bow_short")
	for id in ["barrage", "triple_volley", "dash"]:
		warband.toggle_ability(merc, id)
	# The sword row is stored but hidden while the bow is out.
	warband.equip_merc(merc, "main", "sword_short")
	warband.toggle_ability(merc, "double_slash")
	warband.equip_merc(merc, "main", "bow_short")
	check(_same(warband.hotbar_layout(merc),
		["barrage", "triple_volley", "dash", "snap_shot", "focus",
			"", "", "", "bandage", "healing_potion"]),
		"the bow rows draw first, got %s" % str(warband.hotbar_layout(merc)))
	var moved: Dictionary = warband.move_hotbar_skill(merc, 0, 2)
	check(bool(moved.get("ok", false)), "moving a row answers ok: %s"
		% str(moved.get("message", "")))
	check(_same(warband.hotbar_layout(merc),
		["dash", "triple_volley", "barrage", "snap_shot", "focus",
			"", "", "", "bandage", "healing_potion"]),
		"the two rows traded keys, got %s" % str(warband.hotbar_layout(merc)))
	check(warband.roster.hotbar_order_of(merc).has("double_slash"),
		"the hidden sword row survived the move")
	# A staff puts the starter on the row; its key is not movable.
	warband.equip_merc(merc, "main", "staff_fire")
	check(_same(warband.hotbar_layout(merc),
		["dash", "fireball", "focus", "", "", "", "", "", "bandage", "healing_potion"]),
		"a staff draws the starter after the any-hand row, got %s"
		% str(warband.hotbar_layout(merc)))
	var starter_move: Dictionary = warband.move_hotbar_skill(merc, 1, 0)
	check(not bool(starter_move.get("ok", true))
			and str(starter_move.get("message", "")).contains("starter"),
		"the starter keeps its key, got %s" % str(starter_move.get("message", "")))
	warband.equip_merc(merc, "main", "bow_short")
	var consumable_move: Dictionary = warband.move_hotbar_skill(merc, 8, 0)
	check(not bool(consumable_move.get("ok", true)),
		"the consumables keep their keys")

	var saved: Dictionary = warband.to_dict()
	warband.reset_state()
	warband.from_dict(saved)
	check(warband.roster.count() == 1, "the body is back after the round-trip")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["dash", "triple_volley", "barrage", "double_slash"]),
		"the equipped order and the hidden sword row survive, got %s"
		% str(warband.roster.hotbar_order_of(merc)))
	check(_same(warband.hotbar_layout(merc),
		["dash", "triple_volley", "barrage", "snap_shot", "focus",
			"", "", "", "bandage", "healing_potion"]),
		"and the bar still draws the bow rows")

	warband.set_hotbar_order(merc, ["dash", "barrage"])
	warband.lent = true
	var lent_refusal: Dictionary = warband.toggle_ability(merc, "triple_volley")
	check(not bool(lent_refusal.get("ok", true)),
		"a lent warband refuses the equip")
	warband.lent = false


## The paperdoll row draws the same keys; the starter is not selectable, the
## consumables are not movable, and UNEQUIP ALL is the reset.
func _check_paperdoll() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Keys")
	warband.stash.add("staff_fire", 1)
	warband.equip_merc(merc, "main", "staff_fire")
	warband.toggle_ability(merc, "dash")
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(merc)
	check(doll.hotbar_tiles.size() == AbilityRules.SLOT_COUNT,
		"the paperdoll draws one key per slot")
	check(_same(doll.hotbar_layout(), warband.hotbar_layout(merc)),
		"the paperdoll's row is the body's own layout")
	check(tile_id(doll.hotbar_tiles[0]) == "dash",
		"the first key draws the equipped skill, got %s" % tile_id(doll.hotbar_tiles[0]))
	check(tile_id(doll.hotbar_tiles[1]) == "fireball",
		"a staff draws the starter after the equipped rows, got %s"
		% tile_id(doll.hotbar_tiles[1]))
	check(doll._reset_hotbar_button.text == "UNEQUIP ALL",
		"the reset button says what it now does")
	doll._on_hotbar_pressed(1)
	check(doll._hotbar_selected < 0,
		"the starter is not selectable for a move")
	doll._reset_hotbar()
	check(warband.roster.hotbar_order_of(merc).is_empty(),
		"the page's reset clears the player's list")
	doll.queue_free()
