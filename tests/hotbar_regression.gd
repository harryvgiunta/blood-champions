extends SceneTree
## The skill bar: five keys, one assignment per key.
##
## A skill is opened once on the player's ledger, then assigned to a key on a
## body. The body's hands decide which assigned skills actually reach the keys: a
## bow skill waits while the sword is out and comes back with the bow. The family
## starters are automatic and fill the first free keys behind the assignment; the
## bandage and the potion are not on the bar at all (Z and V). A run upgrade can
## buy up to five more keys, and ten is the ceiling. This walks the catalog layer,
## the player unlock ledger, the rig's grant, the warband's per-body assignment,
## its save round-trip, the character screen's SKILLS page and the co-op refusal.

const Actor = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const MetaScript = preload("res://scripts/roguelite/roguelite_meta.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const ProcEngine = preload("res://scripts/roguelite/proc_engine.gd")

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
	_check_widened_bar()
	_check_slots_and_save()
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
	check(AbilityRules.unlockable_ids().size() == 28,
		"there are 28 purchasable combat skills, got %d"
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


## The rig: equipped ids laid on the keys the player chose, then the starters in
## the first free keys; a weapon swap changes the visible row, not the list. The
## bandage and the potion are not on this row at all.
func _check_rig(world: Node3D) -> void:
	var actor := fighter(world, 0, Vector3.ZERO)
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, true))
	actor.rig.set_ability_loadout(["barrage", "triple_volley", "double_slash",
		"dash"])
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["barrage", "triple_volley", "snap_shot", "dash", "focus"]),
		"a bow shows its bow skills, the starter in the first free key and the any-hand dash, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.SLOT_COUNT,
		"the hotbar is five keys wide")
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.slots_for(actor.rig),
		"and it is exactly as wide as the rig's own bar")

	var hud := HudScript.new()
	hud.name = "Hud"
	world.add_child(hud)
	hud.set_body(actor, "Probe", 1)
	var tiles: Array = hud.ability_tiles()
	check(tiles.size() == AbilityRules.MAX_SLOT_COUNT,
		"the HUD builds every key a bar can ever have, got %d" % tiles.size())
	check(tile_id(tiles[0]) == "barrage", "the HUD draws the first assigned skill")
	check(tile_key(tiles[0]) == "1", "the tile numbers stay the keys")
	var shown := 0
	for tile in tiles:
		if (tile as Control).visible:
			shown += 1
	check(shown == AbilityRules.SLOT_COUNT,
		"a five-key bar shows five frames, got %d" % shown)
	hud.queue_free()

	# A sword hand: the bow skills wait, the sword skill and the any-hand skill
	# ride, and the stored list is untouched.
	actor.rig.apply_loadout(State.build_loadout("sword_short", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["quick_cut", "focus", "double_slash", "dash"]),
		"a sword shows its own skill, the two starters in the keys the bow rows freed and the any-hand skill, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))
	check(_same(Array(actor.rig.ability_loadout),
		["barrage", "triple_volley", "double_slash", "dash"]),
		"the equipped list survives the swap")

	# Back to the bow: the two bow skills return to the keys they were given.
	actor.rig.apply_loadout(State.build_loadout("bow_short", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["barrage", "triple_volley", "snap_shot", "dash", "focus"]),
		"the bow brings its rows back to their own keys")

	# Bare hands: the fallback charge takes the first free key, then Focus, and
	# the any-hand dash the bar still carries keeps its own key.
	actor.rig.apply_loadout(State.build_loadout("", "", ARMOR, {}, true))
	check(_same(_ids(AbilityRules.granted(actor.rig)), ["charge", "focus", "dash"]),
		"an empty main hand shows the fallback charge, the any-hand starter and the any-hand skill, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))

	# A staff is a staff, not a greatsword: a two-hand skill does not slip in
	# through the staff's sword-index two.
	actor.rig.apply_loadout(State.build_loadout("staff_fire", "", ARMOR, {}, true))
	actor.rig.set_ability_loadout(["executioner", "cinder_lance", "dash"])
	check(_same(_ids(AbilityRules.granted(actor.rig)),
		["fireball", "cinder_lance", "dash", "focus"]),
		"a staff carries its lance and not a two-hand blade, got %s"
		% str(_ids(AbilityRules.granted(actor.rig))))

	# A skill that changes key keeps its cooldown: the timer belongs to the skill
	# id, not to the key the player laid it on.
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

	# A run upgrade buys the rig another key, and the row grows to it.
	actor.rig.set("ability_extra_slots", 2)
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.SLOT_COUNT + 2,
		"two keys bought by the run widen the bar, got %d"
		% AbilityRules.granted(actor.rig).size())
	actor.rig.set("ability_extra_slots", 99)
	check(AbilityRules.granted(actor.rig).size() == AbilityRules.MAX_SLOT_COUNT,
		"and the bar never passes its ceiling")
	actor.rig.set("ability_extra_slots", 0)

	# The seat hand-off carries the list beside the kit.
	SeatLoadout.apply(actor.rig, State.build_loadout("bow_short", "", ARMOR, {}, true),
		["barrage", "dash"], true)
	check(_same(Array(actor.rig.ability_loadout), ["barrage", "dash"]),
		"a dressing puts the body's assigned keys on the rig")


## The warband owns the assignment and filters it by the body's current hands.
func _check_warband() -> void:
	warband.reset_state()
	var merc: int = warband.add_mercenary("Keys")
	for item_id in ["bow_short", "sword_short", "shield_kite", "focus_skull",
			"staff_fire"]:
		warband.stash.add(item_id, 1)
	check(bool(warband.equip_merc(merc, "main", "bow_short").get("ok", false)),
		"the body holds a bow")
	var started: Array = warband.hotbar_layout(merc)
	check(_same(started, ["snap_shot", "focus", "", "", ""]),
		"a bow carries its starter and the any-hand starter; medicine is not on the row, got %s"
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
		["barrage", "dash", "snap_shot", "focus", ""]),
		"the assigned keys come first and the starters fill the free ones, got %s"
		% str(warband.hotbar_layout(merc)))

	# The sword set: the bow row waits on its own key, the sword row can now be
	# equipped, and the bow row is still in the stored list.
	warband.equip_merc(merc, "main", "sword_short")
	check(_same(warband.hotbar_layout(merc),
		["quick_cut", "dash", "focus", "", ""]),
		"the sword hides the bow row and fills the key it freed, got %s"
		% str(warband.hotbar_layout(merc)))
	check(bool(warband.toggle_ability(merc, "double_slash").get("ok", false)),
		"the sword skill equips on the sword")
	check(_same(warband.hotbar_layout(merc),
		["quick_cut", "dash", "double_slash", "focus", ""]),
		"the sword's own row joins the visible keys")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["barrage", "dash", "double_slash"]),
		"the waiting bow row is still stored, on its own key")

	# Five keys are the bar: a sixth skill refuses rather than sliding the row.
	for id in ["lunge_thrust", "butchers_cut"]:
		warband.toggle_ability(merc, id)
	check(warband.roster.hotbar_order_of(merc).size() == AbilityRules.SLOT_COUNT,
		"the bar holds five assigned skills, got %d"
		% warband.roster.hotbar_order_of(merc).size())
	var overflow: Dictionary = warband.toggle_ability(merc, "gut_hook")
	check(not bool(overflow.get("ok", true)),
		"the sixth assigned skill is refused (%s)" % str(overflow.get("message", "")))
	warband.set_hotbar_order(merc, [])
	warband.equip_merc(merc, "main", "staff_fire")
	check(_same(warband.hotbar_layout(merc), ["fireball", "focus", "", "", ""]),
		"and a staff draws the starter spell the clear exposed")

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


