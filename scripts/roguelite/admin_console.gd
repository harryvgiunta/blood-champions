class_name AdminConsole
extends CanvasLayer
## The host's debug door into the loop (`F9`): the arena's switches, the three
## catalogues the run is built from, and a way to stand on any floor or back in
## Hearthstead.
##
## The console owns the window and nothing else. Every press is a `admin_*` call
## on the director or a warband call the game already makes, so what it produces
## is what the loop produces: a granted row is the row a chest pays, a re-stood
## gate is the gate `_spawn_gates` builds, a rolled chest is a promise from the
## same ladder. It writes the player's own ledgers through
## `Roguelite.grant_weapon`/`grant_ability`, which exist for this window alone.
##
## It is the host's, because the host owns the level, the mobs and the rolls. On
## a guest every arena press is refused with that line rather than half-applied
## on a machine that does not own the state.
##
## The catalogues are read at open, not cached: a run's stacks, a body's hands and
## its bar move while the window is up, and a list that lied about them would be
## a list the operator has to re-open to believe.

const Ledger = preload("res://scripts/ui/ledger_theme.gd")
const LedgerFrameScript = preload("res://scripts/ui/ledger_frame.gd")
const PointerGate = preload("res://scripts/pointer_gate.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const State = preload("res://scripts/player_state.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")

## Above the plate (7) and the town's counters (9): the console is the last word
## on the screen while it is up.
const LAYER := 11
const PANEL := Vector2(1260.0, 812.0)
const LEFT_COLUMN := 320.0
## How often the readout re-reads the director while the window is up. The plate
## is text; a quarter second is faster than anybody reads it and cheaper than a
## frame's worth of `state()` calls.
const READOUT_PERIOD := 0.25

const INK := Ledger.INK
const MUTED := Ledger.INK_MUTED
const BLOOD := Ledger.BLOOD
const TEAL := Ledger.TEAL
## Rarity is the card's metal in the world, where the plate is iron; on the
## ledger's vellum the same four tiers need inks that read on paper.
const RARITY_INK := {
	Mods.RARITY_COMMON: Color("4a321d"),
	Mods.RARITY_EPIC: Color("21567a"),
	Mods.RARITY_LEGENDARY: Color("7a4f06"),
	Mods.RARITY_GREED: Color("761819"),
}

const TABS := [
	{"id": "arena", "label": "THE ARENA"},
	{"id": "upgrades", "label": "UPGRADES"},
	{"id": "weapons", "label": "WEAPONS"},
	{"id": "abilities", "label": "ABILITIES"},
	{"id": "travel", "label": "TRAVEL"},
]

var world = null
var director = null

var _built := false
var _open := false
var _tab := "arena"
var _search := ""
var _group := "ALL"
var _readout_clock := 0.0

var _shell: Control
var _frame
var _tab_buttons: Dictionary = {}   # tab id -> Button
var _left: VBoxContainer
var _right: VBoxContainer
var _filter: HBoxContainer
var _search_box: LineEdit
var _group_select: OptionButton
var _scroll: ScrollContainer
var _list: VBoxContainer
var _spot: Label
var _status: Label


func setup(world_node: Node3D, director_node) -> void:
	world = world_node
	director = director_node
	layer = LAYER
	visible = false


# --- the window ------------------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> void:
	if not _built:
		_build()
	_open = true
	visible = true
	_rebuild()
	PointerGate.release()


func close() -> void:
	_open = false
	visible = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Escape, from the world's own handler: shut the window and say so, so the press
## never falls through to the game menu behind it.
func close_top() -> bool:
	if not _open:
		return false
	close()
	return true


func _process(delta: float) -> void:
	if not _open:
		return
	# A window on screen is a window that owns the cursor, exactly as the run's
	# own plate does while a chest's draft is up.
	PointerGate.release()
	_readout_clock += delta
	if _readout_clock >= READOUT_PERIOD:
		_readout_clock = 0.0
		_tick_readout()


# --- construction ----------------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_shell = Control.new()
	_shell.name = "Shell"
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shell.theme = Ledger.get_theme()
	add_child(_shell)
	var dim := ColorRect.new()
	dim.name = "Shade"
	dim.color = Color(0.02, 0.015, 0.01, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.add_child(dim)

	_frame = LedgerFrameScript.new()
	_frame.name = "Frame"
	_frame.configure("Admin Console", "gear", "ADM")
	_frame.set_anchors_preset(Control.PRESET_CENTER)
	_frame.offset_left = -PANEL.x * 0.5
	_frame.offset_right = PANEL.x * 0.5
	_frame.offset_top = -PANEL.y * 0.5
	_frame.offset_bottom = PANEL.y * 0.5
	_shell.add_child(_frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	_frame.body.add_child(column)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for entry in TABS:
		var id := str(entry["id"])
		var button := Button.new()
		button.text = str(entry["label"])
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 34)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_tab.bind(id))
		tabs.add_child(button)
		_tab_buttons[id] = button

	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 16)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	_left = VBoxContainer.new()
	_left.name = "Switches"
	_left.custom_minimum_size = Vector2(LEFT_COLUMN, 0)
	_left.add_theme_constant_override("separation", 6)
	content.add_child(_left)

	_right = VBoxContainer.new()
	_right.name = "Board"
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 6)
	content.add_child(_right)

	_filter = HBoxContainer.new()
	_filter.name = "Filter"
	_filter.add_theme_constant_override("separation", 8)
	_right.add_child(_filter)
	_search_box = LineEdit.new()
	_search_box.name = "Search"
	_search_box.placeholder_text = "filter by name"
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.add_theme_font_size_override("font_size", 14)
	_search_box.text_changed.connect(_on_search_changed)
	_filter.add_child(_search_box)
	_group_select = OptionButton.new()
	_group_select.name = "Group"
	_group_select.custom_minimum_size = Vector2(190, 0)
	_group_select.item_selected.connect(_on_group_selected)
	_filter.add_child(_group_select)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "Rows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)
	# The readout is the arena's and the travel board's whole right side, and the
	# catalogues' filter and list take the same room: one of the two is on screen,
	# never both, so neither squeezes the other.
	_spot = Label.new()
	_spot.name = "Readout"
	_spot.add_theme_font_size_override("font_size", 16)
	_spot.add_theme_color_override("font_color", INK)
	_spot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_right.add_child(_spot)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_status = Label.new()
	_status.name = "Status"
	_status.text = "F9 or Escape closes. The console writes through the run's own calls."
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", TEAL)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_status)
	var shut := Button.new()
	shut.text = "CLOSE"
	shut.custom_minimum_size = Vector2(120, 32)
	shut.pressed.connect(close)
	footer.add_child(shut)


