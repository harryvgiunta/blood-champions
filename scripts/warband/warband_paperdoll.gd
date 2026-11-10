class_name WarbandPaperdoll
extends CanvasLayer
## The character screen: GEAR, INVENTORY, SKILLS and UPGRADES over one body.
##
## GEAR is the body itself - the portrait, the seven worn slots and the numbers
## those slots add up to, with the band's medicine counted beside them. A
## left-click on a worn slot opens the alternatives the warband owns for that
## slot and puts one on; it never takes a piece off. The hands are the one place
## a choice displaces another: a two-hander clears the off hand, an off-hand piece
## clears a two-hander, and both land through `Warband.equip_merc`, so the pieces
## go where the roster stores them. A right-click opens the piece's own menu,
## whose one action is SELL: a worn copy is taken off the body first, because a
## piece somebody is wearing is not the warband's to sell behind their back.
##
## INVENTORY is the shared stash as a grid of the catalogue's own rendered icons
## (`assets/ui/items`, the game's own 3D renders). A hover raises a small card
## with the piece's description; a right-click sells the spare. The grid is a
## fixed page inside the frame, never a window that grows to the bottom of the
## screen.
##
## SKILLS is the bar: five keys, or more while a run's upgrade has bought them,
## with the skill assigned to each. Clicking a key opens the player's unlocked
## skills and puts one on that key; the panel beside it lists every unlock and
## every upgrade the run has taken, with the words the catalogue wrote for them.
##
## UPGRADES is the pool itself, family by family: every row a chest, the stall or
## a boss can pay, with its rarity, its ceiling and the sentence the pool writes
## for what it does, and the rows this run has taken marked with their stacks. It
## is a catalogue - nothing on it is pressed.
##
## Nothing here writes state itself. Every press is a `Warband` verb
## (`equip_merc`, `unequip_merc`, `sell_gear`, `set_hotbar_slot`) and the page is
## repainted from the live state, so a change made anywhere else - a loot take, a
## chest's piece, the band's own arming - shows up here without reopening.
##
## The same renderer also shows a dead enemy. `show_corpse()` puts the screen on
## the gear page with the right column become the kit the body still carries, and
## every take goes through `WarbandLoot.take_from_corpse()` - the same booking
## path a hand pickup uses, so the stash stays the warband's only inventory.

signal changed

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Rules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const CharacterPreview = preload("res://scripts/character_preview.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Looks = preload("res://scripts/warband/warband_looks.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const AbilitySlotScript = preload("res://scripts/ability_slot.gd")
const ItemCard = preload("res://scripts/warband/item_card.gd")
const Archer = preload("res://scripts/archer.gd")
const Stamina = preload("res://scripts/stamina.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")

const CREAM := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const GOLD := LedgerThemeScript.BLOOD
const TEAL := LedgerThemeScript.TEAL
const BONE := Color("e9e0c9")
const BONE_DIM := Color("b7ab93")
const SIZE := Vector2(1240, 780)

## The four pages, in the order the tabs read. The id is what `open_page` takes.
const PAGE_GEAR := "gear"
const PAGE_INVENTORY := "inventory"
const PAGE_SKILLS := "skills"
const PAGE_UPGRADES := "upgrades"
const PAGES: Array[String] = [PAGE_GEAR, PAGE_INVENTORY, PAGE_SKILLS, PAGE_UPGRADES]
const PAGE_LABELS := {
	PAGE_GEAR: "GEAR", PAGE_INVENTORY: "INVENTORY", PAGE_SKILLS: "SKILLS",
	PAGE_UPGRADES: "UPGRADES",
}

## The page the frame draws inside its own edges. The gear page's three columns
## add up to it: the worn rows, the portrait's own measure and the stats.
const PAGE_WIDTH := SIZE.x - 2.0 * (
	LedgerFrameScript.PAGE_INSET + LedgerFrameScript.BODY_PAD_X)
const GUTTER := 16.0
const WORN_WIDTH := 300.0
## Half the old stage's 420: a portrait, not a diorama. The box is square-ish so
## the standing figure is framed by the camera, not squashed by its own window.
const PORTRAIT_WIDTH := 210.0
const PORTRAIT_HEIGHT := 430.0
## The inventory grid: one square per kind, the catalogue's render inside it.
const TILE := 84.0
const TILE_GAP := 8
## The skills page's keys, at the HUD's own compact measure (a compact tile is
## anything at or below `AbilitySlot.COMPACT`), widened enough to point at.
const SKILL_TILE := 50.0
const SKILL_GAP := 6
## The hover card and the two mini menus, and the margin they keep from the screen
## edge. Both are sized by their content and clamped into the frame: neither ever
## grows into the space the game is drawn in.
const MENU_WIDTH := 380.0
const MENU_MAX_HEIGHT := 460.0
const HOVER_EDGE := 18.0

## The worn slots' own icon per slot id.
const SLOT_ICON := {
	"head": "helm", "chest": "cuirass", "hands": "gauntlet", "legs": "greaves",
	"feet": "boot",
	"main": "blade", "off": "shield",
}

## What a slot says when the piece on it is the run's own: a chest's armour and
## the pair the island carries leave when the run ends.
const RUN_PIECE_MESSAGE := "Won in this run: it leaves when the run ends."
const RUN_HANDS_MESSAGE := "The run's hands are the body's kit: TAB on the island brings the other one up."

## What the page says about moving a piece, in the one line it has for it.
const USAGE_HINT := "Click a worn slot for the pieces that fit it  ·  right-click for the piece's menu."

## The header line: the body on the page, or the body being stripped in corpse mode.
var title_label: Label
## The vacuum a corpse's pieces are booked through. `CorpseLootPanel` binds it;
## null means the corpse screen can list the kit but take nothing.
var corpse_loot = null
## Set only on a co-op guest: `(corpse_id, item_id, all) -> void`. The body and
## the pool are the host's, so a take is a request and the record that comes back
## down the session is what repaints this screen. Unset means the vacuum books
## locally, which is what the host's own screen does.
var corpse_request: Callable = Callable()
## The body being shown; 0 while the screen dresses mercenaries.
var corpse_id := 0
## The carried pieces exactly as listed, in carry order: `{item_id, name, value,
## button}`. Empty means the body is stripped.
var corpse_rows: Array[Dictionary] = []

## The mercenary being dressed; `-1` when the warband is empty.
var selected_merc := -1
## The body the soul is inside right now (`-1` when no soul holds one here). The
## page opens on it and the header names it: the gear on the page is always the
## gear the player's own hands would feel.
var controlled_merc := -1
## The active run's own armour, as `(merc_id) -> {slot: piece}`. A run dresses
## its bodies from the chest's pieces, not from the roster, so the page reads
## this over the wardrobe for the body inside the run. Unset in the town's own
## page (and on a guest with no runtime for the body): the wardrobe is then the
## whole truth.
var run_armour: Callable = Callable()
## The pair a body's hands are holding, as `(merc_id) -> {main, off}`: the run's
## pair while a run owns the body, read out of the same inventory the page lists.
var hands_for: Callable = Callable()
## The keys a run's upgrades have bought the body, as `(merc_id) -> int`. The bar
## is five keys plus this, capped at `AbilityRules.MAX_SLOT_COUNT`.
var slot_bonus: Callable = Callable()
## The upgrades the run has taken on a body, as `(merc_id) -> [{id, name, stacks,
## rarity, family}]`. Unset outside a run, where the page says so.
var run_upgrades: Callable = Callable()

## The page on show: `PAGE_GEAR`, `PAGE_INVENTORY` or `PAGE_SKILLS`.
var page := PAGE_GEAR
## Slot rows keyed by slot id (`head`..`off`): `{slot, id, button, item_id,
## run_piece, hand}`.
var slot_rows: Dictionary = {}
## The inventory grid exactly as rendered, in value order: `{item_id, name,
## count, value, button}`.
var inventory_rows: Array[Dictionary] = []
## Tab buttons keyed by page id.
var tabs: Dictionary = {}

## The skills page's keys: the tile and the button per key, and the ids the row is
## drawing (`""` for a key that fires nothing), kept for callers and tests.
var hotbar_tiles: Array = []
var hotbar_buttons: Array = []
var hotbar_ids: Array[String] = []
## The key whose picker is open, `-1` when none is.
var _skill_slot_selected := -1

var _warband = null
var _built := false
var _open := false
var _corpse_active := false
## The pieces the body carries, re-read from the vacuum on every repaint.
var _corpse_ids: Array[String] = []

var _shell: Control
var _head_hint: Label
var _merc_label: Label
var _tab_row: HBoxContainer
var _page_stack: Control
var _pages: Dictionary = {}
var _status: Label

## The gear page.
var _worn_title: Label
var _stage: NinePatchRect
var preview = null
var _stats_box: VBoxContainer
var _stat_values: Dictionary = {}
var _medicine_box: VBoxContainer
var _medicine_values: Dictionary = {}
var _corpse_box: VBoxContainer
var _corpse_rows_box: VBoxContainer
var _corpse_empty: Label
var _take_all_button: Button

## The inventory page.
var _inventory_head: Label
var _inventory_empty: Label
var _inventory_grid: GridContainer
var _inventory_tiles: Dictionary = {}   # item_id -> {button, count}

## The skills page.
var _skills_head: Label
var _skills_hint: Label
var _skills_row: HBoxContainer
var _book_head: Label
var _book_box: VBoxContainer
var _upgrade_head: Label
var _upgrade_box: VBoxContainer

## The upgrades page: the pool itself, the census line over it and the signature
## the list was last built for (the row is 142 labels, so it is not rebuilt on
## every repaint).
var _pool_head: Label
var _pool_hint: Label
var _pool_box: VBoxContainer
var _pool_sig := ""

## The overlays: one hover card, one picker menu, one sell menu.
var _overlay: Control
var _hover_card = null
var _hover_id := ""
var _menu_box: PanelContainer
var _menu_title: Label
var _menu_note: Label
var _menu_rows: VBoxContainer
var _menu_scroll: ScrollContainer
var _sell_box: PanelContainer
var _sell_title: Label
var _sell_button: Button
var _sell_item := ""
var _sell_slot := ""
var _icon_cache: Dictionary = {}

func _ready() -> void:
	layer = 25
	visible = _open
	_ensure_built()

func _exit_tree() -> void:
	_detach_source()

## Bind the panel to a warband (`null` falls back to the `/root/Warband` autoload).
func configure(warband) -> void:
	_detach_source()
	_warband = warband if warband != null else get_node_or_null("/root/Warband")
	if _warband != null and _warband.has_signal("changed") \
			and not _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.connect(_on_warband_changed)
	_ensure_built()
	refresh()

func is_open() -> bool:
	return _open

## Open on `merc_id`, or keep the current selection. `-1` picks the body the soul
## is inside when it is here, then the last name chosen, then the first
## mercenary. A real id is taken as the controlled body: every caller that opens
## this page is standing in the body it passes. Opening the character screen
## leaves the corpse screen behind: one screen, one job at a time.
func open(merc_id: int = -1) -> void:
	_ensure_built()
	if _corpse_active:
		clear_corpse()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if merc_id > 0:
		controlled_merc = merc_id
	var target := merc_id
	if target <= 0 or not _can_dress(target):
		if _can_dress(controlled_merc):
			target = controlled_merc
		elif _can_dress(selected_merc):
			target = selected_merc
		else:
			target = _first_merc_id()
	select_merc(target, false)
	set_status("")

## The body the soul is inside, so the page can open on it and the header can
## name it. `-1` when the soul is watching from outside a body.
func set_controlled(merc_id: int) -> void:
	if merc_id == controlled_merc:
		return
	controlled_merc = merc_id
	refresh()

## A soul changed bodies while this page was up. A page that was showing the body
## it just left follows the player, so the gear under the cursor stays the body
## under their hands; a page nobody could follow falls back to the first name.
func follow_controlled(merc_id: int) -> void:
	var followed := selected_merc == controlled_merc
	controlled_merc = merc_id
	if followed and _open and _can_dress(merc_id):
		select_merc(merc_id, false)
		return
	refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	close_menu()
	hide_hover()
	# A shut screen draws nothing: its stage stops rendering and posing.
	if preview != null:
		preview.set_active(false)

## Put the screen on one of its pages. Unknown ids keep the page they were on.
func open_page(page_id: String) -> void:
	if not PAGES.has(page_id):
		return
	page = page_id
	close_menu()
	hide_hover()
	refresh()

func current_page() -> String:
	return page

## Put the screen on the body `new_corpse_id` names. `ids` is what the body still
## carries; every repaint re-reads the same list from the vacuum, so a piece the
## squad took on its own never lingers here.
func show_corpse(new_corpse_id: int, ids: Array[String]) -> void:
	_ensure_built()
	_corpse_active = true
	corpse_id = new_corpse_id
	_corpse_ids = ids.duplicate()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	page = PAGE_GEAR
	close_menu()
	hide_hover()
	refresh_corpse()

## Leave the corpse screen and go back to dressing mercenaries.
func clear_corpse() -> void:
	if not _corpse_active:
		return
	_corpse_active = false
	corpse_id = 0
	_corpse_ids.clear()
	corpse_rows.clear()
	refresh()

## Whether the screen is showing a body instead of the warband.
func showing_corpse() -> bool:
	return _corpse_active

## The header line. The corpse screen names the body it is stripping; the gear
## pages name the body they are dressing.
func set_title(text: String) -> void:
	if title_label != null:
		title_label.text = text

## Take one carried piece off the body. This is the corpse screen's only action,
## and the list row and the worn slot both land here; the vacuum refuses a piece
## that is already gone, so a stale row can never pay twice.
##
## One row is one take. When the body carries several copies of the same piece -
## the shafts off a trail archer - the row names the bunch and the click books all
## of them, so the count on the button is what actually moves.
func take_piece(item_id: String) -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "item_id": item_id, "message": ""}
	if corpse_request.is_valid():
		# A guest's take: the row stays until the host's answer lands, and the
		# record that arrives is what moves it off the body.
		corpse_request.call(corpse_id, item_id, false)
		set_status("Taking %s..." % _item_name(item_id))
		return {"ok": true, "item_id": item_id, "message": ""}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_from_corpse"):
		set_status("There is no way to take that piece.")
		return {"ok": false, "item_id": item_id, "message": ""}
	var result: Dictionary = corpse_loot.take_from_corpse(corpse_id, item_id)
	var taken := 1 if bool(result.get("ok", false)) else 0
	var last: Dictionary = result
	while bool(result.get("ok", false)) and _corpse_holds(item_id):
		result = corpse_loot.take_from_corpse(corpse_id, item_id)
		if bool(result.get("ok", false)):
			taken += 1
			last = result
	set_status(str(last.get("message", "")))
	refresh_corpse()
	# Gear moved, exactly as it does when the page's own rows equip a piece:
	# whoever is watching the panel (a scene refreshing the body it drives) hears
	# the same signal for a corpse take.
	if taken > 0:
		changed.emit()
	return result