## The bar's own legendary upgrade: one more key a stack, five stacks, and the
## ceiling is the engine's - the sixth card is refused, so a session's bar is
## never wider than ten keys.
func _check_widened_bar() -> void:
	var row: Dictionary = Mods.get_mod("widened_bar")
	check(not row.is_empty(), "the bar has its own upgrade row")
	check(str(row.get("rarity", "")) == Mods.RARITY_LEGENDARY,
		"and it is a legendary, got %s" % str(row.get("rarity", "")))
	check(int(row.get("max_stacks", 0)) == 5,
		"five cards are the whole staircase, got %d" % int(row.get("max_stacks", 0)))
	check(Mods.ready_of("widened_bar"), "the row is live, not a placeholder")
	check(AbilityRules.SLOT_COUNT + int(row.get("max_stacks", 0)) == AbilityRules.MAX_SLOT_COUNT,
		"five keys plus five cards is the ten-key ceiling")
	var engine = ProcEngine.new(7, 1)
	check(engine.add_mod("widened_bar"), "the card takes")
	check(is_equal_approx(engine.stat("hotbar_slots"), 1.0),
		"one card buys one key, got %.1f" % engine.stat("hotbar_slots"))
	for _copy in 4:
		engine.add_mod("widened_bar")
	check(is_equal_approx(engine.stat("hotbar_slots"), 5.0),
		"five cards buy five keys, got %.1f" % engine.stat("hotbar_slots"))
	check(not engine.add_mod("widened_bar"), "a sixth card is refused")


