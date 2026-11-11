class_name RunPlayer
extends Node
## One player's run: the mods they carry, the numbers those mods produce, and the
## translation of the proc engine's decisions into effects the island can spawn.
##
## A `RoguelitePlayer` is created by the run director for each body that enters
## the portal and lives as a child of the world for the length of the run. It is
## the body's *second* brain: `WarbandBody` still owns health, downing and the
## rig, and this node owns only what the arena loop adds on top. The body reaches
## it through `body.roguelite`, and the four hook sites in the engine
## (`note_attack_landed`, `take_damage`, a shot's `on_hit`, the world's fire
## callback) are the only places the two touch.
##
## It rolls nothing for damage itself. `RogueliteProcEngine` decides; this node
## asks, and hands the answers to the director to execute. What it does own is
## the *state* a row's condition reads - health, purse, kills, islands, whether
## the body is planted - because that state lives here and nowhere else.

const EngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const State = preload("res://scripts/player_state.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")

## How often the standing bleed of Slippery Slope is applied. One tick per frame
## would be a hundred tiny damage numbers; four a second reads as a bleed.
const DRAIN_TICK := 0.25
## The same cadence for the standing aura, a deferred wound and a zone's tick.
const EFFECT_TICK := 0.25
## How long a kill's own buffs last: Ring Of Fury, Adrenaline Amulet.
const KILL_WINDOW := 4.0
## How still a body counts as planted for Steady Draw.
const PLANTED_SPEED := 0.6
## How much of a body's pool one blow may take as a floor, so Bribe and Damage
## Seeker can hurt without ever deleting the body outright.
const MIN_POOL := 25.0

var body = null
var director = null
var peer_id := 1
var merc_id := -1
var engine
var ranged_id := ""
var melee_id := ""
var ranged_profile: Dictionary = {}
var melee_profile: Dictionary = {}
var kills := 0
## Islands finished. Gemstone and Turbo Ring read it, and Level Up pays it out.
var islands := 0
## Set when a Greed mod has locked the hands for the rest of the run.
var hands_locked := false
## The pieces a chest has put on this body, one per slot: `{slot: piece}`, where
## a piece is `{slot, set, item_id, name, level, mods}`. Empty until the first
## chest hands one out, and the roster's own kit is what the rig wears until
## then - `run_director._dress_weapon` merges this table over it. The run owns
## these; the campaign's armour is never written.
var armor: Dictionary = {}
## Which slot the body is holding: `"ranged"` or `"melee"`. TAB flips it.
var _active_slot := "ranged"

var _base_max_health := 100.0
## Pool taken for the rest of the run by Damage Seeker. It is subtracted from the
## recomputed pool, so the next upgrade never hands the points back.
var _pool_debt := 0.0
var _drain_clock := 0.0
var _effect_clock := 0.0
## Seconds into the live level, for Regenerator's own window.
var _level_clock := 0.0
## Whether the wave was live on the last frame: the edge restarts the window.
var _wave_live := false
## Seconds left on the kill-triggered buffs.
var _damage_window := 0.0
var _rate_window := 0.0
## A deferred melee wound: `{target, left, total, source}` per hit.
var _wounds: Array = []


func bind(owner_body, run_director, owner_peer: int, owner_merc: int,
		ranged_weapon: String, melee_weapon: String) -> void:
	body = owner_body
	director = run_director
	peer_id = maxi(1, owner_peer)
	merc_id = owner_merc
	name = "RoguelitePlayer%d" % peer_id
	ranged_id = ranged_weapon
	melee_id = melee_weapon
	_set_profiles()
	if body != null:
		body.roguelite = self
		body.roguelite_hold_downed = true
		_base_max_health = body.max_health
	var seed_value := 0
	if director != null:
		seed_value = int(director.get("run_seed"))
	engine = EngineScript.new(seed_value, peer_id)
	apply_stats()


func _set_profiles() -> void:
	# An empty hand has an empty profile: the run reads what the body's kit
	# carries, and never invents a starter the inventory does not hold.
	ranged_profile = Weapons.resolve(ranged_id)
	melee_profile = Weapons.resolve(melee_id)


