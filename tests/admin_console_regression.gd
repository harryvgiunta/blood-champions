extends SceneTree
## The admin console: a window over the loop's own calls, not a second loop.
##
## What this owns: that the world builds the console and `F9` opens and closes
## it; that god mode is the body's switch and a body under it takes no blow; that
## the console kills a wave and empties the queue so the level clears; that a
## granted row lands on the engine and stops at its cap, and that a row the pool
## does not offer yet can still be written; that a weapon is opened on the
## player's ledger and worn in the hand its class belongs to; that an ability is
## opened and put on the bar; that the gates and the chest are re-stood and
## rolled from the console's own seed; that a floor can be jumped to and the
## square returned to; and that the three catalogues list every row they own.

const WORLD := "res://scenes/warband_world.tscn"
const TEST_STATE := "user://admin_console_state.json"
const TEST_WARBAND := "user://admin_console_warband.json"
const TEST_META := "user://admin_console_meta.json"

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const DirectorScript = preload("res://scripts/roguelite/run_director.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")

var game
var run
var body
var meta
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ADMIN_FAIL  ", message)


func _initialize() -> void:
	call_deferred("execute")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func execute() -> void:
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	await _open_world()
	_check_window()
	await _check_arena()
	_check_catalogues()
	_check_gates_and_chests()
	_check_travel()
	_check_boards()
	BodyScript.god_mode = false
	game.queue_free()
	await process_frame
	_remove(TEST_STATE)
	_remove(TEST_WARBAND)
	_remove(TEST_META)
	print("ADMIN_CONSOLE_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _open_world() -> void:
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	var flow = root.get_node("GameFlow")
	meta = root.get_node("Roguelite")
	state.save_path = TEST_STATE
	state.reset(false)
	warband.save_path = TEST_WARBAND
	warband.reset_state()
	meta.save_path = TEST_META
	meta.reset(false)
	flow.active = false
	flow.world_start = "town"
	game = load(WORLD).instantiate()
	root.add_child(game)
	current_scene = game
	var waited := 0.0
	while waited < 40.0 and (game.get("controller") == null or game.bodies.size() < 1):
		await physics_frame
		waited += 0.016
	run = game.get("roguelite")
	check(game.bodies.size() >= 1, "the world stands a body up")
	check(run != null, "the world owns a run director")
	if game.bodies.size() >= 1:
		body = game.bodies[0]


## The window itself: the world builds one, it starts shut, and the world's own
## keys open and close it.
func _check_window() -> void:
	check(game.admin_console != null, "the world builds an admin console")
	check(not game.admin_console.is_open(), "and it starts shut")
	check(not game._panel_open(), "so the world calls no panel open")
	game.admin_console.open()
	check(game.admin_console.is_open(), "the console opens")
	check(str(game.admin_console._tab) == "arena", "on the arena board")
	check(game.admin_console._left.get_child_count() > 0, "with its switches built")
	check(game._panel_open(), "and the world counts it as a panel")
	check(game.admin_console.close_top(), "Escape shuts it")
	check(not game.admin_console.is_open(), "and it is gone")
	check(not game.admin_console.close_top(), "a second Escape falls through")
	game.admin_console.toggle()
	check(game.admin_console.is_open(), "toggle opens it again")
	game.admin_console.close()
	# The key itself, through the world's own handler: the console's door is one
	# line in the scene's input, and a window nobody can raise is no window.
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	game._unhandled_input(f9)
	check(game.admin_console.is_open(), "F9 raises the console")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	check(not game.admin_console.is_open(), "Escape sets it down again")


func _check_arena() -> void:
	var start: Dictionary = run.start_run()
	check(bool(start.get("ok", false)), "the portal opens a run: %s"
		% str(start.get("message", "")))
	check(run.is_running(), "the director is live")
	check(run.players.has(1), "the body has a run runtime")

	# God mode is the body's own switch: the console presses it, and no damage
	# path in the game can reach a body under it.
	BodyScript.god_mode = false
	game.admin_console._on_god()
	check(BodyScript.god_mode, "the console turns god mode on")
	var before := float(body.health)
	body.take_damage(50.0, 99)
	check(is_equal_approx(float(body.health), before),
		"a body in god mode takes no blow (%0.1f -> %0.1f)" % [before, float(body.health)])
	check(not bool(body.downed), "and is never put down")
	check(is_equal_approx(body.pay_cost(0.5), 0.0), "and pays no price for the edge of the ring")
	game.admin_console._on_god()
	check(not BodyScript.god_mode, "the console turns it off again")
	body.take_damage(6.0, 99)
	check(float(body.health) < before, "a body out of god mode takes the blow (%0.1f)"
		% float(body.health))

	# The wave. The opening lead is ten seconds, so the spawner is stepped rather
	# than waited on; the console's kill is then the whole of the clear.
	var landed := 0
	for _round in 14:
		if not run.live_mobs().is_empty():
			break
		run.tick(1.0)
	landed = run.live_mobs().size()
	check(landed > 0, "the wave lands a body (%d)" % landed)
	var queued_before: int = run._queue.size()
	check(queued_before > 0, "with more inbound (%d)" % queued_before)
	# The press itself, through the button the board built: the wiring is the one
	# thing a direct call cannot prove.
	game.admin_console.open()
	var kills_before: int = int(run.total_kills)
	var kill_button := _find_button(game.admin_console._left, "KILL EVERYTHING")
	check(kill_button != null, "the arena board wires a kill press")
	if kill_button != null:
		kill_button.pressed.emit()
	check(run.live_mobs().is_empty(), "the press empties the field")
	check(run._queue.is_empty(), "and the inbound queue with it")
	check(int(run.total_kills) > kills_before, "the bodies are booked as kills (%d -> %d)"
		% [kills_before, int(run.total_kills)])
	run.tick(0.2)
	check(run.level_cleared, "the level clears with the field empty")
	var again: Dictionary = run.admin_kill_all()
	check(not bool(again.get("ok", true)), "a cleared level has nothing left to kill")
	game.admin_console.close()


func _check_catalogues() -> void:
	var player = run.players.get(1)
	check(player != null, "the run runtime is readable")
	if player == null:
		return
	# Every row the pool holds is one press away, and the row's own cap is still
	# the cap: the console is a shortcut, not a second rule.
	var started := int(player.engine.stacks_of("broadhead"))
	var grant: Dictionary = run.admin_grant_mod(1, "broadhead", 2)
	check(bool(grant.get("ok", false)), "the console grants an upgrade")
	check(int(player.engine.stacks_of("broadhead")) == started + 2, "two stacks land")
	var cap := Mods.max_stacks("broadhead")
	var fill: Dictionary = run.admin_grant_mod(1, "broadhead", 99)
	check(bool(fill.get("ok", false)), "a fill to the cap is taken")
	check(int(player.engine.stacks_of("broadhead")) == cap,
		"and stops at the row's own cap (%d)" % cap)
	var over: Dictionary = run.admin_grant_mod(1, "broadhead", 1)
	check(not bool(over.get("ok", true)), "a maxed row is refused")
	var nonsense: Dictionary = run.admin_grant_mod(1, "not_a_row", 1)
	check(not bool(nonsense.get("ok", true)), "an unknown row is refused")

	# A row the pool keeps but the loop does not offer yet is written anyway:
	# the chest can never do this, which is why the console exists.
	var inert := ""
	for raw in Mods.all():
		if not bool((raw as Dictionary).get("ready", true)):
			inert = str((raw as Dictionary).get("id", ""))
			break
	check(not inert.is_empty(), "the pool carries rows the loop does not offer yet")
	if not inert.is_empty():
		check(not Mods.ready_of(inert), "%s is one of them" % inert)
		var forced: Dictionary = run.admin_grant_mod(1, inert, 1)
		check(bool(forced.get("ok", false)), "the console writes it")
		check(int(player.engine.stacks_of(inert)) == 1, "and the engine holds the stack")
		check(str(forced.get("message", "")).contains("forced"), "the line says it was forced")

	# Weapons: opened on the player's own ledger, and worn in the hand the piece's
	# class belongs to.
	check(Weapons.has("sword_short"), "the shortsword is in the armory")
	check(not meta.is_unlocked("sword_short"), "and starts locked")
	var steel: Dictionary = run.admin_give_weapon(1, "sword_short")
	check(bool(steel.get("ok", false)), "the console opens and wears a weapon: %s"
		% str(steel.get("message", "")))
	check(meta.is_unlocked("sword_short"), "the piece is open on the player's ledger")
	check(str(player.melee_id) == "sword_short", "the run carries it in the melee hand")
	check(str(body.rig.weapon) != "bow", "and the body is holding steel")
	var bow: Dictionary = run.admin_give_weapon(1, "bow_short")
	check(bool(bow.get("ok", false)), "a bow opens too")
	check(str(player.ranged_id) == "bow_short", "and takes the ranged hand")
	check(str(body.rig.weapon) == "bow", "which puts the bow back in the body's hands")
	check(meta.is_unlocked("bow_short"), "the bow is open as well")

	# Abilities: the unlock is the player's, the equip is the body's.
	check(not AbilityRules.by_id("barrage").is_empty(), "Barrage is in the catalog")
	check(not meta.is_ability_unlocked("barrage"), "and starts locked")
	var skill: Dictionary = run.admin_give_ability(1, "barrage")
	check(bool(skill.get("ok", false)), "the console grants an ability")
	check(meta.is_ability_unlocked("barrage"), "the skill is open on the player's ledger")
	var merc := int(player.merc_id)
	check(game.warband.roster.hotbar_order_of(merc).has("barrage"),
		"and it is on the body's bar")
	check(str(skill.get("message", "")).contains("on the bar"), "the line says so")


func _check_gates_and_chests() -> void:
	check(run.level_cleared, "a cleared level is what stands the gates")
	var gates := _count_props("portal")
	check(gates == DirectorScript.GATES.size(), "the clear stood three gates (%d)" % gates)
	var labels_before := _gate_labels()
	var restood: Dictionary = run.admin_stand_gates(false)
	check(bool(restood.get("ok", false)), "the console re-stands the gates")
	check(_count_props("portal") == DirectorScript.GATES.size(), "and exactly three stand")
	var rolled: Dictionary = run.admin_stand_gates(true)
	check(bool(rolled.get("ok", false)), "the console rolls the gates")
	check(int(run._gate_salt) == 1, "the roll moves the route seed")
	check(_count_props("portal") == DirectorScript.GATES.size(), "and three fresh gates stand")
	var labels_after := _gate_labels()
	check(labels_after != labels_before, "the rolled board is a different board (%s -> %s)"
		% [str(labels_before), str(labels_after)])

	# The chest: re-stood with its own three cards, and rolled onto the promise
	# the level is now paid by.
	var boxes := _count_props("chest")
	check(boxes >= 1, "the clear stood a box a soul (%d)" % boxes)
	var before_promise := str(run._active_chest_spec().get("surface", "")) + "/" \
		+ str(run._active_chest_spec().get("tier", ""))
	var restood_chest: Dictionary = run.admin_stand_chests(false)
	check(bool(restood_chest.get("ok", false)), "the console re-stands the chest")
	check(_count_props("chest") == boxes, "with as many boxes as the promise stands (%d)"
		% _count_props("chest"))
	check(_dealt_rows() >= 3, "and a fresh box deals three cards again")
	var rolled_chest: Dictionary = run.admin_stand_chests(true)
	check(bool(rolled_chest.get("ok", false)), "the console rolls the chest")
	check(str(run._active_chest_spec().get("surface", "")) == str(rolled_chest.get("surface", "")),
		"the contract now names the surface the chest shows")
	check(str(run._active_chest_spec().get("tier", "")) == str(rolled_chest.get("tier", "")),
		"and the tier it was rolled at")
	var after_promise := str(run._active_chest_spec().get("surface", "")) + "/" \
		+ str(run._active_chest_spec().get("tier", ""))
	check(not after_promise.is_empty(), "the promise is written (%s -> %s)"
		% [before_promise, after_promise])
	check(_dealt_rows() >= 3, "the rolled boxes deal their own cards")


func _check_travel() -> void:
	var jump: Dictionary = run.admin_goto_level(11)
	check(bool(jump.get("ok", false)), "the console jumps floors")
	check(int(run.level) == 11, "level 11 is live (%d)" % int(run.level))
	check(int(run.stage_index) == 1, "and the depth block moved with it (%d)" % int(run.stage_index))
	check(run.stage != null and is_instance_valid(run.stage), "a fresh island was built")
	check(int(run.stage.stage_index) == 1, "the stage is the second block's own")
	check(bool(run.wave_active), "and the floor's wave is opening")
	var back: Dictionary = run.admin_goto_level(3)
	check(int(run.level) == 3 and int(run.stage_index) == 0,
		"level 3 is back on the first island (%d/%d)" % [int(run.level), int(run.stage_index)])
	var boss: Dictionary = run.admin_goto_level(10)
	check(int(run.level) == 10 and bool(run.boss_level), "level 10 opens a boss")
	var town: Dictionary = run.admin_goto_town()
	check(bool(town.get("ok", false)), "the console walks the party home")
	check(not run.is_running(), "the run closes")
	check(run.players.is_empty(), "and no runtime is left bound")
	check(body.bounds < 2000.0, "the world's own bound is back (%0.1f)" % body.bounds)
	var again: Dictionary = run.admin_goto_town()
	check(bool(again.get("ok", false)), "calling it in the square is harmless")
	check(str(again.get("message", "")).contains("Hearthstead"), "and says where the party is")
	# The square is a floor too: a piece opens and is worn out of a run, on the
	# body's own roster kit rather than on an island.
	var square: Dictionary = run.admin_give_weapon(1, "dagger_iron")
	check(bool(square.get("ok", false)), "a weapon opens from the square as well")
	check(meta.is_unlocked("dagger_iron"), "the piece is the player's own")
	check(game.warband.stash.owns("dagger_iron", game.warband.roster),
		"and is forged into the warband's hands")


## The three catalogues, read off the console's own boards: every row the run can
## be built from is listed, and the filter narrows the list rather than lying
## about it.
func _check_boards() -> void:
	var console = game.admin_console
	console.open()
	console._on_tab("upgrades")
	check(console._list.get_child_count() == Mods.all().size(),
		"the upgrade board lists the whole pool (%d of %d)"
		% [console._list.get_child_count(), Mods.all().size()])
	console._on_search_changed("broadhead")
	check(console._list.get_child_count() >= 1 and console._list.get_child_count()
		< Mods.all().size(), "the filter narrows the board (%d)"
		% console._list.get_child_count())
	console._on_search_changed("")
	check(console._list.get_child_count() == Mods.all().size(), "and clearing it restores it")
	console._on_tab("weapons")
	check(console._list.get_child_count() == Weapons.all_ids().size(),
		"the weapon board lists the whole armory (%d of %d)"
		% [console._list.get_child_count(), Weapons.all_ids().size()])
	console._on_group_selected(2)
	check(console._list.get_child_count() < Weapons.all_ids().size(),
		"and its hand filter narrows it (%d)" % console._list.get_child_count())
	console._on_tab("abilities")
	check(console._list.get_child_count() == AbilityRules.catalog_ids().size(),
		"the ability board lists the whole catalog (%d of %d)"
		% [console._list.get_child_count(), AbilityRules.catalog_ids().size()])
	check(bool(console._filter.visible), "the catalogues show their filter row")
	console._on_tab("arena")
	check(not bool(console._filter.visible), "the arena board hides it again")
	console.close()
	check(not console.is_open(), "the console shuts")


## The first button under `node` wearing `text`, the way a player finds it: by
## reading the board.
func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and str((child as Button).text) == text:
			return child
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _count_props(kind: String) -> int:
	var count := 0
	for prop in run._props:
		if is_instance_valid(prop) and Props.prop_kind(prop) == kind:
			count += 1
	return count


## The three lintels' promises, as the party reads them.
func _gate_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for prop in run._props:
		if not is_instance_valid(prop) or Props.prop_kind(prop) != "portal":
			continue
		out.append(str(Props.payload_of(prop).get("label", "")))
	out.sort()
	return out


## How many cards the freshest box deals its owner.
func _dealt_rows() -> int:
	var best := 0
	for serial in run.draft_offers:
		var table: Dictionary = run.draft_offers[serial]
		for peer in table:
			best = maxi(best, (table[peer] as Array).size())
	return best