## One skill per key: the assignment is positional, keeps a hole where the player
## left one, survives the save round-trip, and a lent warband refuses the press.
func _check_slots_and_save() -> void:
	warband.reset_state()
	meta.award_keys(20)
	meta.unlock_ability("triple_volley")
	if not meta.is_ability_unlocked("barrage"):
		meta.unlock_ability("barrage")
	var merc: int = warband.add_mercenary("Moves")
	for item_id in ["bow_short", "sword_short", "staff_fire"]:
		warband.stash.add(item_id, 1)
	warband.equip_merc(merc, "main", "bow_short")
	var placed: Dictionary = warband.set_hotbar_slot(merc, 0, "barrage")
	check(bool(placed.get("ok", false)), "a key takes a skill: %s"
		% str(placed.get("message", "")))
	warband.set_hotbar_slot(merc, 2, "triple_volley")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["barrage", "", "triple_volley"]),
		"assigning key 3 leaves the empty key it stepped over, got %s"
		% str(warband.roster.hotbar_order_of(merc)))
	check(_same(warband.hotbar_layout(merc),
		["barrage", "snap_shot", "triple_volley", "focus", ""]),
		"the starters fill the free keys behind the assignment, got %s"
		% str(warband.hotbar_layout(merc)))

	warband.set_hotbar_slot(merc, 0, "")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["", "", "triple_volley"]),
		"emptying a key leaves the rows behind it where they were, got %s"
		% str(warband.roster.hotbar_order_of(merc)))
	check(_same(warband.hotbar_layout(merc),
		["snap_shot", "focus", "triple_volley", "", ""]),
		"the starters take the keys the empty row left, got %s"
		% str(warband.hotbar_layout(merc)))

	var misfit: Dictionary = warband.set_hotbar_slot(merc, 1, "double_slash")
	check(not bool(misfit.get("ok", true)),
		"a sword skill refuses a key while a bow is held (%s)" % str(misfit.get("message", "")))
	var automatic: Dictionary = warband.set_hotbar_slot(merc, 1, "snap_shot")
	check(not bool(automatic.get("ok", true)),
		"a family starter cannot be assigned")
	var locked: Dictionary = warband.set_hotbar_slot(merc, 1, "backstab")
	check(not bool(locked.get("ok", true)),
		"a skill the player has not unlocked cannot be assigned (%s)"
		% str(locked.get("message", "")))
	var beyond: Dictionary = warband.set_hotbar_slot(merc, AbilityRules.MAX_SLOT_COUNT, "dash")
	check(not bool(beyond.get("ok", true)), "there is no eleventh key")

	var saved: Dictionary = warband.to_dict()
	warband.reset_state()
	warband.from_dict(saved)
	check(warband.roster.count() == 1, "the body is back after the round-trip")
	check(_same(Array(warband.roster.hotbar_order_of(merc)),
		["", "", "triple_volley"]),
		"the hole and the rows behind it survive the round-trip, got %s"
		% str(warband.roster.hotbar_order_of(merc)))
	check(_same(warband.hotbar_layout(merc),
		["snap_shot", "focus", "triple_volley", "", ""]),
		"and the bar still draws the bow rows on their keys, got %s"
		% str(warband.hotbar_layout(merc)))

	warband.lent = true
	var lent_refusal: Dictionary = warband.set_hotbar_slot(merc, 0, "triple_volley")
	check(not bool(lent_refusal.get("ok", true)),
		"a lent warband refuses the assignment")
	warband.lent = false