# --- the boards ------------------------------------------------------------

func _on_tab(id: String) -> void:
	if id == _tab and _open:
		# Pressing the lit tab again is not a press on anything: keep the board.
		if _tab_buttons.has(id):
			(_tab_buttons[id] as Button).set_pressed_no_signal(true)
		return
	_tab = id
	_group = "ALL"
	_search = ""
	if _search_box != null:
		_search_box.text = ""
	_rebuild()


func _rebuild() -> void:
	if not _built:
		return
	if _tab_buttons.has(_tab):
		var lit: Button = _tab_buttons[_tab]
		if not lit.button_pressed:
			lit.set_pressed_no_signal(true)
	_clear(_left)
	_clear(_list)
	var catalog := _is_catalog()
	_filter.visible = catalog
	_scroll.visible = catalog
	_spot.visible = not catalog
	if catalog:
		_build_groups()
		_build_list()
	_build_switches()
	_tick_readout()


## The five boards that are lists of rows, against the two that are a readout.
func _is_catalog() -> bool:
	return _tab == "upgrades" or _tab == "weapons" or _tab == "abilities"


func _build_switches() -> void:
	match _tab:
		"arena":
			_head(_left, "THE ARENA")
			var kill := _button(_left, "KILL EVERYTHING", "DangerButton", _on_kill)
			kill.tooltip_text = "Kills every hostile on the field and empties the inbound queue."
			var god := _button(_left, _god_label(), "PrimaryButton", _on_god)
			god.tooltip_text = "A body in god mode takes no blow: no downing, no bleed, no bounds price."
			_head(_left, "GATES")
			_button(_left, "RE-SPAWN GATES", "Button", _on_respawn_gates.bind(false))
			_button(_left, "ROLL GATES", "Button", _on_respawn_gates.bind(true))
			_head(_left, "CHEST")
			_button(_left, "RE-SPAWN CHEST", "Button", _on_respawn_chests.bind(false))
			_button(_left, "ROLL CHEST", "Button", _on_respawn_chests.bind(true))
			_note(_left, "A cleared level stands its own gates and boxes; the loop's "
				+ "own calls stand them again here.")
		"travel":
			_head(_left, "THE RUN")
			_button(_left, "TO HEARTHSTEAD", "DangerButton", _on_town)
			_button(_left, "NEXT LEVEL  ·  PORTAL", "PrimaryButton", _on_next_level)
			_button(_left, "NEXT BOSS", "Button", _on_next_boss)
			_head(_left, "FLOOR")
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			_left.add_child(row)
			var floor_box := SpinBox.new()
			floor_box.name = "Floor"
			floor_box.min_value = 1
			floor_box.max_value = 9999
			floor_box.step = 1
			floor_box.value = _level() if _level() > 0 else 1
			floor_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# The spin box is the one field the ledger theme does not skin, and its
			# own field is dark ink on a dark plate: the number is set to the ink
			# every other counter on the page uses.
			floor_box.get_line_edit().add_theme_color_override("font_color", Ledger.BONE)
			row.add_child(floor_box)
			var go := Button.new()
			go.text = "GO"
			go.custom_minimum_size = Vector2(72, 0)
			go.pressed.connect(_on_go_floor.bind(floor_box))
			row.add_child(go)
			_note(_left, "A jumped-to floor carries the gate's own promise for its depth; "
				+ "crossing a depth block rebuilds the island.")
		"upgrades":
			_head(_left, "EVERY UPGRADE")
			var run = _local_run()
			var carried := "No run is live: a grant waits for a body to land on."
			if run != null:
				carried = "%d stacks ride this body." % int(run.engine.total_stacks())
			_note(_left, "%d rows in the pool, %d of them live. %s" % [
				Mods.all().size(), _ready_rows(), carried])
			_note(_left, "Click a row for one stack, Shift-click to fill it to its cap.")
		"weapons":
			_head(_left, "EVERY WEAPON")
			_note(_left, "%d pieces in the armory, %d open to this player. A click opens "
				% [Weapons.all_ids().size(), _open_weapons()] + "the piece and wears it in "
				+ "the hand its class belongs to.")
		"abilities":
			_head(_left, "EVERY ABILITY")
			_note(_left, "%d skills in the catalog, %d open to this player. A click opens "
				% [AbilityRules.catalog_ids().size(), _open_abilities()] + "the skill and "
				+ "puts it on the bar; a skill the hands do not fit is still opened.")


