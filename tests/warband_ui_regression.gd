extends SceneTree
## Warband UI regression: the tactical screen tells the truth about a warband
## with a living, a downed and a dead body; click-to-control emits once and only
## for a body the player may actually enter; `Warband.changed` repaints without a
## reopen; the paperdoll dresses and undresses a mercenary out of the collective
## stash without losing a single gold of value; and the recruiter charges the
## vendor's price and refuses honestly at the hire cap.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const SaveFileScript = preload("res://scripts/save_file.gd")
const ScreenScript = preload("res://scripts/warband/warband_screen.gd")
const DollScript = preload("res://scripts/warband/warband_paperdoll.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")

const TEST_SAVE := "user://warband_ui_state.json"

var checks := 0
var failures := 0
var state
var warband

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("WARBAND_UI_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

func _set_gold(amount: int) -> void:
	state.add_credits(amount - int(state.credits))

func run() -> void:
	_remove_test_save()
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_set_gold(1000)
	_check_rows_and_control()
	_check_refresh()
	_check_paperdoll()
	await _check_page_fit()
	_check_item_hover()
	_check_sell_menu()
	_check_upgrade_pool()
	_check_recruiter()
	_check_old_save_purge()
	warband.reset_state()
	state.reset(false)
	_remove_test_save()
	print("WARBAND_UI_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- the screen ------------------------------------------------------------

func _check_rows_and_control() -> void:
	warband.reset_state()
	_set_gold(1000)
	var alive: int = warband.add_mercenary("Aldous")
	var downed: int = warband.add_mercenary("Brine")
	var fallen: int = warband.add_mercenary("Cael")
	warband.stash.add("dagger_iron", 1)
	check(bool(warband.equip_merc(fallen, "main", "dagger_iron").get("ok", false)),
		"the doomed body wears a dagger")
	var pieces_before: int = warband.stash.pooled_count("dagger_iron")
	warband.roster.apply_damage(downed, 100.0)
	warband.roster.apply_damage(fallen, 120.0)
	check(warband.roster.state_of(alive) == Contracts.HealthState.ALIVE, "the first mercenary stands")
	check(warband.roster.state_of(downed) == Contracts.HealthState.DOWNED, "100 damage only downs")
	check(not warband.roster.has(fallen), "120 damage kills and takes the record with it")
	check(warband.roster.count() == 2, "the dead leave the roster at once (%d left)"
		% warband.roster.count())
	check(warband.stash.pooled_count("dagger_iron") == pieces_before + 1,
		"what the dead were wearing goes back into the shared stash")

	var souls = warband.souls
	var screen = ScreenScript.new()
	screen.configure(warband, souls)
	root.add_child(screen)
	screen.open()
	check(screen.is_open(), "open() opens the screen")
	check(screen.rows.size() == 2, "one row per mercenary still on the books, got %d"
		% screen.rows.size())
	check(not screen.rows.has(fallen), "the fallen have no row")
	check(screen.rows[alive]["name"].text == "Aldous", "the row names the mercenary")
	check(screen.rows[downed]["name"].text == "Brine", "rows stay in roster order")

	check(screen.rows[alive]["state"].text == "ALIVE", "the living row reads ALIVE")
	check(screen.rows[downed]["state"].text == "DOWNED", "the downed row reads DOWNED")
	check(screen.rows[downed]["state"].get_theme_color("font_color")
		!= screen.rows[alive]["state"].get_theme_color("font_color"),
		"a downed row is coloured apart from a living one")
	check(screen.rows[alive]["bar"].value == 100.0, "the live health bar reads the roster")
	check(screen.rows[alive]["health"].text == "100 / 100", "the health line reads the roster")
	check(screen.rows[downed]["bar"].value == 0.0, "a downed body reads zero health")
	check(screen.rows[alive]["gear"].text.contains("empty"),
		"the gear summary names the empty hands: %s" % screen.rows[alive]["gear"].text)

	check(not screen.rows[alive]["control"].disabled, "a living body can be controlled")
	check(screen.rows[downed]["control"].disabled, "a downed body cannot be jumped into")

	check(screen.gold_label.text == "1000 G", "the header shows the purse, got %s" % screen.gold_label.text)
	check(screen.value_label.text.contains(str(warband.total_value())),
		"the header shows the warband's worth, got %s" % screen.value_label.text)

	var seen: Array[int] = []
	screen.possess_requested.connect(func(merc_id: int) -> void: seen.append(merc_id))
	screen.rows[alive]["control"].pressed.emit()
	check(seen.size() == 1 and seen[0] == alive,
		"clicking the living row emits exactly one possess_requested, got %s" % str(seen))
	screen.rows[downed]["control"].pressed.emit()
	check(seen.size() == 1, "disabled rows never emit, got %s" % str(seen))

	# Another peer inside the living body: the button advertises the lock.
	var body := Node3D.new()
	souls.register_body(alive, body, "Aldous")
	# Re-binding the same warband and router must not duplicate rows or wires:
	# the possession checks below run on the freshly attached listener.
	screen.configure(warband, souls)
	check(screen.rows.size() == 2, "re-configuring keeps one row per mercenary")
	check(bool(souls.request_transfer(7, alive).get("ok", false)), "peer 7 takes the living body")
	check(screen.rows[alive]["control"].disabled, "a body held by another peer is disabled")
	check(screen.rows[alive]["control"].text == "IN USE", "the held body says so")
	screen.rows[alive]["control"].pressed.emit()
	check(seen.size() == 1, "an occupied body cannot be requested")
	souls.release_peer(7, "test")
	check(not screen.rows[alive]["control"].disabled, "the released body is controlable again")
	souls.unregister_body(alive)
	body.free()
	screen.close()
	check(not screen.is_open(), "close() closes the screen")

func _check_refresh() -> void:
	var alive := int(warband.roster.ids()[0])
	var screen = ScreenScript.new()
	screen.configure(warband)
	root.add_child(screen)
	screen.open()
	warband.roster.set_health(alive, 55.0)
	warband.changed.emit()
	check(screen.is_open(), "a changed warband does not close the screen")
	check(screen.rows[alive]["health"].text == "55 / 100",
		"Warband.changed repaints the health line, got %s" % screen.rows[alive]["health"].text)
	check(screen.rows[alive]["bar"].value == 55.0, "Warband.changed repaints the bar")
	check(screen.rows[alive]["gear"].text.contains("empty"), "the row is still the same row")
	warband.stash.add("sword_short", 1)
	warband.equip_merc(alive, "main", "sword_short")
	check(screen.rows[alive]["gear"].text.contains("Shortsword"),
		"an equip made elsewhere shows in the gear summary, got %s"
		% screen.rows[alive]["gear"].text)
	screen.close()

# --- an old file's dead ----------------------------------------------------

## A save written before the dead left the books still carries their records.
## Opening it must free the hire cap on the spot and hand the stash back what
## the corpse was wearing - not inherit a graveyard and its kit.
func _check_old_save_purge() -> void:
	warband.reset_state()
	_set_gold(0)
	var survivor: int = warband.add_mercenary("Ash")
	var fallen: int = warband.add_mercenary("Bram")
	warband.roster.equip(fallen, "main", "sword_short")
	var data: Dictionary = warband.to_dict()
	var records: Array = data["roster"]["mercenaries"]
	for record in records:
		if int((record as Dictionary)["id"]) == fallen:
			record["state"] = Contracts.HealthState.DEAD
			record["health"] = 0.0
	check(SaveFileScript.write(TEST_SAVE, data), "the old save is written")
	check(warband.load_state(), "an old save with a dead record still loads")
	check(not warband.roster.has(fallen), "the dead record is gone from the roster")
	check(warband.roster.has(survivor), "the living record stays")
	check(warband.roster.count() == 1, "the party is the living alone (%d)"
		% warband.roster.count())
	check(warband.stash.pooled_count("sword_short") == 1,
		"and what the dead body wore is back in the shared stash")

# --- the character screen: gear -------------------------------------------

## The gear page: the body, the seven worn slots and its numbers. A click on a
## slot opens the pieces the warband owns for it and puts one on - never takes one
## off; a right-click's menu is the only way a piece leaves the body, and it sells.
func _check_paperdoll() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	var other: int = warband.add_mercenary("Brine")
	warband.stash.add("sword_short", 2)
	warband.stash.add("shield_buckler", 1)
	warband.stash.add("sword_great", 1)
	warband.add_supply("potion", 3)
	warband.add_supply("bandage", 5)
	var baseline: int = warband.total_value()

	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)
	var notices := [0]
	doll.changed.connect(func() -> void: notices[0] += 1)
	check(doll.is_open(), "open() opens the character screen")
	check(doll.current_page() == "gear", "and it opens on the gear page")
	check(doll.selected_merc == first, "the page opens on the asked-for mercenary")
	check(doll.title_label.text == "ALDOUS",
		"the header names the body, got %s" % doll.title_label.text)
	check(doll.slot_rows.size() == Contracts.SLOT_ORDER.size(),
		"the seven worn slots are drawn, got %d" % doll.slot_rows.size())
	check(Contracts.slot_id(Contracts.SLOT_ORDER[0]) == "main"
			and Contracts.slot_id(Contracts.SLOT_ORDER[1]) == "off",
		"the rows put the steel first, in the order the body is armed")
	check(doll.controlled_merc == first, "the page opens on the body the soul is in")
	# The page is the body and its numbers: no picker of other bodies, no set
	# button, no re-kit, no hotbar, no unequip-all.
	check(doll.tabs.size() == 4, "the screen has four tabs, got %d" % doll.tabs.size())
	check(doll.tabs.has("gear") and doll.tabs.has("inventory")
			and doll.tabs.has("skills") and doll.tabs.has("upgrades"),
		"GEAR, INVENTORY, SKILLS and UPGRADES")
	check(doll.get("picker_buttons") == null, "there is no strip of other bodies")
	check(doll.get("_set_button") == null, "there is no weapon-set button")
	check(doll.get("_reequip_button") == null, "there is no RE-EQUIP button")
	check(doll.get("_reset_hotbar_button") == null, "there is no UNEQUIP ALL")
	check(doll._stage.custom_minimum_size.x == doll.PORTRAIT_WIDTH,
		"the portrait is the half-width stage, got %s" % str(doll._stage.custom_minimum_size))
	check(doll.PORTRAIT_WIDTH * 2.0 == 420.0, "which is half the old 420 px stage")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"the mercenary starts bare")
	check(doll.slot_rows["main"]["button"].text.contains("empty"),
		"an empty slot says empty")

	# A click on a slot lists what the warband owns for it; picking a row wears it.
	doll.slot_rows["main"]["button"].pressed.emit()
	check(doll._menu_box.visible, "clicking a slot opens its alternatives")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"and puts nothing on by itself")
	var alternatives := doll.slot_alternatives("main")
	check(alternatives.size() == 2,
		"the main hand offers the two blades the warband owns, got %d"
		% alternatives.size())
	var row = _menu_row(doll, "sword_short")
	check(row != null, "the shortsword is one of them")
	row.pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_short",
		"choosing it wears it")
	check(warband.stash.pooled_count("sword_short") == 1, "the pool count drops by one")
	check(not doll._menu_box.visible, "and the menu closes")
	check(doll.slot_rows["main"]["button"].text.contains("Shortsword"),
		"the worn slot label updates, got %s" % doll.slot_rows["main"]["button"].text)
	check(notices[0] > 0, "the page announces the change")

	# Clicking the worn slot again never takes the piece off: it lists the
	# alternatives, and the one worn is marked as such.
	doll.slot_rows["main"]["button"].pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_short",
		"a press on a worn slot does not unequip it")
	var worn_rows := doll.slot_alternatives("main")
	check(bool((worn_rows[0] as Dictionary).get("worn", false)),
		"the worn piece is the first row and is marked, got %s" % str(worn_rows[0]))
	doll.close_menu()

	# A two-hander taken up clears the off hand, and an off-hand piece clears it
	# again: the roster's displacement rules reach the page unchanged.
	doll.open_slot_menu("main")
	_menu_row(doll, "sword_great").pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_great",
		"the greatsword is worn in the main hand")
	doll.open_slot_menu("off")
	check(_menu_row(doll, "shield_buckler") != null,
		"the off hand offers the shield while a two-hander is worn")
	_menu_row(doll, "shield_buckler").pressed.emit()
	check(str(warband.roster.equipped_of(first)["off"]) == "shield_buckler",
		"the shield goes into the off hand")
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"and displaces the two-hander")
	check(warband.stash.pooled_count("sword_great") == 1, "the greatsword returns to the pool")
	check(warband.total_value() == baseline, "no gold is lost moving gear, %d vs %d"
		% [warband.total_value(), baseline])

	# The head slot lists every head the warband owns, the worn one first: "clicking
	# Head cycles through all of your Head equipment".
	for piece in ["armor_leather_head", "armor_mail_head"]:
		warband.stash.add(piece, 1)
	doll.refresh()
	var heads := doll.slot_alternatives("head")
	check(heads.size() == 2, "the head slot lists every helm owned, got %d" % heads.size())
	doll._on_slot_pressed("head")
	check(doll._menu_box.visible, "clicking Head opens its list")
	var helm = _menu_row(doll, "armor_mail_head")
	check(helm != null, "the mail helm is on the list")
	helm.pressed.emit()
	check(str(warband.roster.equipped_of(first).get("head", "")) == "armor_mail_head",
		"and choosing it wears it")
	check(String(doll._stat_values["head_guard"].text) == "%d%%" % int(round(
		ArmorData.reduction_for(ArmorData.set_of_item("armor_mail_head"), "head") * 100.0)),
		"the head guard line reads the worn helm, got %s" % doll._stat_values["head_guard"].text)

	# Another body's worn piece is not offered here: moving it would strip them.
	warband.stash.add("sword_arming", 1)
	check(bool(warband.equip_merc(other, "main", "sword_arming").get("ok", false)),
		"the other body wears the arming sword")
	doll.refresh()
	var mains := doll.slot_alternatives("main")
	var offered := false
	for entry in mains:
		if str(entry["item_id"]) == "sword_arming":
			offered = true
	check(not offered, "a piece another body wears is not offered")

	# The body's numbers, read from the tables that own them.
	check(String(doll._stat_values["health"].text) == str(int(round(
		warband.roster.max_health_of(first)))),
		"the health line reads the roster, got %s" % doll._stat_values["health"].text)
	check(String(doll._stat_values["stamina"].text) == "1000",
		"the stamina line reads the pool, got %s" % doll._stat_values["stamina"].text)
	check(String(doll._medicine_values["potion"].text) == "×3",
		"the potion count reads the band's stock, got %s" % doll._medicine_values["potion"].text)
	check(String(doll._medicine_values["bandage"].text) == "×5",
		"and so does the bandage count, got %s" % doll._medicine_values["bandage"].text)
	check(String(doll._stat_values["worth"].text).ends_with("G"),
		"the kit's worth is on the page")
	doll.close()
	check(not doll.is_open(), "close() closes the screen")
	check(doll.get("_bench_button") == null and doll.get("_bench_layer") == null,
		"the screen carries no annoint bench")
	doll.queue_free()

