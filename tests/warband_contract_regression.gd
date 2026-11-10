extends SceneTree
## Phase 0 contract regression for Ghost of the Warband: the shared enums line up
## with the vocabulary this game already ships, the 10% overkill and downed rules
## answer at every boundary, the passive bubble scaler is one multiplier, and the
## warband roster, infinite stash and recruiter keep their promises.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const Recruits = preload("res://scripts/warband/recruit_catalog.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const StateScript = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://warband_contract_state.json"

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()

	check_slots()
	check_overkill()
	check_gear_transfer(state, warband)
	check_vendor(state, warband)
	check_reserve(warband)
	check_persistence(warband)
	check_party_mode(warband)
	check_auto_arm(warband)
	check_reequip(warband)
	check_hand_set(warband)

	_remove_test_save()
	print("WARBAND_CONTRACT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- slots -----------------------------------------------------------------

func check_slots() -> void:
	var ids: Array[String] = []
	for slot in Contracts.SLOT_ORDER:
		ids.append(Contracts.slot_id(slot))
	# The page lists the steel first, in the order a body is armed. The wire ids
	# keep their own order, so the two only have to name the same seven slots.
	var listed := ids.duplicate()
	listed.sort()
	var known: Array = Rules.SLOTS.duplicate()
	known.sort()
	check(listed == known,
		"SlotType ids must be exactly EquipmentRules.SLOTS, got %s" % str(ids))
	check(ids.slice(0, 2) == ["main", "off"],
		"and the paperdoll order is steel first, got %s" % str(ids))
	check(Contracts.slot_id(Contracts.SlotType.BOOTS) == "feet", "BOOTS is the existing feet id")
	check(Contracts.slot_id(Contracts.SlotType.OFF_HAND) == "off", "OFF_HAND is the existing off id")
	check(Contracts.slot_from_id("feet") == Contracts.SlotType.BOOTS, "feet round-trips")
	check(Contracts.slot_from_id("nope") == -1, "unknown ids are refused")
	check(Contracts.slot_from_id("neck") == -1 and Contracts.slot_from_id("ring1") == -1,
		"and a neck or a ring is not a slot any more")
	check(Contracts.slot_label(Contracts.SlotType.OFF_HAND) == "Off-Hand",
		"labels read as the design does")

	# Every catalog item must map onto exactly one weapon subtype.
	check(Contracts.weapon_subtype(StateScript.ITEMS["bow_short"]) == Contracts.WeaponSubType.BOW, "shortbow is a bow")
	check(Contracts.weapon_subtype(StateScript.ITEMS["sword_great"]) == Contracts.WeaponSubType.TWO_HAND, "greatsword is two-handed")
	check(Contracts.weapon_subtype(StateScript.ITEMS["dagger_iron"]) == Contracts.WeaponSubType.ONE_HAND, "dagger is one-handed")
	check(Contracts.weapon_subtype(StateScript.ITEMS["shield_buckler"]) == Contracts.WeaponSubType.SHIELD, "buckler is a shield")
	check(Contracts.weapon_subtype(StateScript.ITEMS["staff_fire"]) == Contracts.WeaponSubType.STAFF, "ember staff is a staff")
	check(Contracts.weapon_subtype(StateScript.ITEMS["focus_tome"]) == Contracts.WeaponSubType.TOME, "ash tome is a tome")
	check(Contracts.weapon_subtype(StateScript.ITEMS["focus_skull"]) == Contracts.WeaponSubType.SKULL, "bone skull is a skull")
	check(Contracts.weapon_subtype(StateScript.ITEMS["bandage_linen"]) == Contracts.WeaponSubType.NONE, "a bandage is not a weapon")
	for item_id in StateScript.ITEMS:
		var item: Dictionary = StateScript.ITEMS[item_id]
		var subtype := Contracts.weapon_subtype(item)
		if str(item.get("category", "")) == "focus":
			check(subtype in [Contracts.WeaponSubType.SKULL, Contracts.WeaponSubType.TOME],
				"%s must be a skull or a tome" % item_id)
	check(Contracts.two_handed_item(StateScript.ITEMS["sword_great"]), "2H leaves no off hand")
	check(not Contracts.two_handed_item(StateScript.ITEMS["shield_buckler"]), "a shield is not two-handed")

# --- 10% overkill ----------------------------------------------------------

func check_overkill() -> void:
	var clean := Contracts.resolve_damage(100.0, 100.0, 100.0)
	check(int(clean["state"]) == Contracts.HealthState.DOWNED, "an exactly-lethal hit downs, never kills")
	check(bool(clean["downed"]) and not bool(clean["died"]), "exactly lethal sets downed")
	check(is_equal_approx(float(clean["overkill"]), 0.0), "exactly lethal is zero overkill")

	var light := Contracts.resolve_damage(100.0, 100.0, 105.0)
	check(int(light["state"]) == Contracts.HealthState.DOWNED, "-5% overkill downs")
	var edge := Contracts.resolve_damage(100.0, 100.0, 110.0)
	check(int(edge["state"]) == Contracts.HealthState.DOWNED, "exactly -10% still downs")
	check(is_equal_approx(float(edge["overkill"]), 10.0), "the edge overkill is 10")
	var heavy := Contracts.resolve_damage(100.0, 100.0, 110.01)
	check(int(heavy["state"]) == Contracts.HealthState.DEAD, "more than -10% kills outright")
	check(bool(heavy["died"]) and not bool(heavy["downed"]), "heavy overkill is a death")

	var survived := Contracts.resolve_damage(100.0, 100.0, 40.0)
	check(int(survived["state"]) == Contracts.HealthState.ALIVE, "a non-lethal hit stays alive")
	check(is_equal_approx(float(survived["health"]), 60.0), "non-lethal health is subtracted once")
	check(not bool(Contracts.resolve_damage(100.0, 100.0, 0.0)["ok"]), "a zero hit is not a hit")

	# The same rule measured against a bigger pool: 10% of 100 is 10, not 10% of
	# the damage. A 120-damage hit on 50 max health overkills by 70 and kills.
	var big := Contracts.resolve_damage(50.0, 50.0, 120.0)
	check(int(big["state"]) == Contracts.HealthState.DEAD, "threshold scales with max health")
	check(Contracts.finishes_downed(100.0, 10.0) == false, "a light blow cannot finish a downed body")
	check(Contracts.finishes_downed(100.0, 10.5) == true, "a heavy blow finishes a downed body")
	check(Contracts.REVIVE_CHANNEL_SECONDS == 5.0, "the revive channel is five seconds")

# --- gear hand-offs --------------------------------------------------------

## The stash is one pool: a piece another mercenary wears must be transferable,
## a piece can move between slots on the same body, and a pickup can snap into a
## hand when it is the better blade. Nothing in these moves may lose an item.
func check_gear_transfer(_state, warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash
	var ash: int = warband.add_mercenary("Ash")
	var corvin: int = warband.add_mercenary("Corvin")
	# Only the rescuer's shiv exists: the exact shape of the tutorial.
	roster.equip(corvin, "main", "dagger_ironwood")
	var before_total: int = warband.total_value()

	var hand: Dictionary = warband.equip_merc(ash, "main", "dagger_ironwood")
	check(bool(hand.get("ok", false)), "a worn dagger can be handed to another body: %s"
		% str(hand.get("message", "")))
	check(str(roster.equipped_of(ash).get("main", "")) == "dagger_ironwood",
		"the receiving body now holds it")
	check(str(roster.equipped_of(corvin).get("main", "")) == "",
		"the giver no longer wears it")
	check(warband.total_value() == before_total, "a hand-off loses no value")

	# Moving the same piece between slots on one body is legal too.
	var moved: Dictionary = warband.equip_merc(ash, "off", "dagger_ironwood")
	check(bool(moved.get("ok", false)), "the same dagger moves to the off hand")
	check(str(roster.equipped_of(ash).get("main", "")) == "",
		"the main hand is empty after the move")
	check(str(roster.equipped_of(ash).get("off", "")) == "dagger_ironwood",
		"the off hand holds it")

	# An unowned piece is still refused.
	var unowned: Dictionary = warband.equip_merc(ash, "main", "sword_great")
	check(unowned.get("ok") == false, "a piece nobody owns is refused")
	check(str(roster.equipped_of(ash).get("off", "")) == "dagger_ironwood",
		"a refused equip leaves the body alone")

	# A pickup only ever *fills* a hand, and only a body with nothing in them is
	# filled at all.
	var dara: int = warband.add_mercenary("Dara")
	stash.add("sword_short", 1)
	var empty_hand: Dictionary = warband.auto_equip(dara, "sword_short")
	check(bool(empty_hand.get("ok", false)), "a looted blade fills an empty main hand")
	check(str(roster.equipped_of(dara).get("main", "")) == "sword_short",
		"the shortsword is worn")
	stash.add("dagger_iron", 1)
	var worse: Dictionary = warband.auto_equip(dara, "dagger_iron")
	check(worse.get("ok") == false,
		"a second piece does not follow the first into a body holding steel")
	check(warband.stash.pooled_count("dagger_iron") == 1, "and it is still owned")
	# A body already holding steel keeps it, however much better the drop is:
	# nothing is swapped under the player (or a squadmate) in the middle of a fight.
	stash.add("sword_arming", 1)
	var better: Dictionary = warband.auto_equip(dara, "sword_arming")
	check(not bool(better.get("ok", true)), "a better blade does not trade a worn one")
	check(str(roster.equipped_of(dara).get("main", "")) == "sword_short",
		"the shortsword stays in the hand")
	check(warband.stash.pooled_count("sword_arming") == 1,
		"and the arming sword waits in the pool")
	# The press that chooses again is the body's own re-equip.
	var kit: Dictionary = warband.reequip_merc(dara)
	check(bool(kit.get("ok", false)), "the body re-equips: %s" % str(kit.get("message", "")))
	check(str(roster.equipped_of(dara).get("main", "")) == "sword_arming",
		"and the arming sword wins on the band's own priority, got %s"
		% str(roster.equipped_of(dara).get("main", "")))

	# Unarmed bodies get the first thing they pick up - but only what their trade
	# fights with. A blade's body leaves the band's spare bow in the pool
	# (`Contracts.DISPOSITION_GEAR_REFUSED`), and the bow body takes it.
	var bram: int = warband.add_mercenary("Bram")
	stash.add("bow_short", 1)
	var first: Dictionary = warband.auto_equip(bram, "bow_short")
	check(not bool(first.get("ok", true)) and warband.stash.pooled_count("bow_short") == 1,
		"an unarmed melee body does not loot a bow")
	warband.set_disposition(bram, Contracts.DISPOSITION_BOW)
	var first_bow: Dictionary = warband.auto_equip(bram, "bow_short")
	check(bool(first_bow.get("ok", false)), "an unarmed bow body takes the bow it loots")
	check(str(roster.equipped_of(bram).get("main", "")) == "bow_short", "the bow is in hand")

# --- souls -----------------------------------------------------------------

## `TAB`'s two weapon sets: a body carries two complete pairs and exactly one is
## in its hands. The swap alternates, the set being left remembers what it held,
# --- recruiter -------------------------------------------------------------

## The town desk sells *bodies*, the way a run's board does: one of each trade,
## rolled at level 1, already inside the hand and the armour the card names, with
## the one skill on it - and nothing dresses a bought body afterwards. The oath
## itself is the band's own curve (free while the desk is garrisoning, dearer past
## the free places) and the cap is still the field.
func check_vendor(state, warband) -> void:
	warband.reset_state()
	state.credits = 1000
	var board: Array[Dictionary] = warband.town_board()
	check(board.size() == Recruits.OPTIONS, "the desk lays out three bodies")
	var trades: Dictionary = {}
	var names: Dictionary = {}
	for row in board:
		trades[str(row.get("archetype", ""))] = true
		names[str(row.get("name", "")).to_lower()] = true
		check(int(row.get("level", 0)) == Recruits.TOWN_LEVEL, "every body is level one")
		check(int(row.get("rung", -1)) == 0, "so every card is rung 0")
		check(not (row.get("gear", {}) as Dictionary).is_empty(), "and carries its kit on the card")
	for archetype in Recruits.ARCHETYPES:
		check(trades.has(archetype), "a %s body is on the board" % archetype)
	check(names.size() == board.size(), "three rows read as three people")
	check(warband.hire_cost() == 0, "the first oath is free")

	var offer: Dictionary = board[0]
	var hired: Dictionary = warband.hire(offer)
	check(bool(hired.get("ok", false)),
		"hiring swears a body: %s" % str(hired.get("message", "")))
	check(int(hired.get("cost", -1)) == 0, "and quotes nothing")
	check(int(state.credits) == 1000, "a free oath spends no gold")
	check(warband.roster.count() == 1, "the body joins the warband")
	var merc_id := int(hired.get("merc_id", -1))
	# The desk sold the card, not a naked body: the whole kit walks on.
	var card: Dictionary = offer.get("gear", {})
	var worn: Dictionary = warband.roster.equipped_of(merc_id)
	for slot in ["main", "head", "chest", "hands", "legs", "feet"]:
		check(str(worn.get(slot, "")) == str(card.get(slot, "")),
			"the body wears the %s the card named (%s)" % [slot, str(worn.get(slot, ""))])
	check(warband.is_gear_locked(merc_id), "the kit is locked")
	var bar: Array[String] = warband.roster.hotbar_order_of(merc_id)
	check(bar.size() <= 1, "and the bar holds the one skill the card named (%d)" % bar.size())
	check(not warband.roster.is_recruit(merc_id), "a town oath is not a run's recruit")
	check(warband.band_field_count() == 1, "it spends a place in the deployment cap")
	check(not warband.roster.is_reserve(merc_id), "and takes the field at the desk")

	# Nothing re-dresses a bought body and nothing takes its kit back.
	warband.stash.add("sword_great", 1)
	warband.stash.add("armor_plate_chest", 1)
	check(not bool(warband.dress_recruit(merc_id).get("ok", true)),
		"the band's arming pass refuses it")
	check(not bool(warband.equip_merc(merc_id, "main", "sword_great").get("ok", true)),
		"and so does the paperdoll")
	check(not bool(warband.swap_weapon_set(merc_id).get("ok", true)),
		"and the weapon-set swap")
	var stance: Dictionary = warband.cycle_disposition(merc_id)
	check(not bool(stance.get("ok", true)), "and the stance chip")
	check(str(stance.get("message", "")).contains("kit is locked"),
		"which says why: %s" % str(stance.get("message", "")))
	var laid: Dictionary = warband.set_hotbar_order(merc_id, ["double_slash"])
	check(not bool(laid.get("ok", true)), "and the ability bar")
	check(str(laid.get("message", "")).contains("kit is locked"),
		"which says why too: %s" % str(laid.get("message", "")))
	check(str(warband.roster.equipped_of(merc_id).get("main", "")) == str(card.get("main", "")),
		"the kit is where the desk put it")
	check(warband.roster.hotbar_order_of(merc_id).size() == bar.size(),
		"and the bar is the card's")

	# The board brings out three more: the row just bought is not for sale again.
	var remade: Array[Dictionary] = warband.town_board()
	check(remade.size() == Recruits.OPTIONS, "the desk lays out three more after a sale")
	for row in remade:
		check(str(row.get("name", "")) != str(offer.get("name", "")),
			"and does not sell the name it just swore")

	# Past the free places the desk prices again, and every oath costs more than
	# the one before it.
	while warband.roster.count() < VendorScript.FREE_HIRES:
		warband.add_mercenary("Free %d" % warband.roster.count())
	warband.deployment_cap = VendorScript.FREE_HIRES + 1
	var first_paid: int = warband.hire_cost()
	check(first_paid == VendorScript.HIRE_BASE_COST + VendorScript.HIRE_STEP_COST * VendorScript.FREE_HIRES,
		"the oath past the free places is priced again (%d)" % first_paid)
	var paid_board: Array[Dictionary] = warband.town_board()
	check(int((paid_board[0] as Dictionary).get("price", -1)) == first_paid,
		"and the card carries the desk's price")
	var paid: Dictionary = warband.hire(paid_board[0])
	check(bool(paid.get("ok", false)), "a priced oath goes through while there is room")
	check(int(state.credits) == 1000 - first_paid, "exactly the quoted price is spent")
	check(warband.hire_cost() > first_paid, "the next body costs more")

	# The cap is hard.
	warband.deployment_cap = VendorScript.FREE_HIRES
	var full: Dictionary = warband.hire(warband.town_board()[0])
	check(full.get("ok") == false, "the cap refuses another body")
	check(warband.roster.count() == VendorScript.FREE_HIRES + 1, "the roster stays where it was")

	# A poor purse buys nothing, once the free places are behind it, and a ware is
	# never a body.
	state.credits = 5
	warband.deployment_cap = VendorScript.FREE_HIRES + 4
	var sworn: int = warband.roster.count()
	var poor: Dictionary = warband.hire(warband.town_board()[0])
	check(poor.get("ok") == false, "no gold, no blade")
	check(warband.roster.count() == sworn, "the roster is unchanged")
	check(not bool(warband.hire({"id": "bandage_linen"}).get("ok", true)),
		"a ware is not a body")
	check(warband.roster.count() == sworn, "and swears nobody")
	state.credits = 99999
	warband.deployment_cap = Contracts.MAX_DEPLOYMENT_CAP

# --- the field and the reserve ---------------------------------------------

## The field holds at most the deployment cap; a name sworn past it waits in the
## reserve, the name that waited longest is the first to take a freed place, and
## a load always stands the warband up inside the cap.
func check_reserve(warband) -> void:
	warband.reset_state()
	var cap: int = warband.deployment_cap
	var ids: Array[int] = []
	for index in cap + 2:
		ids.append(warband.add_mercenary("Oath %d" % index))
	check(warband.roster.field_count() == cap,
		"the field fills to the cap (%d)" % warband.roster.field_count())
	check(warband.roster.is_reserve(ids[cap]) and warband.roster.is_reserve(ids[cap + 1]),
		"the two sworn past it wait in the reserve")
	check(warband.field_room() == 0 and warband.deploy_reserve() == -1,
		"a full field calls nobody up")
	warband.roster.apply_damage(ids[0], 10000.0)
	check(not warband.roster.has(ids[0]), "a fallen body leaves the books")
	check(warband.field_room() == 1, "and frees one place (%d)" % warband.field_room())
	check(warband.deploy_reserve() == ids[cap], "the name that waited longest takes it")
	check(not warband.roster.is_reserve(ids[cap]) and warband.roster.is_reserve(ids[cap + 1]),
		"and only him")
	# A file written before the reserve fielded every name: a load steps the
	# newest back until the field fits.
	var data: Dictionary = warband.to_dict()
	for record in data["roster"]["mercenaries"]:
		record["reserve"] = false
	warband.from_dict(data)
	check(warband.roster.field_count() == cap,
		"a load fields no more than the cap (%d)" % warband.roster.field_count())
	check(warband.roster.is_reserve(ids[cap + 1]) and not warband.roster.is_reserve(ids[cap]),
		"and the newest name goes back to wait")
	# An empty field takes its reserve, so a load always has bodies to stand up.
	for record in data["roster"]["mercenaries"]:
		record["reserve"] = true
	warband.from_dict(data)
	check(warband.roster.field_count() == cap,
		"an empty field takes the reserve up to the cap (%d)" % warband.roster.field_count())
	warband.reset_state()

# --- persistence -----------------------------------------------------------

func check_persistence(warband) -> void:
	warband.reset_state()
	warband.add_mercenary("Kestrel")
	warband.stash.add("club_makeshift", 2)
	warband.save_state()
	var before : String = warband.describe()
	var merc_count : int = warband.roster.count()
	warband.reset_state()
	check(warband.roster.count() == 0, "reset clears the roster")
	var loaded: bool = warband.load_state()
	check(loaded, "a saved warband loads")
	check(warband.roster.count() == merc_count, "mercenaries survive")
	check(warband.stash.pooled_count("club_makeshift") == 2, "the stash survives")
	check(warband.describe() == before, "the saved card round-trips exactly")
	check(warband.total_value() > 0, "the warband has a worth")

# --- the party's mode ------------------------------------------------------

## How the squad picks its fights is the warband's: a fresh band answers rather
## than hunts (`Contracts.DEFAULT_PARTY_MODE`), a named mode takes and is announced
## once (the co-op mirror sends on `changed`), an unknown mode and a guest's press
## change nothing, and the mode rides the save - a file from before it existed
## comes up on the same default.
func check_party_mode(warband) -> void:
	warband.reset_state()
	check(warband.party_mode == Contracts.DEFAULT_PARTY_MODE
			and warband.party_mode == Contracts.PARTY_DEFENSIVE,
		"a fresh warband answers before it hunts: the default is defensive (%s)"
		% str(warband.party_mode))
	var told := [0]
	var count := func() -> void: told[0] += 1
	warband.changed.connect(count)
	var result: Dictionary = warband.set_party_mode(Contracts.PARTY_OFFENSIVE)
	check(bool(result.get("ok", false)) and warband.party_mode == Contracts.PARTY_OFFENSIVE,
		"the party takes a named mode (%s)" % str(result.get("message", "")))
	check(told[0] == 1, "and says so once (%d)" % told[0])
	warband.set_party_mode(Contracts.PARTY_OFFENSIVE)
	check(told[0] == 1, "the mode it is already in is no change (%d)" % told[0])
	result = warband.set_party_mode("berserk")
	check(not bool(result.get("ok", true)) and warband.party_mode == Contracts.PARTY_OFFENSIVE,
		"an unknown mode is refused and the party keeps its own")
	warband.changed.disconnect(count)

	warband.set_party_mode(Contracts.PARTY_PASSIVE)
	warband.save_state()
	warband.reset_state()
	check(warband.party_mode == Contracts.DEFAULT_PARTY_MODE,
		"a reset is a fresh band on the default (%s)" % str(warband.party_mode))
	check(warband.load_state() and warband.party_mode == Contracts.PARTY_PASSIVE,
		"the party's mode survives a save")
	var old: Dictionary = warband.to_dict()
	old.erase("party_mode")
	warband.from_dict(old)
	check(warband.party_mode == Contracts.DEFAULT_PARTY_MODE,
		"a file written before the mode existed comes up on the default (%s)"
		% str(warband.party_mode))
	old["party_mode"] = "berserk"
	warband.from_dict(old)
	check(warband.party_mode == Contracts.DEFAULT_PARTY_MODE,
		"and so does a mode this build never heard of (%s)" % str(warband.party_mode))

	# The world's `B` steps through the modes in the menu's order and round again.
	# From OFFENSIVE the walk is the shipped order and the last step comes back.
	warband.set_party_mode(Contracts.PARTY_OFFENSIVE)
	var stepped: Array[String] = []
	for _press in Contracts.PARTY_MODES.size():
		stepped.append(str(warband.cycle_party_mode().get("mode", "")))
	check(stepped == [Contracts.PARTY_DEFENSIVE, Contracts.PARTY_PASSIVE, Contracts.PARTY_OFFENSIVE],
		"a step walks OFFENSIVE, DEFENSIVE, PASSIVE and back round (%s)" % str(stepped))

	# A guest's copy is the host's books: the press is refused and nothing moves.
	warband.lent = true
	result = warband.set_party_mode(Contracts.PARTY_DEFENSIVE)
	check(not bool(result.get("ok", true)) and warband.party_mode == Contracts.PARTY_OFFENSIVE,
		"a lent warband's mode is the host's to set (%s)" % str(result.get("message", "")))
	result = warband.cycle_party_mode()
	check(not bool(result.get("ok", true)) and warband.party_mode == Contracts.PARTY_OFFENSIVE,
		"and so is a step")
	warband.lent = false
	warband.reset_state()

# --- the band arms itself --------------------------------------------------

## The warband dresses itself out of the global pool: a purchase fills every slot
## that is empty or still wearing the naked set, the bare body's rags are
## replaced, a real worn piece is never upgraded, and a held item id stays pooled
## until the player lifts the hold - while a manual equip is always allowed.
func check_auto_arm(warband) -> void:
	warband.reset_state()
	var state = root.get_node("PlayerState")
	state.credits = 10000
	var roster = warband.roster
	var stash = warband.stash
	var ash: int = warband.add_mercenary("Ash")
	var bram: int = warband.add_mercenary("Bram")
	# Bram is the band's bowman: a free bow has an owner to go to, and a blade's
	# body never takes one (`Contracts.DISPOSITION_GEAR_REFUSED`).
	warband.set_disposition(bram, Contracts.DISPOSITION_BOW)
	# The camp's rags, the state every prisoner starts in.
	roster.equip(ash, "chest", "armor_naked_chest")

	# No keeper sells steel any more, so the band arms itself out of what a run
	# gathered - seeded here exactly as a loot take seeds it (`stash.add`), and
	# then the band-wide pass is what dresses the bodies.
	var refused_blade: Dictionary = warband.buy_gear("sword_short")
	check(not bool(refused_blade.get("ok", true)), "no keeper sells a blade")
	check(stash.pooled_count("sword_short") == 0, "and a refused purchase pools nothing")
	var restock: Dictionary = warband.buy_gear("bandage_linen")
	check(bool(restock.get("ok", false)), "the keeper sells a bandage")
	check(warband.supply_count("bandage") == 1, "which is a count in the band's pack")
	check(stash.pooled_total() == 0, "and never a row in the shared stash")

	stash.add("sword_short", 1)
	var armed: Dictionary = warband.arm_warband()
	check(str(roster.equipped_of(ash).get("main", "")) == "sword_short",
		"the first bare body takes the blade the band carried in")
	check(stash.pooled_count("sword_short") == 0, "and its copy leaves the pool")
	check((armed.get("fitted", []) as Array).size() == 1,
		"the pass names the body it armed")
	check(str(roster.equipped_of(bram).get("main", "")).is_empty(),
		"the next body is still waiting for a weapon")

	stash.add("bow_short", 1)
	warband.arm_warband()
	check(str(roster.equipped_of(bram).get("main", "")) == "bow_short",
		"a second weapon arms the second bare body")
	stash.add("shield_wood", 2)
	warband.arm_warband()
	check(str(roster.equipped_of(ash).get("off", "")) == "shield_wood",
		"a shield fills a free off hand")
	check(str(roster.equipped_of(bram).get("off", "")).is_empty(),
		"a bow's two-handed grip keeps that off hand empty")
	stash.add("armor_makeshift_chest", 1)
	warband.arm_warband()
	check(str(roster.equipped_of(ash).get("chest", "")) == "armor_makeshift_chest",
		"a real cuirass replaces the naked shirt")
	check(stash.pooled_count("armor_naked_chest") == 1, "the rags go back to the pool")

	# A real worn piece is not upgraded by a later purchase: arming fills, it
	# does not re-kit a body the player already dressed. Every slot that could take
	# a spare one-hander is full, so the better blade stays in the pool.
	stash.add("sword_arming", 1)
	warband.arm_warband()
	check(str(roster.equipped_of(ash).get("main", "")) == "sword_short",
		"the arming pass leaves a real worn blade alone")
	check(stash.pooled_count("sword_arming") == 1, "and the better spare waits in the pool")

	# The arming pass fills a bare body from the pool. There is no hold any more:
	# a piece on the shelf is a piece the band may wear.
	var cade: int = warband.add_mercenary("Cade")
	var snapped: Dictionary = warband.auto_equip(cade, "sword_arming")
	check(bool(snapped.get("ok", false)),
		"a pooled piece snaps into a bare hand: %s" % str(snapped.get("message", "")))
	check(str(roster.equipped_of(cade).get("main", "")) == "sword_arming",
		"and the body holds it")
	warband.unequip_merc(cade, "main")
	check(stash.pooled_count("sword_arming") == 1, "and taking it off returns it to the pool")

# --- re-equipping ----------------------------------------------------------

## A re-equip is the deliberate re-kit the arming pass is not: the kit goes back
## into the pool first, then the body is dressed again by its own priorities -
## dearest armour, the weapon its disposition wants, a shield for a tank. One
## press, one body: the band's gear is its own, and nothing re-kits the roster
## wholesale.
func check_reequip(warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash

	# A dressed body hands the salvage tier back and takes the forged tier the
	# warband looted since. Nothing is minted and nothing is lost on the way.
	var ash: int = warband.add_mercenary("Ash")
	roster.equip(ash, "main", "sword_makeshift")
	roster.equip(ash, "chest", "armor_makeshift_chest")
	stash.add("sword_arming", 1)
	stash.add("armor_plate_chest", 1)
	var worth: int = warband.total_value()
	var one: Dictionary = warband.reequip_merc(ash)
	check(bool(one.get("ok", false)), "a body re-equips: %s" % str(one.get("message", "")))
	check(str(roster.equipped_of(ash)["main"]) == "sword_arming",
		"the better spare replaces the worn salvage blade, got %s"
		% str(roster.equipped_of(ash)["main"]))
	check(str(roster.equipped_of(ash)["chest"]) == "armor_plate_chest",
		"the heavier cuirass replaces the bark one")
	var handed: Array = one.get("released", [])
	check(handed.has("sword_makeshift") and handed.has("armor_makeshift_chest"),
		"the pass names what it handed back, got %s" % str(handed))
	check(stash.pooled_count("armor_makeshift_chest") == 1,
		"what the fill did not re-wear is a stash row")
	check(warband.total_value() == worth, "the warband is worth the same either side (%d vs %d)"
		% [warband.total_value(), worth])

	# The disposition is the priority. A tank wants a shield and a one-hander more
	# than the dearer greatsword; a melee body wants the greatsword.
	warband.reset_state()
	var dorn: int = warband.add_mercenary("Dorn")
	warband.set_disposition(dorn, Contracts.DISPOSITION_TANK)
	stash.add("sword_arming", 1)
	stash.add("sword_great", 1)
	stash.add("shield_tower", 1)
	warband.reequip_merc(dorn)
	check(str(roster.equipped_of(dorn)["main"]) == "sword_arming",
		"a tank re-equips with a one-hander, not the dearer greatsword, got %s"
		% str(roster.equipped_of(dorn)["main"]))
	check(str(roster.equipped_of(dorn)["off"]) == "shield_tower",
		"and the shield it wants in the other hand")

	warband.reset_state()
	var edda: int = warband.add_mercenary("Edda")
	warband.set_disposition(edda, Contracts.DISPOSITION_MELEE)
	stash.add("sword_arming", 1)
	stash.add("sword_great", 1)
	stash.add("shield_tower", 1)
	warband.reequip_merc(edda)
	check(str(roster.equipped_of(edda)["main"]) == "sword_great",
		"a melee body takes the greatsword, got %s" % str(roster.equipped_of(edda)["main"]))
	check(str(roster.equipped_of(edda)["off"]).is_empty(),
		"and its two-handed grip keeps the off hand empty")

	warband.reset_state()
	var wren: int = warband.add_mercenary("Wren")
	warband.set_disposition(wren, Contracts.DISPOSITION_BOW)
	stash.add("sword_great", 1)
	stash.add("bow_long", 1)
	warband.reequip_merc(wren)
	check(str(roster.equipped_of(wren)["main"]) == "bow_long",
		"a bowman takes the bow over the blade, got %s"
		% str(roster.equipped_of(wren)["main"]))

	# The rags are the mesh, not gear: they stay on when the pool holds nothing and
	# go back into it the moment real armour turns up.
	warband.reset_state()
	var rags: int = warband.add_mercenary("Cade")
	roster.equip(rags, "chest", "armor_naked_chest")
	var bare: Dictionary = warband.reequip_merc(rags)
	check(str(roster.equipped_of(rags)["chest"]) == "armor_naked_chest",
		"an empty pool leaves the body in its rags")
	var stripped: Array = bare.get("released", [])
	check(not stripped.has("armor_naked_chest"),
		"and the rags are never handed to the pool")
	stash.add("armor_mail_chest", 1)
	warband.reequip_merc(rags)
	check(str(roster.equipped_of(rags)["chest"]) == "armor_mail_chest",
		"real armour trades the rags out")
	check(stash.pooled_count("armor_naked_chest") == 1, "and the old shirt becomes a stash row")

	# A body that cannot be dressed keeps its kit: no strip without a refill.
	warband.reset_state()
	var downed: int = warband.add_mercenary("Fen")
	roster.equip(downed, "main", "sword_short")
	roster.set_state(downed, Contracts.HealthState.DOWNED)
	var refused: Dictionary = warband.reequip_merc(downed)
	check(not bool(refused.get("ok", true)), "a downed body is refused")
	check(str(roster.equipped_of(downed)["main"]) == "sword_short",
		"and it is left holding what it held")

	# A body with a second weapon set comes back with one: the pass fills the set
	# in its hands first, then puts that set down and fills the other, then swaps
	# back, so what the player set up is re-armed instead of halved. Both sets are
	# its trade's, though: the pooled bow is no second-set weapon for a blade's body.
	warband.reset_state()
	var twin: int = warband.add_mercenary("Otto")
	roster.equip(twin, "main", "sword_short")
	roster.swap_weapon_set(twin)
	roster.equip(twin, "main", "sword_makeshift")
	roster.swap_weapon_set(twin)
	stash.add("sword_great", 1)
	stash.add("sword_arming", 1)
	stash.add("bow_recurve", 1)
	warband.reequip_merc(twin)
	check(str(roster.weapon_set_pair(twin, 0).get("main", "")) == "sword_great",
		"Set 1 is re-armed with the better blade, got %s"
		% str(roster.weapon_set_pair(twin, 0).get("main", "")))
	check(str(roster.weapon_set_pair(twin, 1).get("main", "")) == "sword_arming",
		"and Set 2 keeps a set of its own, got %s"
		% str(roster.weapon_set_pair(twin, 1).get("main", "")))
	check(stash.pooled_count("bow_recurve") == 1,
		"a melee body's second set is no place for the pooled bow")

	# The off hand is a stance of its own, not a second main hand: a tank takes the
	# board over a second blade at any price, because holding the line is what the
	# hand is for - the cheap wooden shield must beat the dear spare dagger.
	warband.reset_state()
	var tank: int = warband.add_mercenary("Dorn")
	warband.set_disposition(tank, Contracts.DISPOSITION_TANK)
	stash.add("dagger_iron", 2)
	stash.add("shield_wood", 1)
	warband.reequip_merc(tank)
	check(str(roster.equipped_of(tank)["main"]) == "dagger_iron",
		"a tank down to daggers takes one in its sword hand, got %s"
		% str(roster.equipped_of(tank)["main"]))
	check(str(roster.equipped_of(tank)["off"]) == "shield_wood",
		"and the board in the other, never the second dagger, got %s"
		% str(roster.equipped_of(tank)["off"]))
	check(stash.pooled_count("dagger_iron") == 1, "the spare dagger stays in the pool")

	warband.reset_state()
	var line: int = warband.add_mercenary("Dorn")
	warband.set_disposition(line, Contracts.DISPOSITION_TANK)
	stash.add("sword_arming", 2)
	stash.add("shield_wood", 1)
	warband.reequip_merc(line)
	check(str(roster.equipped_of(line)["off"]) == "shield_wood",
		"a tank's cheap board still beats a dear second blade, got %s"
		% str(roster.equipped_of(line)["off"]))

	# A melee body means the other thing by the same hand: a second blade.
	warband.reset_state()
	var press: int = warband.add_mercenary("Edda")
	warband.set_disposition(press, Contracts.DISPOSITION_MELEE)
	stash.add("sword_short", 2)
	stash.add("shield_wood", 1)
	warband.reequip_merc(press)
	check(str(roster.equipped_of(press)["off"]) == "sword_short",
		"a melee body pairs a second blade, got %s"
		% str(roster.equipped_of(press)["off"]))

	# A knife is not a sword to a body with an opinion of knives: the `dagger` row
	# is read as a refinement of `1h` instead of being a key that never matches.
	var dagger: Dictionary = StateScript.ITEMS["dagger_iron"]
	var shortsword: Dictionary = StateScript.ITEMS["sword_short"]
	var dagger_score: float = Contracts.disposition_gear_score(Contracts.DISPOSITION_TANK, dagger, 70)
	check(dagger_score == 50.0, "a tank scores a knife as a knife, got %s" % str(dagger_score))
	check(dagger_score < Contracts.disposition_gear_score(Contracts.DISPOSITION_TANK, shortsword, 70),
		"so a same-priced sword is the tank's blade")
	warband.reset_state()


# --- the player's own hands ------------------------------------------------

## The rules that keep automatic arming out of the player's way. A pickup only
## fills a bare body; what a hand dressed is never swapped and never carried off
## to another body; and the body's own re-kit is the one press that clears the
## pins a hand set.
func check_hand_set(warband) -> void:
	warband.reset_state()
	var roster = warband.roster
	var stash = warband.stash
	var ash: int = warband.add_mercenary("Ash")

	# 1. A body with steel in its hands is never armed by a pickup - not into the
	# free hand, and not over the piece already in it.
	stash.add("sword_short", 1)
	stash.add("shield_wood", 1)
	check(bool(warband.equip_merc(ash, "main", "sword_short").get("ok", false)),
		"the player sets a blade in a hand")
	check(roster.is_manual(ash, "main"), "and the slot is marked as a hand's")
	var free_hand: Dictionary = warband.auto_equip(ash, "shield_wood")
	check(not bool(free_hand.get("ok", true)), "a pickup leaves an armed body alone")
	check(str(roster.equipped_of(ash).get("off", "")).is_empty(),
		"the free hand stays empty")
	stash.add("sword_great", 1)
	check(not bool(warband.auto_equip(ash, "sword_great").get("ok", true)),
		"and a dearer blade never trades the one in hand")
	check(str(roster.equipped_of(ash).get("main", "")) == "sword_short",
		"the worn blade is where the player put it")
	check(stash.pooled_count("sword_great") == 1, "the better blade waits in the pool")

	# 2. A bare body is still armed by a pickup - and that arming pins nothing.
	var bare: int = warband.add_mercenary("Bare")
	stash.add("dagger_iron", 1)
	check(bool(warband.auto_equip(bare, "dagger_iron").get("ok", false)),
		"a bare body takes the blade it loots")
	check(not roster.is_manual(bare, "main"), "and the arming pins no slot")
	stash.add("sword_arming", 1)
	check(not bool(warband.auto_equip(bare, "sword_arming").get("ok", true)),
		"but the next drop of a better blade waits in the pool")

	# 3. The body's own press is the one that clears the pins.
	var first: int = warband.add_mercenary("Ash")
	stash.add("dagger_ironwood", 1)
	stash.add("sword_short", 1)
	check(bool(warband.equip_merc(first, "main", "dagger_ironwood").get("ok", false)),
		"the player arms one hand")
	check(bool(warband.equip_merc(first, "off", "sword_short").get("ok", false)),
		"and the other")
	var cleared: Dictionary = warband.reequip_merc(first)
	check(bool(cleared.get("ok", false)), "the body re-equips: %s" % str(cleared.get("message", "")))
	check(not roster.is_manual(first, "main") and not roster.is_manual(first, "off"),
		"and the pins go with the press")

	# 4. A pin rides the save with the kit it belongs to.
	check(bool(warband.equip_merc(first, "main", "sword_great").get("ok", false))
			or bool(warband.equip_merc(first, "main", "sword_short").get("ok", false)),
		"the player sets a blade again")
	warband.save_state()
	warband.reset_state()
	check(not warband.roster.is_manual(first, "main"), "a fresh warband pins nothing")
	check(warband.load_state(), "the saved warband loads")
	check(warband.roster.is_manual(first, "main"),
		"the hand-set slot rides in the save (%s)" % str(warband.roster.manual_slots(first)))
	warband.reset_state()