func _build_groups() -> void:
	_group_select.clear()
	_group_select.add_item("ALL")
	var seen: Array[String] = []
	match _tab:
		"upgrades":
			for family in Mods.FAMILIES:
				seen.append(str(Mods.FAMILY_LABEL.get(family, family)))
		"weapons":
			seen.append("RANGED")
			seen.append("MELEE")
		"abilities":
			for id in AbilityRules.catalog_ids():
				var definition: Dictionary = AbilityRules.by_id(id)
				if definition.is_empty():
					continue
				var label := AbilityRules.type_label(AbilityRules.type_of(definition))
				if not seen.has(label):
					seen.append(label)
	for label in seen:
		_group_select.add_item(label)
	_group_select.selected = 0


func _build_list() -> void:
	_clear(_list)
	match _tab:
		"upgrades":
			_build_upgrades()
		"weapons":
			_build_weapons()
		"abilities":
			_build_abilities()
	if _list.get_child_count() == 0:
		_note(_list, "Nothing on this board matches the filter.")


func _build_upgrades() -> void:
	var run = _local_run()
	var needle := _search.strip_edges().to_lower()
	for raw in Mods.all():
		var row: Dictionary = raw
		var id := str(row.get("id", ""))
		var name := str(row.get("name", id))
		if not _grouped(str(Mods.FAMILY_LABEL.get(Mods.family_of(id), ""))):
			continue
		if not needle.is_empty() and not name.to_lower().contains(needle) \
				and not id.contains(needle):
			continue
		var cap := Mods.max_stacks(id)
		var stacks := int(run.engine.stacks_of(id)) if run != null else 0
		var line := "%s   ·   %s   ·   %s   ·   %d/%d" % [name,
			Mods.rarity_of(id).to_upper(), Mods.family_label_of(id), stacks, cap]
		if not Mods.ready_of(id):
			line += "   ·   INERT"
		var button := _list_button(line, _rarity_ink(Mods.rarity_of(id)),
			_grant_upgrade.bind(id))
		button.disabled = run == null or stacks >= cap