## The character screen's SKILLS page: one tile per key it can have, the body's own
## row drawn on the five, a press on a key opening the picker, and the review
## listing the player's unlocks with the catalogue's words.
func _check_paperdoll() -> void:
	warband.reset_state()
	meta.award_keys(20)
	if not meta.is_ability_unlocked("barrage"):
		meta.unlock_ability("barrage")
	var merc: int = warband.add_mercenary("Keys")
	warband.stash.add("bow_short", 1)
	warband.equip_merc(merc, "main", "bow_short")
	warband.set_hotbar_slot(merc, 2, "barrage")
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(merc)
	doll.open_page("skills")
	check(doll.current_page() == "skills", "the screen opens the skills page")
	check(doll.hotbar_tiles.size() == AbilityRules.MAX_SLOT_COUNT,
		"the page builds every key a bar can have, got %d" % doll.hotbar_tiles.size())
	check(doll.bar_keys() == AbilityRules.SLOT_COUNT,
		"a body outside a run has the five keys the game ships with")
	check(_same(doll.hotbar_ids, warband.hotbar_layout(merc)),
		"the page's row is the body's own layout, got %s" % str(doll.hotbar_ids))
	check(tile_id(doll.hotbar_tiles[0]) == "snap_shot",
		"the first key draws the starter, got %s" % tile_id(doll.hotbar_tiles[0]))
	check(tile_id(doll.hotbar_tiles[2]) == "barrage",
		"key 3 draws the skill the player put there, got %s"
		% tile_id(doll.hotbar_tiles[2]))
	var shown := 0
	for index in doll.hotbar_buttons.size():
		if (doll.hotbar_buttons[index] as Control).visible:
			shown += 1
	check(shown == AbilityRules.SLOT_COUNT,
		"five keys are drawn for a five-key bar, got %d" % shown)

	# A press on a key raises the picker; choosing a row assigns it to that key.
	doll._on_skill_slot_pressed(2)
	check(doll._skill_slot_selected == 2, "a press on a key picks that key")
	check(doll._menu_box.visible, "and the picker opens")
	var cleared: Dictionary = doll.assign_skill(2, "")
	check(bool(cleared.get("ok", false)), "a key can be emptied from the page: %s"
		% str(cleared.get("message", "")))
	check(_same(warband.hotbar_layout(merc), ["snap_shot", "focus", "", "", ""]),
		"the emptied key is empty again, got %s" % str(warband.hotbar_layout(merc)))
	var placed: Dictionary = doll.assign_skill(2, "barrage")
	check(bool(placed.get("ok", false)), "and a skill can be put back on it: %s"
		% str(placed.get("message", "")))
	check(tile_id(doll.hotbar_tiles[2]) == "barrage",
		"the page repaints the key it just wrote")
	var locked: Dictionary = doll.assign_skill(3, "dash")
	check(not bool(locked.get("ok", true)),
		"a skill the player has not unlocked is refused by the page (%s)"
		% str(locked.get("message", "")))

	# The review: the unlocked rows and their words are on the page, and the run's
	# upgrades are not (no island is live in this harness).
	check(doll._book_box.get_child_count() > 0,
		"the review lists the player's unlocked skills")
	check(doll._book_head.text.begins_with("UNLOCKED SKILLS"),
		"the review says what it is, got %s" % doll._book_head.text)
	check(doll._upgrade_head.text.begins_with("UPGRADES THIS RUN"),
		"and the upgrades have their own list, got %s" % doll._upgrade_head.text)

	# The gear page's rows: a press opens the alternatives and never unequips.
	doll.open_page("gear")
	var before := String(warband.roster.equipped_of(merc).get("main", ""))
	doll.slot_rows["main"]["button"].pressed.emit()
	check(doll._menu_box.visible, "a press on a worn slot raises its alternatives")
	check(String(warband.roster.equipped_of(merc).get("main", "")) == before,
		"and never takes the piece off")
	doll._on_slot_pressed("main")
	check(String(warband.roster.equipped_of(merc).get("main", "")) == before,
		"a second press still does not unequip")
	doll.close()
	doll.queue_free()