## Whether the body still carries this piece, for a caller that is emptying a row.
func _corpse_holds(item_id: String) -> bool:
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("corpse_items"):
		return false
	var ids: Array = corpse_loot.corpse_items(corpse_id)
	return ids.has(item_id)

## Strip the body in one go - the TAKE ALL row.
func take_all() -> Dictionary:
	if not _corpse_active:
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	if corpse_request.is_valid():
		corpse_request.call(corpse_id, "", true)
		set_status("Taking everything on that body...")
		return {"ok": true, "ids": [], "count": 0, "value": 0}
	if corpse_loot == null or not is_instance_valid(corpse_loot) \
			or not corpse_loot.has_method("take_all_from_corpse"):
		set_status("There is no way to take that gear.")
		return {"ok": false, "ids": [], "count": 0, "value": 0}
	var result: Dictionary = corpse_loot.take_all_from_corpse(corpse_id, 1)
	var count := int(result.get("count", 0))
	if count <= 0:
		set_status("There is nothing left on that body.")
	else:
		set_status("%d piece(s) go into %s." % [count, _pool_label()])
	refresh_corpse()
	if count > 0:
		changed.emit()
	return result

## Put the page on `merc_id`. The assignment of skills is per key on that body's
## own bar, so a body change closes any open picker.
func select_merc(merc_id: int, announce: bool = true) -> void:
	selected_merc = merc_id if _can_dress(merc_id) else -1
	_skill_slot_selected = -1
	refresh()
	if announce:
		changed.emit()

## Repaint from the live state. `Warband.changed` calls this, so an equip made
## anywhere else (a loot take, the band's arming, the rack) shows up here without
## reopening.
func refresh() -> void:
	if not _built:
		return
	if _corpse_active:
		refresh_corpse()
		return
	if _warband == null:
		_sync_hotbar()
		return
	if selected_merc <= 0 or not _can_dress(selected_merc):
		selected_merc = controlled_merc if _can_dress(controlled_merc) else _first_merc_id()
	_paint_mode()
	_paint_header()
	_refresh_slots()
	_refresh_preview()
	_refresh_stats()
	_sync_inventory()
	_sync_hotbar()
	_sync_skills_review()
	# The pool page is 142 rows of labels: it is built only while it is on show,
	# and only when the run's taken rows have moved.
	if page == PAGE_UPGRADES:
		_sync_upgrades()

## The pool this screen shows and dresses from: the field stash.
func _pool() -> WarbandStash:
	return _warband.field_stash()

func _pool_label() -> String:
	return str(_warband.field_label()) if _warband != null else "the shared stash"

## The pieces the live run has put on a body, one per armour slot. Read over the
## roster's own kit so a piece a chest handed out is on the page from the moment
## it lands, not only on the rig. Empty when no run owns the body.
func _run_pieces(merc_id: int = -1) -> Dictionary:
	if _corpse_active or not run_armour.is_valid():
		return {}
	var id := selected_merc if merc_id < 0 else merc_id
	if id <= 0:
		return {}
	var raw: Variant = run_armour.call(id)
	if not (raw is Dictionary):
		return {}
	return raw

## The pair the body's hands are holding, `{main, off}`, read over the wardrobe's
## own two hands. The page is a picture of the body: a hand the player fights with
## is the run's, and it is drawn from the body's kit, so the page names the same
## pieces the island carries. Empty when the roster's kit is what the body holds.
func _owned_hands(merc_id: int = -1) -> Dictionary:
	if _corpse_active or not hands_for.is_valid():
		return {}
	var id := selected_merc if merc_id < 0 else merc_id
	if id <= 0:
		return {}
	var raw: Variant = hands_for.call(id)
	if not (raw is Dictionary):
		return {}
	var hands: Dictionary = raw
	if not hands.has("main") and not hands.has("off"):
		return {}
	return hands

