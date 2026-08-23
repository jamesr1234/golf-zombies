class_name Player
extends CharacterBody3D
## One script for both players. The only difference between them is the input
## prefix and whether they steer with a trackpad or a right stick.

enum State { NORMAL, GOLFING, RIDING, SWIMMING, SHIELDING, PLACING }

const WALK_SPEED := 5.4
const SPRINT_SPEED := 8.2
const ACCELERATION := 14.0
const JUMP_VELOCITY := 4.8
## Capsule radius. The planted shield is twice this body's width.
const BODY_RADIUS := 0.4
const MOUSE_DEG_PER_PIXEL := 0.12
const STICK_DEG_PER_SEC := 130.0
const PITCH_LIMIT := 85.0
## Horizontal, since the split-screen cameras keep their aspect by width.
const BASE_FOV := 85.0
const ADS_FOV := 60.0
const DRIVER_FOV := 105.0
const REVIVE_RANGE := 2.8
const STAND_HEAD_HEIGHT := 1.55
const DOWNED_HEAD_HEIGHT := 0.45
## A little down so the wheel sits in frame instead of only showing sky.
const DRIVER_PITCH := -8.0
const SIT_HEAD_HEIGHT := 0.96
const VIEW_KICK_DEG := 5.5
const VIEW_KICK_RECOVER := 22.0
const MELEE_VIEW_KICK := 4.0
const HIT_FLASH_TIME := 0.16
const HIT_KNOCK := 6.5
const SWIM_SPEED := 4.2
const SWIM_VERTICAL := 3.4
const SWIM_DIVE_SPEED := 4.0
## Water this deep is still walked through on foot, which is how you wade in off
## the bank. Past it the ground is too far down to stand on and you tread instead.
const WADE_DEPTH := 1.2
## Ankle-deep is enough to slow a run down.
const WADE_DRAG_DEPTH := 0.3
const WADE_SPEED_SCALE := 0.62
## How far the feet hang below the water line while treading, so the head and
## shoulders stay above it until you choose to dive.
const SWIM_FLOAT_DEPTH := 1.05
## Treading rises onto the water line at this rate rather than snapping to it.
const SWIM_SETTLE_SPEED := 3.2
## The body stands on its origin, so this is only enough to keep a dive off the
## pond floor rather than fighting the heightmap for it.
const SWIM_FLOOR_CLEARANCE := 0.1
const SWIM_GRAB_RANGE := 2.4
## How far from the bank you can haul yourself out while treading. Long enough
## to clear the slope you jam into, short enough that open water is still a swim.
const SWIM_CLIMB_REACH := 3.6
const SWIM_THROW_SPEED := 15.0
const SWIM_THROW_LIFT := 0.38
const SWIM_CARRY_FORWARD := 0.55
const SWIM_CARRY_HEIGHT := 0.15
const _Shield := preload("res://scripts/player/shield.gd")
const _HexBarrier := preload("res://scripts/player/hex_barrier.gd")
const _BeerCan := preload("res://scripts/player/beer_can.gd")
const _ThrownBeer := preload("res://scripts/player/thrown_beer.gd")
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _ShopInspect := preload("res://scripts/shop/shop_inspect.gd")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const PLACE_WATER := 0.3
const CPU_SHOT_HOLD := 0.45
const CHEER_CAM_BACK := 3.6
const CHEER_CAM_SIDE := 1.15
const CHEER_CAM_HEIGHT := 1.9
const CHEER_CAM_LOOK := 1.15
const CHEER_FOV := 70.0
## Same snap the walkers use. Without it a capsule slowly sinks through the
## heightmap, and after a minute of that physics can hang the whole play session.
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 60.0
const SAFE_MARGIN := 0.04

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
@export var sync_xform := Transform3D.IDENTITY

var peer_id := 0
var net_driven := false
var _net_interp := NetInterp.new()
var score

var input: PlayerInput
var golf: GolfController
var cart: GolfCart
## Filled in by MatchFlow. Left untyped so Player and MatchFlow are not a
## class cycle (MatchFlow already holds the players).
var flow
var partner: Player
var state: State = State.NORMAL
@export var aiming := false
var brain: CpuBuddy
var shopping := false
var shop_choice := 0
var shop_dept := Shop.Dept.WEAPONS
var talking := false
var talk_name := ""
var talk_line := ""
var _talk_npc: ClubhouseNpc
var _inspect
var _dressing := false
var _dress_saved_yaw := 0.0
var _boost_count := 0
var _boost_along := Vector3.ZERO

var _yaw := 0.0
var _pitch := 0.0
var _mouse_delta := Vector2.ZERO
var _view_kick := 0.0
## Driver-only: L1 pulls the camera out behind the cart.
var _cart_chase := false
var _underwater := false
var _shield: _Shield
var _place_ghost: _HexBarrier
var _place_at := Vector3.ZERO
var _place_ok := false
var _cpu_shot_hold := 0.0
var _cpu_shot_latched := false
var buzz := Buzz.new()
@export var holding_beer := false
var _beer: _BeerCan
var _hit_flash_left := 0.0
var _flash_material: StandardMaterial3D
## CPU partner plants a shield after a tower sniper connects, or while you snipe.
var wants_cover := false
var _cheer_left := 0.0
var _fling_left := 0.0

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
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	floor_constant_speed = true
	safe_margin = SAFE_MARGIN
	body.build(body_color)
	raygun.build(body_color)
	_flash_material = MeshFactory.material(Color(1.0, 0.12, 0.08), false, Palette.GLOW_STRONG)
	_add_glow()
	health.damaged.connect(_on_damaged)
	health.downed.connect(_on_downed)
	health.revived.connect(_on_revived)
	weapon.fired.connect(_on_fired)
	_shield = _Shield.new()
	add_child(_shield)
	_inspect = _ShopInspect.new()
	add_child(_inspect)
	_beer = _BeerCan.create(1.2)
	_beer.paint_view()
	_beer.visible = false
	head.add_child(_beer)
	add_to_group("players")


func _physics_process(delta: float) -> void:
	if (
		state == State.RIDING
		and (cart == null or not cart.is_riding(self))
		and (not net_driven or is_multiplayer_authority())
	):
		_drop_from_lost_ride()
	if net_driven and not is_multiplayer_authority():
		_animate(delta)
		return
	if brain != null:
		brain.tick(delta)
	if is_driving() and NetSession.is_active() and not multiplayer.is_server() and cart != null:
		cart.report_drive.rpc_id(1, input.move_vector(), input.pressed("shoot"))
	_apply_look(delta)
	_update_shield()
	if health.is_downed():
		head.position.y = DOWNED_HEAD_HEIGHT
	elif is_riding():
		head.position.y = SIT_HEAD_HEIGHT
	else:
		head.position.y = STAND_HEAD_HEIGHT
	_move(delta)
	_fight(delta)
	_interact(delta)
	buzz.tick(delta)
	weapon.power_mult = buzz.weapon_mult()
	_tick_hit_flash(delta)
	_tick_cheer(delta)
	sync_pace = pace()
	sync_gun = weapon.index
	sync_state = int(state)
	sync_dive = _underwater
	sync_firing = weapon.is_firing()
	sync_reload = weapon.reload_fraction()
	sync_scoped = weapon.is_scoped()
	sync_pitch = _pitch
	sync_xform = global_transform
	_animate(delta)