## The menu row that would put `item_id` on, or null when the menu holds none.
func _menu_row(doll, item_id: String) -> Button:
	for child in doll._menu_rows.get_children():
		if str(child.get_meta("item_id", "")) == item_id:
			return child as Button
	return null

# --- the page fits ---------------------------------------------------------

## The screen is a fixed page inside the frame. Every page and every overlay must
## stay inside it: the worn rows, the portrait, the numbers, the grid, the skills
## row and the hover card - and a page must never grow its frame to fit its
## content, which is what once drew the item window off the bottom of the screen.
func _check_page_fit() -> void:
	warband.reset_state()
	_set_gold(1000)
	for index in 8:
		var merc_id: int = warband.add_mercenary("Body %d" % (index + 1))
		if index % 3 == 1:
			warband.roster.apply_damage(merc_id, 100.0)
	for item_id in ["sword_short", "shield_wood", "armor_leather_chest",
			"armor_leather_head", "bow_short", "focus_skull", "sword_great"]:
		warband.stash.add(item_id, 1)
	var doll = DollScript.new()
	root.add_child(doll)
	doll.configure(warband)
	doll.open(-1)
	# Four frames: the panel, the frame's page, and the pages' own layout.
	for _pass in 4:
		await process_frame
	var frame: Control = doll.get_node("WarbandPaperdoll/Frame")
	var page := _page_rect(frame)
	for page_id in ["gear", "inventory", "skills", "upgrades"]:
		doll.open_page(page_id)
		for _pass in 2:
			await process_frame
		var needed: Vector2 = frame.body.get_combined_minimum_size()
		check(needed.x <= page.size.x, "the %s page fits the frame's width: %s of %s"
			% [page_id, str(needed), str(page.size)])
		check(needed.y <= page.size.y, "the %s page fits the frame's height: %s of %s"
			% [page_id, str(needed), str(page.size)])
		check(frame.body.size.x <= page.size.x,
			"and the %s page does not widen its own frame" % page_id)
	doll.open_page("gear")
	for _pass in 2:
		await process_frame
	check(page.encloses(doll._stage.get_global_rect()),
		"the portrait sits inside the page, at %s" % str(doll._stage.get_global_rect()))
	check(page.encloses(doll.slot_rows["main"]["button"].get_global_rect()),
		"and so do the worn rows")
	# A hover card is a card, not a window: it never grows past its ceiling.
	doll._hover_item("sword_great", "")
	for _pass in 2:
		await process_frame
	doll._fit_overlay(doll._hover_card)
	check(doll._hover_card.size.y <= doll.MENU_MAX_HEIGHT,
		"the item card is capped, got %s" % str(doll._hover_card.size))
	check(doll._hover_card.size.x <= doll.MENU_WIDTH + 1.0,
		"and it is one card wide, got %s" % str(doll._hover_card.size))
	check(doll._shell.get_global_rect().encloses(
		Rect2(doll._hover_card.position, doll._hover_card.size)),
		"the card is clamped inside the window, at %s" % str(doll._hover_card.position))
	doll.hide_hover()
	doll.close()
	doll.queue_free()
	await process_frame

