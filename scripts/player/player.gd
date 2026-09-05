class_name Player
extends CharacterBody3D
## One script for both players. Movement, swim, shop, beer, combat, and camera
## live in composable helpers so each stays under the line-count rule.

enum State { NORMAL, GOLFING, RIDING, SWIMMING, SHIELDING, PLACING, CLIMBING, MECH, GRAPPLING, ZIPLINING }

## Re-exported for callers and tests that still read Player.CONST.
const SPRINT_SPEED := PlayerMotion.SPRINT_SPEED
const ACCELERATION := PlayerMotion.ACCELERATION
const BODY_RADIUS := PlayerHitFx.BODY_RADIUS
const BASE_FOV := PlayerLook.BASE_FOV
const DRIVER_FOV := PlayerLook.DRIVER_FOV
const REVIVE_RANGE := 2.8
## How hard the ragdoll spills when a thrown gun floors you.
const FLOOR_FLOP_STRENGTH := 1.7
const STAND_HEAD_HEIGHT := PlayerHitFx.STAND_HEAD_HEIGHT
const DOWNED_HEAD_HEIGHT := PlayerAnim.DOWNED_HEAD_HEIGHT
const SIT_HEAD_HEIGHT := PlayerAnim.SIT_HEAD_HEIGHT
const SLIDE_HEAD_HEIGHT := PlayerAnim.SLIDE_HEAD_HEIGHT
const HIT_FLASH_TIME := PlayerHitFx.HIT_FLASH_TIME
const HIT_KNOCK := PlayerMotion.HIT_KNOCK
const WADE_DEPTH := PlayerSwim.WADE_DEPTH
const SWIM_FLOAT_DEPTH := PlayerSwim.SWIM_FLOAT_DEPTH
const SWIM_FLOOR_CLEARANCE := PlayerSwim.SWIM_FLOOR_CLEARANCE
const CHEER_FOV := PlayerLook.CHEER_FOV
const FLOOR_SNAP := PlayerMotion.FLOOR_SNAP
const FLOOR_MAX_DEG := PlayerMotion.FLOOR_MAX_DEG
const SAFE_MARGIN := PlayerMotion.SAFE_MARGIN
const REMOTE_POSE_EASE := PlayerAnim.REMOTE_POSE_EASE
const _WorldFx := preload("res://scripts/net/world_fx.gd")

@export var input_prefix := "p1"
@export var uses_mouse := true
@export var body_color := Palette.PLAYER_ONE
@export var sync_pace := 0.0
@export var sync_gun := 0
@export var sync_state := 0
@export var sync_dive := false
@export var sync_firing := false
@export var sync_reload := 0.0
@export var sync_scoped := false
@export var sync_pitch := 0.0
@export var sync_stick := Vector2.ZERO
@export var sync_sprint := false
@export var sync_slide := false
@export var sync_glide := false
@export var sync_glide_worn := false
@export var sync_jumps := 0
@export var sync_xform := Transform3D.IDENTITY:
	set(value):
		sync_xform = value
		if (
			is_inside_tree() and not NetSession.should_simulate(self)
			and not carried_by_cart() and not is_in_mech() and not predicts_locally()
		):
			_net_interp.arrive(value)

var peer_id := 0
var net_driven := false
var cpu_filled := false
var vs_brain: VsCpu
var _net_interp := NetInterp.new()
var _predict := NetPredict.new()
var score

var input: PlayerInput
var golf: GolfController
var cart: GolfCart
var mech: MechSuit
## Filled in by MatchFlow. Left untyped so Player and MatchFlow are not a
## class cycle (MatchFlow already holds the players).
var flow
var partner: Player
var state: State = State.NORMAL
## Seconds left flat on your back after a thrown gun landed on you. Short and
## self-righting, unlike being downed, which waits on a partner.
var floored_for := 0.0
@export var aiming := false
var brain: CpuBuddy
var shopping := false
var shop_choice := 0
var shop_dept := Shop.Dept.WEAPONS
var talking := false
var talk_name := ""
var talk_line := ""
var _talk_npc: ClubhouseNpc
var buzz := Buzz.new()
@export var holding_beer := false
@export var holding_mines := false
## CPU partner plants a shield after a tower sniper connects, or while you snipe.
var wants_cover := false
var climber := Climber.new()
var grappler := Grappler.new()
var zipliner := Zipliner.new()
var _grapple_line: GrappleLine
## World point of a latched claw, so a watcher can draw the rope.
@export var sync_grapple_at := Vector3.INF
var mill_desk