func _process(delta: float) -> void:
	if not NetSession.should_simulate(self):
		_net_interp.follow(self, sync_xform, delta, NetSync.PAWN_HZ)


func is_golfing() -> bool:
	return state == State.GOLFING


func is_swimming() -> bool:
	return state == State.SWIMMING


func is_underwater() -> bool:
	return state == State.SWIMMING and _underwater


func is_carrying_ball() -> bool:
	return golf != null and golf.ball != null and golf.ball.carrier() == self


func is_shielding() -> bool:
	return state == State.SHIELDING


func is_placing() -> bool:
	return state == State.PLACING


func is_celebrating() -> bool:
	return _cheer_left > 0.0


## Solo hole-out: third-person so you see the robot, arms up for a beat.
func celebrate() -> void:
	if is_cpu() or not health.is_alive():
		return
	if is_riding() or is_swimming() or is_golfing():
		return
	_cancel_place()
	if state == State.SHIELDING:
		state = State.NORMAL
		if _shield != null:
			_shield.set_raised(false)
	_cheer_left = PlayerBody.CHEER_TIME
	velocity = Vector3.ZERO


func _tick_cheer(delta: float) -> void:
	if _cheer_left <= 0.0:
		return
	_cheer_left = maxf(0.0, _cheer_left - delta)


func _cheer_view() -> Transform3D:
	var eye := (
		global_position + transform.basis.z * CHEER_CAM_BACK
		+ transform.basis.x * CHEER_CAM_SIDE + Vector3.UP * CHEER_CAM_HEIGHT
	)
	var target := global_position + Vector3.UP * CHEER_CAM_LOOK
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP)


func is_cpu() -> bool:
	return brain != null


## Hands this body to a CPU so a human can play the other seat alone.
func possess_cpu() -> void:
	uses_mouse = false
	input = CpuInput.new(input_prefix, false)
	brain = CpuBuddy.new()
	brain.setup(self)


## Same body answers to the keyboard seat and the pad, for solo play.
func listen_to_both_devices() -> void:
	uses_mouse = true
	var other := "p1" if input_prefix == "p2" else "p2"
	input = PlayerInput.new(input_prefix, true, PackedStringArray([other]))


## Co-op assigns one device per body so a stick or the trackpad cannot turn both.
func bind_seat(p_prefix: String, p_uses_mouse: bool) -> void:
	input_prefix = p_prefix
	uses_mouse = p_uses_mouse
	input = PlayerInput.new(p_prefix, p_uses_mouse)


## How much of a sprint the player is actually travelling at. Both the run cycle and
## the gun bob key off this, so they always agree with each other.
func pace() -> float:
	if net_driven and not is_multiplayer_authority():
		return sync_pace
	return clampf(Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED, 0.0, 1.0)


func wallet():
	if score != null:
		return score
	if flow != null:
		return flow.score
	return null