## The page the frame hands its content: the frame's own rect less the inset and
## padding it reserves for the clamp, the title rail and the page's torn edge.
## Read from the frame, never from the body - a body that grew to fit an
## overflowing strip would otherwise measure itself and pass.
func _page_rect(frame: Control) -> Rect2:
	var rect := frame.get_global_rect()
	var inset := LedgerFrameScript.PAGE_INSET + LedgerFrameScript.BODY_PAD_X
	var top := rect.position.y + LedgerFrameScript.PAGE_INSET \
		+ LedgerFrameScript.HEADER + LedgerFrameScript.BODY_PAD_TOP
	var bottom := rect.end.y - LedgerFrameScript.PAGE_INSET \
		- LedgerFrameScript.BODY_PAD_BOTTOM
	return Rect2(rect.position.x + inset, top,
		rect.size.x - 2.0 * inset, bottom - top)

# --- item hover details ----------------------------------------------------

## The hover card is the only place the screen says what a piece actually is: the
## slots carry a name and the grid carries an icon, so a card that slipped back to
## a sentence would leave the inventory with no item details at all. Every check
## reads its expectation from the catalogue or the table that owns the number.
func _check_item_hover() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	warband.stash.add("sword_short", 1)
	warband.stash.add("armor_leather_chest", 1)
	warband.stash.add("focus_skull_life", 1)
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)
	doll.open_page("inventory")

	# The grid is the catalogue's own renders, one tile per kind.
	check(doll.inventory_rows.size() == 3, "the grid lists every pooled kind, got %d"
		% doll.inventory_rows.size())
	var tile: Dictionary = doll._inventory_tiles.get("sword_short", {})
	check(not tile.is_empty(), "the shortsword has a tile")
	var tile_icon: TextureRect = (tile["button"] as Button).get_node_or_null("Icon")
	check(tile_icon != null and tile_icon.texture != null,
		"and the tile draws the piece's own rendered icon")
	check(str((tile["button"] as Button).name) == "Item_sword_short",
		"the tile is named for the piece, got %s" % str((tile["button"] as Button).name))

	# A weapon: name, kind, the catalogue's detail line and its worth.
	doll._hover_item("sword_short", "")
	var sword_text := _card_text(doll._hover_card)
	check(doll._hover_card.visible, "hovering a tile raises the item card")
	check(sword_text.contains("Shortsword"), "the card names the piece")
	check(sword_text.contains("ONE-HAND"), "the card carries the type line, got %s" % sword_text)
	check(sword_text.contains(str(State.ITEMS["sword_short"]["detail"])),
		"the card carries the catalogue's detail text")
	check(sword_text.contains("WORTH"), "the card prices the piece")

	# Armor: the guard the set actually grants, not a word about clicking.
	doll._hover_item("armor_leather_chest", "")
	var armor_text := _card_text(doll._hover_card)
	var guard := int(round(ArmorData.reduction_for(
		ArmorData.set_of_item("armor_leather_chest"), "chest") * 100.0))
	check(armor_text.contains("BODY GUARD"),
		"the card names the guard channel, got %s" % armor_text)
	check(armor_text.contains("+%d%%" % guard),
		"the card prints the set's real guard (%d%%)" % guard)

	# The one carrying piece a body can still wear in the off hand: the skull's
	# modifier rows come from the table combat reads.
	doll._hover_item("focus_skull_life", "")
	var focus_text := _card_text(doll._hover_card)
	var focus_rows: Array = TrinketStats.effect_rows("focus_skull_life")
	check(not focus_rows.is_empty(), "the skull carries a modifier row")
	if not focus_rows.is_empty():
		check(focus_text.contains(str((focus_rows[0] as Dictionary)["label"])),
			"the card names the skull's modifier, got %s" % focus_text)
		check(focus_text.contains(str((focus_rows[0] as Dictionary)["value"])),
			"the card prints the skull's real value, got %s" % focus_text)

	# A worn slot describes what it holds; an empty one raises nothing.
	warband.equip_merc(first, "main", "sword_short")
	warband.unequip_merc(first, "armor_leather_chest")
	doll.refresh()
	doll._hover_slot("main")
	check(doll._hover_card.visible, "hovering a worn slot raises its card")
	check(_card_text(doll._hover_card).contains(str(State.ITEMS["sword_short"]["detail"])),
		"the worn slot's card carries the piece's details")
	warband.unequip_merc(first, "main")
	doll.refresh()
	doll.hide_hover()
	doll._hover_slot("main")
	check(not doll._hover_card.visible, "an empty slot raises no card")
	doll.close()
	doll.queue_free()

