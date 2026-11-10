extends SceneTree
## The recruiter's board and the bodies it sells.
##
## A run's market and shop levels stand a recruiter beside the stall. What he
## sells is a *body*: a warband mercenary bought for the run, sworn in the kit the
## board sold it, carrying one rolled item skill, driven by the band's own AI. Three
## things about that body are new and all three are measured here:
##
##   1. the catalogue - five rungs of ten levels, a kit per archetype per rung that
##      exists in the item catalog and fits its slots, a skill rolled from the
##      archetype's own families that its own hands can fire, and a price that
##      rises with the level and stops at 50;
##   2. the board - three rows, always, one of each archetype, re-rolled per visit,
##      with the bodies bought out of the run's purse: they spend no place in the
##      band's deployment cap and their kit is locked the frame they are sworn;
##   3. the permanence - a lethal blow destroys a recruit where it stands, where
##      the same blow puts a sworn mercenary on his chest for ten seconds; the
##      roster's own reap erases either name, and the hireling's kit is left where
##      he fell instead of walking back into the shared stash.
##
## The live half runs on the real world scene, because the spawn, the downing and
## the reap are the scene's business: `_sync_field` stands the body up,
## `_sync_roster` books the death and `Warband.reap_dead` does the erasing.

const WORLD := "res://scenes/warband_world.tscn"
const Recruits = preload("res://scripts/warband/recruit_catalog.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const StateScript = preload("res://scripts/player_state.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")

const TEST_SAVE := "user://recruit_state.json"
const WARBAND_SAVE := "user://recruit_warband.json"

var state
var warband
var game
var checks := 0
var failures := 0
var _done := false


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("RECRUIT_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	check_catalogue()
	check_board()
	check_hire()
	check_locked_kit()
	await check_live_world()
	await check_run_board()
	print("RECRUIT_REGRESSION checks=", checks, " failures=", failures)
	if game != null and is_instance_valid(game):
		game.queue_free()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	quit(0 if failures == 0 else 1)


# --- 1. the catalogue ------------------------------------------------------

## Five rungs of ten levels, and every row a real piece of the game's own steel.
func check_catalogue() -> void:
	check(Recruits.ARCHETYPES.size() == 3 and Recruits.OPTIONS == 3,
		"three archetypes, three rows on a board")
	check(Recruits.rung_for(1) == 0 and Recruits.rung_for(10) == 0,
		"the first rung is levels 1 to 10")
	check(Recruits.rung_for(11) == 1 and Recruits.rung_for(20) == 1,
		"then 11 to 20")
	check(Recruits.rung_for(50) == 4 and Recruits.rung_for(99) == 4,
		"the table stops at level 50 (%d)" % Recruits.rung_for(99))

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for archetype in Recruits.ARCHETYPES:
		for rung in 5:
			for roll in 3:
				var gear := Recruits.gear_for(archetype, rung, rng)
				var main := str(gear.get("main", ""))
				var main_item: Dictionary = StateScript.ITEMS.get(main, {})
				check(not main_item.is_empty(),
					"%s rung %d sells a real blade (%s)" % [archetype, rung, main])
				check(EquipmentRules.allowed(main_item, "main"),
					"%s rung %d's blade may be held in the sword hand (%s)"
						% [archetype, rung, main])
				var off := str(gear.get("off", ""))
				if off.is_empty():
					check(Contracts.two_handed_item(main_item),
						"%s rung %d leaves the off hand bare only for a two-hander (%s)"
							% [archetype, rung, main])
				else:
					var off_item: Dictionary = StateScript.ITEMS.get(off, {})
					check(EquipmentRules.allowed(off_item, "off"),
						"%s rung %d's second piece may be held in the off hand (%s)"
							% [archetype, rung, off])
					check(not Contracts.two_handed_item(main_item),
						"%s rung %d never wears a board it cannot raise" % [archetype, rung])
				for slot in ArmorData.SLOTS:
					var piece := str(gear.get(slot, ""))
					check(StateScript.ITEMS.has(piece),
						"%s rung %d wears %s on its %s" % [archetype, rung, piece, slot])

	# The salvage opening: a level-6 body is sworn in the make-do tier, because the
	# first board a party sees is supposed to sell a body its own arming must carry.
	for archetype in Recruits.ARCHETYPES:
		var opening := Recruits.gear_for(archetype, Recruits.rung_for(6), rng)
		for slot in ArmorData.SLOTS:
			check(str(opening.get(slot, "")).begins_with("armor_makeshift_"),
				"a level-6 %s starts in makeshift armour (%s)" % [archetype, opening[slot]])
		var main_price := int(StateScript.ITEMS.get(str(opening["main"]), {}).get("price", 999))
		check(main_price <= 20,
			"and in a shitty weapon (%s, %d gold)" % [opening["main"], main_price])

	# The one skill: in the archetype's family, a kind a body can land, and one its
	# own hands can fire.
	for archetype in Recruits.ARCHETYPES:
		for rung in 5:
			var armour: Dictionary = Recruits.KITS[archetype][rung]
			check(not (armour as Dictionary).is_empty(),
				"the %s ladder has row %d" % [archetype, rung])
			for roll in 12:
				var gear := Recruits.gear_for(archetype, rung, rng)
				var skill := Recruits.skill_for(archetype, gear, rng)
				check(not skill.is_empty(),
					"a %s in rung %d rolls a skill" % [archetype, rung])
				if skill.is_empty():
					continue
				var definition: Dictionary = AbilityRules.by_id(skill)
				var in_family := false
				for tag in AbilityRules.families_of(definition):
					if Recruits.FAMILIES[archetype].has(str(tag)):
						in_family = true
				check(in_family,
					"%s rolled a skill of its own family (%s)" % [archetype, skill])
				check(str((definition.get("effect", {}) as Dictionary).get("kind", "")) \
						in AbilityRules.AI_KINDS,
					"%s rolled a kind a body can land (%s)" % [archetype, skill])
				check(AbilityRules.fits_gear(definition,
						StateScript.ITEMS.get(str(gear["main"]), {}),
						StateScript.ITEMS.get(str(gear["off"]), {})),
					"%s rolled a skill its hands can fire (%s)" % [archetype, skill])

	# The price: up with the level, flat past the cap, and worth a body.
	for archetype in Recruits.ARCHETYPES:
		var previous := 0
		for level in range(1, Recruits.MAX_LEVEL + 1):
			var price := Recruits.price_for(level, archetype)
			check(price > previous,
				"%s costs more at level %d (%d)" % [archetype, level, price])
			previous = price
		check(Recruits.price_for(51, archetype) == previous,
			"the %s price stops at level 50" % archetype)
	check(Recruits.price_for(6, "tank") > Recruits.price_for(6, "ranged"),
		"a shield and a mail coat cost more than a bow")


# --- 2. the board ----------------------------------------------------------

## Three rows, one of each archetype, in a fresh order and with fresh kits on
## every roll.
func check_board() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 11
	var first: Array = Recruits.offers(a, 6)
	check(first.size() == Recruits.OPTIONS, "a board carries three rows (%d)" % first.size())
	var seen: Dictionary = {}
	for offer in first:
		check(str(offer.get("kind", "")) == "hire", "every row is a body for sale")
		seen[str(offer.get("archetype", ""))] = true
		check(not str(offer.get("skill", "")).is_empty(),
			"every row names its one skill (%s)" % str(offer.get("name", "")))
		check(not str(offer.get("body", "")).is_empty(), "and says what the body does")
		var kit: Dictionary = offer.get("gear", {})
		check(not kit.is_empty(), "and what it carries")
	check(seen.size() == 3, "one of each archetype is on the board")

	var b := RandomNumberGenerator.new()
	b.seed = 12
	var second: Array = Recruits.offers(b, 6)
	var differs := false
	for index in first.size():
		if str((first[index] as Dictionary).get("name", "")) \
				!= str((second[index] as Dictionary).get("name", "")):
			differs = true
	check(differs, "a different visit rolls different names")

	# The same seed sells the same board: a replay is not a different shop.
	var b_again := RandomNumberGenerator.new()
	b_again.seed = 12
	var again: Array = Recruits.offers(b_again, 6)
	check(str((again[0] as Dictionary).get("name", ""))
			== str((second[0] as Dictionary).get("name", "")),
		"and the same seed sells the same three")


# --- 3. the hire -----------------------------------------------------------

## A recruit is bought for the run: the purse pays, the cap does not, the field
## keeps it, and its one skill is on its bar.
func check_hire() -> void:
	warband.reset_state()
	warband.seed_starting_band()
	state.credits = 5000
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var offers: Array = Recruits.offers(rng, 21)
	var offer: Dictionary = offers[0]
	var price := int(offer.get("price", 0))
	var gold_before: int = warband.gold()
	var room_before: int = warband.field_room()
	var cap_before: int = warband.band_field_count()
	var result: Dictionary = warband.hire_recruit(offer)
	check(bool(result.get("ok", false)),
		"the board sells a body: %s" % str(result.get("message", "")))
	var merc_id := int(result.get("merc_id", -1))
	check(merc_id > 0 and warband.roster.has(merc_id), "the recruiter swears a name")
	check(warband.gold() == gold_before - price,
		"the purse pays the board's price (%d of %d)" % [price, gold_before])
	check(warband.roster.is_recruit(merc_id), "the body is a bought recruit")
	check(not warband.roster.is_player(merc_id), "and not a guest's own character")
	check(warband.band_field_count() == cap_before,
		"it spends no place in the deployment cap (%d)" % warband.band_field_count())
	check(warband.field_room() == room_before,
		"so the desk still has its own places to sell")
	check(not warband.roster.is_reserve(merc_id), "and it takes the field at once")
	check(warband.roster.disposition_of(merc_id)
			== str(offer.get("disposition", "")),
		"it fights on its archetype's disposition (%s)"
			% warband.roster.disposition_of(merc_id))
	var worn: Dictionary = warband.roster.equipped_of(merc_id)
	var kit: Dictionary = offer.get("gear", {})
	check(str(worn.get("main", "")) == str(kit.get("main", "")),
		"it is sworn with the blade the board sold it (%s)" % worn.get("main", ""))
	check(str(worn.get("chest", "")) == str(kit.get("chest", "")),
		"and the armour")
	var bar: Array = warband.roster.hotbar_order_of(merc_id)
	check(bar.size() == 1 and str(bar[0]) == str(offer.get("skill", "")),
		"its bar is the one skill on the card (%s)" % str(bar))
	check(warband.roster.max_health_of(merc_id) > 0.0, "and it is a body like any other")

	# A refused hire spends nothing.
	var poor: Dictionary = offer.duplicate(true)
	poor["sold"] = false
	poor["name"] = "Penniless"
	poor["price"] = warband.gold() + 500
	var before: int = warband.gold()
	var refused: Dictionary = warband.hire_recruit(poor)
	check(not bool(refused.get("ok", true)), "the board refuses a purse that cannot pay")
	check(warband.gold() == before, "and takes nothing")
	check(warband.roster.count() == 2, "no name is sworn for a refused hire")
	var junk: Dictionary = warband.hire_recruit({"id": "bandage_linen"})
	check(not bool(junk.get("ok", true)), "and a ware is not a body")


# --- 4. the locked kit -----------------------------------------------------

## A recruit fights in what it was sworn in. Every gear verb refuses it, and a
## normal mercenary beside it keeps every verb it always had.
func check_locked_kit() -> void:
	warband.reset_state()
	warband.seed_starting_band()
	state.credits = 5000
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var offer: Dictionary = Recruits.offers(rng, 31)[0]
	var merc_id := int(warband.hire_recruit(offer).get("merc_id", -1))
	check(merc_id > 0, "a recruit is sworn for the lock check")
	check(warband.is_gear_locked(merc_id), "and its kit is locked")
	var before: Dictionary = warband.roster.equipped_of(merc_id)
	warband.stash.add("sword_great", 1)
	warband.stash.add("armor_plate_chest", 1)

	var equipped: Dictionary = warband.equip_merc(merc_id, "off", "shield_tower")
	check(not bool(equipped.get("ok", true)),
		"the paperdoll cannot dress a recruit (%s)" % str(equipped.get("message", "")))
	check(str(equipped.get("message", "")).contains("locked"),
		"and it says why")
	check(warband.unequip_merc(merc_id, "main").is_empty(),
		"the recruit's hand cannot be emptied")
	var swapped: Dictionary = warband.swap_weapon_set(merc_id)
	check(not bool(swapped.get("ok", true)), "nor its weapon set swapped")
	var rekitted: Dictionary = warband.reequip_merc(merc_id)
	check(not bool(rekitted.get("ok", true)), "nor its kit re-picked")
	var looted: Dictionary = warband.auto_equip(merc_id, "armor_plate_chest")
	check(not bool(looted.get("ok", true)), "nor a loot pickup put on it")
	var dressed: Dictionary = warband.dress_recruit(merc_id)
	check(not bool(dressed.get("ok", true)), "nor the band's arming pass")
	check(warband.arm_one_piece(merc_id).is_empty(), "nor the kill-by-kill arming")
	# A bought body is whole, not just dressed: the stance it was sold as and the
	# one skill on its card are the contract too.
	var stance: Dictionary = warband.cycle_disposition(merc_id)
	check(not bool(stance.get("ok", true)), "nor its stance stepped")
	check(str(stance.get("message", "")).contains("locked"), "and the refusal says why")
	var laid: Dictionary = warband.set_hotbar_order(merc_id, ["double_slash"])
	check(not bool(laid.get("ok", true)), "nor a skill laid on its bar")
	check(warband.roster.equipped_of(merc_id) == before,
		"and not one slot moved (%s)" % str(warband.roster.equipped_of(merc_id)))

	# The rule is the recruit's, not every body's: a sworn mercenary still dresses.
	var sworn := int(warband.add_mercenary("Ash"))
	check(not warband.is_gear_locked(sworn), "a sworn mercenary's kit is its own to change")
	check(bool(warband.equip_merc(sworn, "main", "sword_great").get("ok", false)),
		"and the paperdoll still dresses him")


# --- 5. permanence, on the real field --------------------------------------

## The body the board sells dies where it stands; the body the town swore only
## goes down. Run on the world scene, because the spawn, the booking and the reap
## are its business.
func check_live_world() -> void:
	warband.reset_state()
	warband.seed_starting_band()
	warband.save_state()
	state.credits = 6000
	var flow = root.get_node("GameFlow")
	flow.active = false
	flow.world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.9).timeout
	var controller = game.get("controller")
	check(controller != null, "the world seats a controller")
	if controller == null:
		return
	var soul = controller.focus_body()
	check(soul != null, "and the soul stands in a body")
	if soul == null:
		return

	# The island's pools count souls, not bodies: a peer under the ally base is a
	# human at the table and everything above it is a body the AI drives.
	var run = game.get("roguelite")
	check(run != null, "the world owns a run director")
	if run != null:
		var held: Dictionary = run.players
		run.players = {1: null, 2: null, 1003: null, 1007: null}
		check(run._player_count() == 2,
			"two souls and two AI bodies are two bodies' worth of island (%d)"
				% run._player_count())
		run.players = {1: null, 1003: null}
		check(run._player_count() == 1, "and one soul is one (%d)" % run._player_count())
		run.players = {1003: null}
		check(run._player_count() == 1, "a table with no human still stands one island")
		run.players = held

	# A recruit, bought and stood up on the field beside the party.
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var offer: Dictionary = Recruits.offers(rng, 6)[0]
	var hired: Dictionary = warband.hire_recruit(offer)
	var recruit_id := int(hired.get("merc_id", -1))
	check(bool(hired.get("ok", false)) and recruit_id > 0, "the recruiter swears a body")
	game.stand_up_field()
	var recruit = controller.body_of(recruit_id)
	check(recruit != null, "and the field stands it up")
	if recruit == null:
		return
	check(bool(recruit.permadeath), "the body knows its death is final")
	check(str((recruit.rig.ability_loadout as Array)[0] if not (recruit.rig.ability_loadout as Array).is_empty() else "")
			== str(offer.get("skill", "")),
		"and it carries the one skill the card named (%s)" % str(recruit.rig.ability_loadout))

	# A sworn mercenary beside it: the control for the same blow.
	var sworn_id := int(warband.add_mercenary("Brine"))
	warband.stash.add("sword_short", 1)
	warband.stash.add("armor_leather_chest", 1)
	warband.dress_recruit(sworn_id)
	game.stand_up_field()
	var sworn = controller.body_of(sworn_id)
	check(sworn != null, "and so does the body the town swore")
	check(str(warband.roster.equipped_of(sworn_id).get("chest", "")) == "armor_leather_chest",
		"the sworn body takes the field in the armour the pool fitted")

	var killer := int(soul.slot)
	# The marking the world does at a fall: a peer inside the body means it is
	# that player's character, and nobody inside means it is the band's hireling.
	var soul_merc := int(controller.merc_of(soul))
	check(warband.souls.occupied_by(soul_merc) != 0,
		"the soul's own body reads a peer inside it, so no fall marks it expendable")
	check(warband.souls.occupied_by(sworn_id) == 0,
		"while the hireling beside it has nobody inside")
	if sworn != null:
		check(not bool(sworn.permadeath), "a sworn body is not on the recruit's rule")
		sworn.take_damage(float(sworn.max_health) * 3.0, killer)
		check(bool(sworn.get("alive")) and bool(sworn.get("downed")),
			"a lethal blow puts a sworn mercenary on his chest")
		# Nobody's soul is inside him, so the fall is the band's: the world reads
		# it as a hireling's and gives him the ten seconds, not the soul's thirty.
		check(bool(sworn.expendable), "the world reads the fall as the band's hireling")
		check(is_equal_approx(sworn.downed_limit(),
				Contracts.MERCENARY_DOWNED_SECONDS),
			"with the contract's ten seconds on his clock (%s)" % str(sworn.downed_limit()))
		check(warband.roster.has(sworn_id), "he is on the books while he can be picked up")
		var floor_before: int = (game.get("pickups") as Array).size()
		sworn.take_damage(float(sworn.max_health) * 3.0, killer)
		check(not bool(sworn.get("alive")),
			"a second blow takes the hireling off the field for good")
		check((game.get("pickups") as Array).size() > floor_before,
			"his kit drops where he fell")
		check(int(warband.stash.pooled_count("armor_leather_chest")) == 0,
			"and does not walk back into the shared stash with the reap")
	recruit.take_damage(float(recruit.max_health) * 3.0, killer)
	check(not bool(recruit.get("alive")),
		"the same blow destroys a recruit where it stands")
	check(not bool(recruit.get("downed")), "and it never lies down")

	# The reap is the roster's own: the name is gone a beat later, for good.
	await create_timer(0.9).timeout
	check(not warband.roster.has(recruit_id),
		"the dead recruit is reaped out of the warband")
	check(not warband.roster.has(sworn_id),
		"and the hireling the second blow finished goes with him")
	var price := int(offer.get("price", 0))
	check(price > 0 and warband.gold() < 6000, "and the purse paid for the body it lost")


# --- 6. the board on the island --------------------------------------------

## A market level stands the recruiter, and a press on him buys a body into the
## party on that frame: the verb, the runtime, the purse, the sold row and the
## island's pools are all measured here, where the run and the arena are the
## game's own.
func check_run_board() -> void:
	var run = game.get("roguelite")
	check(run != null, "the world owns a run director")
	if run == null:
		return
	var started: Dictionary = run.start_run()
	check(bool(started.get("ok", false)),
		"the portal opens a run: %s" % str(started.get("message", "")))
	# Straight to the market: five combat levels in, the stop is level 6.
	run.wave = 6
	run.level = 5
	run.level_cleared = true
	run._begin_level()
	check(run.market_level and run.level == 6, "level 6 is the market")
	var desk: Node3D = null
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == "recruiter":
			desk = prop
			break
	check(desk != null, "the market stands the recruiter's desk")
	if desk == null:
		return
	var serial := int(desk.get_meta("serial"))
	var board: Array = run.recruit_board.get(serial, [])
	check(board.size() == 3, "with three bodies on it (%d)" % board.size())
	if board.is_empty():
		return
	var offer: Dictionary = board[0]
	var price := int(offer.get("price", 0))
	state.credits = maxi(int(state.credits), price + 100)
	var purse_before: int = warband.gold()
	var souls_before: int = run._player_count()
	var hired: Dictionary = run.hire(serial, 0, 1)
	check(bool(hired.get("ok", false)),
		"the board sells the first body: %s" % str(hired.get("message", "")))
	var merc_id := int(hired.get("merc_id", -1))
	check(merc_id > 0 and warband.roster.has(merc_id), "the recruit is sworn")
	check(warband.roster.is_recruit(merc_id), "as a bought recruit")
	check(not warband.roster.is_reserve(merc_id), "and it takes the island at once")
	check(bool((run.recruit_board[serial][0] as Dictionary).get("sold", false)),
		"its row is sold")
	check(warband.gold() == purse_before - price,
		"the run's purse paid the board's price (%d of %d)" % [price, purse_before])
	check(run._player_count() == souls_before,
		"and the island is no heavier for it (%d souls)" % run._player_count())
	var brought = game.controller.body_of(merc_id)
	check(brought != null, "the island stands the body up on the same press")
	if brought != null:
		check(bool(brought.permadeath), "the run's body knows its death is final")
		check(run.players.has(1000 + merc_id),
			"and it carries a run runtime beside the party")
	# The desk that sold him pays him off: the name, the runtime and the body leave
	# the party, and the kit goes with him - it was sold with the body and locked to
	# it, so a dismissal that fed the shared stash would be a way to buy steel for a
	# recruit's price and keep the piece.
	var main_piece := str((offer.get("gear", {}) as Dictionary).get("main", ""))
	var pooled_before: int = warband.stash.pooled_count(main_piece)
	var paid: Dictionary = run.dismiss(merc_id)
	check(bool(paid.get("ok", false)),
		"the recruiter pays the body off: %s" % str(paid.get("message", "")))
	check(not warband.roster.has(merc_id), "and the name leaves the warband")
	check(not run.players.has(1000 + merc_id), "the run runtime goes with him")
	check(warband.stash.pooled_count(main_piece) == pooled_before,
		"and his kit never falls into the shared stash")
	await physics_frame
	await physics_frame
	check(game.controller.body_of(merc_id) == null, "his body leaves the field")
	var sworn_body := int(warband.add_mercenary("Brine"))
	var kept: Dictionary = run.dismiss(sworn_body)
	check(not bool(kept.get("ok", true)),
		"a sworn mercenary cannot be paid off: he is the band's")
	warband.roster.remove(sworn_body)
	# A second body, bought and then killed in the run, where every other body is
	# held on its chest: the recruit is the one that does not come back.
	var second: Dictionary = run.hire(serial, 1, 1)
	check(bool(second.get("ok", false)),
		"the board sells a second body: %s" % str(second.get("message", "")))
	var doomed := int(second.get("merc_id", -1))
	var corpse = game.controller.body_of(doomed)
	check(corpse != null, "and the island stands it up")
	if corpse != null:
		var soul = game.controller.focus_body()
		corpse.take_damage(float(corpse.max_health) * 4.0, int(soul.slot))
		check(not bool(corpse.get("alive")), "a lethal blow destroys it inside the run")
		check(not bool(corpse.get("downed")), "and it never lies down")
		var waited := 0
		while waited < 120 and warband.roster.has(doomed):
			await physics_frame
			waited += 1
		check(not warband.roster.has(doomed),
			"the run reaps the name off the warband (%d frames)" % waited)
	var twice: Dictionary = run.hire(serial, 0, 1)
	check(not bool(twice.get("ok", true)), "a sold row cannot be bought twice")