func fling(direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	if is_riding():
		return
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = -transform.basis.z
	dir = dir.normalized()
	velocity = dir * speed
	velocity.y = maxf(velocity.y, lift)
	_fling_left = lock
	if golf != null and is_golfing():
		golf.cancel_swing()


func apply_knockback(from: Vector3, speed := 10.0) -> void:
	if net_driven and not is_multiplayer_authority():
		_receive_knockback.rpc_id(maxi(1, peer_id), from, speed)
		return
	_do_knockback(from, speed)


func _do_knockback(from: Vector3, speed: float) -> void:
	var away := global_position - from
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -transform.basis.z
	away = away.normalized()
	velocity.x = away.x * speed
	velocity.z = away.z * speed
	velocity.y = maxf(velocity.y, 2.4)
	if golf != null and is_golfing():
		golf.cancel_swing()


@rpc("any_peer", "reliable")
func _receive_knockback(from: Vector3, speed: float) -> void:
	if is_multiplayer_authority():
		_do_knockback(from, speed)


func get_view_transform() -> Transform3D:
	if is_celebrating():
		return _cheer_view()
	if state == State.GOLFING and golf != null:
		return golf.get_camera_transform()
	if is_driving():
		if _cart_chase:
			return cart.chase_view_transform()
		return _drunk_view(cart.driver_view_transform())
	if is_shielding():
		return _drunk_view(_Shield.view_transform(global_position, _yaw, _pitch))
	if is_placing():
		return _drunk_view(_HexBarrier.view_transform(global_position, _yaw, _place_look_at()))
	if shopping:
		return _drunk_view(_ShopInspect.view_transform(global_position, _yaw))
	return _drunk_view(head.global_transform)


func _drunk_view(xform: Transform3D) -> Transform3D:
	var sway := buzz.sway_amount()
	if sway <= 0.0:
		return xform
	var t := Time.get_ticks_msec() * 0.001
	xform.basis = xform.basis.rotated(xform.basis.z, sin(t * 1.35) * sway)
	xform.basis = xform.basis.rotated(xform.basis.y, cos(t * 1.05) * sway * 0.55)
	return xform


func get_view_fov() -> float:
	var bump := buzz.fov_bump() if wants_drunk_fx() else 0.0
	if is_celebrating():
		return CHEER_FOV
	if is_driving():
		return (GolfCart.CHASE_FOV if _cart_chase else DRIVER_FOV) + bump
	if is_shielding():
		return _Shield.CAM_FOV
	if is_placing():
		return _HexBarrier.CAM_FOV
	if shopping:
		return _ShopInspect.CAM_FOV
	var base := BASE_FOV
	if aiming and state == State.NORMAL:
		if weapon != null and weapon.is_scoped():
			base = BASE_FOV / weapon.zoom_mult()
		else:
			base = ADS_FOV
	return base + bump


## The driver's and diver's cameras skip this player's chest, head and legs.
## Arms stay visible.
func cabin_layer() -> int:
	return PlayerBody.CABIN_P1 if input_prefix == "p1" else PlayerBody.CABIN_P2


func view_cull_mask() -> int:
	if _hides_own_cabin():
		return 0xFFFFF & ~cabin_layer()
	return 0xFFFFF


func _hides_own_cabin() -> bool:
	if is_underwater():
		return true
	return is_driving() and not _cart_chase


## Mouse motion is routed here by the splitscreen root, because a captured
## mouse cannot be relied on to land in the right half of the screen.
func add_mouse_look(relative: Vector2) -> void:
	if uses_mouse:
		_mouse_delta += relative


## Plants the player on a spot facing a direction. The golf controller calls this
## every frame to keep the golfer at address, which is also why it leaves pitch
## alone: only a fresh spawn should reset where you are looking.
func stand_at(position: Vector3, facing_yaw: float) -> void:
	global_position = position
	_yaw = facing_yaw
	rotation.y = deg_to_rad(_yaw)
	velocity = Vector3.ZERO
	_fling_left = 0.0


func spawn_at(position: Vector3, facing_yaw: float) -> void:
	if cart != null and cart.is_riding(self):
		cart.eject(self)
	elif state == State.RIDING:
		exit_ride()
	if state == State.GOLFING and golf != null:
		golf.release()
	if is_placing():
		_cancel_place()
	_cheer_left = 0.0
	if _shield != null:
		_shield.set_raised(false)
	if state == State.SHIELDING or state == State.PLACING:
		state = State.NORMAL
	stand_at(position, facing_yaw)
	_pitch = 0.0
	_underwater = false
	if state == State.SWIMMING:
		state = State.NORMAL


func enter_golf_mode() -> void:
	_cancel_place()
	state = State.GOLFING
	velocity = Vector3.ZERO
	aiming = false
	if weapon != null:
		weapon.zoom_step = -1
	if _shield != null:
		_shield.set_raised(false)


func exit_golf_mode() -> void:
	state = State.NORMAL


func enter_ride() -> void:
	_cancel_place()
	state = State.RIDING
	velocity = Vector3.ZERO
	_cart_chase = false
	_set_solid(false)
	if _shield != null:
		_shield.set_raised(false)


func exit_ride() -> void:
	state = State.NORMAL
	_cart_chase = false
	_set_solid(true)


func _set_solid(on: bool) -> void:
	collision_layer = Layers.PLAYER if on else 0
	collision_mask = Layers.PLAYER_MASK if on else 0


## Seat list and rider state drifted apart. Drop beside the cart, not inside it.
func _drop_from_lost_ride() -> void:
	var drop := global_position + Vector3.UP * 0.4
	if cart != null:
		drop = cart.exit_point(1.0 if cart.driver == self else -1.0)
	exit_ride()
	stand_at(drop, _yaw)


func is_riding() -> bool:
	return state == State.RIDING


func is_driving() -> bool:
	return state == State.RIDING and cart != null and cart.driver == self


func enter_boost(along: Vector3) -> void:
	_boost_count += 1
	_boost_along = along
	if _boost_count == 1 and state != State.RIDING:
		Sfx.play("boost_pad", self)


func exit_boost() -> void:
	_boost_count = maxi(0, _boost_count - 1)


## Locked to the cart's heading. Look input is ignored while driving.
func sit_as_driver(sit_at: Vector3, facing_yaw: float) -> void:
	global_position = sit_at
	_yaw = facing_yaw
	_pitch = DRIVER_PITCH
	_mouse_delta = Vector2.ZERO
	rotation.y = deg_to_rad(_yaw)
	head.rotation.x = deg_to_rad(_pitch)


func sit_as_passenger(sit_at: Vector3) -> void:
	global_position = sit_at


func get_prompt() -> String:
	if talking:
		return "%s to move on" % input.hint("interact")
	if shopping:
		return _shop_prompt()
	if is_cpu() and health.is_alive() and state == State.NORMAL:
		if _partner_needs_revive():
			return "CPU reviving"
		if brain != null and brain.is_taking_shot():
			return "CPU taking the shot"
		return "CPU partner"
	if health.is_downed():
		return "Downed - hold on for your partner"
	if _partner_needs_revive():
		return "Hold %s to revive" % input.hint("revive")
	if state == State.SWIMMING:
		return _swim_prompt()
	if state == State.GOLFING:
		return "%s to swing   %s to leave the ball" % [input.hint("swing"), input.hint("interact")]
	if state == State.SHIELDING:
		return "Shield up   look to cover   release %s to drop" % input.hint("shield")
	if state == State.PLACING:
		if _place_ok:
			return "%s to place   %s to cancel" % [
				input.hint("shoot"), input.hint("swap_gear")
			]
		return "No room to place   %s to cancel" % input.hint("swap_gear")
	if state == State.RIDING:
		if cart.driver == self:
			return "Drive with %s   %s boost / drift   %s view   %s to hop out" % [
				input.hint("move"), input.hint("shoot"), input.hint("melee"),
				input.hint("interact")
			]
		return "Riding along   %s to hop out" % input.hint("interact")
	if _can_start_play():
		return "%s to start the hole" % input.hint("interact")
	if _can_open_doors():
		return "%s to enter the clubhouse" % input.hint("interact")
	if _can_open_exit():
		return "%s to the next hole" % input.hint("interact")
	if _station() != null:
		return "%s to shop %s" % [input.hint("interact"), _station().title]
	if _npc() != null:
		return "%s to talk to %s" % [input.hint("interact"), _npc().npc_name]
	if _beer_cart() != null:
		return _beer_prompt()
	if _can_retrieve_ball():
		return "%s to pick up your ball" % input.hint("interact")
	if golf != null and golf.can_claim(self):
		if _orders_cpu_shots():
			return "%s to play the ball   hold %s for CPU shot" % [
				input.hint("interact"), input.hint("interact")
			]
		return "%s to play the ball" % input.hint("interact")
	if _active_cart() != null and _active_cart().can_board(self):
		return "%s to hop in the cart" % input.hint("interact")
	if _orders_cpu_shots() and golf != null and golf.is_available():
		return "Hold %s for CPU to take the shot" % input.hint("interact")
	if is_holding_beer():
		return "%s to drink   %s to throw   beer x%d" % [
			input.hint("interact"), input.hint("shoot"), buzz.held
		]
	if buzz.held > 0:
		return "%s for beer" % input.hint("swap_weapon")
	return ""


## Hold triangle (or M) for a top-down of the hole. Triangle still revives when
## a partner is down next to you, so the map waits until they are up. In a shop
## the same button reads the hovered item instead.
func wants_map() -> bool:
	if is_cpu() or not health.is_alive() or shopping or talking:
		return false
	if _partner_needs_revive():
		return false
	return input.pressed("map")


func wants_shop_info() -> bool:
	return shopping and health.is_alive() and input.pressed("map")


func _partner_needs_revive() -> bool:
	return (
		partner != null and partner.health.is_downed()
		and _distance_to(partner) <= REVIVE_RANGE
	)


func _apply_look(delta: float) -> void:
	_view_kick = move_toward(_view_kick, 0.0, VIEW_KICK_RECOVER * delta)
	if is_driving():
		if input.just_pressed("melee"):
			_cart_chase = not _cart_chase
		_mouse_delta = Vector2.ZERO
		return
	if is_celebrating():
		_mouse_delta = Vector2.ZERO
		return
	var look := Vector2.ZERO
	if uses_mouse:
		look += _mouse_delta * MOUSE_DEG_PER_PIXEL
	# Co-op keyboard seats must not also read the stick, or one pad turns both
	# viewports. Solo and online still stack mouse and pad on the same body.
	if not uses_mouse or GameSettings.mode != GameSettings.Mode.COOP:
		look += input.stick_look() * STICK_DEG_PER_SEC * delta
	_mouse_delta = Vector2.ZERO
	var zoom := 1.0
	if weapon != null:
		zoom = weapon.zoom_mult()
	if zoom > 1.0:
		look /= zoom
	if state == State.GOLFING:
		golf.aim_by(-look.x)
		return
	if shopping:
		_turn_shop(look, delta)
		return
	_yaw = wrapf(_yaw - look.x, -180.0, 180.0)
	_pitch = clampf(_pitch - look.y, -PITCH_LIMIT, PITCH_LIMIT)
	rotation.y = deg_to_rad(_yaw)
	head.rotation.x = deg_to_rad(clampf(_pitch + _view_kick, -PITCH_LIMIT, PITCH_LIMIT))


func _update_shield() -> void:
	if is_placing():
		return
	var was_up := state == State.SHIELDING
	if state == State.SHIELDING and not _wants_shield():
		state = State.NORMAL
	elif state == State.NORMAL and _wants_shield():
		state = State.SHIELDING
		velocity.x = 0.0
		velocity.z = 0.0
	if _shield != null:
		_shield.set_raised(state == State.SHIELDING)
	if state == State.SHIELDING and not was_up:
		Sfx.play("shield_up", self)
	elif was_up and state != State.SHIELDING:
		Sfx.play("shield_down", self)


func _wants_shield() -> bool:
	return (
		health.is_alive()
		and input.pressed("shield")
		and not shopping
		and not talking
		and not _in_clubhouse()
		and not is_carrying_ball()
	)


func _swap_gear() -> void:
	if is_placing():
		_cancel_place()
		return
	if _has_barrier_charges():
		_begin_place()


func _tick_scope() -> void:
	if weapon.stats().has_scope():
		if input.just_pressed("zoom"):
			weapon.cycle_zoom()
			Sfx.play("scope", self)
		aiming = weapon.is_scoped()
		return
	weapon.zoom_step = -1
	aiming = input.pressed("aim")


func _has_barrier_charges() -> bool:
	var card = wallet()
	return card != null and card.barrier_charges > 0


func _begin_place() -> void:
	if not _has_barrier_charges() or not health.is_alive():
		return
	state = State.PLACING
	if _place_ghost == null:
		_place_ghost = _HexBarrier.preview()
		add_child(_place_ghost)
	_tick_place()


func _cancel_place() -> void:
	if _place_ghost != null:
		_place_ghost.queue_free()
		_place_ghost = null
	_place_ok = false
	if state == State.PLACING:
		state = State.NORMAL


func _confirm_place() -> void:
	if not _place_ok or not _has_barrier_charges():
		return
	if NetSession.defers_world():
		_request_place.rpc_id(1, _place_at, _yaw)
		_cancel_place()
		return
	_host_place(_place_at, _yaw)


func _host_place(at: Vector3, yaw_deg: float) -> void:
	if not _has_barrier_charges():
		return
	if not wallet().try_place_barrier():
		_cancel_place()
		return
	var parent: Node = flow.hole_node() if flow.has_method("hole_node") else null
	if parent == null:
		parent = get_parent()
	_HexBarrier.spawn(parent, at, yaw_deg)
	_WorldFx.announce_barrier(self, at, yaw_deg)
	_cancel_place()


@rpc("any_peer", "reliable")
func _request_place(at: Vector3, yaw_deg: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_host_place(at, yaw_deg)


func _tick_place() -> void:
	if not _has_barrier_charges():
		_cancel_place()
		return
	var aimed := _HexBarrier.aim_point(
		get_world_3d(), head.global_position, -head.global_transform.basis.z
	)
	_place_at = aimed["point"]
	_place_ok = bool(aimed["ok"]) and not _place_in_water(_place_at)
	if _place_ghost == null:
		return
	_place_ghost.global_position = _place_at
	_place_ghost.rotation.y = deg_to_rad(_yaw)
	_place_ghost.set_ghost_visible(_place_ok)


func _place_look_at() -> Vector3:
	if _place_ghost != null:
		return _place_at
	return global_position + Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(_yaw)) * 6.0


func _place_in_water(at: Vector3) -> bool:
	if flow == null or flow.hole == null:
		return false
	return flow.hole.water_depth_at(at) >= PLACE_WATER


func _move(delta: float) -> void:
	# Riders are carried by the cart. Golfers are planted at address. Either one
	# calling move_and_slide inside the heightmap is how a seat can freeze.
	if state == State.RIDING or state == State.GOLFING:
		return
	if _fling_left > 0.0:
		_fling_left = maxf(0.0, _fling_left - delta)
		if not is_on_floor():
			velocity += get_gravity() * delta
		move_and_slide()
		return
	var wading := _water_depth()
	if _should_swim(wading):
		_swim(delta)
		return
	if state == State.SWIMMING:
		_leave_water()
	if not is_on_floor():
		velocity += get_gravity() * delta
	var mobile := (
		health.is_alive() and (state == State.NORMAL or state == State.PLACING)
		and not is_celebrating()
	)
	var wish := Vector3.ZERO
	if mobile:
		var stick := input.move_vector()
		wish = (transform.basis * Vector3(stick.x, 0.0, stick.y))
		wish.y = 0.0
		wish = wish.normalized() * minf(1.0, stick.length())
		if input.just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY
			Sfx.play("jump", self)
	var speed := SPRINT_SPEED if mobile and input.pressed("sprint") else WALK_SPEED
	if wading > WADE_DRAG_DEPTH:
		speed *= WADE_SPEED_SCALE
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	if _boost_count > 0:
		velocity = _Boost.player_velocity(velocity, _boost_along, delta)
	move_and_slide()


func _fight(delta: float) -> void:
	melee.tick(delta)
	if shopping:
		aiming = false
		if weapon != null:
			weapon.zoom_step = -1
		weapon.tick(delta, head.global_transform, false, false, false)
		if input.just_pressed("swap_weapon") or input.just_pressed("swap_weapon_prev"):
			_cycle_shop(-1 if input.just_pressed("swap_weapon_prev") else 1)
		return
	if is_placing():
		aiming = false
		if weapon != null:
			weapon.zoom_step = -1
		weapon.tick(delta, head.global_transform, false, false, false)
		_tick_place()
		if input.just_pressed("swap_gear") or input.just_pressed("swap_gear_prev"):
			_cancel_place()
		elif input.just_pressed("swap_weapon"):
			_cycle_held(1)
		elif input.just_pressed("swap_weapon_prev"):
			_cycle_held(-1)
		elif input.just_pressed("shoot"):
			_confirm_place()
		return
	# Riding shotgun you can still shoot. The driver is on the wheel. Water is a
	# swim: R2 dives or throws the ball instead of firing.
	var can_fight := (
		health.is_alive() and state != State.GOLFING and not is_driving()
		and not is_swimming() and not is_carrying_ball() and not is_shielding()
		and not _in_clubhouse() and not is_celebrating()
	)
	if not can_fight:
		aiming = false
		if weapon != null:
			weapon.zoom_step = -1
		weapon.tick(delta, head.global_transform, false, false, false)
		if is_carrying_ball() and not is_underwater() and input.just_pressed("shoot"):
			_throw_ball()
		return
	if is_holding_beer():
		aiming = false
		weapon.tick(delta, head.global_transform, false, false, false)
		if input.just_pressed("shoot"):
			throw_beer()
		if input.just_pressed("swap_weapon"):
			_cycle_held(1)
		elif input.just_pressed("swap_weapon_prev"):
			_cycle_held(-1)
		if input.just_pressed("swap_gear") or input.just_pressed("swap_gear_prev"):
			_swap_gear()
		return
	_tick_scope()
	weapon.tick(
		delta, head.global_transform,
		input.pressed("shoot"), input.just_pressed("shoot"), aiming
	)
	if input.just_pressed("reload"):
		weapon.start_reload()
	if input.just_pressed("swap_weapon"):
		_cycle_held(1)
	if input.just_pressed("swap_weapon_prev"):
		_cycle_held(-1)
	if input.just_pressed("swap_gear") or input.just_pressed("swap_gear_prev"):
		_swap_gear()
	if input.just_pressed("melee"):
		_try_melee()


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


func _try_melee() -> void:
	var origin := head.global_position
	var forward := -head.global_transform.basis.z
	var strength := buzz.strength_mult()
	if NetSession.is_active() and not multiplayer.is_server():
		_request_melee.rpc_id(1, origin, forward, strength)
		_play_melee()
		return
	if melee.shove(origin, forward, strength, self):
		_play_melee()


func _play_melee() -> void:
	if body != null:
		body.start_melee()
	if raygun != null:
		raygun.start_melee()
	_view_kick += MELEE_VIEW_KICK
	Sfx.play("melee_swing", self)
	if NetSession.is_active() and is_multiplayer_authority():
		_replicate_melee.rpc()


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


func _apply_replicated_pose() -> void:
	state = sync_state as State
	_underwater = sync_dive
	if weapon != null:
		weapon.apply_replicated_index(sync_gun)
		weapon.apply_replicated_pose(sync_firing, sync_reload, sync_scoped)
	if _shield != null:
		_shield.set_raised(state == State.SHIELDING)
	_pitch = sync_pitch
	if head != null:
		head.rotation.x = deg_to_rad(clampf(sync_pitch, -PITCH_LIMIT, PITCH_LIMIT))
	if health != null and health.is_downed():
		head.position.y = DOWNED_HEAD_HEIGHT
	elif is_riding():
		head.position.y = SIT_HEAD_HEIGHT
	else:
		head.position.y = STAND_HEAD_HEIGHT


## The gun is stowed for the swing, since the golfer is holding a club, and dropped
## when you go down.
func _animate(delta: float) -> void:
	if net_driven and not is_multiplayer_authority():
		_apply_replicated_pose()
	if health.is_alive() and body != null and body.is_locked_limp():
		body.stop_limp()
	var travel := pace()
	if body != null and body.is_limp():
		body.tick_limp(delta, not is_on_floor() and not is_riding())
	elif is_riding():
		var wheel := 0.0
		var grips: Array[Vector3] = []
		if is_driving() and cart != null:
			wheel = cart.wheel_angle_deg()
			grips = cart.wheel_grips()
		body.sit(is_driving(), wheel, grips)
	elif is_swimming():
		body.swim(delta, pace(), _underwater)
	elif is_celebrating():
		body.cheer(delta, _cheer_left)
	elif is_shielding():
		body.guard()
	else:
		body.animate(delta, travel)
	if not is_celebrating():
		body.tick_melee(delta)
	if net_driven and not is_multiplayer_authority() and body != null and body.head != null:
		if not body.is_limp() and not is_celebrating():
			body.head.rotation.x = deg_to_rad(clampf(sync_pitch, -PITCH_LIMIT, PITCH_LIMIT))
	body.hide_cabin_from_driver(cabin_layer(), _hides_own_cabin())
	var show_gun := (
		health.is_alive() and state != State.GOLFING and not is_driving()
		and not is_swimming() and not is_shielding() and not is_placing()
		and not is_holding_beer() and not weapon.is_scoped() and not is_celebrating()
		and not shopping
	)
	raygun.visible = show_gun
	if show_gun:
		raygun.show_gun(weapon.stats().visual)
		raygun.animate(delta, travel, weapon.is_firing(), weapon.reload_fraction())
	if _beer != null:
		var show_beer := (
			is_holding_beer() and health.is_alive() and state != State.GOLFING
			and not is_driving() and not is_swimming() and not is_shielding()
			and not is_placing()
		)
		_beer.animate(delta, show_beer)


func _orders_cpu_shots() -> bool:
	return partner != null and partner.is_cpu() and not is_cpu()


func _interact(delta: float) -> void:
	if shopping and _station() == null:
		close_shop()
	if talking and _npc() == null:
		stop_talk()
	if is_swimming() and input.just_pressed("grab"):
		if _can_grab_ball():
			_try_grab_ball()
		else:
			_try_climb_out()
	elif _orders_cpu_shots():
		_tick_cpu_shot_command(delta)
	elif not is_swimming() and health.is_alive() and input.just_pressed("interact"):
		_use_interact()
	if state == State.GOLFING and input.just_pressed("swing"):
		golf.click()
	if partner == null:
		return
	if health.is_alive() and _partner_needs_revive() and input.pressed("revive"):
		if NetSession.defers_world():
			_request_revive.rpc_id(1, partner.peer_id)
		else:
			partner.health.add_revive_progress(delta)
	elif partner.health.revive_progress > 0.0 and not NetSession.is_active():
		partner.health.reset_revive_progress()


func _tick_cpu_shot_command(delta: float) -> void:
	if shopping or talking or not health.is_alive() or is_swimming():
		if (shopping or talking) and input.just_pressed("interact"):
			_use_interact()
			_cpu_shot_latched = true
		if not input.pressed("interact"):
			_cpu_shot_hold = 0.0
			_cpu_shot_latched = false
		return
	if not _cpu_shot_hold_applies():
		if input.just_pressed("interact"):
			_use_interact()
			_cpu_shot_latched = true
		elif not input.pressed("interact"):
			_cpu_shot_hold = 0.0
			_cpu_shot_latched = false
		return
	if input.pressed("interact"):
		if _cpu_shot_latched:
			return
		_cpu_shot_hold += delta
		if _cpu_shot_hold >= CPU_SHOT_HOLD:
			_cpu_shot_latched = true
			if partner != null and partner.brain != null:
				partner.brain.request_shot()
	elif input.just_released("interact"):
		if not _cpu_shot_latched:
			_use_interact()
		_cpu_shot_hold = 0.0
		_cpu_shot_latched = false
	else:
		_cpu_shot_hold = 0.0
		_cpu_shot_latched = false


## Hold vs tap is only for "you take this shot or the CPU does". Cart, shop,
## retrieve, and hop-out stay on press so a release cannot undo them.
func _cpu_shot_hold_applies() -> bool:
	if state != State.NORMAL or shopping or talking:
		return false
	if _can_open_doors() or _can_open_exit() or _station() != null or _npc() != null or _can_retrieve_ball():
		return false
	if _can_start_play() or _beer_cart() != null:
		return false
	if _active_cart() != null and _active_cart().can_board(self) and (golf == null or not golf.can_claim(self)):
		return false
	return true


## One button covers the ball, the cart, and the clubhouse. Hop out if you are
## riding; shop if the pavilion is open; pick the ball out of the cup after a
## hole-out; else play the ball; else climb in.
func _use_interact() -> void:
	if shopping:
		_shop_confirm()
	elif talking:
		stop_talk()
	elif state == State.RIDING:
		cart.eject(self)
	elif _can_open_doors():
		open_doors()
	elif _station() != null:
		open_station(_station())
	elif _npc() != null:
		start_talk(_npc())
	elif _can_open_exit():
		flow.leave_clubhouse()
	elif _can_start_play():
		flow.start_play()
	elif _beer_cart() != null:
		_use_beer_cart()
	elif _can_retrieve_ball():
		flow.retrieve_ball(self)
	elif golf != null and (golf.golfer == self or golf.can_claim(self)):
		golf.try_toggle(self)
	elif _active_cart() != null and _active_cart().can_board(self):
		_active_cart().board(self)
	elif is_holding_beer():
		chug()


func open_shop() -> void:
	open_doors()


func open_doors() -> void:
	if flow == null or not flow.has_shop():
		return
	flow.arrive_at_clubhouse()


func open_station(station: ShopStation) -> void:
	if station == null or flow == null or not flow.has_shop():
		return
	stop_talk()
	shopping = true
	shop_choice = 0
	shop_dept = station.dept
	Sfx.play("shop_open", self)
	if station.cashier != null:
		station.cashier.address(self)
	_begin_shop_inspect(station)


func start_talk(npc: ClubhouseNpc) -> void:
	if npc == null:
		return
	close_shop()
	if _talk_npc != null and _talk_npc != npc:
		_talk_npc.stop_address()
	_talk_npc = npc
	npc.address(self)
	talking = true
	talk_name = npc.npc_name
	talk_line = npc.next_line()
	Sfx.play("talk", self)


func stop_talk() -> void:
	if _talk_npc != null:
		_talk_npc.stop_address()
		_talk_npc = null
	talking = false
	talk_line = ""


func close_shop() -> void:
	_end_shop_inspect()
	shopping = false
	if flow == null:
		return
	var house = flow.get("clubhouse")
	if house == null or not is_instance_valid(house):
		return
	for station in house.stations:
		if station.cashier != null:
			station.cashier.stop_address()


func incoming_damage(amount: float) -> float:
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
	_knock_from(from)
	_flop_from(from, hit_at, amount, health.is_downed())


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
	return _hit_flash_left > 0.0


## Horizontal shove away from the attacker. Kept flat so a blow from above still
## slides you back instead of driving you into the turf.
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
	return shopping and shop_dept == Shop.Dept.APPAREL


func _begin_shop_inspect(station: ShopStation) -> void:
	_dressing = true
	_dress_saved_yaw = _yaw
	_face_aisle(station)
	_preview_shop_item()


func _end_shop_inspect() -> void:
	if _dressing:
		_yaw = _dress_saved_yaw
		rotation.y = deg_to_rad(_yaw)
		_dressing = false
	if body != null:
		body.rotation = Vector3.ZERO
		body.clear_try_on()
	if _inspect != null:
		_inspect.clear()


func _face_aisle(station: ShopStation) -> void:
	if station == null:
		return
	var aisle := station.global_transform.basis.z
	aisle.y = 0.0
	if aisle.length_squared() < 0.0001:
		return
	aisle = aisle.normalized()
	_yaw = wrapf(rad_to_deg(atan2(-aisle.x, -aisle.z)), -180.0, 180.0)
	rotation.y = deg_to_rad(_yaw)
	_pitch = 0.0
	if head != null:
		head.rotation.x = 0.0


func _preview_shop_item() -> void:
	if flow == null or not flow.has_shop():
		if body != null:
			body.clear_try_on()
		if _inspect != null:
			_inspect.clear()
		return
	var item: Dictionary = flow.shop_item(shop_choice, shop_dept)
	if trying_on_apparel():
		if _inspect != null:
			_inspect.clear()
		if body != null:
			body.rotation = Vector3.ZERO
			body.try_on(item)
		return
	if body != null:
		body.clear_try_on()
		body.rotation = Vector3.ZERO
	if _inspect != null:
		_inspect.show_item(item)


func _turn_shop(look: Vector2, _delta: float) -> void:
	if _inspect == null:
		return
	_inspect.spin(look, not trying_on_apparel())
	if trying_on_apparel() and body != null:
		body.rotation.y = deg_to_rad(_inspect.yaw)


func _in_clubhouse() -> bool:
	return flow != null and flow.in_clubhouse()


func _can_open_doors() -> bool:
	return flow != null and flow.has_method("can_open_doors") and flow.can_open_doors(self)


func _can_open_exit() -> bool:
	return flow != null and flow.has_method("can_open_exit") and flow.can_open_exit(self)


func _station() -> ShopStation:
	if flow == null or not flow.has_method("station_for"):
		return null
	return flow.station_for(self)


func _npc() -> ClubhouseNpc:
	if flow == null or not flow.has_method("npc_for"):
		return null
	return flow.npc_for(self)


func _beer_cart():
	if flow == null or not flow.has_method("beer_cart_for"):
		return null
	return flow.beer_cart_for(self)


func _active_cart() -> GolfCart:
	if flow != null and flow.has_method("cart_for"):
		return flow.cart_for(self)
	return cart


func _beer_prompt() -> String:
	var girl = _beer_cart()
	if girl == null:
		return ""
	if not girl.cooler_open:
		return "%s to flip the cooler" % input.hint("interact")
	var cash := 0
	var card = wallet()
	if card != null:
		cash = card.money
	if not Buzz.can_afford(cash):
		return "Beer %s   need more cash" % GameState.format_money(Buzz.PRICE)
	return "%s to grab a beer %s" % [
		input.hint("interact"), GameState.format_money(Buzz.PRICE)
	]


func _use_beer_cart() -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		_request_beer_cart.rpc_id(1)
		return
	_commit_beer_cart()


func _commit_beer_cart() -> void:
	var girl = _beer_cart()
	if girl == null:
		return
	if not girl.cooler_open:
		girl.open_cooler()
		_WorldFx.announce_sfx(self, "cooler_open")
		return
	if not girl.sell_to(self):
		return
	_WorldFx.announce_sfx(self, "buy_beer")
	_WorldFx.announce_cart_girl(self, "cheer")
	if flow != null and flow.has_method("note_beer_sale"):
		flow.note_beer_sale(self)


func apply_held_beers(held: int) -> void:
	buzz.held = maxi(0, held)


@rpc("any_peer", "reliable")
func _request_beer_cart() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	_commit_beer_cart()


func is_holding_beer() -> bool:
	if net_driven and not is_multiplayer_authority():
		return holding_beer
	var sipping: bool = _beer != null and _beer.is_busy()
	if holding_beer and buzz.held <= 0 and not sipping:
		holding_beer = false
	return holding_beer


func _cycle_held(step := 1) -> void:
	if step == 0:
		return
	if is_holding_beer():
		holding_beer = false
		Sfx.play("weapon_swap", self)
		if step > 0:
			weapon.index = 0
		return
	if buzz.held > 0:
		if step > 0 and weapon.index == weapon.loadout.size() - 1:
			holding_beer = true
			Sfx.play("weapon_swap", self)
			return
		if step < 0 and weapon.index == 0:
			holding_beer = true
			Sfx.play("weapon_swap", self)
			return
	weapon.swap(step)


func throw_beer() -> bool:
	if not is_holding_beer() or (_beer != null and _beer.is_busy()):
		return false
	if not buzz.spend():
		holding_beer = false
		return false
	if _beer != null:
		_beer.toss()
	Sfx.play("throw_beer", self)
	var view := get_view_transform()
	var fly := -view.basis.z
	var muzzle := view.origin + fly * 0.7
	if NetSession.defers_world():
		_request_throw_beer.rpc_id(1, muzzle, fly)
		return true
	_spawn_thrown_beer(muzzle, fly)
	return true


func _spawn_thrown_beer(muzzle: Vector3, fly: Vector3) -> void:
	var root := get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = get_tree().current_scene
	_ThrownBeer.spawn(root, muzzle, fly)
	_WorldFx.announce_beer(self, muzzle, fly)


@rpc("any_peer", "reliable")
func _request_throw_beer(muzzle: Vector3, fly: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	if not buzz.spend():
		return
	_spawn_thrown_beer(muzzle, fly)


func chug() -> bool:
	if not health.is_alive() or not is_holding_beer():
		return false
	if _beer != null and _beer.is_busy():
		return false
	if not buzz.chug():
		holding_beer = false
		return false
	if _beer != null:
		_beer.drink()
	_view_kick += Buzz.CHUG_KICK
	Sfx.play("drink_beer", self)
	if NetSession.is_active() and not multiplayer.is_server():
		_request_chug.rpc_id(1)
	return true


@rpc("any_peer", "reliable")
func _request_chug() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != peer_id:
		return
	buzz.spend()


func wants_drunk_fx() -> bool:
	if buzz.extra_beers() <= 0:
		return false
	if is_golfing():
		return false
	if is_driving() and _cart_chase:
		return false
	return true


func _can_retrieve_ball() -> bool:
	return flow != null and flow.can_retrieve_ball(self)


func _can_start_play() -> bool:
	return flow != null and flow.has_method("can_start_play") and flow.can_start_play(self)


func _cycle_shop(step := 1) -> void:
	if flow == null or not flow.has_shop():
		return
	shop_choice = posmod(shop_choice + step, flow.shop_count(shop_dept))
	Sfx.play("ui_move", self)
	_preview_shop_item()


func _shop_confirm() -> void:
	if flow == null or not flow.has_shop():
		return
	var item: Dictionary = flow.shop_item(shop_choice, shop_dept)
	if item.is_empty():
		return
	flow.buy_shop_item(String(item["id"]), self)


func _shop_prompt() -> String:
	if flow == null or not flow.has_shop():
		return ""
	var item: Dictionary = flow.shop_item(shop_choice, shop_dept)
	var browse := input.hint("swap_weapon")
	var inspect := input.hint("map")
	if String(item.get("kind", "")) == "next":
		return "%s to leave for the next hole   %s to browse" % [
			input.hint("interact"), browse
		]
	if flow.shop_owned(String(item["id"]), self):
		return "%s   owned   %s to browse   %s to turn   %s for info" % [
			String(item["name"]), browse, input.hint("look"), inspect
		]
	if not flow.shop_can_buy(String(item["id"]), self):
		return "%s   %s   %s to browse   %s to turn   %s for info" % [
			String(item["name"]), GameState.format_money(int(item["price"])),
			browse, input.hint("look"), inspect
		]
	return "%s to buy %s  %s   %s to browse   %s to turn   %s for info" % [
		input.hint("interact"), String(item["name"]),
		GameState.format_money(int(item["price"])), browse,
		input.hint("look"), inspect
	]


## Each player carries a lamp in their own colour. The course is lit by moonlight
## only, so this is what makes footing and nearby zombies readable, and it doubles
## as the tell for where your partner is.
func _add_glow() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_cull_mask = ~Raygun.VIEW_LAYER
	lamp.light_color = body_color
	lamp.light_energy = 0.85
	lamp.omni_range = 12.0
	lamp.omni_attenuation = 0.8
	lamp.position.y = 1.4
	add_child(lamp)


func _distance_to(other: Node3D) -> float:
	var offset := other.global_position - global_position
	offset.y = 0.0
	return offset.length()


## Shallow water is walked through, so the shoreline is waded into on foot. Only
## once it is over your chest do you start treading, and only your own dive takes
## you under from there.
func _should_swim(water_depth: float) -> bool:
	if not health.is_alive() or state == State.GOLFING or state == State.RIDING:
		return false
	if state == State.SWIMMING and _underwater:
		return true
	return water_depth >= WADE_DEPTH


func _water_depth() -> float:
	if flow == null or flow.hole == null:
		return 0.0
	return flow.hole.water_depth_at(global_position)


func _enter_water() -> void:
	_cancel_place()
	state = State.SWIMMING
	aiming = false
	Sfx.play("splash", self)
	if _shield != null:
		_shield.set_raised(false)
	if golf != null and golf.golfer == self:
		golf.release()


func _leave_water() -> void:
	_underwater = false
	if state == State.SWIMMING:
		state = State.NORMAL


## Treading water. You ride the surface with your head out until the dive button
## takes you under, and from there descend and ascend hold you between the floor
## and the water line.
func _swim(delta: float) -> void:
	if state != State.SWIMMING:
		_enter_water()
	var bed_y := _water_floor_y() + SWIM_FLOOR_CLEARANCE
	var float_y := maxf(_water_surface_y() - SWIM_FLOAT_DEPTH, bed_y)
	if not _underwater and not is_carrying_ball() and input.just_pressed("shoot"):
		_underwater = true
		velocity.y = -SWIM_DIVE_SPEED
		Sfx.play("dive", self)
	var stick := input.move_vector() if health.is_alive() else Vector2.ZERO
	var wish := (transform.basis * Vector3(stick.x, 0.0, stick.y))
	wish.y = 0.0
	if wish.length_squared() > 0.0001:
		wish = wish.normalized() * minf(1.0, stick.length()) * SWIM_SPEED
	else:
		wish = Vector3.ZERO
	velocity.x = move_toward(velocity.x, wish.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, wish.z, ACCELERATION * delta)
	if _underwater:
		var vertical := 0.0
		if input.pressed("melee"):
			vertical -= SWIM_VERTICAL
		if input.pressed("ascend"):
			vertical += SWIM_VERTICAL
		velocity.y = move_toward(velocity.y, vertical, ACCELERATION * delta)
	else:
		velocity.y = 0.0
	move_and_slide()
	if _underwater:
		global_position.y = clampf(global_position.y, bed_y, float_y)
		if input.pressed("ascend") and global_position.y >= float_y - 0.05:
			_underwater = false
			velocity.y = 0.0
		return
	# Buoyancy rather than a snap, so stepping off the bank is a wade and not a
	# teleport onto the water line.
	global_position.y = move_toward(global_position.y, float_y, SWIM_SETTLE_SPEED * delta)


func _water_surface_y() -> float:
	if flow != null and flow.hole != null:
		return flow.hole.water_surface_y(global_position)
	return global_position.y + SWIM_FLOAT_DEPTH


func _water_floor_y() -> float:
	if flow != null and flow.hole != null:
		return flow.hole.water_floor_y(global_position)
	return global_position.y - HeightField.WATER_DEPTH


func _try_grab_ball() -> void:
	if golf == null or golf.ball == null or golf.ball.is_carried():
		return
	if global_position.distance_to(golf.ball.global_position) > SWIM_GRAB_RANGE:
		return
	golf.ball.pick_up(self)
	Sfx.play("grab_ball", self)


## Circle / Space while treading, empty-handed, and close enough to the bank.
## The float sits you below the shelf, so walking into it never gets you out.
func _try_climb_out() -> bool:
	if _underwater or is_carrying_ball():
		return false
	var land := _climb_out_at()
	if land == Vector3.INF:
		return false
	_leave_water()
	global_position = land
	velocity = Vector3.ZERO
	Sfx.play("splash", self)
	return true


func _can_climb_out() -> bool:
	return not _underwater and not is_carrying_ball() and _climb_out_at() != Vector3.INF


func _climb_out_at() -> Vector3:
	if flow == null or flow.hole == null:
		return Vector3.INF
	var facing := Vector3(-transform.basis.z.x, 0.0, -transform.basis.z.z)
	if facing.length_squared() < 0.0001:
		facing = Vector3.FORWARD
	else:
		facing = facing.normalized()
	var probes: Array[Vector3] = []
	for dist in [1.2, 2.2, SWIM_CLIMB_REACH]:
		probes.append(global_position + facing * dist)
	for radius in [1.8, SWIM_CLIMB_REACH]:
		for i in 12:
			var angle := TAU * float(i) / 12.0
			probes.append(global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius)
	var best := Vector3.INF
	var best_depth := INF
	for probe in probes:
		var depth: float = flow.hole.water_depth_at(probe)
		if depth >= WADE_DEPTH:
			continue
		if depth < best_depth:
			best_depth = depth
			best = Vector3(probe.x, flow.hole.water_floor_y(probe), probe.z)
	return best


func _throw_ball() -> void:
	if not is_carrying_ball():
		return
	var forward := -head.global_transform.basis.z
	golf.ball.toss(
		head.global_position + forward * 0.8,
		throw_velocity(forward)
	)
	Sfx.play("throw_ball", self)


static func throw_velocity(forward: Vector3) -> Vector3:
	var dir := (forward + Vector3.UP * SWIM_THROW_LIFT).normalized()
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	return dir * SWIM_THROW_SPEED


static func carry_point(held_at: Transform3D) -> Vector3:
	return held_at.origin + (-held_at.basis.z * SWIM_CARRY_FORWARD) + Vector3.DOWN * SWIM_CARRY_HEIGHT


func _swim_prompt() -> String:
	if _underwater:
		if _can_grab_ball():
			return "%s to grab the ball   %s down   %s up" % [
				input.hint("grab"), input.hint("descend"), input.hint("ascend")
			]
		return "Underwater   %s down   %s up to the surface" % [
			input.hint("descend"), input.hint("ascend")
		]
	if is_carrying_ball():
		return "%s to throw the ball to your partner" % input.hint("shoot")
	if _can_climb_out():
		return "Treading water   %s to climb out   %s to dive" % [
			input.hint("grab"), input.hint("shoot")
		]
	return "Treading water   %s to dive for the ball" % input.hint("shoot")


func _can_grab_ball() -> bool:
	if golf == null or golf.ball == null or is_carrying_ball():
		return false
	return global_position.distance_to(golf.ball.global_position) <= SWIM_GRAB_RANGE


func _on_fired() -> void:
	var kick := weapon.stats().kick
	raygun.kick(kick)
	_view_kick += kick * VIEW_KICK_DEG


func _on_damaged(_amount: float) -> void:
	if state == State.GOLFING and golf != null:
		golf.cancel_swing()
	_start_hit_flash()


func _start_hit_flash() -> void:
	_hit_flash_left = HIT_FLASH_TIME
	if body != null:
		body.set_flash(_flash_material)


func _tick_hit_flash(delta: float) -> void:
	if _hit_flash_left <= 0.0:
		return
	_hit_flash_left = maxf(0.0, _hit_flash_left - delta)
	if is_zero_approx(_hit_flash_left) and body != null:
		body.set_flash(null)


func _knock_from(from: Vector3) -> void:
	if is_riding():
		return
	var push := hit_push(from, global_position)
	velocity.x += push.x
	velocity.z += push.z


func _on_downed() -> void:
	if is_carrying_ball():
		golf.ball.release_carried()
	if state == State.GOLFING and golf != null:
		golf.release()
	if state == State.SWIMMING:
		_leave_water()
	# Dumped out of the cart, so your partner has to come and pick you up.
	if state == State.RIDING:
		cart.eject(self)
	if is_placing():
		_cancel_place()
		state = State.NORMAL
	_cheer_left = 0.0
	if _shield != null:
		_shield.set_raised(false)
	if body != null:
		body.flop(Ragdoll.Region.TORSO, -transform.basis.z, 1.7, true)


func _on_revived() -> void:
	if body != null:
		body.stop_limp()


func _flop_from(from: Vector3, hit_at: Vector3, amount: float, locked: bool) -> void:
	if body == null or is_riding():
		return
	var at := hit_at
	if not at.is_finite():
		at = global_position + Vector3.UP * STAND_HEAD_HEIGHT * 0.6
	var region := Ragdoll.region(
		at, global_position, 1.8, BODY_RADIUS, global_transform.basis.x
	)
	var direction := at - from
	if direction.length_squared() < 0.0001:
		direction = -transform.basis.z
	body.flop(region, direction, Ragdoll.strength_for(amount, 1.0), locked)
	if not locked:
		velocity.y += Ragdoll.shot_pop(region, amount, 1.0).y