func _build_weapons() -> void:
	var warband = _warband()
	var merc := _merc()
	var worn: Dictionary = {}
	if warband != null and merc > 0:
		worn = warband.roster.equipped_of(merc)
	var run = _local_run()
	var in_hand := [str(run.ranged_id), str(run.melee_id)] if run != null \
		else [str(worn.get("main", "")), str(worn.get("off", ""))]
	var meta = _meta()
	var needle := _search.strip_edges().to_lower()
	for id in Weapons.all_ids():
		var def: Dictionary = Weapons.get_weapon(id)
		var slot := str(def.get("slot", ""))
		if not _grouped(slot.to_upper()):
			continue
		var name := Weapons.display_name(id)
		if not needle.is_empty() and not name.to_lower().contains(needle) \
				and not id.contains(needle):
			continue
		var open := meta != null and bool(meta.is_unlocked(id))
		var state := "OPEN"
		if not open:
			state = "%d KEYS" % int(def.get("unlock_cost", 3))
		var line := "%s   ·   %s   ·   %s   ·   %s" % [name, slot.to_upper(),
			str(def.get("rarity", "common")).to_upper(), state]
		if in_hand.has(id):
			line += "   ·   IN HAND"
		_list_button(line, _rarity_ink(str(def.get("rarity", "common"))),
			_give_weapon.bind(id))


func _build_abilities() -> void:
	var warband = _warband()
	var merc := _merc()
	var bar: Array = []
	var gear: Dictionary = {}
	if warband != null and merc > 0:
		bar = warband.roster.hotbar_order_of(merc)
		gear = warband.roster.equipped_of(merc)
	var main_row: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
	var off_row: Dictionary = State.ITEMS.get(str(gear.get("off", "")), {})
	var meta = _meta()
	var needle := _search.strip_edges().to_lower()
	for id in AbilityRules.catalog_ids():
		var definition: Dictionary = AbilityRules.by_id(id)
		if definition.is_empty():
			continue
		if not _grouped(AbilityRules.type_label(AbilityRules.type_of(definition))):
			continue
		var name := str(definition.get("name", id)).capitalize()
		if not needle.is_empty() and not name.to_lower().contains(needle) \
				and not id.contains(needle):
			continue
		var owned := meta != null and bool(meta.is_ability_unlocked(id))
		var state := "ON THE BAR" if bar.has(id) else ("OPEN" if owned
			else "%d KEYS" % AbilityRules.unlock_cost_of(id))
		var line := "%s   ·   %s   ·   %s" % [name,
			AbilityRules.family_label(definition), state]
		if not AbilityRules.fits_gear(definition, main_row, off_row):
			line += "   ·   HANDS: %s" % AbilityRules.requirement_label(definition)
		_list_button(line, TEAL if bar.has(id) else INK, _give_ability.bind(id))


