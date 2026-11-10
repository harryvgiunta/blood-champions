class_name RogueliteHud
extends CanvasLayer
## The run's own plate: level, island and party on the top line, the run's
## upgrade stack down the right, the draft and the shop as the only modal windows.
##
## It reads the director's `state()` and the local player's engine every frame
## rather than being pushed events, because a HUD that misses one signal is a HUD
## that lies; the state it reads is the same dictionary the host broadcasts, so a
## guest's plate is the host's truth.
##
## The two panels are the only places this node takes the mouse. When either is
## open, `open_panels()` is true and the world keeps the cursor visible.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const PointerGate = preload("res://scripts/pointer_gate.gd")

const LAYER := 7
## How many carried upgrades the plate lists before it says "and more".
const MOD_ROWS_SHOWN := 12
## The draft card: one column of three, or two abreast past four offers. The card
## wraps its own description, so the height is the row and not the panel.
const CARD_HEIGHT := 108
const CARD_WIDTH := 322
const PANEL_SINGLE := 660.0
const PANEL_GRID := 720.0
const INK := Color(0.94, 0.88, 0.72)
const MUTED := Color(0.70, 0.64, 0.52)
const BRASS := Color(0.85, 0.72, 0.42)
const BLOOD := Color(0.92, 0.36, 0.28)
const GOOD := Color(0.66, 0.86, 0.70)

var world = null
var director = null
var _root: Control
var _top: HBoxContainer
var _island_label: Label
var _wave_label: Label
var _party_label: Label
var _purse_label: Label
var _luck_label: Label
var _boss_label: Label
var _mod_box: VBoxContainer
var _mod_title: Label
var _downed_label: Label
var _overlay: Control
var _overlay_title: Label
var _overlay_body: VBoxContainer
var _overlay_hint: Label
var _overlay_serial := 0
var _draft_buttons: Array[Button] = []
var _shop_buttons: Array[Button] = []
var _last_mods := ""


func setup(world_node: Node3D, director_node) -> void:
	world = world_node
	director = director_node
	layer = LAYER
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "RoguelitePlate"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_top = HBoxContainer.new()
	_top.name = "TopLine"
	# The band's own plate already owns the top centre and the top right; the
	# run's line sits at the top left, where nothing else is written during a
	# fight, and never covers the warband's name or its purse.
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_top.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top.add_theme_constant_override("separation", 18)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.offset_left = 16
	_top.offset_top = 10
	_root.add_child(_top)
	_island_label = _top_label("", 19, INK)
	_wave_label = _top_label("", 19, BRASS)
	_party_label = _top_label("", 16, MUTED)
	_purse_label = _top_label("", 17, GOOD)
	_luck_label = _top_label("", 17, BRASS)
	_boss_label = _top_label("", 17, BLOOD)

	_mod_box = VBoxContainer.new()
	_mod_box.name = "Mods"
	_mod_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mod_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_mod_box.offset_left = -300
	_mod_box.offset_right = -14
	# Below the band's own purse panel, never on top of it.
	_mod_box.offset_top = 118
	_mod_box.add_theme_constant_override("separation", 2)
	_root.add_child(_mod_box)
	_mod_title = Label.new()
	_mod_title.text = "UPGRADES"
	_mod_title.add_theme_color_override("font_color", MUTED)
	_mod_title.add_theme_font_size_override("font_size", 16)
	_mod_box.add_child(_mod_title)

	_downed_label = Label.new()
	_downed_label.name = "Downed"
	_downed_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_downed_label.offset_left = -300
	_downed_label.offset_right = 300
	_downed_label.offset_top = -196
	_downed_label.offset_bottom = -160
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.add_theme_color_override("font_color", BLOOD)
	_downed_label.add_theme_font_size_override("font_size", 22)
	_downed_label.visible = false
	_root.add_child(_downed_label)

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_root.add_child(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.03, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "DraftPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 340)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -170
	panel.offset_bottom = 170
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.065, 0.06, 1.0)
	style.border_color = Color(0.55, 0.45, 0.28)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	_overlay.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	_overlay_title = Label.new()
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_color_override("font_color", BRASS)
	_overlay_title.add_theme_font_size_override("font_size", 24)
	column.add_child(_overlay_title)
	_overlay_body = VBoxContainer.new()
	_overlay_body.add_theme_constant_override("separation", 8)
	column.add_child(_overlay_body)
	_overlay_hint = Label.new()
	_overlay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_hint.add_theme_color_override("font_color", MUTED)
	_overlay_hint.add_theme_font_size_override("font_size", 15)
	column.add_child(_overlay_hint)


func _top_label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(label)
	return label