## The keys the run's upgrades have bought this body: 0 outside a run.
func _bar_bonus(merc_id: int = -1) -> int:
	if _corpse_active or not slot_bonus.is_valid():
		return 0
	var id := selected_merc if merc_id < 0 else merc_id
	if id <= 0:
		return 0
	var raw: Variant = slot_bonus.call(id)
	if not (raw is int) and not (raw is float):
		return 0
	return clampi(int(raw), 0, AbilityRules.MAX_SLOT_COUNT - AbilityRules.SLOT_COUNT)

## How many keys the bar on this page has: the five the game ships with plus the
## run's own.
func bar_keys() -> int:
	return AbilityRules.SLOT_COUNT + _bar_bonus()

## The kit's worth as the page displays it: a run piece replaces the wardrobe
## piece in that slot, so its price replaces that piece's price on the header -
## and a hand the run owns replaces the wardrobe's hand the same way.
func _kit_value(gear: Dictionary, run_pieces: Dictionary,
		hands: Dictionary = {}) -> int:
	var total := int(_warband.gear_value(selected_merc))
	for slot in ArmorData.SLOTS:
		var won: Dictionary = run_pieces.get(slot, {})
		if won.is_empty():
			continue
		var roster_id := str(gear.get(slot, ""))
		if not roster_id.is_empty():
			total -= StashScript.value_of(roster_id)
		total += StashScript.value_of(str(won.get("item_id", "")))
	for slot_id in ["main", "off"]:
		if not hands.has(slot_id):
			continue
		var roster_hand := str(gear.get(slot_id, ""))
		if not roster_hand.is_empty():
			total -= StashScript.value_of(roster_hand)
		var held := str(hands.get(slot_id, ""))
		if not held.is_empty():
			total += StashScript.value_of(held)
	return maxi(total, 0)

## The mercenaries this panel may dress.
func _dressable_ids() -> Array[int]:
	var none: Array[int] = []
	if _warband == null:
		return none
	return _warband.dressable_ids()

func _can_dress(merc_id: int) -> bool:
	return merc_id > 0 and _dressable_ids().has(merc_id)

func _first_merc_id() -> int:
	var ids: Array[int] = _dressable_ids()
	return ids[0] if not ids.is_empty() else -1

## Repaint the corpse half: the carried slots, the takeable list and the two lines
## that say what the body is still worth.
func refresh_corpse() -> void:
	if not _built or not _corpse_active:
		return
	if corpse_loot != null and is_instance_valid(corpse_loot) \
			and corpse_loot.has_method("corpse_items"):
		_corpse_ids = corpse_loot.corpse_items(corpse_id)
	_paint_mode()
	_paint_header()
	_sync_corpse_slots()
	_sync_corpse_rows()

func set_status(message: String) -> void:
	if _status != null:
		_status.text = message

func status_text() -> String:
	return _status.text if _status != null else ""

func _on_warband_changed() -> void:
	# A closed page is repainted by `open()`, and `Warband.changed` is a coarse
	# event - a pickup, a spare booked - that fires many times a second in a
	# fight. Repainting the whole sheet for a picture nobody is looking at is pure
	# frame cost.
	if not _open:
		return
	refresh()

func _detach_source() -> void:
	if _warband != null and is_instance_valid(_warband) and _warband.has_signal("changed") \
			and _warband.changed.is_connected(_on_warband_changed):
		_warband.changed.disconnect(_on_warband_changed)

# --- build -----------------------------------------------------------------