func _on_search_changed(text: String) -> void:
	_search = text
	_build_list()
	_tick_readout()


func _on_group_selected(index: int) -> void:
	_group = _group_select.get_item_text(index)
	_build_list()


## One row belongs to the group named by its own key: a weapon's class, an
## upgrade's family, an ability's first hand.
func _grouped(key: String) -> bool:
	return _group == "ALL" or _group.is_empty() or key == _group


# --- the presses -----------------------------------------------------------

func _on_kill() -> void:
	_say(_call("admin_kill_all"))


func _on_god() -> void:
	BodyScript.god_mode = not BodyScript.god_mode
	_rebuild()


func _on_respawn_gates(roll: bool) -> void:
	_say(_call("admin_stand_gates", [roll]))


func _on_respawn_chests(roll: bool) -> void:
	_say(_call("admin_stand_chests", [roll]))


func _on_town() -> void:
	_say(_call("admin_goto_town"))


func _on_next_level() -> void:
	_say(_call("admin_goto_level", [_level() + 1]))


func _on_next_boss() -> void:
	var next_boss := (int(floor(float(_level()) / 10.0)) + 1) * 10
	_say(_call("admin_goto_level", [maxi(10, next_boss)]))


func _on_go_floor(box: SpinBox) -> void:
	_say(_call("admin_goto_level", [int(box.value)]))


func _grant_upgrade(mod_id: String) -> void:
	var want := Mods.max_stacks(mod_id) if Input.is_key_pressed(KEY_SHIFT) else 1
	_say(_call("admin_grant_mod", [_peer(), mod_id, want]))
	_build_list()


func _give_weapon(weapon_id: String) -> void:
	_say(_call("admin_give_weapon", [_peer(), weapon_id]))
	_build_list()


func _give_ability(ability_id: String) -> void:
	_say(_call("admin_give_ability", [_peer(), ability_id]))
	_build_list()


## One console press, whatever the director answers. A missing method is a build
## whose director predates the console, and it says so rather than failing open.
func _call(method: String, args: Array = []) -> Dictionary:
	if director == null or not is_instance_valid(director):
		return {"ok": false, "message": "There is no run director in this world."}
	if not director.has_method(method):
		return {"ok": false, "message": "This build's director has no %s." % method}
	var answer: Variant = director.callv(method, args)
	return answer if answer is Dictionary else {"ok": true, "message": ""}


# --- the readout -----------------------------------------------------------

func _tick_readout() -> void:
	if _spot == null or not is_instance_valid(_spot):
		return
	_spot.text = _readout_text()


func _readout_text() -> String:
	if director == null or not is_instance_valid(director):
		return "No director in this world."
	if bool(director.is_client()):
		return "A GUEST  ·  the arena is the host's; this window reads only."
	if not bool(director.is_running()):
		return "NO RUN  ·  the wood is quiet.\nThe portal in Hearthstead opens one; " \
			+ "the WEAPONS and ABILITIES boards work from the square."
	var state: Dictionary = director.state()
	var lines: PackedStringArray = []
	lines.append("LEVEL %d  ·  ISLAND %d  ·  %s" % [int(state.get("level", 0)),
		int(state.get("island", 0)), str(state.get("biome_name", "")).to_upper()])
	var kind := str(state.get("kind", "combat")).to_upper()
	if bool(state.get("market_level", false)):
		kind = "MARKET"
	elif bool(state.get("shop_level", false)):
		kind = "SHOP"
	elif bool(state.get("boss_level", false)):
		kind = "BOSS"
	lines.append("KIND        %s%s" % [kind, "   ·   CLEAR" if bool(
		state.get("cleared", false)) else "   ·   WAVE LIVE" if bool(
		state.get("wave_active", false)) else ""])
	lines.append("BODIES      %d alive   ·   %d inbound" % [
		int(state.get("living", 0)), int(state.get("queue", 0))])
	var contract: Variant = state.get("contract", {})
	if contract is Dictionary and not (contract as Dictionary).is_empty():
		var trial := str((contract as Dictionary).get("trial", "open")).to_upper()
		var chest: Variant = (contract as Dictionary).get("chest", {})
		var promise := "—"
		if chest is Dictionary and not (chest as Dictionary).is_empty():
			var surface := str((chest as Dictionary).get("surface", ""))
			var tier := str((chest as Dictionary).get("tier", ""))
			promise = str((chest as Dictionary).get("payout", "")).to_upper()
			if not surface.is_empty():
				promise = "%s  ·  %s" % [Mods.surface_label(surface), tier.to_upper()]
		lines.append("CONTRACT    %s   ·   %s" % [trial, promise])
	lines.append("PURSE       %d gold   ·   %d keys" % [int(state.get("gold", 0)),
		_banked_keys()])
	var party := int(state.get("party", 0))
	lines.append("PARTY       %d %s" % [party, "body" if party == 1 else "bodies"])
	lines.append("GOD MODE    %s" % ("ON" if BodyScript.god_mode else "off"))
	lines.append("")
	lines.append("A guest cannot press this window: the host owns the level, the "
		+ "mobs and the rolls.")
	return "\n".join(lines)