func _process(_delta: float) -> void:
	_refresh()
	if open_panels():
		PointerGate.release()


func _refresh() -> void:
	if director == null or not is_instance_valid(director):
		return
	var running := bool(director.is_running())
	_top.visible = running
	_mod_box.visible = running
	_downed_label.visible = false
	if not running:
		return
	var state: Dictionary = director.state()
	var level := int(state.get("level", 0))
	var island := int(state.get("island", 1))
	_island_label.text = str(state.get("biome_name", ""))
	var tag := ""
	if bool(state.get("shop_level", false)):
		tag = "   ·   SHOP BEFORE THE BOSS"
	elif bool(state.get("boss_level", false)):
		tag = "   ·   BOSS"
	_wave_label.text = "LEVEL %d   ·   ISLAND %d%s" % [level, island, tag]
	_party_label.text = "ALIVE %d  ·  HOSTILES %d" % [
		int(state.get("party", 1)) - _downed_count(), int(state.get("living", 0))]
	_purse_label.text = "%d GOLD   ·   %d KEYS" % [
		int(state.get("gold", 0)), _banked_keys()]
	var local = _local_player()
	# Luck is the one number a body buys that changes the loot rather than the
	# fight, so it is written where the purse is: a plate, not a card.
	var held_luck: int = int(local.luck()) if local != null and is_instance_valid(local) else 0
	_luck_label.text = "LUCK %d" % held_luck if held_luck > 0 else ""
	if bool(state.get("boss_level", false)):
		_boss_label.text = "BOSS LEVEL"
		_boss_label.visible = true
	else:
		_boss_label.text = ""
	if local != null and is_instance_valid(local):
		var line := _mods_line(local)
		if line != _last_mods:
			_last_mods = line
			_write_mods(local)
		if local.is_downed() and bool(state.get("wave_active", false)):
			_downed_label.text = "DOWNED  ·  SPECTATING  ·  the living clear the level to raise you"
			_downed_label.visible = true
		else:
			_downed_label.visible = false


## The player's banked unlock keys. They are the ledger's, not the run's: a boss
## banks them the moment it falls, and they are still there after the wipe.
func _banked_keys() -> int:
	var meta = get_node_or_null("/root/Roguelite")
	return int(meta.keys) if meta != null else 0


func _downed_count() -> int:
	if director == null:
		return 0
	var count := 0
	for peer in director.players:
		var run = director.players[peer]
		if run != null and is_instance_valid(run) and run.is_downed():
			count += 1
	return count


func _local_player():
	if director == null:
		return null
	if world != null and world.get("controller") != null:
		return director.players.get(int(world.controller.local_peer_id))
	return director.players.get(1)


func _mods_line(run) -> String:
	var parts: PackedStringArray = []
	for row in run.engine.mod_list():
		parts.append("%s x%d" % [str(row.get("name", row.get("id", ""))), int(row.get("stacks", 1))])
	return "|".join(parts)


func _write_mods(run) -> void:
	for child in _mod_box.get_children():
		if child != _mod_title:
			_mod_box.remove_child(child)
			child.queue_free()
	var count := 0
	var family := ""
	# A body can carry rows from five families by the end of an island, so the
	# list names the family a run of rows belongs to instead of making the player
	# read the card again to know whether a name is a shot or a hand.
	for row in run.engine.mod_list():
		if count >= MOD_ROWS_SHOWN:
			var more := Label.new()
			more.text = "…and more"
			more.add_theme_color_override("font_color", MUTED)
			more.add_theme_font_size_override("font_size", 15)
			_mod_box.add_child(more)
			break
		var held := str(row.get("family", ""))
		if held != family:
			family = held
			var header := Label.new()
			header.text = str(Mods.FAMILY_LABEL.get(held, ""))
			header.add_theme_color_override("font_color", MUTED)
			header.add_theme_font_size_override("font_size", 13)
			header.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
			header.add_theme_constant_override("shadow_offset_x", 1)
			header.add_theme_constant_override("shadow_offset_y", 1)
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_mod_box.add_child(header)
		var label := Label.new()
		label.text = "%s  ×%d" % [str(row.get("name", row.get("id", ""))),
			int(row.get("stacks", 1))]
		label.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(row.get("rarity", "common")), INK))
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mod_box.add_child(label)
		count += 1
	if count == 0:
		var empty := Label.new()
		empty.text = "no upgrades yet"
		empty.add_theme_color_override("font_color", MUTED)
		empty.add_theme_font_size_override("font_size", 15)
		_mod_box.add_child(empty)


# --- the draft and the shop -------------------------------------------------

