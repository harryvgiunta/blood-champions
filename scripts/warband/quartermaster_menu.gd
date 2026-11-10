class_name QuartermasterMenu
extends CanvasLayer
## The keeper who sells the band's medicine. Steel is not for sale in the town
## any more - a piece comes off the Weapon Rack's unlocks or out of a run's chests
## - so this counter is the healer's: bandages and draughts, bought out of the
## shared purse and pressed into the warband's own stock (`Warband.supplies`),
## where key 9 and key 0 spend them.

signal changed
## A keeper actually took the coin (see `VendorMenu.purchased`).
signal purchased(item_id: String)

const State = preload("res://scripts/player_state.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const LedgerThemeScript = preload("res://scripts/ui/ledger_theme.gd")
const ItemHover = preload("res://scripts/warband/item_hover.gd")

const INK := LedgerThemeScript.INK
const MUTED := LedgerThemeScript.INK_MUTED
const BLOOD := LedgerThemeScript.BLOOD

## The whole counter: the two things a body can buy to stay standing. There is
## no gear row here by design - the only way a piece of steel reaches a hand is a
## key spent at the rack or a chest opened in a run.
const STOCK := ["bandage_linen", "healing_potion"]

const PANEL_SIZE := Vector2(640, 680)

var _warband = null
var _open := false
var _built := false
var _list: VBoxContainer
var _purse: Label
## What the band is carrying, repainted with the purse: the count is the whole
## point of the counter, because a dressing nobody holds closes nothing.
var _stock_line: Label
var _status: Label
var _rows: Dictionary = {}   # item_id -> {root, button, price_label}

func _ready() -> void:
	layer = 9
	visible = false

func configure(warband) -> void:
	_warband = warband
	if not _built:
		_build()
	refresh()

func open() -> void:
	if not _built:
		_build()
	_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	_open = false
	visible = false

func is_open() -> bool:
	return _open

func status_text() -> String:
	return str(_status.text) if _status != null else ""

## The band's medicine as one line: what a press of BUY is actually adding to.
func carried_line() -> String:
	var bandages := int(_warband.supply_count("bandage")) if _warband != null else 0
	var potions := int(_warband.supply_count("potion")) if _warband != null else 0
	return "YOU CARRY  ·  BANDAGES %d  ·  POTIONS %d" % [bandages, potions]

## The stock with the price the shop will charge and whether the purse covers it.
## `price` is one purchase: a piece sold by the bunch (ammunition) prices the whole
## `bundle`, exactly what `Warband.buy_gear` takes for it.
func stock_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if _warband == null:
		return rows
	var gold: int = _warband.gold()
	for item_id in STOCK:
		var item: Dictionary = State.ITEMS.get(str(item_id), {})
		if item.is_empty():
			continue
		var bundle := State.item_bundle(str(item_id))
		var price := int(item.get("price", 0)) * bundle
		rows.append({"item_id": str(item_id), "name": str(item.get("name", item_id)),
			"price": price, "affordable": gold >= price, "bundle": bundle})
	return rows

## Buy one dose into the band's stock. Everything about the transaction - the
## price, the purse, the count - belongs to `Warband.buy_gear`.
func buy(item_id: String) -> Dictionary:
	if _warband == null:
		return {"ok": false, "message": "The keeper is not here.", "item_id": item_id, "cost": 0}
	# Only what is on this board: a press can never walk the whole catalogue
	# through a counter that does not stock it.
	var stocked := false
	for row in stock_rows():
		if str(row["item_id"]) == item_id:
			stocked = true
			break
	if not stocked:
		var refusal := {"ok": false, "message": "%s does not stock that." % "The quartermaster",
			"item_id": item_id, "cost": 0}
		if _status != null:
			_status.text = str(refusal["message"])
		return refusal
	var result: Dictionary = _warband.buy_gear(item_id)
	if _status != null:
		_status.text = str(result.get("message", ""))
	refresh()
	if bool(result.get("ok", false)):
		purchased.emit(item_id)
	return result

func refresh() -> void:
	if not _built:
		return
	var gold: int = _warband.gold() if _warband != null else 0
	_purse.text = "%d G" % gold
	_stock_line.text = carried_line()
	for item_id in _rows:
		var row: Dictionary = _rows[item_id]
		var price := int(row.get("price", 0))
		var button: Button = row["button"]
		button.disabled = gold < price
		button.text = "BUY  %d" % price
	changed.emit()

# --- construction ----------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	var root_control := Control.new()
	root_control.name = "Root"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.theme = LedgerThemeScript.get_theme()
	add_child(root_control)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.015, 0.01, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root_control.add_child(dim)

	var frame = LedgerFrameScript.new()
	frame.name = "Frame"
	frame.configure("Quartermaster", "coin")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5
	frame.offset_bottom = PANEL_SIZE.y * 0.5
	root_control.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.body.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	column.add_child(head)
	_label(head, "THE TOWN  \u00b7  MEDICINE", 10, MUTED)
	_purse = _label(column, "", 22, INK)
	_purse.add_theme_font_override("font", LedgerThemeScript.FONT_DISPLAY)
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var blurb := _label(column, "Dressings and draughts, into the band's own pack.", 13, MUTED)
	blurb.add_theme_font_override("font", LedgerThemeScript.FONT_ITALIC)
	_stock_line = _label(column, "", 12, MUTED)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_status = _label(column, "", 12, LedgerThemeScript.TEAL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 34)

	_rows.clear()
	for row in stock_rows():
		var item_id := str(row["item_id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		# A bunch row says how many shafts the coin buys, as the stalls' boards do.
		var label := str(row["name"])
		if int(row["bundle"]) > 1:
			label = "%s  ×%d" % [label, int(row["bundle"])]
		var name_label := ItemHover.LabelRow.new()
		name_label.text = label
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 17)
		name_label.add_theme_color_override("font_color", INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.show_item(item_id, _warband,
			"Click BUY - the keeper asks %d G." % int(row["price"]), int(row["bundle"]))
		line.add_child(name_label)
		var buy_button := Button.new()
		buy_button.custom_minimum_size = Vector2(120, 30)
		buy_button.add_theme_font_size_override("font_size", 11)
		buy_button.pressed.connect(_on_buy.bind(item_id))
		line.add_child(buy_button)
		_list.add_child(line)
		_rows[item_id] = {"root": line, "button": buy_button, "price": int(row["price"])}

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	parent.add_child(result)
	return result


func _on_buy(item_id: String) -> void:
	buy(item_id)
