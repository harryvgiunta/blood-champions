extends SceneTree
## The quartermaster: gold into the band's medicine, at the keeper price, with
## the same refusal rules the rest of the town uses. The counter sells dressings
## and draughts and nothing else - not one piece of steel or plate, because those
## come off the Weapon Rack's unlocks and out of a run's chests.

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

const TEST_SAVE := "user://quartermaster_state.json"
const WARBAND_SAVE := "user://quartermaster_warband.json"

var game
var warband
var state
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("QUARTERMASTER_FAIL  ", message)

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
	state.credits = 1000
	for index in 4:
		var merc_id: int = warband.add_mercenary("Merc %d" % index)
		# The second body is the band's bowman, so a bow bought at the desk has an
		# owner: a blade's body never takes one (`Contracts.disposition_refuses_gear`).
		if index == 1:
			warband.set_disposition(merc_id, Contracts.DISPOSITION_BOW)

	game = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	var desk: Vector3 = game.quartermaster_desk.global_position
	check(game.service_at(desk) == "quartermaster", "the desk resolves as the quartermaster")
	check(game.interact_at(1, desk) == "quartermaster", "G opens the quartermaster")
	check(game.quartermaster.is_open(), "the shop is open")
	check(game.quartermaster.stock_rows().size() == QuartermasterMenu.STOCK.size(),
		"every stocked row is on the board (%d)" % game.quartermaster.stock_rows().size())
	var stocked: Array = []
	for row in game.quartermaster.stock_rows():
		stocked.append(str(row["item_id"]))
	stocked.sort()
	var wanted: Array = ["bandage_linen", "healing_potion"]
	wanted.sort()
	check(stocked == wanted, "the counter sells medicine and nothing else, got %s" % str(stocked))
	# No steel and no plate anywhere on the board: those are opened, not bought.
	for row in game.quartermaster.stock_rows():
		var category := str((State.ITEMS[str(row["item_id"])] as Dictionary).get("category", ""))
		check(category == "misc", "%s is a carried ware, not gear" % str(row["item_id"]))

	var rows: Array[Dictionary] = game.quartermaster.stock_rows()
	var bandage_row: Dictionary = {}
	var potion_row: Dictionary = {}
	for row in rows:
		if str(row["item_id"]) == "bandage_linen":
			bandage_row = row
		elif str(row["item_id"]) == "healing_potion":
			potion_row = row
	check(not bandage_row.is_empty() and not potion_row.is_empty(),
		"both the bandage and the draught are on the board")
	check(int(bandage_row["price"]) == int(State.ITEMS["bandage_linen"]["price"]),
		"the counter charges the keeper price for a bandage")
	check(int(potion_row["price"]) == int(State.ITEMS["healing_potion"]["price"]),
		"and the keeper price for a draught")
	check(bool(bandage_row["affordable"]) and bool(potion_row["affordable"]),
		"1000 gold covers both")
	check(warband.supply_count("bandage") == 0 and warband.supply_count("potion") == 0,
		"a fresh warband carries no medicine until it buys some")

	var bandages_before: int = warband.supply_count("bandage")
	var bought: Dictionary = game.quartermaster.buy("bandage_linen")
	check(bool(bought.get("ok", false)), "the purchase succeeds")
	check(int(state.credits) == 1000 - int(State.ITEMS["bandage_linen"]["price"]),
		"exactly the price is spent (%d)" % state.credits)
	check(warband.supply_count("bandage") == bandages_before + 1,
		"one bandage lands in the band's pack")
	check(warband.stash.pooled_count("bandage_linen") == 0,
		"medicine is a count, not a stash row")
	check(warband.stash.pooled_total() == 0,
		"and the shared stash is still empty in the town")
	check(game.quartermaster.is_open(), "buying keeps the shop open")
	check(game.quartermaster.status_text().contains("Bandage"),
		"the keeper says what was bought")
	check(game.quartermaster.carried_line().contains("BANDAGES 1"),
		"and the panel counts what the band carries, got %s"
		% game.quartermaster.carried_line())

	# Arrows are unlimited, so the desk no longer sells shafts: there is no
	# quiver to stock and no row to buy.
	var arrow_row: Dictionary = {}
	for row in game.quartermaster.stock_rows():
		if str(row["item_id"]) == "arrow":
			arrow_row = row
	check(arrow_row.is_empty(), "the quartermaster stocks no arrows: arrows are unlimited")

	# No duty, no gear: the counters that used to sell a warband's whole kit are
	# refused outright, and the refusal costs nothing.
	var steel: Dictionary = game.quartermaster.buy("sword_short")
	check(not bool(steel.get("ok", true)), "the counter does not sell a sword")
	check(int(state.credits) == 1000 - int(State.ITEMS["bandage_linen"]["price"]),
		"and the refusal spends nothing")
	var plate: Dictionary = game.quartermaster.buy("armor_mail_chest")
	check(not bool(plate.get("ok", true)), "and it does not sell plate either")

	var draught: Dictionary = game.quartermaster.buy("healing_potion")
	check(bool(draught.get("ok", false)), "a draught can be bought")
	check(warband.supply_count("potion") == 1, "and the pack counts it")

	# An empty purse buys nothing, and nothing is lost.
	state.credits = 1
	var held: int = warband.supply_count("bandage")
	var refused: Dictionary = game.quartermaster.buy("bandage_linen")
	check(refused.get("ok") == false, "a short purse is refused")
	check(int(state.credits) == 1, "a refused purchase spends nothing")
	check(warband.supply_count("bandage") == held, "and adds nothing to the pack")
	check(game.quartermaster.status_text().contains("gold"), "the refusal names the shortfall")
	var unaffordable := false
	for row in game.quartermaster.stock_rows():
		if not bool(row["affordable"]):
			unaffordable = true
	check(unaffordable, "the board greys out what the purse cannot cover")

	game.quartermaster.close()
	check(not game.quartermaster.is_open(), "the shop closes")

	game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("QUARTERMASTER_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