func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_shell = Control.new()
	_shell.name = "WarbandPaperdoll"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.theme = LedgerThemeScript.get_theme()
	add_child(_shell)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_shell_input)
	_shell.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Gear", "cuirass")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -SIZE.x * 0.5
	frame.offset_right = SIZE.x * 0.5
	frame.offset_top = -SIZE.y * 0.5
	frame.offset_bottom = SIZE.y * 0.5
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.body.add_child(column)

	# The page's own line: the body being dressed on the left, the purse-worth of
	# its kit on the right. The screen's name is the frame's rail; the tabs say
	# which page of it is up, so the body is what this line has to name.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	column.add_child(head)
	title_label = _label(head, "", 14, GOLD)
	_head_hint = _label(head, "", 12, MUTED)
	var spacer_head := Control.new()
	spacer_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer_head)
	_merc_label = _label(head, "", 12, TEAL)
	_merc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# The tabs: one press per page, and the page's content underneath.
	_tab_row = HBoxContainer.new()
	_tab_row.name = "Tabs"
	_tab_row.add_theme_constant_override("separation", 6)
	column.add_child(_tab_row)
	for page_id in PAGES:
		var button := Button.new()
		button.name = "Tab_%s" % page_id
		button.text = str(PAGE_LABELS[page_id])
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(132, 30)
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func() -> void: open_page(page_id))
		_tab_row.add_child(button)
		tabs[page_id] = button
	var tab_tail := Control.new()
	tab_tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.add_child(tab_tail)

	# One stack, one visible page. A Control (not a Container) so a page keeps the
	# measure it was built at: the frame decides the size of the screen, and no
	# page is allowed to grow past it.
	_page_stack = Control.new()
	_page_stack.name = "Pages"
	_page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_stack.clip_contents = true
	column.add_child(_page_stack)
	for page_id in PAGES:
		var page_root := Control.new()
		page_root.name = "Page_%s" % page_id
		page_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page_stack.add_child(page_root)
		_pages[page_id] = page_root
	_build_gear_page(_pages[PAGE_GEAR])
	_build_inventory_page(_pages[PAGE_INVENTORY])
	_build_skills_page(_pages[PAGE_SKILLS])
	_build_upgrades_page(_pages[PAGE_UPGRADES])

	_status = _label(column, "", 12, TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The status line is the only part of the column whose height a message
	# decides, and the page has no room for a third line: a long answer would push
	# the content off the bottom of the vellum. Two lines are what the instruction
	# needs, so two lines are what the page keeps for it.
	_status.max_lines_visible = 2

	_build_overlays()

## The gear page: worn rows on the left, the portrait in the middle, the numbers
## (or a dead body's pockets) on the right.
func _build_gear_page(root: Control) -> void:
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", int(GUTTER))
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	left.custom_minimum_size = Vector2(WORN_WIDTH, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_worn_title = _label(left, "WORN GEAR", 10, MUTED)
	for slot in Contracts.SLOT_ORDER:
		slot_rows[Contracts.slot_id(slot)] = _make_slot_row(left, slot)

	var centre := VBoxContainer.new()
	centre.add_theme_constant_override("separation", 6)
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.alignment = BoxContainer.ALIGNMENT_BEGIN
	body.add_child(centre)
	_stage = NinePatchRect.new()
	_stage.name = "Stage"
	_stage.texture = load(LedgerThemeScript.DIR + "plate_iron_idle.png")
	_stage.patch_margin_left = 20
	_stage.patch_margin_right = 20
	_stage.patch_margin_top = 12
	_stage.patch_margin_bottom = 12
	_stage.custom_minimum_size = Vector2(PORTRAIT_WIDTH, PORTRAIT_HEIGHT)
	_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	centre.add_child(_stage)
	preview = CharacterPreview.new()
	preview.name = "Preview"
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 6
	preview.offset_top = 6
	preview.offset_right = -6
	preview.offset_bottom = -6
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.built.connect(_refresh_preview)
	_stage.add_child(preview)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.custom_minimum_size = Vector2(300, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_stats_box = VBoxContainer.new()
	_stats_box.name = "Stats"
	_stats_box.add_theme_constant_override("separation", 3)
	_stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_stats_box)
	_label(_stats_box, "CHARACTER", 10, MUTED)
	for key in ["health", "stamina", "head_guard", "body_guard", "main_hand"]:
		_stat_row(_stats_box, key, str({
			"health": "HEALTH", "stamina": "STAMINA", "head_guard": "HEAD GUARD",
			"body_guard": "BODY GUARD", "main_hand": "MAIN HAND",
		}[key]))
	_stat_row(_stats_box, "worth", "KIT WORTH")
	# The medicine is the band's, counted where the body's own numbers are: it is
	# the one stock the player spends on this body, and the gear page is where a
	# body is read.
	var rule := ColorRect.new()
	rule.color = Color("4a4232")
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_box.add_child(rule)
	_medicine_box = VBoxContainer.new()
	_medicine_box.name = "Medicine"
	_medicine_box.add_theme_constant_override("separation", 3)
	_stats_box.add_child(_medicine_box)
	_label(_medicine_box, "MEDICINE", 10, MUTED)
	for kind in ["potion", "bandage"]:
		_medicine_row(_medicine_box, kind)

	# The corpse page: the same two columns, with the dead body's pockets in the
	# place the body's numbers were.
	_corpse_box = VBoxContainer.new()
	_corpse_box.name = "Corpse"
	_corpse_box.add_theme_constant_override("separation", 4)
	_corpse_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_corpse_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_corpse_box.visible = false
	right.add_child(_corpse_box)
	_corpse_rows_box = VBoxContainer.new()
	_corpse_rows_box.add_theme_constant_override("separation", 4)
	_corpse_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_corpse_box.add_child(_corpse_rows_box)
	_corpse_empty = _label(_corpse_box, "Nothing left on the body.", 13, MUTED)
	_take_all_button = Button.new()
	_take_all_button.text = "TAKE ALL"
	_take_all_button.focus_mode = Control.FOCUS_NONE
	_take_all_button.custom_minimum_size = Vector2(0, 32)
	_take_all_button.pressed.connect(take_all)
	_corpse_box.add_child(_take_all_button)

func _build_inventory_page(root: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)
	_inventory_head = _label(column, "THE SHARED STASH", 10, MUTED)
	_inventory_empty = _label(column,
		"Nothing in the stash. The town hands over no spares: a run is where "
		+ "pieces are gathered.", 13, MUTED)
	_inventory_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.name = "Grid"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_inventory_grid = GridContainer.new()
	_inventory_grid.name = "Tiles"
	_inventory_grid.add_theme_constant_override("h_separation", TILE_GAP)
	_inventory_grid.add_theme_constant_override("v_separation", TILE_GAP)
	_inventory_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(_inventory_grid)
	# The grid's column count comes from the page's own width, so a wider window
	# draws more per row instead of a single line that runs off the vellum.
	scroll.resized.connect(_fit_inventory_columns)

func _build_skills_page(root: Control) -> void:
	var body := HBoxContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", int(GUTTER))
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(360, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_skills_head = _label(left, "THE BAR", 10, MUTED)
	_skills_row = HBoxContainer.new()
	_skills_row.name = "Keys"
	_skills_row.add_theme_constant_override("separation", SKILL_GAP)
	left.add_child(_skills_row)
	hotbar_tiles.clear()
	hotbar_buttons.clear()
	for index in AbilityRules.MAX_SLOT_COUNT:
		var button := Button.new()
		button.name = "Key%d" % (index + 1)
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.custom_minimum_size = Vector2(SKILL_TILE, SKILL_TILE)
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_skill_slot_pressed.bind(index))
		button.visible = index < AbilityRules.SLOT_COUNT
		_skills_row.add_child(button)
		var tile = AbilitySlotScript.new()
		tile.name = "Skill"
		tile.configure(index, SKILL_TILE)
		button.add_child(tile)
		hotbar_buttons.append(button)
		hotbar_tiles.append(tile)
	_skills_hint = _label(left, "", 12, MUTED)
	_skills_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skills_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	# One scroll for both lists: the skills the player owns and the upgrades the
	# run has taken read as one column, so a short book does not leave a hole
	# between two half-empty half-pages.
	var review := ScrollContainer.new()
	review.name = "Review"
	review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(review)
	var review_column := VBoxContainer.new()
	review_column.add_theme_constant_override("separation", 4)
	review_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review.add_child(review_column)
	_book_head = _label(review_column, "UNLOCKED SKILLS", 10, MUTED)
	_book_box = VBoxContainer.new()
	_book_box.add_theme_constant_override("separation", 4)
	_book_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_column.add_child(_book_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	review_column.add_child(gap)
	_upgrade_head = _label(review_column, "UPGRADES THIS RUN", 10, MUTED)
	_upgrade_box = VBoxContainer.new()
	_upgrade_box.add_theme_constant_override("separation", 4)
	_upgrade_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_column.add_child(_upgrade_box)

## The upgrades page: the pool a chest, the stall or a boss pays from, family by
## family, with the words each row carries and the stacks this run has taken of
## it. A catalogue, not a live sheet: nothing here is clickable.
func _build_upgrades_page(root: Control) -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 6)
	root.add_child(column)
	_pool_head = _label(column, "THE UPGRADE POOL", 10, MUTED)
	_pool_hint = _label(column,
		"Every row the chests, the stall and the bosses can pay - the whole pool, "
		+ "with the words it writes for itself. What this run has taken is marked "
		+ "TAKEN; a row the game cannot offer yet is not listed.", 12, MUTED)
	_pool_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pool_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.name = "Pool"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_pool_box = VBoxContainer.new()
	_pool_box.add_theme_constant_override("separation", 3)
	_pool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pool_box)

## Repaint the pool list. Rebuilt only when the run's taken rows change: 142 rows
## of labels are a page's content, not a per-frame cost, and the page is only
## built while it is the one on show.
func _sync_upgrades() -> void:
	if _pool_box == null:
		return
	var taken: Dictionary = {}
	if run_upgrades.is_valid() and selected_merc > 0:
		var raw: Variant = run_upgrades.call(selected_merc)
		if raw is Array:
			for entry in raw:
				var row: Dictionary = entry
				taken[str(row.get("id", ""))] = int(row.get("stacks", 1))
	var signature := "%d|%s" % [selected_merc, str(taken)]
	if signature == _pool_sig:
		return
	_pool_sig = signature
	_clear_children(_pool_box)
	var live := 0
	for row in Mods.all():
		if Mods.ready_of(str(row.get("id", ""))):
			live += 1
	_pool_head.text = "THE UPGRADE POOL  ·  %d LIVE ROWS" % live
	if not taken.is_empty():
		_pool_head.text += "  ·  %d TAKEN THIS RUN" % taken.size()
	for family in Mods.FAMILIES:
		var rows: Array = []
		for row in Mods.all():
			var id := str(row.get("id", ""))
			if str(row.get("family", "")) != family:
				continue
			if not Mods.ready_of(id):
				continue
			rows.append(row)
		if rows.is_empty():
			continue
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var left := Mods.RARITIES.find(str(a.get("rarity", "")))
			var right := Mods.RARITIES.find(str(b.get("rarity", "")))
			if left != right:
				return left < right
			return str(Mods.name_of(str(a.get("id", "")))).to_lower() \
				< str(Mods.name_of(str(b.get("id", "")))).to_lower())
		_pool_group(_pool_box, str(Mods.FAMILY_LABEL.get(family, family)), rows.size())
		for row in rows:
			var id := str(row.get("id", ""))
			var rarity := str(row.get("rarity", ""))
			var line := "%s  ·  %s  ·  UP TO ×%d" % [Mods.name_of(id),
				rarity.to_upper(), Mods.max_stacks(id)]
			if taken.has(id):
				line += "  ·  TAKEN ×%d" % int(taken[id])
			_review_row(_pool_box, line, str(row.get("description", "")))

## One family heading on the pool page: the family's name, a rule and how many
## rows the family offers.
func _pool_group(parent: Node, text: String, count: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	_label(row, "%s  ·  %d ROWS" % [text, count], 11, GOLD)
	var rule := ColorRect.new()
	rule.color = Color("4a4232")
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rule)

## The three overlays above the pages: the hover card, the slot's alternatives and
## the piece's own menu. They live on their own control so a page's layout can
## never clip them, and each is clipped to the window instead of growing.
func _build_overlays() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlays"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shell.add_child(_overlay)

	_hover_card = ItemCard.new()
	_hover_card.name = "Hover"
	_hover_card.visible = false
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_hover_card)

	_menu_box = PanelContainer.new()
	_menu_box.name = "Menu"
	_menu_box.visible = false
	_menu_box.add_theme_stylebox_override("panel", _menu_style())
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 4)
	_menu_box.add_child(menu_column)
	_menu_title = _label(menu_column, "", 12, GOLD)
	_menu_note = _label(menu_column, "", 11, MUTED)
	# One clipped line, not a wrapped one: an autowrapped Label reports the height
	# of a column one word wide before it has been laid out at its final width,
	# which is what once made this menu a 900 px panel with three rows in it.
	_menu_note.clip_text = true
	_menu_note.custom_minimum_size = Vector2(MENU_WIDTH - 16.0, 0)
	_menu_note.visible = false
	_menu_scroll = ScrollContainer.new()
	_menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_menu_scroll.custom_minimum_size = Vector2(MENU_WIDTH - 16.0, 0)
	menu_column.add_child(_menu_scroll)
	_menu_rows = VBoxContainer.new()
	_menu_rows.add_theme_constant_override("separation", 3)
	_menu_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_scroll.add_child(_menu_rows)
	_overlay.add_child(_menu_box)

	_sell_box = PanelContainer.new()
	_sell_box.name = "SellMenu"
	_sell_box.visible = false
	_sell_box.add_theme_stylebox_override("panel", _menu_style())
	var sell_column := VBoxContainer.new()
	sell_column.add_theme_constant_override("separation", 4)
	_sell_box.add_child(sell_column)
	_sell_title = _label(sell_column, "", 12, GOLD)
	_sell_button = Button.new()
	_sell_button.focus_mode = Control.FOCUS_NONE
	_sell_button.custom_minimum_size = Vector2(220, 30)
	_sell_button.add_theme_font_size_override("font_size", 13)
	_sell_button.pressed.connect(_on_sell_pressed)
	sell_column.add_child(_sell_button)
	_overlay.add_child(_sell_box)

func _menu_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.043, 0.032, 0.99)
	style.border_color = Color("7c6a45")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 12
	return style

# --- gear: the worn rows ----------------------------------------------------