# --- small pieces ----------------------------------------------------------

func _head(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MUTED)
	parent.add_child(label)
	return label


func _note(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, variation: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	if variation != "Button":
		button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(0, 34)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button


## A catalogue row is a line written on the ledger's page, not a forged slab: a
## hundred and seventy iron plates stacked on vellum read as a wall, and the ink
## the rest of the page uses is what a list of names wants.
func _list_button(text: String, colour: Color, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 31)
	button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _row_style(state))
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, colour)
	button.add_theme_color_override("font_disabled_color",
		Color(colour.r, colour.g, colour.b, 0.42))
	button.pressed.connect(action)
	_list.add_child(button)
	return button


func _row_style(state: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	match state:
		"hover":
			box.bg_color = Color(0.42, 0.30, 0.14, 0.14)
		"pressed":
			box.bg_color = Color(0.42, 0.30, 0.14, 0.26)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _say(answer: Dictionary) -> void:
	var text := str(answer.get("message", ""))
	if text.is_empty():
		text = "done" if bool(answer.get("ok", true)) else "refused"
	if _status != null:
		_status.text = "ADMIN  ·  " + text
		_status.add_theme_color_override("font_color",
			TEAL if bool(answer.get("ok", true)) else BLOOD)
	_tick_readout()


func _god_label() -> String:
	return "GOD MODE  ·  ON" if BodyScript.god_mode else "GOD MODE  ·  OFF"


func _rarity_ink(rarity: String) -> Color:
	return RARITY_INK.get(rarity, INK)


func _ready_rows() -> int:
	var live := 0
	for row in Mods.all():
		if bool((row as Dictionary).get("ready", true)):
			live += 1
	return live


func _open_weapons() -> int:
	var meta = _meta()
	if meta == null:
		return 0
	var open := 0
	for id in Weapons.all_ids():
		if bool(meta.is_unlocked(id)):
			open += 1
	return open


func _open_abilities() -> int:
	var meta = _meta()
	if meta == null:
		return 0
	var open := 0
	for id in AbilityRules.catalog_ids():
		if bool(meta.is_ability_unlocked(id)):
			open += 1
	return open


func _banked_keys() -> int:
	var meta = _meta()
	return int(meta.keys) if meta != null else 0


func _level() -> int:
	if director == null or not is_instance_valid(director):
		return 0
	return int(director.get("level"))


func _peer() -> int:
	if world != null and world.get("controller") != null:
		return int(world.controller.local_peer_id)
	return 1


func _merc() -> int:
	if world == null or world.get("controller") == null:
		return -1
	return int(world.controller.merc_for_peer(_peer()))


func _warband():
	return world.get("warband") if world != null else null


func _meta():
	return get_node_or_null("/root/Roguelite")


func _local_run():
	if director == null or not is_instance_valid(director):
		return null
	var run = director.players.get(_peer())
	return run if run != null and is_instance_valid(run) else null
