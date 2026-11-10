extends SceneTree
## The ability layer after the family pass: eight free starters, 40 tagged
## ability upgrades, and the engine reads that make those rows real. Pure
## systems only: no world, no mobs, no run director.

const AbilityRules = preload("res://scripts/ability_rules.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const ProcEngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const RunPlayerScript = preload("res://scripts/roguelite/run_player.gd")
const SpellProjectile = preload("res://scripts/spell_projectile.gd")
const AbilityRunner = preload("res://scripts/ability_runner.gd")
const State = preload("res://scripts/player_state.gd")

var checks := 0
var failures := 0


class DummyTarget extends StaticBody3D:
	var alive := true


class BlockRig extends RefCounted:
	var shield_equipped := true
	var weapon := "bow"
	var staff_active := false
	var run_rate_scale := 1.0
	var bow_draw_scale := 1.0
	var bow_no_nock := false


class BlockCombat extends RefCounted:
	var blocking := false


class BlockBody extends Node:
	var rig = BlockRig.new()
	var combat = BlockCombat.new()
	var max_health := 100.0
	var health := 100.0
	var roguelite
	var roguelite_hold_downed := false
	var alive := true


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ABILITY_UPGRADES_FAIL  ", message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_starters()
	_check_catalog()
	_check_tagged_stats()
	_check_melee_requests()
	_check_run_plans()
	await _check_spell_bounce()
	_check_passive_block()
	_check_recast_token()
	print("ABILITY_UPGRADES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _check_starters() -> void:
	check(AbilityRules.STARTER_BY_FAMILY.size() == 8,
		"eight families carry a free starter")
	check(AbilityRules.catalog_ids().size() == 36,
		"36 active skills: 29 base + 6 new family starters + Fire Ray (%d)"
		% AbilityRules.catalog_ids().size())
	check(AbilityRules.unlockable_ids().size() == 28,
		"the 28 purchased skills are unchanged")
	for family in AbilityRules.STARTER_BY_FAMILY:
		var id := str(AbilityRules.STARTER_BY_FAMILY[family])
		check(AbilityRules.is_automatic(id) and AbilityRules.is_starter(id),
			"%s is automatic and is a starter" % id)
		check(not AbilityRules.unlockable_ids().has(id),
			"%s is never sold" % id)
	var bow := AbilityRules.starter_ids_for_gear(State.ITEMS["bow_short"], {})
	check(bow == ["snap_shot", "focus"],
		"a bow gets Snap Shot and Focus (%s)" % str(bow))
	var great := AbilityRules.starter_ids_for_gear(State.ITEMS["sword_great"], {})
	check(great == ["heavy_swing", "focus"],
		"a greatsword gets only the two-hand starter (%s)" % str(great))
	var board := AbilityRules.starter_ids_for_gear(State.ITEMS["sword_short"],
		State.ITEMS["shield_kite"])
	check(board == ["quick_cut", "shield_shove", "focus"],
		"sword and board gets both family starters (%s)" % str(board))
	var bare := AbilityRules.starter_ids_for_gear({}, {})
	check(bare == ["charge", "focus"], "empty hands get Charge and Focus (%s)" % str(bare))
	check(AbilityRules.starter_ids_for_gear(State.ITEMS["staff_fire"], {})
		== ["fireball", "focus"], "a staff gets Fireball and Focus")


func _check_catalog() -> void:
	check(Mods.all().size() == 173,
		"the pool grew to 173 rows (%d)" % Mods.all().size())
	var ability_rows := 0
	for row in Mods.all():
		if str(row.family) != Mods.FAMILY_ABILITY:
			continue
		ability_rows += 1
		var id := str(row.id)
		var tags := Mods.tags_of(id)
		var verb := Mods.verb_of(id)
		check(not tags.is_empty() or not verb.is_empty(),
			"%s is categorized as a verb or a family" % id)
		check(bool(row.get("ready", true)) == (not tags.is_empty()),
			"%s is live when it is a family row" % id)
	check(ability_rows == 61, "61 ability rows: 19 verbs + 42 family (%d)" % ability_rows)
	check(Mods.tags_of("echo_cast") == ["any"], "Echo Cast is any-family")
	check(Mods.tags_of("spiral_shot") == ["bow"], "Spiral Shot is bow-only")
	check(Mods.verb_of("fleet_roll") == "roll", "Fleet Roll is a roll verb")
	check(Mods.family_label_of("spiral_shot") == "ABILITY  ·  BOW",
		"a family row names its ability tag (%s)" % Mods.family_label_of("spiral_shot"))
	check(Mods.family_label_of("fleet_roll") == "ABILITY  ·  ROLL",
		"a verb row names both its family and verb")
	for id in ["echo_cast", "spiral_shot", "whirlwind_edge", "guardians_instinct",
			"magical_nock"]:
		check(Mods.ready_of(id), "%s is offered" % id)


func _check_tagged_stats() -> void:
	var engine = ProcEngineScript.new(77, 1)
	engine.add_mod("echo_cast", 2)
	engine.add_mod("duelists_grace", 2)
	engine.add_mod("serrated_edge", 2)
	engine.add_mod("ricochet_rounds", 1)
	engine.add_mod("guardians_instinct", 3)
	check(engine.stat_for("bow", "ability_recast_chance") > 0.0,
		"Echo Cast reaches a bow")
	check(engine.stat_for("staff", "ability_recast_chance") > 0.0,
		"and a staff")
	check(engine.stat_for("sword", "ability_cooldown_mult") < 0.0,
		"Duelist's Grace reaches a sword")
	check(is_zero_approx(engine.stat_for("bow", "ability_cooldown_mult")),
		"but not a bow")
	check(engine.stat_for("sword", "bleed_chance") > 0.0,
		"Serrated Edge reaches a sword")
	check(is_zero_approx(engine.stat_for("bow", "bleed_chance")),
		"not a bow")
	check(engine.stat_for("staff", "projectile_bounce") > 0.0,
		"Ricochet Rounds reaches a staff (ranged)")
	check(is_zero_approx(engine.stat_for("sword", "projectile_bounce")),
		"not a sword")
	engine.add_mod("heavy_robes", 1)
	check(absf(engine.stat("melee_damage_mult") + 0.25) < 0.001,
		"Heavy Robes pays 25% melee")
	check(absf(engine.stat_for("staff", "spell_damage_mult") - 0.1) < 0.001,
		"and pays 10% spell damage")
	check(engine.stat_for("shield", "passive_block_chance") > 0.0,
		"Guardian's Instinct reaches a shield")
	check(is_zero_approx(engine.stat_for("bow", "passive_block_chance")),
		"not a bow")
	# The tagged chance is curved, not counted: more stacks approach the cap.
	var small = ProcEngineScript.new(77, 1)
	small.add_mod("guardians_instinct", 1)
	var big = ProcEngineScript.new(77, 1)
	big.add_mod("guardians_instinct", 5)
	check(big.stat_for("shield", "passive_block_chance")
		> small.stat_for("shield", "passive_block_chance"),
		"the block chance grows with stacks")
	check(big.stat_for("shield", "passive_block_chance") <= 0.75,
		"and never passes its 75% cap")


func _check_melee_requests() -> void:
	var engine = ProcEngineScript.new(4242, 1)
	engine.add_mod("bloodletting", 5)
	engine.add_mod("bloodstorm", 3)
	engine.add_mod("whirling_fury", 4)
	engine.add_mod("broad_arc", 2)
	var target := DummyTarget.new()
	target.name = "Dummy"
	var saw_bleed := false
	var saw_whirl := false
	for _roll in 200:
		var ctx := {"kind": "melee", "target": target, "position": Vector3.ZERO,
			"damage": 50.0, "crit": false, "family": "two_hand", "is_melee": true,
			"proc": 1.0}
		for request in engine.on_hit(ctx):
			if str(request.get("kind", "")) == "bleed":
				saw_bleed = true
			if str(request.get("kind", "")) == "whirlwind":
				saw_whirl = true
		if saw_bleed and saw_whirl:
			break
	check(saw_bleed, "a bleed row answers a melee hit with a bleed")
	check(saw_whirl, "a whirlwind row answers a melee hit with a whirlwind")
	check(engine.stat_for("two_hand", "ability_cleave") >= 2.0,
		"cleave rows stack on the two-hand family")
	target.free()


func _check_run_plans() -> void:
	var caster = RunPlayerScript.new()
	caster.bind(null, null, 1, -1, "bow_twig", "hatchet_makeshift")
	for id in ["focused_force", "focused_force", "focused_force",
			"quickening", "quickening", "split_fletching", "split_fletching",
			"bouncing_arrows", "bouncing_arrows", "spiral_shot",
			"double_nock", "double_nock", "double_nock", "double_nock",
			"quick_draw", "quick_draw", "arcane_focus", "arcane_focus",
			"ricochet_rounds", "magical_nock"]:
		caster.engine.add_mod(id, 1)
	check(caster.ability_damage_multiplier("bow") > 1.0,
		"Focused Force raises bow ability damage")
	check(caster.ability_cooldown_scale("bow") < 1.0,
		"Quickening shortens the cooldown")
	check(caster.ability_arrow_split("bow") == 2,
		"Split Fletching adds two shafts")
	check(caster.ability_bounces("bow") >= 3,
		"Bouncing Arrows and Ricochet Rounds stack bounces")
	check(caster.ability_spiral("bow"), "Spiral Shot marks the arrow")
	check(caster.bow_draw_scale() > 1.0, "Quick Draw shortens the draw")
	check(caster.bow_no_nock(), "Magical Nock reaches the run's bow as the no-nock flag")
	var plan: Dictionary = caster.fire_plan(Vector3.ZERO, Vector3.FORWARD)
	check(int(plan.get("arrow_split", 0)) == 2,
		"the fire plan carries the split shafts")
	check(int(plan.get("shots", 1)) >= 3,
		"the fire plan counts them (%d)" % int(plan.get("shots", 1)))
	check(bool(plan.get("spiral", false)), "the fire plan carries the spiral")
	check(int(plan.get("ricochet", 0)) >= 3,
		"the fire plan carries the bounces")
	var spell: Dictionary = caster.spell_plan(20.0, "staff")
	check(float(spell.get("damage", 0.0)) > 20.0,
		"Arcane Focus raises spell damage (%.1f)" % float(spell.get("damage", 0.0)))
	check(int(spell.get("bounces", 0)) >= 1,
		"Ricochet Rounds reaches a staff cast")
	caster.free()


func _check_spell_bounce() -> void:
	var spell = SpellProjectile.new()
	var first := DummyTarget.new()
	first.name = "First"
	var second := DummyTarget.new()
	second.name = "Second"
	second.position = Vector3(0.0, 0.0, -4.0)
	var holder := Node3D.new()
	holder.add_child(first)
	holder.add_child(second)
	spell.velocity = Vector3.ZERO
	spell.process_mode = Node.PROCESS_MODE_DISABLED
	holder.add_child(spell)
	root.add_child(holder)
	await process_frame
	spell.damage = 30.0
	spell.velocity = Vector3(0.0, 0.0, -10.0)
	spell.bounces = 1
	spell.bounce_scale = 0.5
	spell.bounce_provider = func(_at: Vector3, _taken: Dictionary, _reach: float):
		return second
	var bounced := spell._try_bounce(first, first.global_position)
	check(bounced, "a spell with a bounce budget folds to the next body")
	check(spell.bounces == 0, "the bounce is spent")
	check(absf(spell.damage - 15.0) < 0.001, "and the hop pays half")
	spell.free()
	holder.free()


func _check_passive_block() -> void:
	var body := BlockBody.new()
	var caster = RunPlayerScript.new()
	caster.bind(body, null, 1, -1, "bow_twig", "hatchet_makeshift")
	for id in ["guardians_instinct", "guardians_instinct", "guardians_instinct",
			"guardians_instinct", "guardians_instinct", "bulwark", "bulwark",
			"bulwark", "bulwark", "shield_wall", "shield_wall", "shield_wall"]:
		caster.engine.add_mod(id, 1)
	var blocked := false
	var hurt := false
	for _roll in 120:
		var answer: Dictionary = caster.filter_incoming(10.0, -1)
		if bool(answer.get("blocked", false)):
			blocked = true
		else:
			hurt = true
		if blocked and hurt:
			break
	check(blocked, "a shield with passive-block rows turns a blow while lowered")
	check(hurt, "and still lets some blows through")
	check(caster.engine.stat_for("shield", "passive_block_chance")
		<= 0.75, "the passive block stays under its 75% cap")
	caster.free()
	body.free()


func _check_recast_token() -> void:
	var runner = AbilityRunner.new()
	runner.recast_pending = true
	check(runner.take_recast(), "a recast token pays once")
	check(not runner.take_recast(), "and only once")
	runner.free()
