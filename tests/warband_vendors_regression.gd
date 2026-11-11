extends SceneTree
## The three market keepers: each counter is a real service with its own seat in
## `PlayerState.VENDORS`, `G` at the counter opens that keeper's board, and the
## counter trades through the warband - gold out into the shared stash, spare
## copies back in at the keeper's rate, and a short purse buys nothing.

const State = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://warband_vendors_state.json"
const WARBAND_SAVE := "user://warband_vendors_warband.json"
## The service rings and the market ring the counters must stand inside.
const SERVICE_REACH := 3.0
const MARKET_RADIUS := 16.0

var game
var warband
var state
var checks := 0
var failures := 0

## service id -> the `PlayerState.VENDORS` seat it opens, in counter order.
const VENDOR_SEATS := [
	{"id": "vendor_orla", "seat": 0, "keeper": "Storekeeper Orla"},
	{"id": "vendor_brann", "seat": 1, "keeper": "Smith Brann"},
	{"id": "vendor_vey", "seat": 2, "keeper": "Quartermaster Vey"},
]

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("VENDORS_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _expected_stock(seat: int) -> Array:
	var out: Array = []
	var stock: Array = State.VENDORS[seat].get("stock", [])
	for entry in stock:
		var item_id := str(entry)
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or int(item.get("price", 0)) <= 0:
			continue
		out.append(item_id)
	out.sort()
	return out

func _row_for(rows: Array, item_id: String) -> Dictionary:
	for row in rows:
		if str(row["item_id"]) == item_id:
			return row
	return {}

## The four bodies at the counters are already fully dressed: this test is about
## the pool moving between a keeper and the stash, and an open slot would let the
## warband's arming pass take a bought piece out of the pool before the board can
## show it. The arming pass has its own checks in the contract regression.
func _dress_for_market() -> void:
	var kit := {
		"main": "sword_short", "off": "shield_tower",
		"head": "armor_plate_head", "chest": "armor_plate_chest",
		"hands": "armor_plate_hands", "legs": "armor_plate_legs",
		"feet": "armor_plate_feet",
	}
	for merc_id in warband.roster.ids():
		for slot in kit:
			warband.roster.equip(int(merc_id), str(slot), str(kit[slot]))

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
	# A living warband keeps `seed_warband` from filling the pool with spares, so
	# every count below is this test's own purchase and sale.
	for index in 4:
		warband.add_mercenary("Merc %d" % index)
	_dress_for_market()
	check(warband.stash.pooled_total() == 0, "the test starts with an empty shared stash")

	game = load("res://scenes/town_hub.tscn").instantiate()
	root.add_child(game)
	await create_timer(0.6).timeout

	# Every counter is a service with its own seat, standing inside the market.
	var points: Dictionary = {
		"stash": game.service_point("stash"),
		"roguelite_rack": game.service_point("roguelite_rack"),
		"recruiter": game.service_point("recruiter"),
		"quartermaster": game.service_point("quartermaster"),
		"gate": game.service_point("gate"),
	}
	for entry in VENDOR_SEATS:
		var service := str(entry["id"])
		var seat := int(entry["seat"])
		var point: Vector3 = game.service_point(service)
		check(point != Vector3.ZERO, "%s has a point in the square" % service)
		check(Vector2(point.x, point.z).length() <= MARKET_RADIUS,
			"%s stands on the market ring (%.1f m)" % [service, point.length()])
		check(game.service_at(point) == service,
			"%s ring resolves to itself" % service)
		for other in points:
			var gap: float = point.distance_to(points[other])
			check(gap > SERVICE_REACH * 2.0,
				"%s stays clear of %s (%.1f m)" % [service, other, gap])
		points[service] = point

		var opened: String = game.interact_at(1, point)
		check(opened == service, "G at %s names it (got '%s')" % [service, opened])
		check(game.vendor_menu.is_open(), "%s opens a stall" % service)
		check(game.panels_open(), "an open stall counts as an open panel")
		check(game.vendor_menu.vendor_index() == seat,
			"%s opens seat %d" % [service, seat])
		check(game.vendor_menu.keeper_name() == str(entry["keeper"]),
			"%s is %s" % [service, str(entry["keeper"])])

		var stock_ids: Array = []
		for row in game.vendor_menu.stock_rows():
			stock_ids.append(str(row["item_id"]))
			check(int(row["price"]) > 0, "%s prices %s" % [service, str(row["item_id"])])
		stock_ids.sort()
		check(stock_ids == _expected_stock(seat),
			"%s stocks exactly its vendor seat's catalogue" % service)
		check(not game.vendor_menu.keeper_tag().is_empty(),
			"%s shows a keeper tag" % service)
		check(not game.vendor_menu.keeper_line().is_empty(),
			"%s shows a keeper line" % service)

	# The old quartermaster desk still answers, and so does its menu.
	check(game.service_at(game.quartermaster_desk.global_position) == "quartermaster",
		"the quartermaster desk still resolves to the quartermaster")
	check(game.interact_at(1, game.quartermaster_desk.global_position) == "quartermaster",
		"G at the quartermaster desk still opens the old keeper")
	check(game.quartermaster.is_open(), "the quartermaster menu still opens")
	game.quartermaster.close()

	# No keeper sells steel: the three counters between them trade in bandages
	# and draughts, and nothing on any board is a weapon or a piece of armour.
	for seat in range(State.VENDORS.size()):
		game.vendor_menu.configure(warband, seat)
		for row in game.vendor_menu.stock_rows():
			var stocked_category := str(State.ITEMS[str(row["item_id"])].get("category", ""))
			check(stocked_category == "misc",
				"keeper seat %d sells no gear: %s is '%s'" % [seat, str(row["item_id"]),
				stocked_category])
		check(_row_for(game.vendor_menu.stock_rows(), "bow_short").is_empty(),
			"keeper seat %d does not stock a shortbow" % seat)
		check(_row_for(game.vendor_menu.stock_rows(), "arrow").is_empty(),
			"keeper seat %d stocks no arrows" % seat)
	game.vendor_menu.configure(warband, 0)

	# Orla's shelf: buy a bandage into the band's pack at its keeper price.
	var orla_point: Vector3 = game.service_point("vendor_orla")
	check(game.interact_at(1, orla_point) == "vendor_orla", "Orla's stall opens again")
	check(game.vendor_menu.stock_rows().size() == _expected_stock(0).size(),
		"Orla's board is still whole")
	var bandage_row: Dictionary = _row_for(game.vendor_menu.stock_rows(), "bandage_linen")
	check(not bandage_row.is_empty(), "Orla stocks a linen bandage")
	var bandage_price := int(State.ITEMS["bandage_linen"]["price"])
	check(int(bandage_row.get("price", 0)) == bandage_price,
		"the shelf charges the keeper price (%d)" % bandage_price)
	check(not bool(game.vendor_menu.buy("sword_short").get("ok", true)),
		"a keeper cannot sell what no keeper stocks")

	var credits_before := int(state.credits)
	var bandages_before: int = warband.supply_count("bandage")
	var bandages_bought: Dictionary = game.vendor_menu.buy("bandage_linen")
	check(bool(bandages_bought.get("ok", false)), "Orla sells a bandage")
	check(int(state.credits) == credits_before - bandage_price,
		"exactly the price leaves the purse (%d)" % state.credits)
	check(warband.supply_count("bandage") == bandages_before + 1,
		"the dressing lands in the band's pack")
	check(warband.stash.pooled_total() == 0,
		"and the shared stash stays empty: medicine is a count, not a row")
	check(game.vendor_menu.status_text().contains("Bandage"),
		"the keeper says what was bought")
	check(game.vendor_menu.pack_line().contains("BANDAGES %d" % (bandages_before + 1)),
		"the board counts what the band carries, got %s" % game.vendor_menu.pack_line())

	# The count is the band's to spend, and it is spent one dose at a time: the
	# consumable keys go through exactly this verb, and an empty pack refuses.
	var held_now: int = warband.supply_count("bandage")
	check(warband.take_supply("bandage"), "a dressing can be spent")
	check(warband.supply_count("bandage") == held_now - 1,
		"spending one leaves one fewer, got %d" % warband.supply_count("bandage"))
	warband.supplies["bandage"] = 0
	check(not warband.take_supply("bandage"), "an empty pack spends nothing")
	check(warband.supply_count("bandage") == 0, "and cannot go negative")

	# A spare out of a run is the only thing a keeper buys back: seed one, sell
	# it at the counter's share, and watch the pool empty.
	warband.stash.add("sword_short", 1)
	var short_price := int(State.ITEMS["sword_short"]["price"])
	var pool_row: Dictionary = _row_for(game.vendor_menu.stash_rows(), "sword_short")
	check(not pool_row.is_empty() and int(pool_row.get("count", 0)) == 1,
		"the spare shelf shows the pooled copy with its count")

	var after_buy: int = int(state.credits)
	var sword_sold: Dictionary = game.vendor_menu.sell("sword_short")
	check(bool(sword_sold.get("ok", false)), "Orla buys the spare shortsword back")
	var payout := int(sword_sold.get("price", 0))
	check(payout == int(floor(float(short_price) * 0.6)),
		"the sale pays 60%% of the price (%d)" % payout)
	check(absf(float(payout) / float(short_price) - 0.6) < 0.02,
		"the payout is about sixty percent")
	check(int(state.credits) == after_buy + payout, "the purse is paid the sale price")
	check(warband.stash.pooled_count("sword_short") == 0,
		"the sold copy leaves the shared stash")
	check(_row_for(game.vendor_menu.stash_rows(), "sword_short").is_empty(),
		"the spare shelf drops the sold row")
	check(game.vendor_menu.status_text().contains("Sold"),
		"the keeper says what was sold")
	check(not bool(game.vendor_menu.sell("sword_short").get("ok", true)),
		"selling a copy the pool does not hold is refused")

	# A short purse refuses before the pack is touched.
	state.credits = 1
	var held: int = warband.supply_count("bandage")
	var refused_buy: Dictionary = game.vendor_menu.buy("bandage_linen")
	check(not bool(refused_buy.get("ok", true)), "a short purse buys nothing")
	check(int(state.credits) == 1, "a refused purchase spends nothing")
	check(warband.supply_count("bandage") == held,
		"a refused purchase adds nothing to the pack")
	check(game.vendor_menu.status_text().contains("gold"),
		"the refusal names the shortfall")

	game.vendor_menu.close()
	check(not game.vendor_menu.is_open(), "the stall closes")
	check(not game.panels_open(), "closing the stall leaves no panel open")

	game.queue_free()
	await process_frame
	state.reset(false)
	warband.reset_state()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("WARBAND_VENDORS_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