var swim := PlayerSwim.new()
var slide := PlayerSlide.new()
var glide := PlayerGlide.new()
var place := PlayerPlace.new()
var beer := PlayerBeerKit.new()
var mine_kit := PlayerMines.new()
var shop := PlayerShop.new()
var look := PlayerLook.new()
var motion := PlayerMotion.new()
var combat := PlayerCombat.new()
var prompts := PlayerPrompt.new()
var interact := PlayerInteract.new()
var hit_fx := PlayerHitFx.new()
var vehicle := PlayerVehicle.new()
var anim := PlayerAnim.new()
var poker := PlayerPoker.new()

var _shield:
	get:
		return combat.shield

var _yaw: float:
	get:
		return look.yaw
	set(value):
		look.yaw = value

var _pitch: float:
	get:
		return look.pitch
	set(value):
		look.pitch = value

var _mouse_delta: Vector2:
	get:
		return look.mouse_delta
	set(value):
		look.mouse_delta = value

var _underwater: bool:
	get:
		return swim.underwater
	set(value):
		swim.underwater = value

var _beer:
	get:
		return beer.can

var _inspect:
	get:
		return shop.inspect

var _cheer_left: float:
	get:
		return look.cheer_left
	set(value):
		look.cheer_left = value

var _view_kick: float:
	get:
		return look.view_kick
	set(value):
		look.view_kick = value

var _fling_left: float:
	get:
		return motion.fling_left
	set(value):
		motion.fling_left = value

var _place_ok: bool:
	get:
		return place.ok

var _cart_chase: bool:
	get:
		return look.cart_chase
	set(value):
		look.cart_chase = value

@onready var head: Node3D = $Head
@onready var health: Health = $Health
@onready var weapon: Weapon = $Weapon
@onready var melee: Melee = $Melee
@onready var body: PlayerBody = $Body
@onready var raygun: Raygun = $Head/Raygun


func _ready() -> void:
	if GameSettings.mode == GameSettings.Mode.COOP:
		uses_mouse = input_prefix != "p1"
	input = PlayerInput.new(input_prefix, uses_mouse)
	_set_solid(true)
	motion.configure(self)
	body.build(body_color)
	raygun.build(body_color)
	hit_fx.setup(self)
	health.damaged.connect(_on_damaged)
	health.downed.connect(_on_downed)
	health.revived.connect(_on_revived)
	weapon.fired.connect(_on_fired)
	combat.setup(self)
	shop.setup(self)
	beer.setup(self)
	_grapple_line = GrappleLine.new()
	add_child(_grapple_line)
	add_to_group("players")
	if cpu_filled:
		possess_vs_cpu()