func _make_slot_row(parent: Node, slot: int) -> Dictionary:
	var button := Button.new()
	button.name = "Slot_%s" % Contracts.slot_id(slot)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(WORN_WIDTH, 34)
	button.add_theme_font_size_override("font_size", 13)
	button.icon = LedgerThemeScript.icon_small(str(SLOT_ICON.get(Contracts.slot_id(slot), "blade")))
	button.add_theme_constant_override("icon_max_width", 24)
	button.pressed.connect(func() -> void: _on_slot_pressed(Contracts.slot_id(slot)))
	button.gui_input.connect(func(event: InputEvent) -> void:
		_on_slot_input(event, Contracts.slot_id(slot)))
	button.mouse_entered.connect(func() -> void: _hover_slot(Contracts.slot_id(slot)))
	button.mouse_exited.connect(hide_hover)
	parent.add_child(button)
	return {"slot": slot, "id": Contracts.slot_id(slot), "button": button,
		"item_id": "", "run_piece": {}, "hand": false}

func _refresh_slots() -> void:
	if selected_merc <= 0:
		for slot in Contracts.SLOT_ORDER:
			var bare: Dictionary = slot_rows[Contracts.slot_id(slot)]
			bare["item_id"] = ""
			bare["run_piece"] = {}
			bare["hand"] = false
			_apply_slot_row(bare, slot, "")
		return
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var run_pieces := _run_pieces()
	var hands := _owned_hands()
	for slot in Contracts.SLOT_ORDER:
		var row: Dictionary = slot_rows[Contracts.slot_id(slot)]
		var slot_id := str(row["id"])
		var won: Dictionary = run_pieces.get(slot_id, {})
		var worn := str(won.get("item_id", "")) if not won.is_empty() \
			else str(gear.get(slot_id, ""))
		var owned := hands.has(slot_id)
		if owned:
			worn = str(hands.get(slot_id, ""))
		row["item_id"] = worn
		row["run_piece"] = won
		row["hand"] = owned
		_apply_slot_row(row, slot, worn, won)

func _apply_slot_row(row: Dictionary, slot: int, worn: String,
		run_piece: Dictionary = {}) -> void:
	var button: Button = row["button"]
	var color := BONE if not worn.is_empty() else BONE_DIM
	var text := "%s  /  %s" % [Contracts.slot_label(slot), _item_name(worn)]
	if bool(row.get("hand", false)) or not run_piece.is_empty():
		text += "  ·  RUN"
	if button.text != text:
		button.text = text
	if row.get("text_color", Color.TRANSPARENT) != color:
		row["text_color"] = color
		button.add_theme_color_override("font_color", color)