func unbind() -> void:
	if body != null and is_instance_valid(body):
		body.roguelite = null
		body.roguelite_hold_downed = false
		if is_instance_valid(body.rig):
			body.rig.run_rate_scale = 1.0
			# The extra keys were the run's: a body back in the square fires the
			# five the game ships with again.
			body.rig.ability_extra_slots = 0
		body = null
	director = null


func _physics_process(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	if engine != null:
		engine.advance(delta)
	# Regenerator's window is per level, so the clock restarts when a wave opens
	# rather than when the last one closed.
	var live := director != null and bool(director.get("wave_active"))
	if live and not _wave_live:
		_level_clock = 0.0
	_wave_live = live
	if live:
		_level_clock += delta
	_damage_window = maxf(0.0, _damage_window - delta)
	_rate_window = maxf(0.0, _rate_window - delta)
	_apply_rate()
	_apply_standing_drain(delta)
	_apply_regen(delta)
	_tick_effects(delta)


## The rig reads one rate scale. Which profile it belongs to follows the hands:
## a bow or a staff is the ranged profile, a blade is the melee one.
func _apply_rate() -> void:
	var rig = body.get("rig")
	if rig == null or not is_instance_valid(rig):
		return
	var profile := melee_profile
	var weapon := str(rig.get("weapon"))
	var melee := not (weapon == "bow" or weapon == "staff")
	if not melee:
		profile = ranged_profile
	var scale: float = engine.melee_attack_scale() if melee else engine.attack_scale()
	var want: float = scale * timed_rate_multiplier() \
		* float(profile.get("attack_mult", 1.0))
	if absf(float(rig.run_rate_scale) - want) > 0.0001:
		rig.run_rate_scale = want
	if weapon == "bow":
		var draw := bow_draw_scale()
		if absf(float(rig.get("bow_draw_scale")) - draw) > 0.0001:
			rig.bow_draw_scale = draw
		rig.bow_no_nock = bow_no_nock()


## Slippery Slope: a body that plants its feet in a live wave bleeds. The drain
## is a share of the *pool*, not of current health, so it is a clock a player can
## read rather than a spiral.
func _apply_standing_drain(delta: float) -> void:
	if engine == null or body == null:
		return
	var drain: float = float(engine.stat("standing_drain"))
	if drain <= 0.0:
		return
	if director == null or not bool(director.get("wave_active")):
		_drain_clock = 0.0
		return
	var alive := _flag(body, "alive", true) and not _flag(body, "downed", false)
	if not alive:
		return
	var velocity: Vector3 = body.velocity if body is CharacterBody3D else Vector3.ZERO
	if Vector2(velocity.x, velocity.z).length() > PLANTED_SPEED:
		_drain_clock = 0.0
		return
	_drain_clock += delta
	while _drain_clock >= DRAIN_TICK:
		_drain_clock -= DRAIN_TICK
		var bite: float = maxf(1.0, float(body.max_health) * drain * DRAIN_TICK)
		body.health = maxf(0.0, float(body.health) - bite)
		if float(body.health) <= 0.001:
			if body.has_method("enter_downed"):
				body.enter_downed(-1)
			return


## Regenerator: a slow mending for the first `regen_window` seconds of a wave, and
## nothing at all under Bloodthirst, which is the row's whole bargain.
func _apply_regen(delta: float) -> void:
	if engine == null or body == null:
		return
	var rate: float = engine.stat("regen_hp_per_s")
	if rate <= 0.0 or engine.has_flag("bloodthirst"):
		return
	if director == null or not bool(director.get("wave_active")):
		return
	if _level_clock > engine.stat("regen_window"):
		return
	if not _flag(body, "alive", true) or _flag(body, "downed", false):
		return
	heal(rate * delta)


## The standing aura, the deferred melee wounds and any timed row that has to
## touch the world: one quarter-second, one loop.
func _tick_effects(delta: float) -> void:
	_effect_clock += delta
	if _effect_clock < EFFECT_TICK:
		return
	var step := _effect_clock
	_effect_clock = 0.0
	_apply_aura(step)
	_tick_wounds(step)


func _apply_aura(step: float) -> void:
	if engine == null or director == null or body == null:
		return
	var dps: float = engine.stat("aura_damage")
	if dps <= 0.0:
		return
	var radius: float = engine.stat("aura_radius")
	var at: Vector3 = (body as Node3D).global_position
	for mob in director.live_mobs():
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if (mob as Node3D).global_position.distance_to(at) > radius:
			continue
		if mob.has_method("take_damage"):
			mob.take_damage(dps * step, int(body.get("slot")), false)


func _tick_wounds(step: float) -> void:
	if _wounds.is_empty():
		return
	var keep: Array = []
	for wound in _wounds:
		var entry: Dictionary = wound
		var target = entry.get("target")
		var left := float(entry.get("left", 0.0))
		if left <= 0.0 or target == null or not is_instance_valid(target):
			continue
		if target.get("alive") == false:
			continue
		var tick: float = minf(left, float(entry.get("total", 0.0))
			/ maxf(0.01, float(entry.get("delay", 1.0))) * step)
		if tick <= 0.0:
			continue
		if target.has_method("take_damage"):
			target.take_damage(tick, int(entry.get("source", -1)), false)
		entry["left"] = left - tick
		if float(entry["left"]) > 0.0001:
			keep.append(entry)
	_wounds = keep


# --- the numbers -----------------------------------------------------------

func apply_stats() -> void:
	if body == null or not is_instance_valid(body) or engine == null:
		return
	var factor: float = float(engine.health_factor()) + float(engine.stat("max_hp_flat")) / maxf(_base_max_health, 1.0)
	var pool := maxf(MIN_POOL, _base_max_health * factor - _pool_debt)
	if absf(float(body.max_health) - pool) > 0.01:
		body.max_health = pool
		body.health = minf(float(body.health), pool)
	_apply_rate()
	_apply_bar_keys()


## The keys a run's own upgrades bought this body. The bar is the rig's, so the
## figure rides on the rig and `AbilityRules.granted` lays the row out to it: a
## legendary slot upgrade is a key the fight can fire, not a promise on a screen.
## The ceiling is `AbilityRules.MAX_SLOT_COUNT` minus the five the game ships with.
func _apply_bar_keys() -> void:
	if body == null or not is_instance_valid(body) or engine == null:
		return
	var rig = body.get("rig")
	if rig == null or not is_instance_valid(rig):
		return
	var bonus := clampi(int(engine.stat("hotbar_slots")), 0,
		AbilityRules.MAX_SLOT_COUNT - AbilityRules.SLOT_COUNT)
	var raw: Variant = rig.get("ability_extra_slots")
	var have := int(raw) if raw is int or raw is float else 0
	if have == bonus:
		return
	rig.set("ability_extra_slots", bonus)


## Every multiplier that does not need to know what it is hitting: the rows with
## a counter behind them - health carried, gold in the purse, bodies put down,
## islands cleared, stacks held - all add on top of the flat damage rows.
func damage_multiplier() -> float:
	if engine == null:
		return 1.0
	return engine.damage_multiplier() * conditional_multiplier() \
		* timed_damage_multiplier()


func conditional_multiplier() -> float:
	if engine == null or body == null:
		return 1.0
	var add: float = 0.0
	var hp := float(body.health)
	var pool := maxf(1.0, float(body.max_health))
	if hp >= pool * 0.75:
		add += engine.stat("damage_high_hp_mult")
	add += engine.stat("damage_per_hp") * (hp / 10.0)
	add += engine.stat("damage_per_gold") * (float(_gold()) / 100.0)
	add += engine.stat("damage_per_kill") * (float(kills) / 20.0)
	add += engine.stat("damage_per_island") * float(islands)
	add += engine.stat("damage_per_stack") * float(engine.total_stacks())
	add += engine.stat("damage_per_mark") * float(engine.mark_kinds())
	if _planted():
		add += engine.stat("damage_planted_mult")
	return maxf(0.0, 1.0 + add)


## Danger Close and Eagle Eye: the only two rows that need the range to the body
## the blow is landing on, which is why they are a filter at contact and not a
## number at the shot.
func proximity_multiplier(at: Vector3) -> float:
	if engine == null or body == null or not is_instance_valid(body):
		return 1.0
	var distance: float = (body as Node3D).global_position.distance_to(at)
	var add: float = 0.0
	if distance <= engine.stat("close_range"):
		add += engine.stat("damage_close_mult")
	if distance >= engine.stat("far_range"):
		add += engine.stat("damage_far_mult")
	return maxf(0.0, 1.0 + add)


func damage_filter() -> Callable:
	return Callable(self, "proximity_multiplier")


func timed_damage_multiplier() -> float:
	if engine == null:
		return 1.0
	var add: float = 0.0
	if _damage_window > 0.0:
		add += engine.stat("damage_on_kill")
	return maxf(0.0, 1.0 + add)


func timed_rate_multiplier() -> float:
	if engine == null:
		return 1.0
	var add: float = engine.stat("attack_per_island") * float(islands)
	if _rate_window > 0.0:
		add += engine.stat("attack_on_kill")
	return maxf(0.0, 1.0 + add)


func move_scale() -> float:
	return 1.0 if engine == null else engine.move_scale()


## The Speed chest's whole business: the walk's own scale and the tuning the
## roll, the grounded side step and the sprint slide ask for. It hands back the
## engine's own aggregate rather than a copy, so a body tuning itself every frame
## allocates nothing; the keys are the surface's own list in `mod_catalog.gd`.
func movement() -> Dictionary:
	if engine == null:
		return {}
	return engine.stats()


func melee_reach() -> float:
	return 0.0 if engine == null else engine.stat("melee_reach")


## Slow Cut's ransom: the wound is held, not paid on the blade's own frame.
func wound_delay() -> float:
	return 0.0 if engine == null else engine.stat("melee_delay")


func defer_wound(target, amount: float) -> void:
	var delay := wound_delay()
	if delay <= 0.0 or target == null or not is_instance_valid(target) or amount <= 0.0:
		return
	_wounds.append({"target": target, "left": amount, "total": amount,
		"delay": delay, "source": int(body.get("slot")) if body != null else -1})


func _planted() -> bool:
	if body == null or not (body is CharacterBody3D):
		return false
	var velocity: Vector3 = body.velocity
	return Vector2(velocity.x, velocity.z).length() <= PLANTED_SPEED


func _gold() -> int:
	if director == null:
		return 0
	return int(director.gold())


func currency_multiplier() -> float:
	return maxf(0.0, 1.0 + engine.stat("currency_mult"))


func proc_multiplier() -> float:
	return engine.proc_multiplier()


func luck() -> int:
	return 0 if engine == null else engine.luck()


func hands_locked_now() -> bool:
	return hands_locked


## Bloodthirst's contract: nothing mends a body between fights. The body asks
## this before a bandage, a potion or its own slow regen pays a point.
func blocks_passive_healing() -> bool:
	return engine != null and engine.has_flag("bloodthirst")


func is_downed() -> bool:
	return body == null or not is_instance_valid(body) or _flag(body, "downed", false) or not _flag(body, "alive", true)


func heal(amount: float) -> void:
	if body == null or not is_instance_valid(body) or amount <= 0.0:
		return
	# Bloodthirst turns off the passive heals, never the ones a cut pays for:
	# the gore lifesteal and the harvest are exactly what it leaves standing.
	body.health = minf(float(body.max_health), float(body.health) + amount)


# --- the chest's draft -----------------------------------------------------

## The ability-family tags this body can use right now: its held family, the
## group that family belongs to, and the any-hand wildcard. A chest asks for this
## so a bow is never handed a staff-only card.
func carrier_tags() -> Array[String]:
	var out: Array[String] = []
	var rig = body.get("rig") if body != null and is_instance_valid(body) else null
	if rig != null and is_instance_valid(rig):
		for family in AbilityRules.starter_families(rig):
			if not out.has(family):
				out.append(family)
			if family in ["sword", "two_hand", "dagger", "shield", "unarmed"]:
				if not out.has("melee"):
					out.append("melee")
			elif family in ["bow", "staff"]:
				if not out.has("ranged"):
					out.append("ranged")
	if not out.has("any"):
		out.append("any")
	return out


## Every row this body cannot take again: the ones already at their ceiling. A
## promise asks for this before it is made, so the chest it stands can still fill
## this body's hand.
func maxed_mods() -> Array[String]:
	var out: Array[String] = []
	if engine == null:
		return out
	for id in engine.stacks:
		if int(engine.stacks[id]) >= Mods.max_stacks(str(id)):
			out.append(str(id))
	return out


## The chest's own row: `count` legal cards off the promise the gate named, never
## a row already at its ceiling, and never fewer than a choice - a bare shelf is
## topped up at the promised tier rather than left empty. Three cards, one more
## per `Big Chests` stack and one fewer per `Hoarder`, and the body picks one: the
## chest does not hand it a random row.
func chest_draft(chest_surface: String, tier: String, count: int = 0) -> Array[String]:
	var total := count if count > 0 else 3 + int(round(engine.stat("chest_offers")))
	return Mods.deal(engine.rng, Mods.promise(chest_surface, tier),
		maxi(1, total), maxed_mods(), carrier_tags())


func take_mod(mod_id: String) -> Dictionary:
	if engine == null:
		return {"ok": false, "message": "This body has no run."}
	if not Mods.has(mod_id):
		return {"ok": false, "message": "That is not a mod."}
	if not Mods.ready_of(mod_id):
		return {"ok": false, "message": "%s is not in the pool yet." % Mods.name_of(mod_id)}
	if not Mods.row_fits_carrier(mod_id, carrier_tags()):
		return {"ok": false, "message": "%s does not fit this body's hands." % Mods.name_of(mod_id)}
	if int(engine.stacks.get(mod_id, 0)) >= Mods.max_stacks(mod_id):
		return {"ok": false, "message": "%s is already at its ceiling." % Mods.name_of(mod_id)}
	if not engine.add_mod(mod_id):
		return {"ok": false, "message": "That mod will not take."}
	var flags: Dictionary = Mods.get_mod(mod_id).get("flags", {})
	if bool(flags.get("hands_locked", false)):
		hands_locked = true
	apply_stats()
	return {"ok": true, "id": mod_id, "name": Mods.name_of(mod_id),
		"message": "%s  ·  %s" % [Mods.name_of(mod_id), str(
			(Mods.get_mod(mod_id).get("description", "")))]}


# --- armour ----------------------------------------------------------------

## The piece this run is wearing in one slot, `{}` while the slot still wears the
## roster's own kit.
func armor_piece(slot: String) -> Dictionary:
	var raw: Variant = armor.get(slot, {})
	return raw if raw is Dictionary else {}


## Put a chest's piece on the body and take the modifiers welded to it. The piece
## is the run's, never the roster's: the campaign's kit is still hanging in the
## wardrobe when the portal spits the party back into the square. Answers the
## clean piece it kept - a row the engine refused is dropped from `mods` - so a
## guest can mirror exactly what landed on the host.
func wear_armor(piece: Dictionary) -> Dictionary:
	if engine == null:
		return {}
	var slot := str(piece.get("slot", ""))
	if not slot in ArmorData.SLOTS:
		return {}
	var set_index := clampi(int(piece.get("set", ArmorData.NONE)), 0,
		ArmorData.SET_IDS.size() - 1)
	var item_id := str(piece.get("item_id", ArmorData.item_id(set_index, slot)))
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var clean := {
		"slot": slot,
		"set": set_index,
		"item_id": item_id,
		"name": str(piece.get("name", item.get("name", slot.capitalize()))),
		"level": maxi(1, int(piece.get("level", 1))),
		"mods": [],
	}
	var raw: Variant = piece.get("mods", [])
	if raw is Array:
		for id in raw:
			if bool(take_mod(str(id)).get("ok", false)):
				clean["mods"].append(str(id))
	armor[slot] = clean
	var rig = body.get("rig") if body != null and is_instance_valid(body) else null
	if rig != null and is_instance_valid(rig) and rig.has_method("set_armor_piece"):
		rig.set_armor_piece(slot, set_index)
	return clean


# --- hooks called by the body and the world --------------------------------

## The ability family the body is swinging, read from the hands rather than the
## catalog id: a staff is staff even though the rig calls its mode "sword", and
## a two-hander is two_hand even though both hands hold a sword index.
func melee_family() -> String:
	if body == null or not is_instance_valid(body):
		return "melee"
	var rig = body.get("rig")
	if rig == null or not is_instance_valid(rig):
		return "melee"
	if bool(rig.get("staff_active")):
		return "staff"
	var weapon := str(rig.get("weapon"))
	if weapon == "bow":
		return "bow"
	if weapon == "dagger":
		return "dagger"
	if weapon in ["sword", "dual"]:
		if rig.has_method("swings_two_handed") and bool(rig.swings_two_handed()):
			return "two_hand"
		return "sword"
	return "unarmed"


func ability_damage_multiplier(family: String) -> float:
	if engine == null:
		return 1.0
	return maxf(0.0, 1.0 + engine.stat_for(family, "ability_damage_mult"))


func ability_cooldown_scale(family: String) -> float:
	if engine == null:
		return 1.0
	return maxf(0.1, 1.0 + engine.stat_for(family, "ability_cooldown_mult"))


func ability_recast_roll(family: String) -> bool:
	return engine != null and engine.chance_for(family, "ability_recast_chance")


func ability_stamina_scale(family: String) -> float:
	if engine == null:
		return 1.0
	return maxf(0.1, 1.0 + engine.stat_for(family, "ability_stamina_mult"))


func ability_cleave(family: String) -> int:
	return maxi(0, int(round(engine.stat_for(family, "ability_cleave")))) \
		if engine != null else 0


func ability_bounces(family: String) -> int:
	return maxi(0, int(round(engine.stat_for(family, "projectile_bounce")))) \
		if engine != null else 0


func ability_pierce(family: String) -> int:
	return maxi(0, int(round(engine.stat_for(family, "ability_pierce")))) \
		if engine != null else 0


func ability_homing(family: String) -> float:
	return engine.stat_for(family, "arrow_homing") if engine != null else 0.0


func ability_speed_scale(family: String) -> float:
	if engine == null:
		return 1.0
	return maxf(0.2, 1.0 + engine.stat_for(family, "ability_speed_mult"))


func ability_radius(family: String) -> float:
	return engine.stat_for(family, "ability_radius") if engine != null else 0.0


func ability_spiral(family: String) -> bool:
	return engine != null and engine.stat_for(family, "bow_spiral") > 0.0


func ability_arrow_split(family: String) -> int:
	return maxi(0, int(round(engine.stat_for(family, "arrow_split")))) \
		if engine != null else 0


func ability_extra_arrow(family: String) -> bool:
	return engine != null and engine.chance_for(family, "extra_arrow_chance")


func spell_damage_multiplier() -> float:
	if engine == null:
		return 1.0
	return maxf(0.0, 1.0 + engine.stat_for("staff", "spell_damage_mult"))


func bow_draw_scale() -> float:
	if engine == null:
		return 1.0
	return maxf(0.1, 1.0 + engine.stat_for("bow", "bow_draw_mult"))


func bow_no_nock() -> bool:
	return engine != null and engine.stat_for("bow", "bow_no_nock") > 0.0


func passive_block_roll() -> bool:
	return engine != null and engine.chance_for("shield", "passive_block_chance")


## A bow or a staff released. Answers the shot plan(s) the firing controllers
## execute: count, fan, size, speed, crit, pierce, ricochet, homing, proc.
func fire_plan(origin: Vector3, direction: Vector3) -> Dictionary:
	if engine == null:
		return {}
	var plan: Dictionary = engine.on_weapon_fire(ranged_profile, origin, direction)
	plan["damage_scale"] = float(plan.get("damage_scale", 1.0)) \
		* conditional_multiplier() * timed_damage_multiplier() \
		* ability_damage_multiplier("bow")
	var base_shots := maxi(1, int(plan.get("shots", 1)))
	var arrow_split := ability_arrow_split("bow")
	var extra := 1 if ability_extra_arrow("bow") else 0
	plan["split_shots"] = base_shots - 1
	plan["arrow_split"] = arrow_split
	plan["shots"] = base_shots + arrow_split + extra
	plan["pierce"] = int(plan.get("pierce", 0)) + ability_pierce("bow")
	plan["ricochet"] = int(plan.get("ricochet", 0)) + ability_bounces("bow")
	plan["homing"] = float(plan.get("homing", 0.0)) + ability_homing("bow")
	plan["speed"] = float(plan.get("speed", 1.0)) * ability_speed_scale("bow")
	plan["spiral"] = 4.0 if ability_spiral("bow") else 0.0
	return plan


## A shot's own landing, told to the engine's streak. Called by the arrow for both
## outcomes: a shaft that burns out without a body in it is the miss that wipes
## Hot Streak.
func note_shot_impact(enemy_hit: bool, _at: Vector3) -> void:
	if engine == null:
		return
	if not enemy_hit:
		engine.note_miss()


## One committed melee swing. The caller scales `state.damage` by the returned
## `damage_scale` and carries `crit` into the contact.
func melee_swing(forward: Vector3) -> Dictionary:
	if engine == null:
		return {"crit": false, "damage_scale": 1.0}
	var out: Dictionary = engine.on_melee_swing(melee_profile, forward)
	out["damage_scale"] = float(out.get("damage_scale", 1.0)) \
		* conditional_multiplier() * timed_damage_multiplier()
	# The swing's own effects - the crescent - leave at the moment the cut is
	# committed, not when it lands: `Combat` starts its sweep on the same frame
	# and a wave that waited for a contact would arrive behind the blade.
	# The profile's own weight rides the knockback too: a javelin throws a body
	# further than a knife even before a single Heavy Caliber is taken.
	out["knockback"] = float(out.get("knockback", 1.0)) \
		* float(melee_profile.get("gore", 1.0))
	out["reach"] = melee_reach()
	out["wound_delay"] = wound_delay()
	_execute(out.get("requests", []))
	return out


## A staff's bolt, planned by the ability runner: the same damage mods and crit a
## shot gets, expressed as the numbers the projectile needs. `family` is the
## ability's family so the tagged staff rows answer only for staff casts.
func spell_plan(base_damage: float, family: String = "staff") -> Dictionary:
	if engine == null:
		return {"damage": base_damage, "crit": false, "proc": 1.0}
	var rolled: Dictionary = engine.roll_crit()
	var crit := bool(rolled.get("crit", false))
	var mult := damage_multiplier() * ability_damage_multiplier(family)
	if family == "staff":
		mult *= spell_damage_multiplier()
	return {
		"damage": base_damage * mult * float(rolled.get("mult", 1.0)),
		"crit": crit,
		"proc": float(ranged_profile.get("proc", 1.0)) * proc_multiplier(),
		"bounces": ability_bounces(family),
		"pierce": ability_pierce(family),
		"speed": ability_speed_scale(family),
		"radius": ability_radius(family),
		"homing": ability_homing(family),
	}


## The projectile's `on_hit` for a run body: one callable per profile, so a blow
## knows which piece's coefficient it carried.
func hit_hook(profile: Dictionary = {}) -> Callable:
	var resolved := profile if not profile.is_empty() else ranged_profile
	return Callable(self, "projectile_hit").bind(resolved)


## A ranged projectile landed. Called from the arrow's own damage frame on the
## authority only.
func projectile_hit(target, at: Vector3, damage: float, crit: bool, proc: float,
		profile: Dictionary = {}) -> void:
	var resolved := profile if not profile.is_empty() else ranged_profile
	var ctx := {"kind": "ranged", "target": target, "position": at, "damage": damage,
		"crit": crit, "proc": proc, "profile": resolved, "is_melee": false}
	var requests: Array = engine.on_hit(ctx)
	_execute(requests)
	if target != null and is_instance_valid(target) and target.get("alive") == false:
		_kill(ctx)


## A melee blow landed. Called by `WarbandBody.note_attack_landed`, which the
## shared `Combat` resolver already calls for every cut, cleave and skill arc.
func melee_hit(target, hand: String, damage: float, crit: bool) -> void:
	var ctx := {"kind": "melee", "target": target,
		"position": target.global_position if target is Node3D else Vector3.ZERO,
		"damage": damage, "crit": crit, "hand": hand,
		"family": melee_family(),
		"proc": float(melee_profile.get("proc", 1.0)) * proc_multiplier(),
		"profile": melee_profile, "is_melee": true}
	var requests: Array = engine.on_hit(ctx)
	_execute(requests)
	if target != null and is_instance_valid(target) and target.get("alive") == false:
		_kill(ctx)


## A proc's own blow landed. It never rolls another proc, by construction: the
## fan-out is one deep.
func proc_hit(target, died: bool, damage: float) -> void:
	if died and target != null and is_instance_valid(target):
		_kill({"kind": "proc", "target": target,
			"position": target.global_position if target is Node3D else Vector3.ZERO,
			"damage": damage, "proc": 0.0, "is_melee": false})


func _kill(ctx: Dictionary) -> void:
	kills += 1
	# A kill is the trigger the temporary rows read: Ring Of Fury and Adrenaline
	# Amulet both start their window here.
	_damage_window = KILL_WINDOW
	_rate_window = KILL_WINDOW
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	# A body that lost its head or was opened in two counts as gibbed; the mob
	# classes carry that as the killing blow's own note (`_sever` for a head,
	# `_split` for a body cut in two), never as a boolean.
	var gibbed := false
	var target = ctx.get("target")
	if target != null and is_instance_valid(target):
		var sever: Variant = target.get("_sever")
		var split: Variant = target.get("_split")
		gibbed = (sever is Vector3 and (sever as Vector3) != Vector3.ZERO) or (split is Vector3 and (split as Vector3) != Vector3.ZERO)
	ctx["gibbed"] = gibbed
	var requests: Array = engine.on_kill(ctx)
	_execute(requests)
	if director != null:
		director.execute_effect(self, {"kind": "kill_credit", "target": target,
			"position": position, "gibbed": gibbed})


## A blow landing on this body, answered before the armour does its work.
func filter_incoming(amount: float, source_id: int) -> Dictionary:
	if engine == null:
		return {"dodged": false, "damage": amount}
	# A shield's passive guard: while the arm is not raised, the board can still
	# turn a blow. The roll is tagged `shield`, capped at 75% by its curve.
	if body != null and is_instance_valid(body):
		var rig = body.get("rig")
		var combat = body.get("combat")
		var raised := combat != null and is_instance_valid(combat) \
			and bool(combat.get("blocking"))
		if not raised and rig != null and is_instance_valid(rig) \
				and bool(rig.get("shield_equipped")) and passive_block_roll():
			return {"dodged": false, "damage": 0.0, "blocked": true}
	var answer: Dictionary = engine.on_player_damaged(amount, source_id)
	# Shockwave answers a blow that landed; Bribe and Damage Seeker take their
	# price in the same breath, which is what makes them bargains rather than
	# bookkeeping.
	_execute(answer.get("requests", []))
	if bool(answer.get("dodged", false)):
		return answer
	var pool_floor := float(engine.stat("max_hp_flat_on_hit"))
	if pool_floor < 0.0 and body != null:
		_pool_loss(-pool_floor)
	return answer


## Damage Seeker's own cost: three points off the pool for the rest of the run,
## floored so a carried row can never leave a body with nothing.
func _pool_loss(amount: float) -> void:
	if body == null or not is_instance_valid(body) or amount <= 0.0:
		return
	var floor_pool: float = maxf(MIN_POOL, _base_max_health * MIN_POOL / 100.0)
	var next: float = maxf(floor_pool, float(body.max_health) - amount)
	if absf(next - float(body.max_health)) <= 0.001:
		return
	_pool_debt += float(body.max_health) - next
	body.max_health = next
	body.health = minf(float(body.health), next)


func stage_clear() -> void:
	if engine == null:
		return
	islands += 1
	_level_clock = 0.0
	# One source of the clear heal: the engine's own `heal_on_clear`, which the
	# request below pays out. Bloodthirst is the one flag that switches it off,
	# and it says so at the engine so the two cannot disagree.
	_execute(engine.on_stage_clear(float(body.max_health) if body else 100.0,
		not engine.has_flag("bloodthirst")))


func revive_for_clear() -> bool:
	if body == null or not is_instance_valid(body):
		return false
	# The chest and the level's clear are the co-op contract for a soul: a
	# hireling whose ten seconds ran out is gone, and a box does not hire him back.
	if _flag(body, "expendable", false):
		return false
	if not _flag(body, "downed", false) or not _flag(body, "alive", true):
		return false
	body.revive_from_downed(0.5)
	return true


# --- execution -------------------------------------------------------------

static func _flag(object, key: String, fallback: bool = false) -> bool:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else bool(value)


func _execute(requests: Array) -> void:
	if requests.is_empty() or director == null:
		return
	for request in requests:
		director.execute_effect(self, request)