func open_draft(serial: int, offers: Array) -> void:
	_clear_overlay()
	_overlay_serial = serial
	_overlay_title.text = "CHOOSE AN UPGRADE"
	var local = _local_player()
	# Seven offers is the ceiling (three, Big Chests' two and luck's two) and seven
	# 64-pixel rows would run off the panel: past four, the cards go two abreast.
	var grid: Container = null
	if offers.size() > 4:
		grid = GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_overlay_body.add_child(grid)
	for index in offers.size():
		var mod_id := str(offers[index])
		var row: Dictionary = Mods.get_mod(mod_id)
		var carried := 0
		if local != null and is_instance_valid(local):
			carried = int(local.engine.stacks_of(mod_id))
		var badge := "    ×%d" % carried if carried > 0 else ""
		# The tier is the colour, the family is the line under the name: 161 rows
		# is why the card has to say which hand a name belongs to.
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s%s\n%s  ·  %s\n%s" % [
			str(row.get("name", mod_id)), badge,
			Mods.family_label_of(mod_id), Mods.rarity_of(mod_id).to_upper(),
			str(row.get("description", ""))]
		button.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(row.get("rarity", "common")), INK))
		button.add_theme_font_size_override("font_size", 17)
		# 161 rows means descriptions long enough to run off a card: every card
		# wraps, and the panel is sized to the grid rather than to the text.
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size = Vector2(CARD_WIDTH if grid != null else 0,
			CARD_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_draft_pressed.bind(index))
		if grid != null:
			grid.add_child(button)
		else:
			_overlay_body.add_child(button)
		_draft_buttons.append(button)
	var rows := ceili(float(offers.size()) / 2.0) if grid != null else offers.size()
	_resize_overlay(maxf(1, rows) * (CARD_HEIGHT + 8), PANEL_GRID if grid != null
		else PANEL_SINGLE)
	_overlay_hint.text = "The pedestal offers one upgrade for this run. Choose with the mouse or Escape to step away."
	_overlay.visible = true


## The panel grows with its cards instead of clipping them: three is the old
## height and anything past it is the card's own row plus the panel's padding.
func _resize_overlay(body_height: float, width: float) -> void:
	var panel = _overlay.get_node_or_null("DraftPanel")
	if panel == null:
		return
	var height := clampf(maxf(340.0, body_height + 150.0), 340.0, 760.0)
	panel.custom_minimum_size = Vector2(width, height)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5


func _on_draft_pressed(index: int) -> void:
	if director == null:
		return
	var peer := 1
	if world != null and world.get("controller") != null:
		peer = int(world.controller.local_peer_id)
	director.choose_draft(peer, _overlay_serial, index)
	close_all()


func open_shop(serial: int, wares: Array) -> void:
	_clear_overlay()
	_overlay_serial = serial
	_overlay_title.text = "THE SHOP  ·  %d GOLD" % int(
		director.state().get("gold", 0) if director != null else 0)
	for index in wares.size():
		var ware: Dictionary = wares[index]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  ·  %d gold" % [str(ware.get("name", "?")),
			int(ware.get("price", 0))]
		button.add_theme_color_override("font_color",
			Mods.RARITY_COLOUR.get(str(ware.get("rarity", "common")), INK))
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size = Vector2(0, 44)
		if bool(ware.get("sold", false)):
			button.disabled = true
			button.text += "  ·  SOLD"
		button.pressed.connect(_on_shop_pressed.bind(index))
		_overlay_body.add_child(button)
		_shop_buttons.append(button)
	_resize_overlay(maxf(1, wares.size()) * 52, PANEL_SINGLE)
	_overlay_hint.text = "The party's gold buys the wares; the rack beside the stall takes the boss keys. Escape steps away."
	_overlay.visible = true


func _on_shop_pressed(index: int) -> void:
	if director == null:
		return
	var peer := 1
	if world != null and world.get("controller") != null:
		peer = int(world.controller.local_peer_id)
	director.buy(_overlay_serial, index, peer)
	close_all()


func _clear_overlay() -> void:
	for child in _overlay_body.get_children():
		_overlay_body.remove_child(child)
		child.queue_free()
	_draft_buttons.clear()
	_shop_buttons.clear()
	_overlay_serial = 0


func open_panels() -> bool:
	return _overlay != null and _overlay.visible


func close_all() -> void:
	if _overlay != null:
		_overlay.visible = false
	_clear_overlay()


func clear_plate() -> void:
	_top.visible = false
	_mod_box.visible = false
	_downed_label.visible = false
	close_all()


## Escape, from the world's own handler: close the modal before it falls through
## to the game menu. True when it consumed the press.
func close_top() -> bool:
	if open_panels():
		close_all()
		return true
	return false