## The alternatives the warband owns for one slot, in value order: every piece it
## has a free copy of that fits the slot, plus the copy already worn there, so a
## click on "Head" is a list of the heads it owns. A piece another body is wearing
## is not offered: moving it would strip that body, and the page is one body's.
func slot_alternatives(slot_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _corpse_active or _warband == null or selected_merc <= 0:
		return out
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var hands := _owned_hands()
	if slot_id in ["main", "off"] and not hands.is_empty():
		return out
	var worn := str(gear.get(slot_id, ""))
	for row in _pool().rows(_warband.roster):
		var item_id := str(row.get("item_id", ""))
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or not Rules.allowed(item, slot_id):
			continue
		if int(_pool().pooled_count(item_id)) <= 0 and item_id != worn:
			continue
		out.append({"item_id": item_id, "name": str(row.get("name", item_id)),
			"value": int(row.get("value", 0)), "worn": item_id == worn,
			"total": int(row.get("total", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["worn"]) != bool(b["worn"]):
			return bool(a["worn"])
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out

## Put one owned piece in one worn slot. The roster owns the displacement rules -
## a two-hander clears the off hand, an off-hand piece clears a two-hander - and
## this is the only path the screen uses to change a slot: nothing is unequipped.
func equip_slot(slot_id: String, item_id: String) -> Dictionary:
	if _corpse_active or _warband == null or selected_merc <= 0:
		return {"ok": false, "message": "Choose a body first."}
	var result: Dictionary = _warband.equip_merc(selected_merc, slot_id, item_id)
	set_status(str(result.get("message", "")))
	close_menu()
	refresh()
	if bool(result.get("ok", false)):
		changed.emit()
	return result

func _on_slot_pressed(slot_id: String) -> void:
	# On a corpse the worn rows are the body's kit, so a press is a take rather
	# than an equip: there is no mercenary whose slot it could be.
	if _corpse_active:
		var carried := str(slot_rows.get(slot_id, {}).get("item_id", ""))
		if carried.is_empty():
			set_status("That slot is empty.")
			return
		take_piece(carried)
		return
	if _warband == null or selected_merc <= 0:
		set_status("Choose a body first.")
		return
	open_slot_menu(slot_id)

## Open the alternatives for one slot at the pointer. A slot the run owns says so
## instead of offering a change the island would overwrite.
func open_slot_menu(slot_id: String) -> void:
	var row: Dictionary = slot_rows.get(slot_id, {})
	var won: Variant = row.get("run_piece", {})
	if won is Dictionary and not (won as Dictionary).is_empty():
		set_status(RUN_PIECE_MESSAGE)
		return
	if bool(row.get("hand", false)):
		set_status(RUN_HANDS_MESSAGE)
		return
	var rows := slot_alternatives(slot_id)
	close_menu()
	_clear_children(_menu_rows)
	_menu_title.text = "THE %s YOU OWN" % Contracts.slot_id_label(slot_id).to_upper()
	for alt in rows:
		var item_id := str(alt["item_id"])
		var button := _menu_row_button(item_id, str(alt["name"]),
			"WORN" if bool(alt["worn"]) else "%d G" % int(alt["value"]))
		button.pressed.connect(func() -> void: equip_slot(slot_id, item_id))
	if rows.is_empty():
		_menu_note.text = "You own nothing that fits this slot."
	else:
		_menu_note.text = "Click a piece to wear it. Nothing here takes one off."
	_menu_note.visible = true
	_show_menu_at_pointer()

func _on_slot_input(event: InputEvent, slot_id: String) -> void:
	if _corpse_active:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		open_sell_menu(slot_id, "")

# --- gear: selling ----------------------------------------------------------

## The piece's own menu: a right-click on a worn slot or an inventory tile. The
## one action is SELL - a worn copy is taken off the body first, so the screen
## never sells a piece it is still showing as worn.
func open_sell_menu(slot_id: String, item_id: String) -> void:
	if _corpse_active:
		return
	close_menu()
	hide_hover()
	_sell_slot = slot_id
	_sell_item = item_id
	if _sell_item.is_empty():
		_sell_item = str(slot_rows.get(slot_id, {}).get("item_id", ""))
	if _sell_item.is_empty():
		set_status("That slot is empty.")
		return
	var item: Dictionary = State.ITEMS.get(_sell_item, {})
	var worth := int(floor(float(item.get("price", 0)) * 0.6))
	_sell_box.visible = true
	_sell_title.text = str(item.get("name", _sell_item)).to_upper()
	_sell_button.text = "SELL  ·  %d G" % worth
	_sell_button.disabled = worth <= 0
	_place_at_pointer(_sell_box)

## Sell the piece the open menu names: the spare out of the pool, or the worn copy
## off the body and then the copy it just handed back.
func sell_piece(slot_id: String, item_id: String) -> Dictionary:
	if _corpse_active or _warband == null:
		return {"ok": false, "message": "Nothing to sell."}
	if item_id.is_empty():
		return {"ok": false, "message": "That slot is empty."}
	if selected_merc <= 0:
		return {"ok": false, "message": "Choose a body first."}
	if not slot_id.is_empty():
		var row: Dictionary = slot_rows.get(slot_id, {})
		var won: Variant = row.get("run_piece", {})
		var run_owned := (won is Dictionary and not (won as Dictionary).is_empty()) \
			or bool(row.get("hand", false))
		if run_owned:
			return {"ok": false, "message": "That piece is the run's own: it cannot be sold here."}
		if str(row.get("item_id", "")) == item_id:
			var returned: String = _warband.unequip_merc(selected_merc, slot_id)
			if returned.is_empty():
				return {"ok": false, "message": "That piece will not come off right now."}
	var result: Dictionary = _warband.sell_gear(item_id)
	set_status(str(result.get("message", "")))
	if _sell_box != null:
		_sell_box.visible = false
	refresh()
	if bool(result.get("ok", false)):
		changed.emit()
	return result

func _on_sell_pressed() -> void:
	sell_piece(_sell_slot, _sell_item)

# --- gear: the portrait and the numbers -------------------------------------

## Dress the stage: the body the page is showing, in the kit it is wearing. The
## run's own armour and hands are read over the wardrobe so the picture is the
## body the island carries, not only what the wardrobe remembers.
func _refresh_preview() -> void:
	if preview == null:
		return
	if _corpse_active or _warband == null or selected_merc <= 0 \
			or not _warband.roster.has(selected_merc):
		preview.set_active(false)
		return
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var armor := {}
	var run_pieces := _run_pieces()
	for slot in ArmorData.SLOTS:
		var won: Dictionary = run_pieces.get(slot, {})
		armor[slot] = int(won.get("set", ArmorData.NONE)) if not won.is_empty() \
			else ArmorData.set_of_item(str(gear.get(slot, "")))
	var worn := {"off": str(gear.get("off", ""))}
	var hands := _owned_hands()
	var main_id := str(gear.get("main", ""))
	var off_id := str(gear.get("off", ""))
	if not hands.is_empty():
		main_id = str(hands.get("main", ""))
		off_id = ""
		worn["off"] = ""
	var loadout := State.build_loadout(main_id, off_id, armor, worn)
	preview.set_appearance(Looks.profile_for(selected_merc))
	preview.apply_kit(loadout)
	# Dressed on every repaint, open or shut, but only an open screen renders and
	# poses its stage.
	preview.set_active(_open and page == PAGE_GEAR)

## Repaint the body's numbers: the pools it fights with, the guard its kit adds,
## and what the main hand lands.
func _refresh_stats() -> void:
	if selected_merc <= 0 or _warband == null:
		for key in _stat_values:
			(_stat_values[key] as Label).text = "—"
		for kind in _medicine_values:
			(_medicine_values[kind] as Label).text = "0"
		return
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var run_pieces := _run_pieces()
	var hands := _owned_hands()
	var health := int(round(_warband.roster.max_health_of(selected_merc)))
	if health <= 0:
		health = int(round(Contracts.BASE_MAX_HEALTH))
	_set_stat("health", str(health))
	_set_stat("stamina", str(int(round(Stamina.MAX))))
	var head_guard := 0.0
	var body_guard := 0.0
	for slot in ArmorData.SLOTS:
		var won: Dictionary = run_pieces.get(slot, {})
		var set_index := int(won.get("set", ArmorData.NONE)) if not won.is_empty() \
			else ArmorData.set_of_item(str(gear.get(slot, "")))
		var piece := ArmorData.reduction_for(set_index, str(slot))
		if str(slot) == "head":
			head_guard += piece
		else:
			body_guard += piece
	_set_stat("head_guard", "%d%%" % int(round(head_guard * 100.0)))
	_set_stat("body_guard", "%d%%" % int(round(body_guard * 100.0)))
	var main_id := str(gear.get("main", ""))
	if not hands.is_empty():
		main_id = str(hands.get("main", ""))
	_set_stat("main_hand", _weapon_line(main_id))
	_set_stat("worth", "%d G" % _kit_value(gear, run_pieces, hands))
	for kind in ["potion", "bandage"]:
		var label: Label = _medicine_values.get(kind)
		if label != null:
			label.text = "×%d" % int(_warband.supply_count(str(kind)))

## What one held piece lands, from the rig's own weapon tables - the same numbers
## the swing reads, so the sheet cannot promise a blow the hand does not land.
func _weapon_line(item_id: String) -> String:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return "empty"
	var kind := str(item.get("kind", ""))
	var index := int(item.get("index", 0))
	match kind:
		"sword":
			var row: Dictionary = Archer.SWORD_DATA[clampi(index, 0, Archer.SWORD_DATA.size() - 1)]
			return "%d dmg  ·  %.1f m  ·  %.1f s" % [
				int(row.get("damage", 0)), float(row.get("reach", 0.0)),
				float(row.get("seconds", 0.0))]
		"dagger":
			var row: Dictionary = Archer.DAGGER_DATA[clampi(index, 0, Archer.DAGGER_DATA.size() - 1)]
			return "%d dmg  ·  %.1f m  ·  %.2f s" % [
				int(row.get("damage", 0)), float(row.get("reach", 0.0)),
				float(row.get("seconds", 0.0))]
		"staff":
			var row: Dictionary = Archer.STAFF_DATA[clampi(index, 0, Archer.STAFF_DATA.size() - 1)]
			return "%d dmg  ·  %.1f s" % [int(row.get("damage", 0)),
				float(row.get("seconds", 0.0))]
		"bow":
			var row: Dictionary = Archer.BOW_DATA[clampi(index, 0, Archer.BOW_DATA.size() - 1)]
			return "%.1f s draw  ·  %d m/s" % [float(row.get("draw_seconds", 0.0)),
				int(row.get("speed", 0))]
		"shield", "focus":
			return "off hand"
	return str(item.get("name", item_id))

func _stat_row(parent: Node, key: String, text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var name := _label(row, text, 11, MUTED)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, "—", 12, CREAM)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stat_values[key] = value
	return value

func _set_stat(key: String, text: String) -> void:
	var label: Label = _stat_values.get(key)
	if label != null and label.text != text:
		label.text = text

## One medicine row: the key's own icon, the name, and the count the band carries.
func _medicine_row(parent: Node, kind: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = AbilityRules.icon_texture("bandage" if kind == "bandage" else "healing_potion")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(22, 22)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name := _label(row, ("BANDAGES  ·  Z" if kind == "bandage" else "POTIONS  ·  V"), 11, MUTED)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, "×0", 12, CREAM)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_medicine_values[kind] = value

# --- inventory --------------------------------------------------------------

## The stash as a grid of the catalogue's rendered icons: one tile per kind, the
## count bottom-right, the piece's own card on hover and its menu on right click.
func _sync_inventory() -> void:
	var seen: Dictionary = {}
	inventory_rows.clear()
	if _warband != null:
		for row in _pool().rows(_warband.roster):
			var item_id := str(row.get("item_id", ""))
			var count := int(_pool().pooled_count(item_id))
			if count <= 0:
				continue
			seen[item_id] = true
			var tile: Dictionary = _inventory_tiles.get(item_id, {})
			var button: Button = tile.get("button")
			if button == null:
				var made: Array = _make_inventory_tile(item_id)
				tile = {"button": made[0], "count": made[1]}
				_inventory_tiles[item_id] = tile
				button = tile["button"]
			if button.get_index() != inventory_rows.size():
				_inventory_grid.move_child(button, inventory_rows.size())
			_apply_inventory_tile(tile, count)
			inventory_rows.append({"item_id": item_id,
				"name": str(row.get("name", item_id)), "count": count,
				"value": int(row.get("value", 0)), "button": button})
	for item_id in _inventory_tiles.keys():
		if seen.has(str(item_id)):
			continue
		var stale: Button = _inventory_tiles[item_id]["button"]
		_inventory_grid.remove_child(stale)
		stale.queue_free()
		_inventory_tiles.erase(item_id)
	if _inventory_empty != null:
		_inventory_empty.visible = inventory_rows.is_empty()
	var kinds := inventory_rows.size()
	if kinds > 0:
		_inventory_head.text = "THE SHARED STASH  ·  %d KIND%s" % [
			kinds, "" if kinds == 1 else "S"]
	else:
		_inventory_head.text = "THE SHARED STASH"
	_fit_inventory_columns()

## One grid tile: the catalogue's own render of the piece drawn edge to edge over
## the plate, a count badge in the corner, the piece's card on hover and its menu
## on a right-click. Answers `[button, badge]`.
func _make_inventory_tile(item_id: String) -> Array:
	var button := Button.new()
	button.name = "Item_%s" % item_id
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(TILE, TILE)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void: _on_inventory_pressed(item_id))
	button.gui_input.connect(func(event: InputEvent) -> void:
		_on_inventory_input(event, item_id))
	button.mouse_entered.connect(func() -> void: _hover_item(item_id,
		"Right-click for the piece's menu."))
	button.mouse_exited.connect(hide_hover)
	# The render fills the tile: a Button's own `icon` is inset by the theme's
	# padding, which drew every piece as a thumbnail inside its own frame.
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _item_icon(item_id)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 7
	icon.offset_top = 7
	icon.offset_right = -7
	icon.offset_bottom = -7
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	if icon.texture == null:
		# Not every carried piece has a render (a pelt, an arrow, a vial): the
		# tile says what it is instead of drawing an empty plate.
		var tag := Label.new()
		tag.text = str((State.ITEMS.get(item_id, {}) as Dictionary)
			.get("short", item_id)).to_upper()
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", BONE_DIM)
		tag.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tag.offset_left = 4
		tag.offset_right = -4
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(tag)
	var count := Label.new()
	count.name = "Count"
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", BONE)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count.offset_right = -4
	count.offset_bottom = -2
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(count)
	_inventory_grid.add_child(button)
	return [button, count]

func _apply_inventory_tile(tile: Dictionary, count: int) -> void:
	var badge: Label = tile["count"]
	if badge != null:
		badge.text = "×%d" % count if count > 1 else ""

func _on_inventory_pressed(item_id: String) -> void:
	# A left-click on a tile is the piece's own menu: the inventory is a shelf to
	# sell from, not a second place to dress a body (the body's slots are).
	open_sell_menu("", item_id)

func _on_inventory_input(event: InputEvent, item_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		open_sell_menu("", item_id)

## Column count from the page's own width, so a wide window draws a wide grid and
## a narrow one keeps every tile inside the frame.
func _fit_inventory_columns() -> void:
	if _inventory_grid == null:
		return
	var width := _page_stack.size.x if _page_stack != null else PAGE_WIDTH
	width = maxf(width, TILE + TILE_GAP)
	var columns := maxi(1, int(floor((width + TILE_GAP) / (TILE + TILE_GAP))))
	if _inventory_grid.columns != columns:
		_inventory_grid.columns = columns

func _item_icon(item_id: String) -> Texture2D:
	if _icon_cache.has(item_id):
		return _icon_cache[item_id]
	var path := "res://assets/ui/items/%s.png" % item_id
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_icon_cache[item_id] = texture
	return texture

# --- skills -----------------------------------------------------------------

## Repaint the bar from the body's own row. The roster's layout is the five keys
## the record holds; a live run's extra keys are drawn empty here and are the
## placeholders an upgrade bought, so the player can see what the session paid
## for before a skill is put on it.
func _sync_hotbar() -> void:
	if hotbar_tiles.is_empty():
		return
	hotbar_ids.clear()
	var layout: Array = []
	if _warband != null and selected_merc > 0 and not _corpse_active:
		layout = _warband.hotbar_layout(selected_merc)
	var keys := bar_keys() if not _corpse_active else AbilityRules.SLOT_COUNT
	var bonus := _bar_bonus()
	for index in hotbar_tiles.size():
		var shown := index < keys
		var id := str(layout[index]) if index < layout.size() else ""
		if shown:
			# The row is exactly as long as the bar: the keys past it are frames
			# the page owns, not assignments.
			hotbar_ids.append(id)
		hotbar_tiles[index].update_state({} if id.is_empty() else {"id": id})
		var button: Button = hotbar_buttons[index]
		button.visible = shown
		var definition := AbilityRules.by_id(id)
		var tooltip := "Key %d" % (index + 1)
		if definition.is_empty():
			tooltip += " - empty. Click to put an unlocked skill on it."
		else:
			tooltip += " - %s\n%s" % [str(definition.get("name", "")).capitalize(),
				str(definition.get("description", ""))]
		button.tooltip_text = tooltip
		button.modulate = Color(1.6, 1.4, 1.0) if index == _skill_slot_selected \
			else Color.WHITE
	if _skills_head != null:
		var head := "THE BAR  ·  %d KEYS" % keys
		if bonus > 0:
			head += "  ·  %d FROM THIS RUN'S UPGRADES" % bonus
		_skills_head.text = head
	if _skills_hint != null:
		var body_name := ""
		if _warband != null and selected_merc > 0:
			body_name = str(_warband.roster.name_of(selected_merc))
		_skills_hint.text = ("Click a key to put one of %s's unlocked skills on it. "
			% body_name if not body_name.is_empty() else "Click a key to put an unlocked skill on it. ") \
			+ "The family starters its hands earn fill the first free keys and are not assignable. " \
			+ "Medicine is not on the bar: bandage is Z, potion is V."

## One press on a key: the picker of the player's unlocked skills, pointed at that
## key. A key that already holds a skill offers to empty it.
func _on_skill_slot_pressed(index: int) -> void:
	if _corpse_active or _warband == null or selected_merc <= 0:
		set_status("Choose a body first.")
		return
	if index < 0 or index >= bar_keys():
		return
	_skill_slot_selected = index
	_sync_hotbar()
	open_skill_menu(index)

## The picker for one key: every unlocked skill whose family fits the hands, the
## one already on the key marked, and a row to empty it.
func open_skill_menu(index: int) -> void:
	# The menu is reset, not closed: the key the player picked is what the picker
	# is for, and `close_menu` would drop the selection it was opened with.
	_menu_box.visible = false
	_sell_box.visible = false
	hide_hover()
	_clear_children(_menu_rows)
	_menu_title.text = "KEY %d  ·  PUT A SKILL ON IT" % (index + 1)
	_menu_note.visible = true
	var current := str(hotbar_ids[index]) if index < hotbar_ids.size() else ""
	var book: Array = _warband.ability_book(selected_merc)
	var any := false
	for entry in book:
		if bool(entry.get("automatic", false)):
			continue
		if not bool(entry.get("unlocked", false)):
			continue
		var id := str(entry.get("id", ""))
		var fits := bool(entry.get("fits", false))
		var label := str(entry.get("name", id)).capitalize()
		var note := ("ON THIS KEY" if id == current else
			("" if fits else "NEEDS A %s" % str(entry.get("type", "")).to_upper()))
		var button := _menu_row_button("", label, note)
		button.disabled = not fits and id != current
		button.pressed.connect(func() -> void: assign_skill(index, id))
		any = true
	if not current.is_empty():
		var clear := _menu_row_button("", "EMPTY THIS KEY", "")
		clear.pressed.connect(func() -> void: assign_skill(index, ""))
		any = true
	_menu_note.text = "The five keys hold what you assign and the family starters." \
		if any else "You have unlocked no skills that fit these hands."
	_show_menu_at_pointer()

## Assign one skill to one key through the warband, and repaint. `""` empties it.
func assign_skill(index: int, ability_id: String) -> Dictionary:
	if _corpse_active or _warband == null or selected_merc <= 0:
		return {"ok": false, "message": "Choose a body first."}
	var result: Dictionary = _warband.set_hotbar_slot(selected_merc, index, ability_id)
	set_status(str(result.get("message", "")))
	close_menu()
	refresh()
	if bool(result.get("ok", false)):
		changed.emit()
	return result

## The review half of the page: the skills the player owns with the catalogue's
## words for them, then the upgrades the run has taken.
func _sync_skills_review() -> void:
	if _book_box == null or _warband == null or selected_merc <= 0:
		return
	_clear_children(_book_box)
	_clear_children(_upgrade_box)
	var book: Array = _warband.ability_book(selected_merc)
	var unlocked := 0
	for entry in book:
		if bool(entry.get("automatic", false)):
			continue
		if not bool(entry.get("unlocked", false)):
			continue
		unlocked += 1
		var kinds: Variant = entry.get("types", [])
		var family := AbilityRules.family_labels(kinds if kinds is Array \
			else [str(entry.get("type", "any"))])
		var name := str(entry.get("name", entry.get("id", ""))).capitalize()
		var line := "%s  ·  %s" % [name, family]
		if not bool(entry.get("fits", false)):
			line += "  ·  NEEDS A %s" % str(entry.get("type", "")).to_upper()
		_review_row(_book_box, line, str(entry.get("description", "")))
	if unlocked == 0:
		_review_row(_book_box, "No skills unlocked yet.",
			"An ABILITY chest stands three skills and keeps one.")
	_book_head.text = "UNLOCKED SKILLS  ·  %d" % unlocked
	var upgrades: Array = []
	if run_upgrades.is_valid() and selected_merc > 0:
		var raw: Variant = run_upgrades.call(selected_merc)
		if raw is Array:
			upgrades = raw
	if upgrades.is_empty():
		_review_row(_upgrade_box, "No run is live on this body.",
			"Upgrades are the run's own: a chest's card, or the stall's.")
		_upgrade_head.text = "UPGRADES THIS RUN"
		return
	var total := 0
	for upgrade in upgrades:
		var row: Dictionary = upgrade
		var id := str(row.get("id", ""))
		var definition: Dictionary = Mods.get_mod(id)
		var stacks := int(row.get("stacks", 1))
		total += stacks
		var name := str(definition.get("name", row.get("name", id)))
		var line := "%s  ·  ×%d" % [name, stacks]
		var rarity := str(definition.get("rarity", row.get("rarity", "")))
		if not rarity.is_empty():
			line += "  ·  " + rarity.to_upper()
		_review_row(_upgrade_box, line, str(definition.get("description", "")))
	_upgrade_head.text = "UPGRADES THIS RUN  ·  %d" % total

## One review row: a name line and the words the table wrote under it. A Label
## pair, not a tooltip: the whole list must be readable without pointing at it.
func _review_row(parent: Node, line: String, text: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _note_style())
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	panel.add_child(column)
	var title := Label.new()
	title.text = line
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	if text.is_empty():
		return
	var body := Label.new()
	body.text = text
	body.add_theme_font_size_override("font_size", 11)
	body.add_theme_color_override("font_color", MUTED)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)

func _note_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.06, 0.10)
	style.border_color = Color(0.38, 0.29, 0.19, 0.35)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

# --- the corpse screen ------------------------------------------------------

## The same page, pointed at a body: the gear page's rows become the kit the body
## still carries and the numbers column becomes its pockets. The tabs and the
## portrait go; one screen, one job.
func _paint_mode() -> void:
	_tab_row.visible = not _corpse_active
	_stage.visible = not _corpse_active
	_stats_box.visible = not _corpse_active
	_medicine_box.visible = not _corpse_active
	_corpse_box.visible = _corpse_active
	for page_id in PAGES:
		var root: Control = _pages[page_id]
		root.visible = (page_id == PAGE_GEAR) if _corpse_active else (page_id == page)
		var tab: Button = tabs[page_id]
		tab.set_pressed_no_signal(page_id == page)
		# The plate marks the page that is up: the plain iron for the pages you
		# can go to, the brass for the one you are on.
		tab.theme_type_variation = "PrimaryButton" if page_id == page else ""
	if _corpse_active:
		_worn_title.text = "WHAT THE BODY CARRIES"
	else:
		_worn_title.text = "WORN GEAR"
	_head_hint.text = "their kit is the warband's" if _corpse_active \
		else USAGE_HINT

## The header line: whose body this is, its state and what its kit is worth -
## or who fell.
func _paint_header() -> void:
	if _corpse_active:
		set_title(_corpse_title())
		return
	if selected_merc <= 0 or _warband == null:
		set_title("NO BODY TO DRESS")
		_merc_label.text = ""
		return
	var body_name := str(_warband.roster.name_of(selected_merc))
	var mine := selected_merc == controlled_merc
	var gear: Dictionary = _warband.roster.equipped_of(selected_merc)
	var worth := _kit_value(gear, _run_pieces(), _owned_hands())
	_merc_label.text = "%s  ·  %d G WORN%s" % [
		Contracts.state_name(int(_warband.roster.state_of(selected_merc))).to_upper(),
		worth, "   ·   YOU" if mine else ""]
	_merc_label.add_theme_color_override("font_color", TEAL if mine else BONE)
	set_title(body_name.to_upper())

## The header line in corpse mode: who fell.
func _corpse_title() -> String:
	var label := ""
	if corpse_loot != null and is_instance_valid(corpse_loot) \
			and corpse_loot.has_method("corpse_label"):
		label = str(corpse_loot.corpse_label(corpse_id))
	if label.is_empty():
		return "THE DEAD"
	return "THE DEAD  /  " + label.to_upper()

func _sync_corpse_slots() -> void:
	var layout := _corpse_layout(_corpse_ids)
	for slot in Contracts.SLOT_ORDER:
		var row: Dictionary = slot_rows[Contracts.slot_id(slot)]
		var carried := str(layout.get(str(row["id"]), ""))
		row["item_id"] = carried
		row["run_piece"] = {}
		row["hand"] = false
		_apply_slot_row(row, slot, carried)

## Where each carried piece would sit on the body: its natural slot first, then
## the free alternative, so a blade and a plank read as hands and a second
## one-hander reads as an off hand. A piece with nowhere left still shows in the
## list, which is what makes the two views agree about what the body holds.
func _corpse_layout(ids: Array[String]) -> Dictionary:
	var layout: Dictionary = {}
	for item_id in ids:
		var item: Dictionary = State.ITEMS.get(item_id, {})
		var slot := Rules.auto_slot(item, layout)
		if slot.is_empty():
			continue
		if layout.has(slot):
			slot = "off" if str(item.get("category", "")) == "1h" and not layout.has("off") else ""
		if slot.is_empty() or layout.has(slot):
			continue
		layout[slot] = item_id
	return layout

func _sync_corpse_rows() -> void:
	for child in _corpse_rows_box.get_children():
		_corpse_rows_box.remove_child(child)
		child.queue_free()
	corpse_rows.clear()
	# One row per piece, not one per copy: a bunch of the same shaft is a single
	# line with its count, in the order the body was carrying them.
	var counts: Dictionary = {}
	var order: Array[String] = []
	var value := 0
	for item_id in _corpse_ids:
		if not counts.has(item_id):
			order.append(item_id)
			counts[item_id] = 0
		counts[item_id] = int(counts[item_id]) + 1
		value += StashScript.value_of(item_id)
	for item_id in order:
		corpse_rows.append(_make_corpse_row(item_id, int(counts[item_id])))
	_corpse_empty.visible = _corpse_ids.is_empty()
	_take_all_button.visible = not _corpse_ids.is_empty()
	_take_all_button.text = "TAKE ALL  /  %d G" % value
	if _corpse_ids.is_empty():
		_merc_label.text = "Nothing left on the body."
	else:
		_merc_label.text = "%d piece(s)  ·  %d G on the body" % [_corpse_ids.size(), value]

func _make_corpse_row(item_id: String, count: int = 1) -> Dictionary:
	var button := Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var display := _item_name(item_id)
	# A row that stands for several copies says so, and its price is the bunch: one
	# click books exactly what the row says.
	var label := display if count <= 1 else "%s  ×%d" % [display, count]
	var worth := StashScript.value_of(item_id) * maxi(count, 1)
	button.text = "%s  /  %d G" % [label, worth]
	button.icon = _item_icon(item_id)
	button.add_theme_constant_override("icon_max_width", 22)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(take_piece.bind(item_id))
	button.mouse_entered.connect(func() -> void: _hover_item(item_id,
		"Click to take it from the body."))
	button.mouse_exited.connect(hide_hover)
	_corpse_rows_box.add_child(button)
	return {"item_id": item_id, "name": display, "count": maxi(count, 1),
		"value": worth, "button": button}

# --- overlays ---------------------------------------------------------------

## The piece's card, raised beside the pointer. The card is the catalogue's own
## (`WarbandItemCard`), so the words on it are the words the item table wrote, and
## it is sized to its content between two bounds: a card is never the screen.
func _hover_item(item_id: String, hint: String) -> void:
	if _hover_card == null or item_id.is_empty():
		return
	if _hover_id == item_id and _hover_card.visible:
		return
	_hover_id = item_id
	_clear_children(_hover_card)
	_hover_card.compose(item_id, _warband, hint)
	_hover_card.visible = true
	_place_at_pointer(_hover_card)

func _hover_slot(slot_id: String) -> void:
	if _corpse_active:
		var carried := str(slot_rows.get(slot_id, {}).get("item_id", ""))
		if carried.is_empty():
			return
		_hover_item(carried, "Click to take it from the body.")
		return
	var row: Dictionary = slot_rows.get(slot_id, {})
	var worn := str(row.get("item_id", ""))
	if worn.is_empty():
		return
	var hint := USAGE_HINT
	if bool(row.get("hand", false)):
		hint = RUN_HANDS_MESSAGE
	elif not (row.get("run_piece", {}) as Dictionary).is_empty():
		hint = RUN_PIECE_MESSAGE
	_hover_item(worn, hint)

func hide_hover() -> void:
	_hover_id = ""
	if _hover_card != null:
		_hover_card.visible = false

## Put one overlay beside the pointer, clamped into the window: a menu opens at the
## cursor and never leaves the screen. The card's width is the card's own; a menu
## is `MENU_WIDTH` wide and no taller than the frame leaves it.
func _place_at_pointer(box: Control) -> void:
	if box == null:
		return
	var pointer := _overlay.get_global_mouse_position() if _overlay != null \
		else Vector2.ZERO
	var bounds := _shell.get_global_rect()
	var extent := _overlay_extent(box)
	box.size = extent
	box.position = _clamped(pointer + Vector2(HOVER_EDGE, HOVER_EDGE), extent, bounds)
	# One deferred fit: a wrapped label's height is only known once it has been
	# laid out at its final width, and a card must close over its own text.
	call_deferred("_fit_overlay", box)

func _overlay_extent(box: Control) -> Vector2:
	box.reset_size()
	var extent := box.get_combined_minimum_size()
	if box == _hover_card or box == _sell_box:
		extent.x = maxf(extent.x, ItemCard.WIDTH if box == _hover_card else 240.0)
	if box == _menu_box:
		extent.x = MENU_WIDTH
	extent.y = minf(extent.y, MENU_MAX_HEIGHT)
	return extent

func _clamped(at: Vector2, extent: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(at.x, bounds.position.x + 8.0,
			maxf(bounds.position.x + 8.0, bounds.end.x - extent.x - 8.0)),
		clampf(at.y, bounds.position.y + 8.0,
			maxf(bounds.position.y + 8.0, bounds.end.y - extent.y - 8.0)))

func _fit_overlay(box: Control) -> void:
	if box == null or not is_instance_valid(box) or not box.visible:
		return
	var extent := _overlay_extent(box)
	box.size = extent
	box.position = _clamped(box.position, extent, _shell.get_global_rect())

func _show_menu_at_pointer() -> void:
	# The menu is a fixed width so a long piece name cannot stretch it into the
	# window; its scroll takes the height the frame leaves.
	_menu_box.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	var rows := _menu_rows.get_child_count()
	var height := minf(float(rows) * 30.0 + 74.0, MENU_MAX_HEIGHT - 90.0)
	_menu_scroll.custom_minimum_size = Vector2(MENU_WIDTH - 16.0, maxf(height, 30.0))
	_menu_box.visible = true
	_place_at_pointer(_menu_box)

## One row in a menu: the piece's icon, its name and the trailing note. The piece
## the row stands for rides as metadata so a menu row is always answerable for
## what it would put on.
func _menu_row_button(item_id: String, text: String, note: String) -> Button:
	var button := Button.new()
	button.set_meta("item_id", item_id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(MENU_WIDTH - 16.0, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.text = text if note.is_empty() else "%s   ·   %s" % [text, note]
	button.clip_text = true
	if not item_id.is_empty():
		var icon := _item_icon(item_id)
		if icon != null:
			button.icon = icon
			button.add_theme_constant_override("icon_max_width", 24)
		button.mouse_entered.connect(func() -> void: _hover_item(item_id, ""))
		button.mouse_exited.connect(hide_hover)
	_menu_rows.add_child(button)
	return button

## Close the alternatives menu, keeping the sell menu's own state alone.
func close_menu() -> void:
	_skill_slot_selected = -1
	if _menu_box != null:
		_menu_box.visible = false
	if _sell_box != null:
		_sell_box.visible = false

## A press anywhere the shell itself owns closes the overlays. Panels over it
## (the frame, a menu) take their own presses first.
func _on_shell_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	if _menu_box != null and _menu_box.visible:
		_menu_box.visible = false
		_skill_slot_selected = -1
	if _sell_box != null and _sell_box.visible:
		_sell_box.visible = false
	hide_hover()

# --- presentation helpers --------------------------------------------------

func _clear_children(parent: Node) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "empty"
	return str(State.ITEMS.get(item_id, {}).get("name", item_id))

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result