func _physics_process(delta: float) -> void:
	floored_for = maxf(0.0, floored_for - delta)
	if (
		state == State.RIDING
		and (cart == null or not cart.is_riding(self))
		and (not net_driven or is_multiplayer_authority())
	):
		_drop_from_lost_ride()
	if (
		state == State.MECH
		and (mech == null or mech.pilot != self)
		and (not net_driven or is_multiplayer_authority())
	):
		eject_from_mech(global_position + Vector3.UP * 0.4, look.yaw)
	if net_driven and not is_multiplayer_authority():
		_tick_watched_combat(delta)
		_walk_as_watched(delta)
		return
	if vs_brain != null:
		if input is CpuInput:
			(input as CpuInput).begin_frame()
		vs_brain.tick(delta)
	elif brain != null:
		brain.tick(delta)
	if is_driving() and NetSession.is_active() and not multiplayer.is_server() and cart != null:
		cart.report_drive.rpc_id(
			1, input.move_vector(), input.pressed("shoot"), input.pressed("aim")
		)
	look.tick(self, delta)
	if is_in_mech() and NetSession.is_active() and not multiplayer.is_server() and mech != null:
		mech.report_pilot.rpc_id(
			1,
			input.move_vector(),
			input.pressed("sprint"),
			look_yaw(),
			look_pitch(),
			input.just_pressed("jump")
		)
		if not is_golfing():
			if input.just_pressed("shoot"):
				mech.report_fire.rpc_id(1)
			if input.just_pressed("reload"):
				mech.report_reload.rpc_id(1)
	combat.update_shield(self)
	_tick_grapple()
	if health.is_downed():
		head.position.y = DOWNED_HEAD_HEIGHT
	elif is_riding() or is_poker_seated():
		head.position.y = SIT_HEAD_HEIGHT
	elif is_sliding():
		head.position.y = SLIDE_HEAD_HEIGHT
	else:
		head.position.y = STAND_HEAD_HEIGHT
	motion.tick(self, delta)
	combat.tick(self, delta)
	interact.tick(self, delta)
	poker.tick(self, delta)
	buzz.tick(delta)
	weapon.power_mult = buzz.weapon_mult()
	hit_fx.tick_flash(self, delta)
	look.tick_cheer(delta)
	sync_pace = pace()
	sync_gun = weapon.index
	sync_state = int(state)
	sync_dive = swim.underwater
	sync_firing = weapon.is_firing()
	sync_reload = weapon.reload_fraction()
	sync_scoped = weapon.is_scoped()
	sync_pitch = look.pitch
	sync_stick = input.move_vector()
	sync_sprint = input.pressed("sprint")
	sync_slide = slide.active
	sync_glide = glide.active
	sync_glide_worn = glide.equipped
	sync_grapple_at = grappler.attach_world() if grappler.is_latched() else Vector3.INF
	sync_xform = global_transform
	anim.tick(self, delta)


func _process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		if predicts_locally():
			_predict.correct(self, sync_xform, delta)
		elif not carried_by_cart() and not is_in_mech():
			_net_interp.follow(self, sync_xform, delta, NetSync.PAWN_HZ, NetSync.WATCH_DELAY)
		anim.tick(self, delta)


func predicts_locally() -> bool:
	return (
		net_driven and not is_multiplayer_authority()
		and health != null and health.is_alive()
		and state == State.NORMAL
		and not carried_by_cart()
		and not is_celebrating()
		and motion.fling_left <= 0.0
	)


func _tick_watched_combat(delta: float) -> void:
	if melee != null:
		melee.tick(delta)
	if weapon != null:
		weapon.tick_timers(delta)
	hit_fx.tick_flash(self, delta)


func _walk_as_watched(delta: float) -> void:
	if not predicts_locally():
		_predict.clear()
		return
	rotation.y = lerp_angle(
		rotation.y, sync_xform.basis.get_euler().y, clampf(REMOTE_POSE_EASE * delta, 0.0, 1.0)
	)
	motion.tick(self, delta)
	_predict.remember(global_position)


func carried_by_cart() -> bool:
	return state == State.RIDING and cart != null and cart.is_riding(self)


func net_interp() -> NetInterp:
	return _net_interp


func is_golfing() -> bool:
	return state == State.GOLFING


func is_swimming() -> bool:
	return state == State.SWIMMING


func is_sliding() -> bool:
	return slide.active


func is_gliding() -> bool:
	return glide.active


func is_underwater() -> bool:
	return state == State.SWIMMING and swim.underwater


func is_carrying_ball() -> bool:
	return golf != null and golf.ball != null and golf.ball.carrier() == self


func is_shielding() -> bool:
	return state == State.SHIELDING


func is_placing() -> bool:
	return state == State.PLACING


func is_climbing() -> bool:
	return state == State.CLIMBING and climber.is_active()