## Every Label under the card, which is how a card says anything at all.
func _card_text(node: Node) -> String:
	var parts := PackedStringArray()
	_collect_card_text(node, parts)
	return "\n".join(parts)


func _collect_card_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		_collect_card_text(child, parts)

# --- selling ---------------------------------------------------------------

## The right-click menu is the screen's only way a piece leaves: SELL. A spare goes
## straight out of the pool; a worn copy is taken off the body first, so the page
## never sells a piece it is still drawing as worn. The old right-click bound a
## piece out of the band's arming and that is gone with it.
func _check_sell_menu() -> void:
	warband.reset_state()
	_set_gold(1000)
	var first: int = warband.add_mercenary("Aldous")
	warband.stash.add("sword_arming", 2)
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(first)

	# A right-click on a worn slot opens the piece's menu, and nothing else happens.
	var worn := String(warband.equip_merc(first, "main", "sword_arming").get("message", ""))
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_arming",
		"the body wears the arming sword (%s)" % worn)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	doll._on_slot_input(right_click, "main")
	check(doll._sell_box.visible, "a right-click on a worn slot opens its menu")
	check(str(warband.roster.equipped_of(first)["main"]) == "sword_arming",
		"and the piece is still worn")
	var payout := int(floor(float(State.ITEMS["sword_arming"]["price"]) * 0.6))
	check(doll._sell_button.text.contains("%d G" % payout),
		"the menu prices the sale at the keeper's share, got %s" % doll._sell_button.text)
	var gold_before: int = warband.gold()
	doll._sell_button.pressed.emit()
	check(str(warband.roster.equipped_of(first)["main"]).is_empty(),
		"selling a worn copy takes it off the body")
	check(warband.gold() == gold_before + payout,
		"and the purse takes the price (%d -> %d)" % [gold_before, warband.gold()])
	check(warband.stash.pooled_count("sword_arming") == 1,
		"one copy was sold, one spare is left, got %d"
		% warband.stash.pooled_count("sword_arming"))

	# A spare sells from the inventory grid with one press.
	doll.open_page("inventory")
	doll.open_sell_menu("", "sword_arming")
	check(doll._sell_box.visible, "the grid's menu opens too")
	gold_before = warband.gold()
	doll._sell_button.pressed.emit()
	check(warband.gold() == gold_before + payout, "and a spare sells for the same share")
	check(warband.stash.pooled_count("sword_arming") == 0,
		"the last copy leaves the pool, got %d" % warband.stash.pooled_count("sword_arming"))
	check(doll.inventory_rows.is_empty(), "and the grid drops the row")

	# The left-click on a tile is that same menu; a right-click on a worn slot is
	# not a hold of any kind - there is no hold left in the warband's books.
	doll.open_page("gear")
	warband.stash.add("sword_great", 1)
	warband.equip_merc(first, "main", "sword_great")
	doll.refresh()
	doll._on_slot_input(right_click, "main")
	check(doll._sell_box.visible, "the right-click is a menu, not a hold")
	check(doll._sell_item == "sword_great", "and it names the piece on the slot")
	doll.close_menu()
	doll.close()
	doll.queue_free()

