extends SceneTree
## GHOST OF THE WARBAND - the 10% overkill rule, the DOWNED body, the backwards
## crawl and the human-only five second revive.
##
## Everything here runs on real `ArenaActor` bodies in a real scene tree and goes
## through the real damage funnels (`receive_melee` -> `take_damage`), because the
## rule being tested is where the damage lands, not what a helper returns. The
## crawl is driven by real physics frames, so a body that is not moved through its
## own collision cannot pass.

const Actor = preload("res://scripts/warband/warband_body.gd")
const Crawl = preload("res://scripts/warband/crawl_to_safety.gd")
const Revive = preload("res://scripts/warband/revive_channel.gd")
const Squad = preload("res://scripts/warband/squad_drive.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## A blow the victim did not land itself: `receive_melee` refuses `source == slot`.
const KILLER_SLOT := 7

var failures := 0
var checks := 0
var scene: Node3D
var _downed_starts := 0
var _downed_ends := 0
var _kill_slots: Array = []
var _kill_sources: Array = []
var _cancels: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DOWNED_REVIVE_FAIL  ",message)

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

func box(size: Vector3, center: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

## A live authoritative fighter. `slot` must be set before the node enters the
## tree: the rig's armour and the combat source id are bound in `_ready`.
func make_actor(slot: int, peer: int, bot: bool, point: Vector3):
	var body = Actor.new()
	body.slot = slot
	body.authoritative = true
	scene.add_child(body)
	body.configure(peer,"Downed %d" % slot,point)
	body.downed_started.connect(func(_slot: int): _downed_starts += 1)
	body.downed_ended.connect(func(_slot: int): _downed_ends += 1)
	body.killed.connect(func(killed_slot: int, source: int):
		_kill_slots.append(killed_slot)
		_kill_sources.append(source))
	return body

## A melee blow from five metres along +x: the crawl must run the other way.
func hit_from_plus_x(actor, amount: float) -> int:
	return actor.receive_melee(amount,KILLER_SLOT,actor.global_position + Vector3(5.0,0.0,0.0))

## The reason string of the most recent broken channel.
func _last_cancel_reason() -> String:
	if _cancels.is_empty():
		return ""
	return str(_cancels[_cancels.size()-1].reason)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	box(Vector3(60,1,120),Vector3(0,-0.5,10))

	# --- the 10% overkill rule ---------------------------------------------
	# A bare fighter must take a blow at face value, or the boundary checks below
	# would be measuring armour instead of the rule.
	var exact = make_actor(1,1,false,Vector3(0,0,0))
	check(is_zero_approx(exact.rig.damage_reduction(false)),"A bare fighter takes a blow at face value")
	hit_from_plus_x(exact,100.0)
	check(exact.downed,"A hit that overkills by exactly 0 downs the body")
	check(exact.alive,"A downed body is still alive enough to exist")
	check(is_zero_approx(exact.health),"A downed body sits at zero health")
	check(exact.health_state == Contracts.HealthState.DOWNED,"The health state is DOWNED, not DEAD")
	check(_downed_starts == 1,"downed_started fires once for one fall")

	var ten = make_actor(2,2,false,Vector3(0,0,4))
	hit_from_plus_x(ten,110.0)
	check(ten.downed and ten.alive,"A hit that overkills by exactly 10% still downs")

	# A campaign body is never killed by the blow itself: a lethal hit of any size
	# puts it on its chest, and the next blow - or the bleed clock - is what ends it.
	var heavy = make_actor(3,3,false,Vector3(0,0,8))
	var kills_before := _kill_slots.size()
	hit_from_plus_x(heavy,110.1)
	check(heavy.alive and heavy.downed,"A hit that overkills by 10.1% still only downs the body")
	check(heavy.health_state == Contracts.HealthState.DOWNED,"The downed body is DOWNED")
	check(_kill_slots.size() == kills_before,"no death is filed for a blow on its feet")
	hit_from_plus_x(heavy,1.0)
	check(not heavy.alive and not heavy.downed,"the next blow that lands ends it")
	check(heavy.health_state == Contracts.HealthState.DEAD,"A killed body is DEAD")
	check(_kill_slots.size() == kills_before + 1 and heavy.slot in _kill_slots,"killed fires for a real death")

	var soft = make_actor(4,4,false,Vector3(0,0,12))
	hit_from_plus_x(soft,40.0)
	check(is_equal_approx(soft.health,60.0) and soft.alive and not soft.downed,
		"A 40 damage hit on 100 health leaves the body standing at 60")

	# --- slow regeneration --------------------------------------------------
	# Every standing warband body knits one point of health every five seconds,
	# and nothing at all while it is on the ground.
	for tick in 49:
		soft.step(0.1,[soft])
	check(is_equal_approx(soft.health,60.0),"4.9 s on its feet heals nothing")
	soft.step(0.1,[soft])
	check(is_equal_approx(soft.health,61.0),
		"five seconds on its feet heals the contract's single point")
	for tick in 50:
		soft.step(0.1,[soft])
	check(is_equal_approx(soft.health,62.0),"the next point takes another five seconds")

	# --- a downed body cannot act ------------------------------------------
	check(exact.combat.attack_progress >= 1.0 - 0.001,"A downed body has no swing in flight")
	check(not exact.rig.is_melee(),"The rig holds no melee pose while downed")
	exact.set_block(true,Vector3.FORWARD)
	check(not exact.combat.blocking,"A downed body cannot raise a guard")
	check(not bool(exact.try_ability(0).get("ok")),"A downed body cannot fire an ability")
	exact.press_jump(true)
	check(not exact.jump_requested,"A downed body cannot jump or roll")
	check(exact.collision_layer != 0,"A downed body keeps its collision")
	check(exact.rig.visible,"A downed body keeps its model")
	var starts_before := _downed_starts
	exact.enter_downed(1)
	check(_downed_starts == starts_before,"Entering downed twice emits downed_started once")
	exact.step(1.0/60.0,[exact])
	check(exact.downed and exact.combat.attack_progress >= 1.0 - 0.001 and exact.jump_requested == false,
		"A downed tick advances nothing a body could act with")
	for tick in 100:
		exact.step(0.1,[exact])
	check(exact.downed and is_zero_approx(exact.health),
		"A downed body regenerates nothing: the bleed clock is its only clock")

	# --- the finisher rule --------------------------------------------------
	var chip = make_actor(5,5,false,Vector3(0,0,16))
	hit_from_plus_x(chip,100.0)
	check(chip.downed,"The chip fixture is downed before the follow-up")
	hit_from_plus_x(chip,5.0)
	check(not chip.alive and not chip.downed,
		"any blow on a downed body is a finisher: there is no chip damage on the floor")
	check(chip.health_state == Contracts.HealthState.DEAD,"The finished body is DEAD")

	# --- the downed crawl belongs to a soul ---------------------------------
	# A body the AI drives holds the ground it fell on. That is what lets the
	# squad walk up to it, stand still and hold the five second channel: a body
	# that kept dragging itself across the field left that reach every frame.
	var crawler = make_actor(6,6,false,Vector3(0,0,20))
	hit_from_plus_x(crawler,100.0)
	var crawl = Crawl.new()
	scene.add_child(crawl)
	check(crawl.attach(crawler),"A downed body accepts a crawl")
	var crawl_start: Vector3 = crawler.global_position
	crawler.move_direction = Vector2(-1.0,0.0)
	await _frames(60)
	check(crawler.global_position.distance_to(crawl_start) < 0.001,
		"A downed body with nobody inside it stays exactly where it fell")
	check(crawl.manual == false,"and its crawl is not the soul's")
	crawler.move_direction = Vector2.ZERO

	# The soul's own body crawls on its keys, and only then: no key is no motion.
	crawl.manual = true
	var manual_start: Vector3 = crawler.global_position
	await _frames(30)
	check(crawler.global_position.distance_to(manual_start) < 0.001,
		"A soul's downed body does not slide with no key held")
	crawler.move_direction = Vector2(-1.0,0.0)
	await _frames(60)
	check(crawler.global_position.x < manual_start.x - 0.5,
		"and one second of held keys drags it along the key's bearing")
	check(absf(crawler.global_position.z - manual_start.z) < 0.2,
		"The crawl stays on its bearing instead of wandering")
	crawler.move_direction = Vector2.ZERO

	crawler.revive_from_downed()
	check(not crawler.downed
		and is_equal_approx(crawler.health, 100.0 * Contracts.REVIVE_HEALTH_FRACTION),
		"A revive stands the body up on a twentieth of its pool")
	check(crawler.health_state == Contracts.HealthState.ALIVE and crawler.alive,
		"A revived body is ALIVE again")
	check(_downed_ends == 1,"downed_ended fires on a revive")
	var revived_at: Vector3 = crawler.global_position
	await _frames(30)
	check(crawler.global_position.distance_to(revived_at) < 0.01,"The crawl stops when the body is revived")

	var standing = make_actor(9,9,false,Vector3(0,0,28))
	var stand_crawl = Crawl.new()
	scene.add_child(stand_crawl)
	check(stand_crawl.attach(standing),"A standing body can be given a crawl")
	var stand_at: Vector3 = standing.global_position
	await _frames(30)
	check(standing.global_position.distance_to(stand_at) < 0.001,"A standing body is never moved by the crawl")

	# A wall on the soul's crawl line stops it: the drag uses the body's capsule.
	var walled = make_actor(10,10,false,Vector3(0,0,-20))
	box(Vector3(0.6,3,6),Vector3(-1.2,1.5,-20))
	hit_from_plus_x(walled,100.0)
	var wall_crawl = Crawl.new()
	scene.add_child(wall_crawl)
	wall_crawl.attach(walled)
	wall_crawl.manual = true
	walled.move_direction = Vector2(-1.0,0.0)
	await _frames(120)
	check(walled.global_position.x < -0.25 and walled.global_position.x > -0.95,
		"The crawl slides up to the wall and stops instead of passing through it")
	walled.move_direction = Vector2.ZERO

	# --- the squad picks a still body up ------------------------------------
	# The end-to-end version of the rule: a real rescuer walks to a downed body
	# that has nobody inside it, opens the real channel while that body's own
	# crawl node runs, and the channel survives the five seconds. With the old
	# autonomous crawl the patient slid out of reach on the first frame the
	# channel opened, and this rescue could never finish.
	var patient_ai = make_actor(20,0,true,Vector3(0,0,-30))
	hit_from_plus_x(patient_ai,100.0)
	var patient_crawl = Crawl.new()
	scene.add_child(patient_crawl)
	patient_crawl.attach(patient_ai)
	var rescuer = make_actor(21,0,true,patient_ai.global_position + Vector3(0,0,9.0))
	var rescue_channel = Revive.new()
	scene.add_child(rescue_channel)
	rescue_channel.set_bodies([rescuer,patient_ai])
	var squad = Squad.new()
	var rescue_controller := RescueController.new()
	rescue_controller.bodies = {20: patient_ai, 21: rescuer}
	squad.controller = rescue_controller
	squad.revive = rescue_channel
	var rescue_ids: Array[int] = [20,21]
	squad.squad_ids = rescue_ids
	squad.watchers = []
	squad.player_body = null
	var patient_at: Vector3 = patient_ai.global_position
	for tick in 480:
		squad._rescue_step(1.0/60.0)
		rescuer.step(1.0/60.0,[rescuer,patient_ai])
		patient_crawl._physics_process(1.0/60.0)
		rescue_channel.tick(1.0/60.0)
		if not patient_ai.downed:
			break
	check(not patient_ai.downed,"the squad's own hands stand the still body up")
	check(patient_ai.global_position.distance_to(patient_at) < 0.001,
		"and the patient held its ground through the whole rescue")

	# --- the human-only five second revive ---------------------------------
	var patient = make_actor(11,11,false,Vector3(0,0,52))
	hit_from_plus_x(patient,100.0)
	var healer = make_actor(12,1,false,patient.global_position + Vector3(2.0,0,0))
	var channel = Revive.new()
	scene.add_child(channel)
	channel.set_bodies([healer,patient])
	var revived: Array = []
	channel.complete.connect(func(_peer: int, actor): revived.append(actor))
	channel.cancelled.connect(func(peer: int, _target, reason: String): _cancels.append({"peer": peer, "reason": reason}))
	check(channel.begin(1,patient),"A human peer opens a revive from two metres")
	check(is_zero_approx(channel.progress(1)),"A fresh channel reads zero")
	var ends_before_channel := _downed_ends
	for tick in 49:
		channel.tick(0.1)
	check(patient.downed,"4.9 s of channel is not enough")
	check(absf(channel.progress(1) - 0.98) < 0.001,"Progress reads back the channel's share of five seconds")
	check(_downed_ends == ends_before_channel,"A half held channel stands nobody up")
	var ends_before := _downed_ends
	var finished: Dictionary = channel.tick(0.1)
	check(not patient.downed,"One more tenth of a second revives the body")
	check(is_equal_approx(patient.health, 100.0 * Contracts.REVIVE_HEALTH_FRACTION),
		"and the revived body comes back on a twentieth of its pool (%.1f)" % patient.health)
	check(is_equal_approx(patient.health, WarbandContracts.REVIVE_HEALTH_FRACTION * 100.0),
		"a revive restores the contract's share of max health")
	check(patient.alive and patient.health_state == Contracts.HealthState.ALIVE,"The revived body is ALIVE")
	check(not channel.channeling(1),"The channel closes when it completes")
	check(revived.has(patient) and (finished.get("revived",[]) as Array).has(patient),
		"Completion reports the body it stood up")
	check(_downed_ends == ends_before + 1,"The revive emits downed_ended exactly once")

	# AI never revives: peer 0 is the router's "nobody", and a bot body has no
	# human holding the key even when it carries a peer id.
	var ai_patient = make_actor(13,13,false,Vector3(0,0,58))
	hit_from_plus_x(ai_patient,100.0)
	var ai_body = make_actor(14,0,true,ai_patient.global_position + Vector3(1.0,0,0))
	channel.set_bodies([ai_body,ai_patient])
	check(not channel.begin(0,ai_patient),"Peer 0 is nobody and never opens a revive")
	var flagged = make_actor(15,4,true,ai_patient.global_position + Vector3(1.0,0,0))
	channel.set_bodies([flagged,ai_patient])
	check(channel.begin(4,ai_patient),"a peer's body opens the channel from reach")
	channel.set_bodies([healer,ai_patient])
	check(not channel.begin(1,ai_patient),"A human cannot revive a body from across the field")
	check(not channel.channeling(1),"A refused channel leaves nothing open")

	# The squad's own hands may pick a body up: an ally channel is not a peer, so
	# the bot refusal does not apply to it - the guard is the field being clear,
	# which `SquadDrive` owns - and it runs the same continuous five seconds.
	var ally_channel = Revive.new()
	scene.add_child(ally_channel)
	var ally_patient = make_actor(18,18,false,Vector3(0,0,70))
	hit_from_plus_x(ally_patient,100.0)
	var ally = make_actor(19,0,true,ally_patient.global_position + Vector3(1.2,0,0))
	ally_channel.set_bodies([ally,ally_patient])
	check(ally_channel.begin_ally(ally,ally_patient),"A squadmate opens a rescue on a downed ally")
	check(ally_channel.channeling(Revive.ALLY_PEER),"the rescue is the squad's own channel")
	ally_channel.tick(1.0)
	check(absf(ally_channel.progress(Revive.ALLY_PEER) - 0.2) < 0.001,
		"and it runs the human five second clock")
	ally.global_position = ally_patient.global_position + Vector3(8.0,0,0)
	ally_channel.tick(0.1)
	check(not ally_channel.channeling(Revive.ALLY_PEER) and ally_patient.downed,
		"an ally that walks off loses the rescue like anyone else")
	ally.global_position = ally_patient.global_position + Vector3(1.2,0,0)
	check(ally_channel.begin_ally(ally,ally_patient),"and can take it back up")
	for tick in 60:
		ally_channel.tick(0.1)
	check(not ally_patient.downed,"five seconds of the squad's hands stands the body up")
	check(is_equal_approx(ally_patient.health,
		WarbandContracts.REVIVE_HEALTH_FRACTION * ally_patient.max_health),
		"a rescued body comes back on a twentieth of its pool (%.1f)" % ally_patient.health)

	# Breaking the channel restarts the clock: five seconds must be continuous.
	var walker_patient = make_actor(16,16,false,Vector3(0,0,64))
	hit_from_plus_x(walker_patient,100.0)
	var walker = make_actor(17,3,false,walker_patient.global_position + Vector3(2.0,0,0))
	channel.set_bodies([walker,walker_patient])
	check(channel.begin(3,walker_patient),"A human opens a channel on a nearby downed body")
	channel.tick(1.0)
	check(absf(channel.progress(3) - 0.2) < 0.001,"One second of channel is a fifth of the contract")
	walker.global_position = walker_patient.global_position + Vector3(6.0,0,0)
	channel.tick(0.1)
	check(not channel.channeling(3) and walker_patient.downed,"Walking out of reach cancels the channel")
	check(is_zero_approx(channel.progress(3)),"A cancelled channel reads zero, not its old progress")
	check(_last_cancel_reason() == Revive.REASON_OUT_OF_REACH,"The cancel names the out-of-reach reason")
	walker.global_position = walker_patient.global_position + Vector3(1.5,0,0)
	check(channel.begin(3,walker_patient),"A human can reopen the channel after being refused")
	channel.tick(2.0)
	walker.enter_downed(-1)
	channel.tick(0.1)
	check(not channel.channeling(3) and walker_patient.downed,"A downed reviver loses the channel")
	check(_last_cancel_reason() == Revive.REASON_REVIVER_DOWNED,"The cancel names the downed reviver")

	# --- bleeding out -------------------------------------------------------
	var bleeder = make_actor(18,18,false,Vector3(0,0,70))
	hit_from_plus_x(bleeder,100.0)
	check(bleeder.downed,"The bleed fixture is downed")
	for tick in 299:
		bleeder.step(0.1,[bleeder])
	check(bleeder.downed and bleeder.alive,"29.9 s on the ground does not kill a downed body")
	bleeder.step(0.1,[bleeder])
	check(not bleeder.alive and not bleeder.downed,"30 s of bleed kills the body with no further hit")
	check(bleeder.health_state == Contracts.HealthState.DEAD,"The bled out body is DEAD")
	check(_kill_slots.has(18) and int(_kill_sources[_kill_slots.rfind(18)]) == KILLER_SLOT,
		"Bleeding out credits the slot that put the body down")

	# --- the town keeps its own ---------------------------------------------
	# A body knocked down on the square's ground is never carried off: the bleed
	# clock runs out into a stand-up instead of a death, and a blow on the body
	# cannot finish it. That is what lets a co-op party scrap in the town - which
	# it may - without a player losing their session to it.
	var town_body = make_actor(24,24,false,Vector3(0,0,80))
	town_body.home_ground = true
	hit_from_plus_x(town_body,100.0)
	check(town_body.downed and town_body.alive,"A blow on town ground downs the body as it would anywhere")
	var kills_before_town := _kill_slots.size()
	hit_from_plus_x(town_body,500.0)
	check(town_body.downed and town_body.alive,
		"and a finisher on the square does not end it")
	check(_kill_slots.size() == kills_before_town,"no death is filed for a blow in the town")
	for tick in 300:
		town_body.step(0.1,[town_body])
	check(not town_body.downed and town_body.alive,
		"the town's own clock stands the body back up")
	check(is_equal_approx(town_body.health,
		WarbandContracts.REVIVE_HEALTH_FRACTION * town_body.max_health),
		"on the contract's revive share (%.1f of %.1f)" % [
			town_body.health, town_body.max_health])
	check(town_body.health_state == Contracts.HealthState.ALIVE,
		"and the roster reads ALIVE again")
	check(town_body.home_ground == false,
		"the town's hold is cleared once the body is on its feet")
	# Off the square's ground the same body is the campaign's again.
	var wild_body = make_actor(25,25,false,Vector3(0,0,84))
	hit_from_plus_x(wild_body,100.0)
	for tick in 300:
		wild_body.step(0.1,[wild_body])
	check(not wild_body.alive,
		"a body downed off the square still bleeds out")

	# --- the band's hireling: ten seconds, and no one hands him back -------
	# A body nobody's soul is inside is the band's man, not the player's: the
	# world marks it at the fall (`WorldScene._on_body_downed`) and the mark is
	# what makes the clock ten seconds, finishes him on any second blow, and gives
	# the town square and the run's hold no claim on him. Nothing in the game
	# stands him up when those ten seconds run out - the desk that sold him does
	# not sell him back, so the band hires another.
	var hireling = make_actor(26,0,true,Vector3(0,0,88))
	hireling.expendable = true
	check(is_equal_approx(hireling.downed_limit(), Contracts.MERCENARY_DOWNED_SECONDS),
		"a hireling's clock is the contract's ten seconds, not the soul's thirty")
	hit_from_plus_x(hireling,100.0)
	check(hireling.downed and hireling.alive,"a lethal blow puts a hireling on his chest like anyone else")
	for tick in 99:
		hireling.step(0.1,[hireling])
	check(hireling.downed and hireling.alive,"9.9 s is still a body worth picking up")
	hireling.step(0.1,[hireling])
	check(not hireling.alive and hireling.health_state == Contracts.HealthState.DEAD,
		"the tenth second kills him where he lies")

	# The square is the band's home ground, and it is not his: it neither stops
	# the clock nor the blow that follows.
	var square = make_actor(27,0,true,Vector3(0,0,92))
	square.expendable = true
	square.home_ground = true
	hit_from_plus_x(square,100.0)
	check(square.downed,"a hireling knocked down on town ground still goes down")
	hit_from_plus_x(square,1.0)
	check(not square.alive,"and the square does not stop a second blow finishing him")

	var square_clock = make_actor(28,0,true,Vector3(0,0,96))
	square_clock.expendable = true
	square_clock.home_ground = true
	hit_from_plus_x(square_clock,100.0)
	for tick in 100:
		square_clock.step(0.1,[square_clock])
	check(not square_clock.alive,"nor does the clock stop killing him on home ground")

	# The arena holds a soul on the dirt until the island is cleared. A hireling
	# is nobody's spectator: his ten seconds run inside a wave just the same.
	var island = make_actor(29,0,true,Vector3(0,0,100))
	island.expendable = true
	island.roguelite_hold_downed = true
	hit_from_plus_x(island,100.0)
	for tick in 100:
		island.step(0.1,[island])
	check(not island.alive,"a run holds a soul on the dirt, never a hireling")

	# The same blow on a body with a soul inside it keeps the campaign's rule.
	var soul_body = make_actor(30,1,false,Vector3(0,0,104))
	soul_body.roguelite_hold_downed = true
	hit_from_plus_x(soul_body,100.0)
	for tick in 320:
		soul_body.step(0.1,[soul_body])
	check(soul_body.downed and soul_body.alive,
		"the run's hold keeps a soul's body down for the whole of the thirty")
	check(is_equal_approx(soul_body.downed_limit(), Contracts.DOWNED_BLEED_SECONDS),
		"and that body's clock is still the thirty seconds")

	# --- a replica reads the downed state back off the wire -----------------
	# The snapshot shape is unchanged: a body at zero health that is still alive
	# is downed, so no new field (and no extra datagram bytes) was needed.
	var replica = make_actor(19,19,false,Vector3(0,0,76))
	replica.authoritative = false
	var wire: Dictionary = patient.snapshot()
	wire["health"] = 0.0
	wire["alive"] = true
	replica.apply_snapshot(wire,1,[])
	check(replica.downed and replica.alive,"A replica reads a zero health living body as downed")
	check(replica.health_state == Contracts.HealthState.DOWNED,"The replica's health state is DOWNED")
	wire["health"] = 50.0
	replica.apply_snapshot(wire,2,[])
	check(not replica.downed and replica.health_state == Contracts.HealthState.ALIVE,
		"A replica stands the body back up when the revive reaches it")

	print("DOWNED_REVIVE_REGRESSION checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)


## The two calls `SquadDrive` makes on a soul's controller: a mercenary id for a
## real body, and that body back again. The rescue reads nothing else.
class RescueController:
	var bodies: Dictionary = {}

	func body_of(merc_id: int):
		return bodies.get(merc_id, null)

	func merc_of(body) -> int:
		for merc_id in bodies:
			if bodies[merc_id] == body:
				return int(merc_id)
		return -1