func is_grappling() -> bool:
	return state == State.GRAPPLING


func is_ziplining() -> bool:
	return state == State.ZIPLINING and zipliner.is_active()


func is_milling() -> bool:
	return mill_desk != null and is_instance_valid(mill_desk) and mill_desk.operator == self


func is_poker_seated() -> bool:
	return poker.seated()


func is_celebrating() -> bool:
	return look.cheer_left > 0.0


func celebrate() -> void:
	look.celebrate(self)


func is_cpu() -> bool:
	return brain != null or vs_brain != null


func seat_index() -> int:
	var seat := NetSession.seat_for(peer_id)
	return seat if seat >= 0 else 0


func possess_cpu() -> void:
	uses_mouse = false
	input = CpuInput.new(input_prefix, false)
	brain = CpuBuddy.new()
	brain.setup(self)


func possess_vs_cpu() -> void:
	uses_mouse = false
	cpu_filled = true
	input = CpuInput.new(input_prefix, false)
	vs_brain = VsCpu.new()
	vs_brain.setup(self, input)


func listen_to_both_devices() -> void:
	uses_mouse = true
	var other := "p1" if input_prefix == "p2" else "p2"
	input = PlayerInput.new(input_prefix, true, PackedStringArray([other]))


func bind_seat(p_prefix: String, p_uses_mouse: bool) -> void:
	input_prefix = p_prefix
	uses_mouse = p_uses_mouse
	input = PlayerInput.new(input_prefix, uses_mouse)


func pace() -> float:
	if net_driven and not is_multiplayer_authority():
		return anim.remote_pace
	return clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)


func wallet():
	if score != null:
		return score
	if flow != null:
		return flow.score
	return null