# --- the upgrades page -----------------------------------------------------

## The upgrades page is the pool itself: every row the game can offer, grouped by
## family, with the sentence the pool writes for what it does and a mark on what
## this run has taken. It is a catalogue - no row is a press.
func _check_upgrade_pool() -> void:
	warband.reset_state()
	_set_gold(1000)
	warband.add_mercenary("Aldous")
	var doll = DollScript.new()
	doll.configure(warband)
	root.add_child(doll)
	doll.open(-1)
	doll.open_page("upgrades")
	check(doll.current_page() == "upgrades", "the upgrades page opens")
	var live := 0
	for row in Mods.all():
		if Mods.ready_of(str(row.get("id", ""))):
			live += 1
	check(doll._pool_head.text.contains("%d LIVE ROWS" % live),
		"the census counts the rows the game can offer, got %s" % doll._pool_head.text)
	var rows := 0
	for child in doll._pool_box.get_children():
		if child is PanelContainer:
			rows += 1
	check(rows == live, "one row per live upgrade, got %d of %d" % [rows, live])
	var text := _card_text(doll._pool_box)
	check(text.contains("Broadhead"), "the pool lists a known row")
	check(text.contains("SHOT"), "the families have their headings")
	check(text.contains("PERK") and text.contains("RELIC"),
		"and every family is in the list")
	check(text.contains("UP TO ×%d" % Mods.max_stacks("broadhead")),
		"a row carries its ceiling")
	check(text.contains(str((Mods.get_mod("broadhead") as Dictionary).get(
		"description", "")).substr(0, 24)),
		"and the words the pool writes for what it does")
	check(not text.contains("TAKEN"), "nothing is taken outside a run")
	var presses := 0
	for child in doll._pool_box.get_children():
		if child is Button:
			presses += 1
	check(presses == 0, "no row of the pool is a press, got %d" % presses)

	# A run's rows are marked with their stacks, and the census counts them. The
	# pool is read through the same callable the SKILLS page reads.
	doll.run_upgrades = func(_merc: int) -> Array:
		return [{"id": "broadhead", "stacks": 3}]
	doll.refresh()
	text = _card_text(doll._pool_box)
	check(text.contains("TAKEN ×3"),
		"a row the run carries is marked with its stacks")
	check(doll._pool_head.text.contains("1 TAKEN THIS RUN"),
		"and the census counts it, got %s" % doll._pool_head.text)
	doll.close()
	doll.queue_free()