func fling(direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	motion.apply_fling(self, direction, speed, lift, lock)


func is_floored() -> bool:
	return floored_for > 0.0


## Flat on your back for a moment: no walking, no shooting, and a ragdoll flop
## that rights itself, so nobody has to come and pick you up.
func knock_to_floor(seconds: float, from: Vector3, speed := 7.0) -> void:
	if seconds <= 0.0:
		return
	if speed > 0.0:
		apply_knockback(from, speed)
	_go_flat(seconds, from)
	if NetSession.is_active() and multiplayer.is_server():
		_replicate_floor.rpc(seconds, from)


@rpc("authority", "call_remote", "reliable")
func _replicate_floor(seconds: float, from: Vector3) -> void:
	_go_flat(seconds, from)


func _go_flat(seconds: float, from: Vector3) -> void:
	floored_for = maxf(floored_for, seconds)
	if body == null or is_riding():
		return
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -global_transform.basis.z
	body.flop(Ragdoll.Region.TORSO, away.normalized(), FLOOR_FLOP_STRENGTH, false)


func request_host_throw(origin: Vector3, direction: Vector3) -> void:
	_request_throw.rpc_id(1, origin, direction)


@rpc("any_peer", "reliable")
func _request_throw(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	WeaponGate.host_throw(self, origin, direction)


func apply_knockback(from: Vector3, speed := 10.0) -> void:
	motion.apply_knockback(self, from, speed)


func _do_knockback(from: Vector3, speed: float) -> void:
	motion.do_knockback(self, from, speed)


@rpc("any_peer", "reliable")
func _receive_knockback(from: Vector3, speed: float) -> void:
	if is_multiplayer_authority():
		_do_knockback(from, speed)


@rpc("any_peer", "reliable")
func _receive_fling(direction: Vector3, speed: float, lift: float, lock: float) -> void:
	if is_multiplayer_authority():
		motion.fling(self, direction, speed, lift, lock)


func get_view_transform() -> Transform3D:
	return look.view_transform(self)


func get_view_fov() -> float:
	return look.view_fov(self)


func cabin_layer() -> int:
	return PlayerBody.CABIN_P1 if input_prefix == "p1" else PlayerBody.CABIN_P2


func view_cull_mask() -> int:
	if look.hides_own_cabin(self):
		return 0xFFFFF & ~cabin_layer()
	return 0xFFFFF


func add_mouse_look(relative: Vector2) -> void:
	look.add_mouse(self, relative)


func add_view_kick(amount: float) -> void:
	look.add_kick(amount)


func look_yaw() -> float:
	return look.yaw


func look_pitch() -> float:
	return look.pitch


func set_look_yaw(value: float) -> void:
	look.yaw = value
	rotation.y = deg_to_rad(look.yaw)


func set_look_pitch(value: float) -> void:
	look.pitch = value


func is_chase_cam() -> bool:
	return look.cart_chase


func stand_at(position: Vector3, facing_yaw: float) -> void:
	if mech != null and mech.pilot == self:
		mech.stand_at(position, facing_yaw)
		return
	global_position = position
	set_look_yaw(facing_yaw)
	velocity = Vector3.ZERO
	motion.fling_left = 0.0


func spawn_at(position: Vector3, facing_yaw: float) -> void:
	vehicle.spawn_at(self, position, facing_yaw)


func enter_golf_mode() -> void:
	vehicle.enter_golf(self)


func exit_golf_mode() -> void:
	vehicle.exit_golf(self)


func enter_ride() -> void:
	vehicle.enter_ride(self)


func exit_ride() -> void:
	vehicle.exit_ride(self)


func is_in_mech() -> bool:
	return mech != null and mech.pilot == self


func golf_claim_origin() -> Vector3:
	if is_in_mech():
		return mech.golf_claim_origin()
	return global_position


func golf_claim_range() -> float:
	if is_in_mech():
		return mech.golf_claim_range()
	return GolfController.CLAIM_RANGE


func golf_stance_point(lie: Vector3, aim_yaw_deg: float) -> Vector3:
	if is_in_mech():
		return mech.golf_stance_point(lie, aim_yaw_deg)
	return GolfClub.stance_point(lie, aim_yaw_deg)


func enter_mech(suit: MechSuit) -> void:
	vehicle.enter_mech(self, suit)


func eject_from_mech(at: Vector3, facing_yaw: float) -> void:
	vehicle.eject_from_mech(self, at, facing_yaw)


func sit_in_mech(sit_at: Vector3, facing_yaw: float, pitch_deg: float) -> void:
	vehicle.sit_in_mech(self, sit_at, facing_yaw, pitch_deg)


func _set_hidden_in_mech(on: bool) -> void:
	if body != null:
		body.visible = not on
	if raygun != null:
		raygun.visible = not on


func _set_solid(on: bool) -> void:
	collision_layer = Layers.PLAYER if on else 0
	collision_mask = Layers.PLAYER_MASK if on else 0


func _drop_from_lost_ride() -> void:
	vehicle.drop_from_lost_ride(self)


func is_riding() -> bool:
	return state == State.RIDING


func is_driving() -> bool:
	return state == State.RIDING and cart != null and cart.driver == self


func enter_boost(along: Vector3) -> void:
	motion.enter_boost_pad(self, along)


func exit_boost() -> void:
	motion.exit_boost()


func enter_escalator(lift) -> void:
	motion.enter_escalator(lift)


func exit_escalator(lift) -> void:
	motion.exit_escalator(lift)


func sit_as_driver(sit_at: Vector3, facing_yaw: float) -> void:
	vehicle.sit_as_driver(self, sit_at, facing_yaw)


func sit_as_passenger(sit_at: Vector3) -> void:
	vehicle.sit_as_passenger(self, sit_at)


func get_prompt() -> String:
	return prompts.text(self)


func wants_map() -> bool:
	if is_cpu() or not health.is_alive() or shopping or talking or is_poker_seated():
		return false
	if partner_needs_revive():
		return false
	return input.pressed("map")


func wants_shop_info() -> bool:
	return shopping and health.is_alive() and input.pressed("map")


func partner_needs_revive() -> bool:
	return (
		partner != null and partner.health.is_downed()
		and _distance_to(partner) <= REVIVE_RANGE
	)


func _partner_needs_revive() -> bool:
	return partner_needs_revive()


func _apply_look(delta: float) -> void:
	look.tick(self, delta)


func _cancel_place() -> void:
	place.cancel(self)


func _swap_gear() -> void:
	place.swap_gear(self)


func _move(delta: float) -> void:
	motion.tick(self, delta)


func _fight(delta: float) -> void:
	combat.tick(self, delta)


func _interact(delta: float) -> void:
	interact.tick(self, delta)


func _animate(delta: float) -> void:
	anim.tick(self, delta)


func _cycle_held(step := 1) -> void:
	beer.cycle_held(self, step)


func _drop_climb() -> void:
	motion.drop_climb(self)


func _start_climb() -> bool:
	return motion.start_climb(self)


func _tick_cpu_shot_command(delta: float) -> void:
	interact.tick_cpu_shot(self, delta)


func _start_hit_flash() -> void:
	hit_fx.start_flash(self)


func _update_shield() -> void:
	combat.update_shield(self)


func _try_latch_climb() -> bool:
	return motion.try_latch_climb(self)


func _cycle_shop(step := 1) -> void:
	shop.cycle(self, step)


func _turn_shop(look_delta: Vector2, delta: float) -> void:
	shop.turn(self, look_delta, delta)


func request_host_fire(view: Transform3D, ads: bool, gun_index: int) -> void:
	_request_fire.rpc_id(
		1, view.origin, view.basis.x, view.basis.y, view.basis.z, ads, gun_index
	)


@rpc("any_peer", "reliable")
func _request_fire(
	origin: Vector3, bx: Vector3, by: Vector3, bz: Vector3, ads: bool, gun_index: int
) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	weapon.host_fire(Transform3D(Basis(bx, by, bz), origin), ads, gun_index)


func request_host_reload(gun_index: int) -> void:
	_request_reload.rpc_id(1, gun_index)


@rpc("any_peer", "reliable")
func _request_reload(gun_index: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	weapon.host_reload(gun_index)


@rpc("any_peer", "reliable")
func _request_melee(origin: Vector3, forward: Vector3, strength: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	melee.shove(origin, forward, strength, self)


@rpc("authority", "call_remote", "reliable")
func _replicate_melee() -> void:
	if body != null:
		body.start_melee()
	if raygun != null:
		raygun.start_melee()


@rpc("any_peer", "reliable")
func _request_place(at: Vector3, yaw_deg: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	place.host_place(self, at, yaw_deg)


@rpc("any_peer", "reliable")
func _request_place_ladder(at: Vector3, yaw_deg: float, span: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	place.host_place_ladder(self, at, yaw_deg, span)


@rpc("any_peer", "reliable")
func _request_throw_ladder() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var ladder := LeanLadder.nearest_throw(self)
	if ladder != null:
		ladder.host_throw(self)


func orders_cpu_shots() -> bool:
	return partner != null and partner.is_cpu() and not is_cpu()


func _orders_cpu_shots() -> bool:
	return orders_cpu_shots()


func open_shop() -> void:
	open_doors()


func open_doors() -> void:
	shop.open_doors(self)


func open_station(station: ShopStation) -> void:
	shop.open_station(self, station)


func start_talk(npc: ClubhouseNpc) -> void:
	shop.start_talk(self, npc)


func stop_talk() -> void:
	shop.stop_talk(self)


func close_shop() -> void:
	shop.close_shop(self)


func incoming_damage(amount: float) -> float:
	if is_in_mech():
		return 0.0
	if is_riding() and cart != null and cart.armored:
		return amount * GolfCart.ARMOR_SCALE
	return amount


func apply_hit(amount: float, from: Vector3, hit_at := Vector3.INF) -> void:
	if NetSession.defers_world():
		return
	var was_alive := health.is_alive()
	health.take_damage(incoming_damage(amount))
	if not was_alive:
		return
	motion.knock_from(self, from)
	hit_fx.flop_from(self, from, hit_at, amount, health.is_downed())


@rpc("any_peer", "reliable")
func _request_revive(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	var target := _player_with_peer(target_id)
	if target == null:
		return
	if global_position.distance_to(target.global_position) > REVIVE_RANGE:
		return
	target.health.add_revive_progress(get_physics_process_delta_time())


func _player_with_peer(id: int) -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as Player
		if other != null and other.peer_id == id:
			return other
	return null


func call_for_cover() -> void:
	wants_cover = true


func is_holding_sniper() -> bool:
	return weapon != null and weapon.stats() != null and weapon.stats().has_scope()


func needs_cover() -> bool:
	return is_golfing() or wants_cover or is_holding_sniper()


func is_hit_flashing() -> bool:
	return hit_fx.is_flashing()


static func hit_push(from: Vector3, at: Vector3) -> Vector3:
	var push := Vector3(at.x - from.x, 0.0, at.z - from.z)
	if push.length_squared() < 0.0001:
		return Vector3.ZERO
	return push.normalized() * HIT_KNOCK


func is_wearing(item_id: String) -> bool:
	return body != null and body.is_wearing(item_id)


func wear_apparel(item: Dictionary) -> void:
	if body == null or item.is_empty():
		return
	match String(item.get("slot", "")):
		"shirt":
			body.wear_shirt(String(item["id"]), item["color"])
		"headband":
			body.wear_headband(String(item["id"]), item["color"])
		"bottom":
			body.wear_bottom(
				String(item["id"]), String(item.get("style", "shorts")), item["color"]
			)


func trying_on_apparel() -> bool:
	return shop.trying_on_apparel(self)


func can_retrieve_ball() -> bool:
	return flow != null and flow.can_retrieve_ball(self)


func can_start_play() -> bool:
	return flow != null and flow.has_method("can_start_play") and flow.can_start_play(self)


func can_open_doors() -> bool:
	return flow != null and flow.has_method("can_open_doors") and flow.can_open_doors(self)


func can_open_exit() -> bool:
	return flow != null and flow.has_method("can_open_exit") and flow.can_open_exit(self)


func station() -> ShopStation:
	if flow == null or not flow.has_method("station_for"):
		return null
	return flow.station_for(self)


func npc() -> ClubhouseNpc:
	if flow == null or not flow.has_method("npc_for"):
		return null
	return flow.npc_for(self)


func active_cart() -> GolfCart:
	return vehicle.active_cart(self)


func ready_mech() -> MechSuit:
	return vehicle.ready_mech(self)


func mill_control():
	return interact.mill_control(self)


func escalator_button():
	return interact.escalator_button(self)


func _in_clubhouse() -> bool:
	return flow != null and flow.in_clubhouse()


func apply_held_beers(held: int) -> void:
	buzz.held = maxi(0, held)


@rpc("any_peer", "reliable")
func _request_beer_cart() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	beer.commit_cart(self)


func is_holding_beer() -> bool:
	return beer.is_holding(self)


func is_holding_mines() -> bool:
	return mine_kit.is_holding(self)


func drop_mine() -> bool:
	return mine_kit.deploy(self)


func throw_beer() -> bool:
	return beer.throw_beer(self)


@rpc("any_peer", "reliable")
func _request_throw_beer(muzzle: Vector3, fly: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if not buzz.spend():
		return
	beer.spawn_thrown(self, muzzle, fly)


func chug() -> bool:
	return beer.chug(self)


@rpc("any_peer", "reliable")
func _request_chug() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	buzz.spend()


func wants_drunk_fx() -> bool:
	return beer.wants_drunk_fx(self)


func begin_zipline(line: Node3D) -> bool:
	if health == null or not health.is_alive():
		return false
	if is_riding() or is_golfing() or is_in_mech() or shopping or talking:
		return false
	_drop_climb()
	_drop_grapple()
	if not zipliner.latch(self, line as Zipline):
		return false
	_cancel_place()
	if _shield != null:
		_shield.set_raised(false)
	state = State.ZIPLINING
	Sfx.play("zipline_grab", self)
	return true


func _drop_zipline() -> void:
	zipliner.drop()
	if state == State.ZIPLINING:
		state = State.NORMAL


func begin_grapple(ride: Node3D, at: Vector3) -> bool:
	if not _can_keep_grapple():
		grappler.drop()
		return false
	if not grappler.latch(self, ride, at):
		return false
	_cancel_place()
	if _shield != null:
		_shield.set_raised(false)
	state = State.GRAPPLING
	_set_grapple_mask(true)
	return true


func _drop_grapple() -> void:
	var was := is_grappling()
	grappler.drop()
	_set_grapple_mask(false)
	floor_snap_length = PlayerMotion.FLOOR_SNAP
	if was:
		state = State.NORMAL
		Sfx.play("grapple_release", self)


func _tick_grapple() -> void:
	if grappler.is_flying() and input.just_pressed("grapple"):
		grappler.cancel_flight()
		return
	if is_grappling():
		return
	if input.just_pressed("grapple") and _can_fire_grapple():
		_fire_grapple()


func _can_fire_grapple() -> bool:
	if state != State.NORMAL or shopping or talking or is_celebrating() or is_milling():
		return false
	if health == null or not health.is_alive():
		return false
	if is_carrying_ball() or is_holding_beer() or grappler.is_active():
		return false
	return true


func _can_keep_grapple() -> bool:
	if health == null or not health.is_alive():
		return false
	return not (
		is_riding() or is_golfing() or is_in_mech() or is_climbing()
		or is_ziplining() or is_milling() or shopping or talking
	)


func _fire_grapple() -> void:
	var origin := Grappler.muzzle_of(self)
	var direction := -head.global_transform.basis.z
	if NetSession.is_active() and not multiplayer.is_server():
		_request_grapple.rpc_id(1, origin, direction)
		grappler.fire(self, origin, direction, true)
		return
	grappler.fire(self, origin, direction, false)
	_WorldFx.announce_grapple(self, origin, direction, peer_id)


func _draw_grapple_line() -> void:
	if _grapple_line == null:
		return
	var from := Grappler.muzzle_of(self)
	var to := grappler.line_end()
	if to == Vector3.INF and is_grappling():
		to = sync_grapple_at
	if to == Vector3.INF:
		_grapple_line.hide_line()
		return
	_grapple_line.draw(from, to, is_grappling() or grappler.is_latched())


func _set_grapple_mask(on: bool) -> void:
	if collision_layer != Layers.PLAYER:
		return
	if on:
		var skip := Layers.VEHICLE | Layers.MECH
		if grappler.is_point():
			skip |= Layers.PROP
		collision_mask = Layers.PLAYER_MASK & ~skip
	else:
		collision_mask = Layers.PLAYER_MASK


@rpc("any_peer", "reliable")
func _request_grapple(origin: Vector3, direction: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if not _can_fire_grapple():
		return
	grappler.fire(self, origin, direction, false)
	_WorldFx.announce_grapple(self, origin, direction, peer_id)


func begin_mill(desk) -> void:
	mill_desk = desk
	if combat.shield != null:
		combat.shield.set_raised(false)


func end_mill(desk) -> void:
	if mill_desk == desk:
		mill_desk = null


func face_mill(at: Vector3, yaw: float) -> void:
	global_position = at
	look.yaw = rad_to_deg(yaw)
	rotation.y = yaw
	velocity = Vector3.ZERO


func _distance_to(other: Node3D) -> float:
	var offset := other.global_position - global_position
	offset.y = 0.0
	return offset.length()


static func throw_velocity(forward: Vector3) -> Vector3:
	return PlayerSwim.throw_velocity(forward)


static func carry_point(held_at: Transform3D) -> Vector3:
	return PlayerSwim.carry_point(held_at)


func _on_fired() -> void:
	combat.on_fired(self)


func _on_damaged(amount: float) -> void:
	hit_fx.on_damaged(self, amount)


func _on_downed() -> void:
	hit_fx.on_downed(self)


func _on_revived() -> void:
	hit_fx.on_revived(self)