# --- the recruiter ---------------------------------------------------------

func _check_recruiter() -> void:
	warband.reset_state()
	_set_gold(1000)
	warband.add_mercenary("Aldous")
	var screen = ScreenScript.new()
	screen.configure(warband)
	root.add_child(screen)
	screen.open()
	check(screen.hire_offers.size() == 3, "the board offers three bodies")
	for row in screen.hire_offers:
		check(not str(row.get("hands", "")).is_empty(),
			"a row names the hands it sells (%s)" % str(row.get("hands", "")))
		check(not str(row.get("archetype_label", "")).is_empty(), "and the trade")
		check(str(row.get("name", "")) != "Aldous", "the board skips a name already sworn")
	var cost: int = warband.hire_cost()
	check(cost == 0, "the recruiter's first oaths are free, got %d" % cost)
	check(screen.hire_buttons[0].text.contains("FREE"), "the HIRE button says the oath is free")
	check(str(screen._hire_rows[0]["detail"].text).contains(
			str(screen.hire_offers[0].get("archetype_label", ""))),
		"the row paints the trade it sells, got %s" % str(screen._hire_rows[0]["detail"].text))
	check(not str(screen._hire_rows[0]["kit"].text).is_empty(),
		"and the armour and skill line is on the page")
	check(str(screen._hire_rows[0]["kit"].text).contains(
			str(screen.hire_offers[0].get("armor_set", "")).capitalize()),
		"with the armour it is sworn in, got %s" % str(screen._hire_rows[0]["kit"].text))

	var gold_before: int = warband.gold()
	var first_offer: Dictionary = screen.hire_offers[0]
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == 2, "HIRE swears a body in")
	check(warband.gold() == gold_before - cost, "a free HIRE takes no gold")
	check(screen.rows.size() == 2, "the roster repaints immediately")
	check(screen.gold_label.text == "%d G" % warband.gold(), "the purse repaints immediately")
	# The body walks in wearing the card: the desk sells whole bodies now, and the
	# kit never changes afterwards.
	var hired_ids: Array[int] = warband.roster.ids()
	var hired_id: int = hired_ids[hired_ids.size() - 1]
	check(warband.is_gear_locked(hired_id), "the hire is locked to the kit it was sold in")
	check(str(warband.roster.equipped_of(hired_id).get("main", ""))
			== str((first_offer.get("gear", {}) as Dictionary).get("main", "")),
		"which is the hand the row sold, got %s"
			% str(warband.roster.equipped_of(hired_id).get("main", "")))
	var board_after: Array = screen.hire_offers.duplicate()
	var rerolled := true
	for row in board_after:
		if str((row as Dictionary).get("name", "")) == str(first_offer.get("name", "")):
			rerolled = false
	check(rerolled, "the board lays out fresh rows after the sale (%d)" % board_after.size())

	# An empty purse still swears a body: gold is only asked for past the free places.
	_set_gold(0)
	var broke: int = warband.roster.count()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == broke + 1, "a free oath needs no gold")
	check(warband.gold() == 0, "and leaves the empty purse alone")
	_set_gold(1000)

	while warband.roster.count() < warband.deployment_cap:
		warband.add_mercenary("")
	var sworn: int = warband.roster.count()
	var gold_at_cap: int = warband.gold()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == sworn, "the cap refuses the hire")
	check(warband.gold() == gold_at_cap, "a refused hire spends nothing")
	check(screen.status_text().contains("No more can be sworn"),
		"the refusal is reported, got %s" % screen.status_text())
	check(screen.rows.size() == sworn, "the roster is unchanged at the cap")

	# A dead mercenary no longer holds a place: the same cap can be filled again.
	var fallen: int = warband.roster.ids()[0]
	warband.roster.apply_damage(fallen, 1000.0)
	check(not warband.roster.has(fallen), "the fallen leave the books at the cap")
	check(warband.roster.count() == sworn - 1, "and free a place in the warband")
	_set_gold(10000)
	var freed: int = warband.roster.count()
	screen.hire_buttons[0].pressed.emit()
	check(warband.roster.count() == freed + 1, "the freed place can be sworn again")
	check(not screen.status_text().contains("No more can be sworn"),
		"the recruiter no longer refuses, got %s" % screen.status_text())
	screen.close()
