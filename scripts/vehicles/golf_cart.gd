class_name GolfCart
extends CharacterBody3D
## The shared cart. Either player can hop in; whoever gets there first drives and
## the other rides shotgun, free to keep shooting. Zombies are not solid to it, so
## anything you drive into gets run over rather than blocking the wheels.

const MAX_SPEED := 35.0 * 5.0 / 6.0
const BOOST_SPEED := 43.0 * 5.0 / 6.0
const REVERSE_SPEED := 10.0 * 5.0 / 6.0
const ACCELERATION := 14.0
const BOOST_ACCEL := 19.0
## Applied when nobody is on the throttle, so a cart left alone rolls to a stop.
const COAST_DECAY := 4.5
const IMPACT_DECAY := 34.0
## Shallower than this and the cart is running along a surface, not into it.
const HEAD_ON_MIN := 0.15
## A cart that has moved less than this in a frame has not moved.
const STUCK_MOVE := 0.04
## How long the driver has to ask for a cart that will not go before it is helped.
const STUCK_TIME := 1.0
## Each nudge off whatever it is wedged against, repeated until it rolls again.
const STUCK_PUSH := 1.2
const TURN_DEG_PER_SEC := 105.0
const DRIFT_TURN := 2.0
## How quickly velocity tracks the nose while sliding. Lower is more sideways.
const DRIFT_FOLLOW := 1.5
## Catch-up rate as the tires bite again after you let go.
const DRIFT_GRIP := 3.0
## Seconds of leftover slide after the drift button is released.
const DRIFT_RECOVER := 1.0
## Extra top speed at a full sideways slide, on top of the boost cap.
const DRIFT_TOP := 13.0
const DRIFT_MIN_SPEED := 5.5
const DRIFT_STEER := 0.28
const BOARD_RANGE := 3.4
const EXIT_SIDE := 2.1
## Above the turf so the capsule is not planted inside the heightmap.
const EXIT_LIFT := 0.25
const FLOOR_SNAP := 0.25
const FLOOR_MAX_DEG := 65.0
## Faster than a crawl, and climbing, before the cart lets go of the ground.
const LAUNCH_MIN_SPEED := 7.0
const LAUNCH_CLIMB := 0.1
const PITCH_CATCH := 10.0
## Heavier than the world's 9.8 so a ramp launch dumps you onto the far bank
## instead of hanging over the pond.
const AIR_GRAVITY := 26.0
const _Boost := preload("res://scripts/course/cart_path_boost.gd")
const _TireMarks := preload("res://scripts/fx/tire_marks.gd")
const _Stance := preload("res://scripts/vehicles/cart_stance.gd")
const _Wobble := preload("res://scripts/vehicles/cart_wobble.gd")
const _Brake := preload("res://scripts/vehicles/cart_brake.gd")

## Below this the cart is just nudging zombies out of the way.
const CRUSH_MIN_SPEED := 4.0
const CRUSH_DAMAGE_PER_SPEED := 24.0
const CRUSH_PUSH := 9.0
const TURBO_MULT := 1.18
const RAM_MULT := 1.45
const ARMOR_SCALE := 0.5
## Zoomed-out chase cam: far enough to read the whole cart and the path ahead.
const CHASE_DISTANCE := 9.5
const CHASE_HEIGHT := 4.8
const CHASE_LOOK_HEIGHT := 1.15
const CHASE_LOOK_AHEAD := 2.5
const CHASE_FOV := 88.0

var driver: Player
var passenger: Player
## The driver's stick as the host resolved it, in (steer, throttle), and whether
## they are on the trigger. Replicated so every peer can run the same drive
## instead of replaying the result of it.
##
## This is the difference between a cart that glides and one that hitches. A pose
## is a sample, so watching one means reconstructing motion from arrivals and
## every irregularity in them is on screen. A stick is a cause: hand it to a peer
## and the motion is generated there, continuously, at the physics rate. A late
## stick holds the last one for a few milliseconds and the cart keeps rolling,
## which is a sliver of steering lag rather than a stutter.
@export var sync_stick := Vector2.ZERO
@export var sync_boost := false
@export var sync_brake := false
@export var sync_brake_pitch := 0.0
@export var sync_tipped := false
@export var sync_tip_sign := 1.0
@export var sync_right := -1.0
## Signed speed along the cart's own forward axis; negative is reverse.
var drive_speed := 0.0
@export var turbo := false
@export var ram_plate := false
@export var armored := false
@export var mines := CartMines.LOAD
@export var visual_scene: PackedScene
@export var top_speed := MAX_SPEED
@export var boost_speed := BOOST_SPEED
@export var acceleration := ACCELERATION
@export var turn_deg := TURN_DEG_PER_SEC
@export var wheel_z := CartVisuals.WHEEL_Z
@export var wheel_x := CartVisuals.WHEEL_X
@export var crush_push := CRUSH_PUSH
@export var crush_damage_per_speed := CRUSH_DAMAGE_PER_SPEED
@export var impact_decay := IMPACT_DECAY
@export var crate_impulse := 0.0
@export var exit_side := EXIT_SIDE
@export var sync_xform := Transform3D.IDENTITY:
	set(value):
		sync_xform = value
		if is_inside_tree() and not NetSession.should_simulate(self) and not _predicting:
			_net_interp.arrive(value)
var _net_interp := NetInterp.new()
## 1 while drifting, then falls to 0 over DRIFT_RECOVER after you let go.
var _drift := 0.0
var _boost_count := 0
var _fling_left := 0.0
var _predicting := false
var _predict := NetPredict.new()
var _airborne := false
var _land_age := -1.0
var _land_strength := 0.0
## Seconds the driver has been asking a wedged cart to move.
var _stuck_for := 0.0
var _was_braking := false
var _brake_pitch := 0.0
var _brake_pitch_vel := 0.0
var _lean := 0.0
var _lean_vel := 0.0
var _shear := 0.0
var _shear_vel := 0.0
var _tip_hold := 0.0
var _tip_age := -1.0
var _tip_sign := 1.0
var _right_age := -1.0
## Lip height we hopped onto, held until the rear axle is up too.
var _step_y := -1.0
# #region agent log
var _dbg_n := 0
var _dbg_prev_y := 0.0
var _dbg_prev_pitch := 0.0
var _dbg_stepped := false
var _dbg_bled := false
var _dbg_bleed_into := 0.0
var _dbg_planted := false
var _dbg_front_y := 0.0
var _dbg_rear_y := 0.0
var _dbg_front_col := ""
var _dbg_rear_col := ""
var _dbg_floor_n := Vector3.UP
# #endregion

@onready var seats: Array[Node3D] = [$DriverSeat, $PassengerSeat]
@onready var crush_area: Area3D = $Crush

var _body: Node3D
var _wheel: SteeringWheel
var _driver_view: Node3D
var _shown_driver: Player
var _marks: _TireMarks
## Zombies already hit on this pass, so one run-over is one hit no matter how many
## frames they spend under the cart.
var _hit := {}


func _ready() -> void:
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.VEHICLE_MASK
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	floor_block_on_wall = false
	floor_constant_speed = true
	crush_area.collision_layer = 0
	crush_area.collision_mask = Layers.ZOMBIE | Layers.PROP
	crush_area.body_exited.connect(_on_body_exited)
	add_to_group("golf_carts")
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var visuals := (
		CarVisuals.build(visual_scene) if visual_scene != null else CartVisuals.build()
	)
	_body.add_child(visuals)
	_marks = _TireMarks.new()
	_marks.name = "TireMarks"
	add_child(_marks)
	_wheel = SteeringWheel.new()
	_wheel.position = _marker_or(visuals, "SteeringWheel", Vector3(-0.42, 1.22, 0.04))
	_body.add_child(_wheel)
	_driver_view = Node3D.new()
	_driver_view.name = "DriverView"
	# Back and up from the wheel so the cabin is in frame, not just the rim.
	_driver_view.position = _marker_or(visuals, "DriverView", Vector3(-0.42, 1.72, 0.78))
	_driver_view.rotation.x = deg_to_rad(-16.0)
	_body.add_child(_driver_view)
	_bind_seats(visuals)
	for seat in seats:
		seat.reparent(_body)
	# Face the rim at the seat so the driver sees a hoop, not the edge of a doughnut.
	var to_seat := _driver_view.position - _wheel.position
	_wheel.rotation.x = -atan2(to_seat.y, to_seat.z)


func apply_tint(color: Color) -> void:
	if visual_scene != null:
		CarVisuals.apply_tint(self, color)
	else:
		CartVisuals.apply_tint(self, color)


func axle_z() -> float:
	return wheel_z


func _marker_or(visuals: Node, marker_name: String, fallback: Vector3) -> Vector3:
	var at := CarVisuals.marker(visuals, marker_name)
	return fallback if at == Vector3.ZERO else at


func _bind_seats(visuals: Node) -> void:
	if seats.size() < 2:
		return
	var driver_at := CarVisuals.marker(visuals, "DriverSeat")
	if driver_at != Vector3.ZERO:
		seats[0].position = driver_at
	var rider_at := CarVisuals.marker(visuals, "PassengerSeat")
	if rider_at != Vector3.ZERO:
		seats[1].position = rider_at


func place_at(position: Vector3, facing_yaw: float) -> void:
	eject_all()
	recover_at(position, facing_yaw)
	mines = CartMines.LOAD


func recover_at(at: Vector3, facing_yaw: float) -> void:
	if is_inside_tree():
		global_position = at
	else:
		position = at
	rotation = Vector3(0.0, deg_to_rad(facing_yaw), 0.0)
	velocity = Vector3.ZERO
	drive_speed = 0.0
	_drift = 0.0
	_boost_count = 0
	_fling_left = 0.0
	_airborne = false
	_land_age = -1.0
	_land_strength = 0.0
	_stuck_for = 0.0
	_was_braking = false
	_step_y = -1.0
	_reset_wobble()
	_hit.clear()
	if _marks != null:
		_marks.clear()


func driver_view_transform() -> Transform3D:
	if _driver_view == null:
		return global_transform
	return _driver_view.global_transform


func chase_view_transform() -> Transform3D:
	return chase_cam(global_position, rotation.y)


## Behind the cart, looking over the roof down the fairway.
static func chase_cam(origin: Vector3, yaw: float) -> Transform3D:
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := origin - facing * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT
	var target := origin + Vector3.UP * CHASE_LOOK_HEIGHT + facing * CHASE_LOOK_AHEAD
	var xform := Transform3D(Basis(), eye)
	return xform.looking_at(target, Vector3.UP)


func wheel_angle_deg() -> float:
	return 0.0 if _wheel == null else _wheel.angle_deg()


func wheel_grips() -> Array[Vector3]:
	if _wheel == null:
		return []
	return _wheel.grip_positions()


func is_riding(player: Player) -> bool:
	return driver == player or passenger == player


func is_overturned() -> bool:
	return _Wobble.is_tipped(_tip_age) and not _Wobble.is_righting(_right_age)


func is_righting() -> bool:
	return _Wobble.is_righting(_right_age)


func can_right(player: Player) -> bool:
	if player == null or not is_overturned() or not player.health.is_alive():
		return false
	if is_riding(player):
		return false
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= BOARD_RANGE


func can_board(player: Player) -> bool:
	if is_overturned() or is_righting():
		return false
	if is_riding(player) or not player.health.is_alive():
		return false
	if player.is_floored() or player.motion.fling_left > 0.0:
		return false
	if driver != null and passenger != null:
		return false
	if player.brain != null and passenger != null:
		return false
	var offset := player.global_position - global_position
	offset.y = 0.0
	return offset.length() <= BOARD_RANGE


func try_right(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_right.rpc_id(1, player.peer_id)
		return
	_do_right(player)


## First one in drives.
func board(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_board.rpc_id(1, player.peer_id)
		return
	_do_board(player)
	_broadcast_seats()


func _do_board(player: Player) -> void:
	if not can_board(player):
		return
	if driver == null and player.brain == null:
		driver = player
	elif passenger == null:
		passenger = player
	else:
		return
	player.cart = self
	player.enter_ride()
	_seat_riders()
	Sfx.play("board", self)


func eject(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_eject.rpc_id(1, player.peer_id)
		_do_eject(player)
		return
	_do_eject(player)
	_broadcast_seats()


func _do_eject(player: Player) -> void:
	if not is_riding(player):
		return
	var side := 1.0 if driver == player else -1.0
	unseat_at(player, exit_point(side))
	Sfx.play("eject", self)


func unseat_at(player: Player, at: Vector3) -> void:
	if not is_riding(player):
		return
	if driver == player:
		driver = null
	else:
		passenger = null
	player.exit_ride()
	player.stand_at(at, rad_to_deg(rotation.y))


func windshield_drop(along: Vector3) -> Vector3:
	var dir := Vector3(along.x, 0.0, along.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	else:
		dir = dir.normalized()
	return _ground_at(global_position + dir * _Brake.AHEAD + Vector3.UP * 0.55)


func eject_all() -> void:
	if driver != null:
		_do_eject(driver)
	if passenger != null:
		_do_eject(passenger)
	_broadcast_seats()


static func can_hijack(driver_player: Player, attacker: Player, distance: float) -> bool:
	if driver_player == null or attacker == null or attacker == driver_player:
		return false
	return distance <= Melee.RANGE


func try_hijack(attacker: Player) -> bool:
	if attacker == null or driver == null:
		return false
	var offset := attacker.global_position - driver.global_position
	offset.y = 0.0
	if not can_hijack(driver, attacker, offset.length()):
		return false
	var victim := driver
	if passenger == attacker:
		passenger = null
		attacker.exit_ride()
	_do_eject(victim)
	victim.apply_knockback(attacker.global_position, 10.0)
	_do_board(attacker)
	_broadcast_seats()
	return true


## Where a rider is dropped off: clear of the wheels on their own side, on the
## turf rather than at the cart's origin, which sits below a bank.
func exit_point(side: float) -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	return _ground_at(_clamp_exit_to_fairway(global_position + right * side * exit_side))


func _physics_process(delta: float) -> void:
	var owned := NetSession.should_simulate(self)
	var predicting := not owned and predicts_locally()
	if predicting != _predicting:
		_predicting = predicting
		_predict.clear()
		if predicting and not sync_tipped:
			_reset_wobble()
	if not owned and not predicting:
		return
	_drive(delta)
	_bleed_speed_on_impact(delta)
	# #region agent log
	_dbg_climb(delta)
	# #endregion
	_seat_riders()
	if predicting:
		_predict.remember(global_position)
		return
	_run_over()
	sync_xform = global_transform


## A watching peer glides the cart here rather than in physics, and a driving one
## corrects it here. Either way its riders have to be re-seated afterwards or
## they would trail a frame behind the seat.
func _process(delta: float) -> void:
	if NetSession.should_simulate(self):
		return
	if _predicting:
		_predict.correct(self, sync_xform, delta)
	else:
		_net_interp.follow(self, sync_xform, delta, NetSync.CART_HZ, NetSync.WATCH_DELAY)
		_apply_synced_cabin()
	_seat_riders()


func net_interp() -> NetInterp:
	return _net_interp


## A cart with someone at the wheel is driven on every peer, from that driver's
## stick: their own machine reads the wheel directly, everyone else reads the
## copy that came with the pose. Nobody replays the pose while it is being
## driven, because a pose is a sample and a stick is a cause, and only one of
## those survives a link that delivers unevenly.
##
## An empty cart is glided instead. There is no stick behind a parked cart, and
## a fling is exactly the kind of thing a watcher cannot see coming.
##
## The host still owns every cart. This decides how the motion is drawn, never
## where the cart really is or what it hit.
func predicts_locally() -> bool:
	return driver != null and not NetSession.should_simulate(self)


## Remote humans publish report_drive onto sync_stick. Local humans and
## host-owned CPUs write CpuInput / PlayerInput on this machine — their
## peer_id is often negative, so comparing it to unique_id would stall them.
func _uses_replicated_stick() -> bool:
	if driver == null or not driver.net_driven:
		return false
	return not driver.is_multiplayer_authority()


func fling(direction: Vector3, speed: float, lift := 14.0, lock := 1.0) -> void:
	var dir := Vector3(direction.x, 0.0, direction.z)
	if dir.length_squared() < 0.0001:
		dir = -transform.basis.z
	dir = dir.normalized()
	velocity = dir * speed + Vector3.UP * lift
	drive_speed = 0.0
	_drift = 0.0
	_fling_left = lock


func is_flung() -> bool:
	return _fling_left > 0.0


func _drive(delta: float) -> void:
	if _fling_left > 0.0:
		_fling_left = maxf(0.0, _fling_left - delta)
		velocity.y -= AIR_GRAVITY * delta
		move_and_slide()
		return
	var throttle := 0.0
	var steer := 0.0
	var boosting := false
	var braking := false
	var tipped := _Wobble.is_tipped(_tip_age)
	if tipped:
		_tip_age += delta
		if _Wobble.is_righting(_right_age):
			_right_age += delta
			sync_right = _right_age
			if not _Wobble.is_righting(_right_age):
				_reset_wobble()
				tipped = false
	if not tipped and driver != null and driver.health.is_alive():
		if _uses_replicated_stick():
			steer = sync_stick.x
			throttle = sync_stick.y
			boosting = sync_boost
			braking = sync_brake
		else:
			var stick := driver.input.move_vector()
			throttle = -stick.y
			steer = stick.x
			boosting = driver.input.pressed("shoot")
			braking = driver.input.pressed("aim")
			# A host at the wheel is the only source of its own stick, so it has
			# to publish what it just read or no one else can run this.
			if is_multiplayer_authority():
				sync_stick = Vector2(steer, throttle)
				sync_boost = boosting
				sync_brake = braking
	if braking:
		if not _was_braking:
			_Brake.slam(self, drive_speed)
		boosting = false
		throttle = 0.0
	_was_braking = braking
	var drifting := is_drifting(boosting, steer, drive_speed)
	_drift = next_drift(_drift, drifting, delta)
	var pull := acceleration
	if boosting and throttle > 0.0:
		pull = acceleration * (BOOST_ACCEL / ACCELERATION)
	elif is_zero_approx(throttle):
		pull = COAST_DECAY
	var nose := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	if braking:
		drive_speed = _Brake.next_speed(drive_speed, delta)
		_drift = 0.0
	elif _boost_count > 0:
		drive_speed = _Boost.cart_speed(drive_speed, delta)
	else:
		var wanted := target_speed(throttle, boosting, max_drive_speed(), boost_drive_speed())
		if wanted > 0.0:
			wanted += drift_bonus(slip_amount(nose, velocity), _drift)
		drive_speed = move_toward(drive_speed, wanted, pull * delta)
	var nod := _Brake.next_pitch(_brake_pitch, _brake_pitch_vel, braking, drive_speed, delta)
	_brake_pitch = nod.x
	_brake_pitch_vel = nod.y
	if is_multiplayer_authority():
		sync_brake_pitch = _brake_pitch
	var turn := turn_rate_deg(drive_speed, steer, max_drive_speed(), turn_deg) * drift_turn_scale(_drift)
	rotation.y += deg_to_rad(turn * delta)
	if _wheel != null:
		_wheel.turn(steer, delta)
		if _shown_driver != driver:
			_shown_driver = driver
			if driver != null:
				_wheel.show_hands(true, driver.body_color, PlayerBody.WORLD_LAYER)
			else:
				_wheel.show_hands(false)
	nose = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var slip := velocity_slip(_drift, delta)
	var reverse := drive_speed < -0.2 or (absf(drive_speed) < 0.2 and throttle < 0.0)
	var front := _probe_axle(-axle_z())
	var rear := _probe_axle(axle_z())
	var look := _probe_axle(_Stance.look_z(axle_z(), reverse))
	var planted := _Stance.both_planted(
		to_global(Vector3(0.0, 0.0, -axle_z())).y,
		to_global(Vector3(0.0, 0.0, axle_z())).y,
		front,
		rear
	)
	# #region agent log
	_dbg_planted = planted
	_dbg_front_y = float(front.position.y) if not front.is_empty() else -999.0
	_dbg_rear_y = float(rear.position.y) if not rear.is_empty() else -999.0
	_dbg_front_col = _dbg_hit_name(front)
	_dbg_rear_col = _dbg_hit_name(rear)
	# #endregion
	var floor_n := get_floor_normal()
	if planted:
		floor_n = _Stance.blend_normal(front.normal, rear.normal)
	# #region agent log
	_dbg_floor_n = floor_n
	# #endregion
	var grounded := planted or is_on_floor()
	if not grounded:
		var deck := _deck_under()
		if _near_deck(global_position.y, deck):
			grounded = true
			if deck.has("normal"):
				floor_n = deck.normal
			if global_position.y < float(deck.position.y) - 0.02:
				global_position.y = deck.position.y
	if _airborne and grounded:
		_begin_land(-velocity.y)
	_airborne = not grounded
	if planted or is_on_floor():
		# Axle probes hold the ride height. Snap would pull the midpoint into
		# the crease and lift the rear tires off a ramp.
		floor_snap_length = 0.0 if planted else snap_length(floor_n, nose, drive_speed)
		var along := slope_velocity(nose, floor_n, drive_speed)
		velocity.x = lerpf(velocity.x, along.x, slip)
		velocity.z = lerpf(velocity.z, along.z, slip)
		velocity.y = along.y
	else:
		floor_snap_length = 0.0
		var wanted := nose * drive_speed
		velocity.x = lerpf(velocity.x, wanted.x, slip)
		velocity.z = lerpf(velocity.z, wanted.z, slip)
		velocity.y -= AIR_GRAVITY * delta
	_align_stance(delta, front, rear, planted)
	_hold_step(rear)
	move_and_slide()
	if _blocked_by_lip() and _wants_step(throttle) and not _field_wall_hit():
		var lip := _lip_from_hits()
		# #region agent log
		if global_position.y < 2.0:
			_dbg_step_try(lip, look)
		# #endregion
		if lip.is_empty():
			lip = look
		if _apply_step(lip):
			if velocity.y < 0.0:
				velocity.y = 0.0
			move_and_slide()
	_track_stuck(throttle, delta)
	if _marks != null:
		var rubber := is_leaving_rubber(_drift, planted or is_on_floor(), drive_speed)
		_marks.trace(_wheel_contacts(), rubber, delta)
	if not tipped:
		_step_wobble(steer, delta)
		if _Wobble.should_tip(_tip_hold, _drift):
			_begin_tip()
	_apply_body_pose()


func _step_wobble(steer: float, delta: float) -> void:
	var motion := _Wobble.next_state(
		_lean, _lean_vel, steer, drive_speed, _drift, delta, top_speed
	)
	_lean = motion.x
	_lean_vel = motion.y
	var canopy := _Wobble.next_follow(_shear, _shear_vel, _lean, delta)
	_shear = canopy.x
	_shear_vel = canopy.y
	_tip_hold = _Wobble.next_tip_hold(
		_tip_hold, _lean, steer, delta, _drift, drive_speed, top_speed
	)


func _begin_tip() -> void:
	_tip_sign = 1.0 if _lean >= 0.0 else -1.0
	_tip_age = 0.0
	_right_age = -1.0
	_tip_hold = 0.0
	drive_speed = 0.0
	sync_tipped = true
	sync_tip_sign = _tip_sign
	sync_right = -1.0
	eject_all()


func _do_right(player: Player) -> void:
	if not can_right(player):
		return
	_right_age = 0.0
	sync_right = 0.0
	Sfx.play("board", self)


func _reset_wobble() -> void:
	_lean = 0.0
	_lean_vel = 0.0
	_shear = 0.0
	_shear_vel = 0.0
	_tip_hold = 0.0
	_tip_age = -1.0
	_tip_sign = 1.0
	_right_age = -1.0
	_brake_pitch = 0.0
	_brake_pitch_vel = 0.0
	sync_brake_pitch = 0.0
	sync_tipped = false
	sync_tip_sign = 1.0
	sync_right = -1.0
	if _body != null:
		_body.basis = Basis.IDENTITY


func _apply_body_pose() -> void:
	if _body == null:
		return
	if _Wobble.is_righting(_right_age):
		_body.basis = _Wobble.right_basis(_right_age, _tip_sign)
		return
	_body.basis = _Wobble.body_basis(
		_lean, _shear, _Wobble.pitch_from_vel(_lean_vel) + _brake_pitch,
		_Wobble.tip_blend(_tip_age), _tip_sign
	)


func _apply_synced_cabin() -> void:
	if _body == null:
		return
	if sync_right >= 0.0:
		_body.basis = _Wobble.right_basis(sync_right, sync_tip_sign)
	elif sync_tipped:
		_body.basis = _Wobble.body_basis(
			sync_tip_sign, sync_tip_sign, 0.0, 1.0, sync_tip_sign
		)
	else:
		_body.basis = _Wobble.body_basis(0.0, 0.0, sync_brake_pitch)


## Hitting a tree or a barrier has to cost the cart its speed, otherwise it grinds
## along the wall at full throttle. Only the part of the drive that is heading
## into the surface is charged for: a graze along the lip keeps rolling, and
## backing off a wall already in contact is free. Contact alone must never bill
## the cart, because depenetration reports it every frame once the cart is
## touching, and a cart drained to zero cannot steer either.
func _bleed_speed_on_impact(delta: float) -> void:
	var floor_dot := _floor_dot()
	var travel := _travel_dir()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) >= floor_dot:
			continue
		if _is_climbable_hit(col):
			continue
		var into := head_on_amount(travel, col.get_normal())
		if into <= 0.0:
			continue
		drive_speed = move_toward(drive_speed, 0.0, impact_decay * into * delta)
		# #region agent log
		_dbg_bled = true
		_dbg_bleed_into = into
		# #endregion
		return


## The cart's own heading, reversed when it is rolling backwards.
func _travel_dir() -> Vector3:
	var nose := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	return nose if drive_speed >= 0.0 else -nose


## How square the hit is: 1 is head-on, 0 is a graze, and driving away from a
## surface already in contact scores nothing at all.
static func head_on_amount(travel: Vector3, normal: Vector3) -> float:
	var wall := Vector3(normal.x, 0.0, normal.z)
	if wall.length_squared() < 0.0001 or travel.length_squared() < 0.0001:
		return 0.0
	var into := -travel.normalized().dot(wall.normalized())
	return 0.0 if into <= HEAD_ON_MIN else into


func _floor_dot() -> float:
	return cos(deg_to_rad(FLOOR_MAX_DEG))


func _wants_step(throttle: float) -> bool:
	return absf(drive_speed) > 0.35 or absf(throttle) > 0.1


func _apply_step(look: Dictionary) -> bool:
	if not _Stance.can_step(global_position.y, look):
		return false
	# #region agent log
	_dbg_stepped = true
	# #endregion
	_step_y = look.position.y
	global_position.y = _step_y
	var nose := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	if drive_speed < 0.0:
		nose = -nose
	global_position += nose * 0.22
	return true


func _hold_step(rear: Dictionary) -> void:
	if _step_y < 0.0:
		return
	var rear_y: float = rear.position.y if not rear.is_empty() else global_position.y
	if rear_y >= _step_y - 0.1:
		_step_y = -1.0
		return
	if global_position.y < _step_y:
		global_position.y = _step_y
	# A climb pitch spears the lip with the box; stay flat until the rear is up.
	rotation.x = 0.0


## A cart can still end up somewhere it cannot drive out of: wedged in the notch
## between two lip panels, or on the wrong side of one. If the driver has been
## asking for a second and nothing has moved, push it clear rather than leaving
## them to work out that the hole is a dead end.
func _track_stuck(throttle: float, delta: float) -> void:
	if driver == null or absf(throttle) < 0.1 or not _blocked_by_lip():
		_stuck_for = 0.0
		return
	if get_position_delta().length() > STUCK_MOVE:
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for < STUCK_TIME:
		return
	_stuck_for = 0.0
	if NetSession.should_simulate(self):
		_shove_free()


## Out along whatever is in the way. A lip panel knows which side is playable,
## so that one is pushed inward onto the strip; anything else is left along its
## own contact normal.
func _shove_free() -> void:
	var out := _free_direction()
	if out.length_squared() < 0.0001:
		return
	global_position = _ground_at(global_position + out.normalized() * STUCK_PUSH)
	velocity = Vector3.ZERO
	drive_speed = 0.0
	_step_y = -1.0


func _free_direction() -> Vector3:
	var floor_dot := _floor_dot()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) >= floor_dot:
			continue
		var out := Vector3.ZERO
		if _hit_is_field(col):
			out = _field_inward_from(col.get_collider(), col.get_position(), col.get_normal())
		else:
			out = Vector3(col.get_normal().x, 0.0, col.get_normal().z)
		if out.length_squared() > 0.0001:
			return out
	return Vector3.ZERO


func _blocked_by_lip() -> bool:
	if is_on_wall():
		return true
	var floor_dot := _floor_dot()
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_normal().dot(up_direction) < floor_dot:
			return true
	return false


func _lip_from_hits() -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	var space := get_world_3d().direct_space_state
	var floor_dot := _floor_dot()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_normal().dot(up_direction) >= floor_dot:
			continue
		if _hit_is_field(col):
			continue
		var hit := _Stance.probe_down(space, _lip_probe_at(col), [get_rid()])
		if _Stance.can_step(global_position.y, hit):
			return hit
	return {}


func _is_climbable_hit(col: KinematicCollision3D) -> bool:
	if _hit_is_field(col):
		return false
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var hit := _Stance.probe_down(
		get_world_3d().direct_space_state, _lip_probe_at(col), [get_rid()]
	)
	return _Stance.can_step(global_position.y, hit)


func _lip_probe_at(col: KinematicCollision3D) -> Vector3:
	var inward := col.get_normal()
	inward.y = 0.0
	if inward.length_squared() > 0.0001:
		inward = -inward.normalized() * 0.18
	else:
		inward = Vector3.ZERO
	return col.get_position() + inward


func _seat_riders() -> void:
	if driver != null:
		driver.sit_as_driver(seats[0].global_position, rad_to_deg(rotation.y))
	if passenger != null:
		passenger.sit_as_passenger(seats[1].global_position)


func _run_over() -> void:
	if absf(drive_speed) < CRUSH_MIN_SPEED:
		# Slowed down: the next time the cart gets going is a fresh pass.
		_hit.clear()
		return
	var direction := -global_transform.basis.z * signf(drive_speed)
	direction.y = 0.0
	direction = direction.normalized()
	for body in crush_area.get_overlapping_bodies():
		if _hit.has(body.get_instance_id()):
			continue
		var zombie := body as Zombie
		if zombie != null:
			if zombie.is_allied():
				continue
			_hit[zombie.get_instance_id()] = true
			var hit := zombie.global_position + Vector3.UP * zombie.stats.height * 0.22
			zombie.take_damage(crush_damage(drive_speed, ram_mult(), crush_damage_per_speed), direction, hit)
			zombie.stagger(direction * crush_push)
			Sfx.play("crush", self)
			continue
		var crate := body as RigidBody3D
		if crate == null or crate_impulse <= 0.0:
			continue
		_hit[crate.get_instance_id()] = true
		crate.apply_central_impulse(direction * crate_impulse)


func _on_body_exited(body: Node3D) -> void:
	_hit.erase(body.get_instance_id())


func enter_boost(_along: Vector3) -> void:
	_boost_count += 1
	if _boost_count == 1:
		Sfx.play("boost_pad", self)


func exit_boost() -> void:
	_boost_count = maxi(0, _boost_count - 1)


func on_boost_pad() -> bool:
	return _boost_count > 0


func install_turbo() -> void:
	turbo = true


func install_ram() -> void:
	ram_plate = true


func install_armor() -> void:
	armored = true


func max_drive_speed() -> float:
	return top_speed * (TURBO_MULT if turbo else 1.0) * beer_mult()


func boost_drive_speed() -> float:
	return boost_speed * (TURBO_MULT if turbo else 1.0) * beer_mult()


func beer_mult() -> float:
	if driver == null:
		return 1.0
	return driver.buzz.cart_mult()


func ram_mult() -> float:
	return RAM_MULT if ram_plate else 1.0


## What the throttle is asking for. Reverse is slow, like a real cart. R2 / click
## adds a little extra on the way forwards.
static func target_speed(
	throttle: float, boost := false, max_speed := MAX_SPEED, boost_speed := BOOST_SPEED
) -> float:
	var wanted := clampf(throttle, -1.0, 1.0)
	if wanted < 0.0:
		return wanted * REVERSE_SPEED
	return wanted * (boost_speed if boost else max_speed)


## Boost plus a turn at speed is a drift: the cart yaws but the slide keeps going.
static func is_drifting(boost: bool, steer: float, speed: float) -> bool:
	return boost and absf(steer) > DRIFT_STEER and absf(speed) > DRIFT_MIN_SPEED


## Pins at full slide while the trigger is held, then eases off over a second.
static func next_drift(current: float, drifting: bool, delta: float) -> float:
	if drifting:
		return 1.0
	return move_toward(current, 0.0, delta / DRIFT_RECOVER)


static func drift_turn_scale(drift: float) -> float:
	return lerpf(1.0, DRIFT_TURN, clampf(drift, 0.0, 1.0))


## How far the cart is sliding off its nose. 0 is rolling straight, 1 is fully sideways.
static func slip_amount(nose: Vector3, travel: Vector3) -> float:
	var facing := Vector3(nose.x, 0.0, nose.z)
	var along := Vector3(travel.x, 0.0, travel.z)
	if facing.length_squared() < 0.0001 or along.length_squared() < 0.25:
		return 0.0
	var aligned := clampf(facing.normalized().dot(along.normalized()), -1.0, 1.0)
	return clampf(acos(aligned) / (PI * 0.5), 0.0, 1.0)


## Extra speed from the slide. A shallow drift is a nudge; a big angle is the fast line.
static func drift_bonus(angle: float, drift: float) -> float:
	return DRIFT_TOP * clampf(angle, 0.0, 1.0) * clampf(drift, 0.0, 1.0)


static func is_leaving_rubber(drift: float, on_floor: bool, speed: float) -> bool:
	return on_floor and drift >= 1.0 and absf(speed) > DRIFT_MIN_SPEED * 0.5


func _wheel_contacts() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for x: float in [-wheel_x, wheel_x]:
		for z: float in [-axle_z(), axle_z()]:
			var at := to_global(Vector3(x, 0.0, z))
			at.y += _TireMarks.LIFT
			points.append(at)
	return points


## How much this frame's velocity catches the nose. 1 is full grip.
static func velocity_slip(drift: float, delta: float) -> float:
	if drift <= 0.0:
		return 1.0
	var rate := lerpf(DRIFT_GRIP, DRIFT_FOLLOW, clampf(drift, 0.0, 1.0))
	return clampf(rate * delta, 0.0, 1.0)


## Drive along the floor so a ramp's slope becomes launch speed instead of being
## flattened into a horizontal shove.
static func slope_velocity(nose: Vector3, floor_normal: Vector3, speed: float) -> Vector3:
	var flat := Vector3(nose.x, 0.0, nose.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	flat = flat.normalized()
	var along := flat.slide(floor_normal)
	if along.length_squared() < 0.0001:
		return flat * speed
	return along.normalized() * speed


## Climbing at speed: snap would glue the cart to the lip and kill the jump.
static func snap_length(floor_normal: Vector3, nose: Vector3, speed: float) -> float:
	if absf(speed) < LAUNCH_MIN_SPEED:
		return FLOOR_SNAP
	var climb := slope_velocity(nose, floor_normal, signf(speed)).y
	return 0.0 if climb > LAUNCH_CLIMB else FLOOR_SNAP


func _probe_axle(local_z: float) -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	return _Stance.probe(
		get_world_3d().direct_space_state, global_position, rotation.y, local_z, [get_rid()]
	)


func _begin_land(down_speed: float) -> void:
	var strength := _Stance.land_strength(down_speed)
	if strength <= 0.0:
		return
	_land_strength = strength
	_land_age = 0.0
	_lean_vel = _Wobble.land_jolt(_lean_vel, _lean, strength)


func _step_land(delta: float) -> Vector2:
	if _land_age < 0.0:
		return Vector2.ZERO
	_land_age += delta
	var offset := _Stance.bounce_offset(_land_strength, _land_age)
	if offset == Vector2.ZERO:
		_land_age = -1.0
		_land_strength = 0.0
	return offset


func _align_stance(delta: float, front: Dictionary, rear: Dictionary, plant: bool) -> void:
	if plant:
		var bounce := _step_land(delta)
		var axle := _Stance.pitch_from_axles(front.position.y, rear.position.y)
		rotation.x = axle + bounce.y
		global_position.y = _Stance.ride_height(front.position.y, rear.position.y) + bounce.x
		return
	if not is_on_floor():
		return
	var nose := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var launching := (
		velocity.y > LAUNCH_CLIMB
		or snap_length(get_floor_normal(), nose, drive_speed) <= 0.0
	)
	if _Stance.holds_air_pitch(rotation.x, true, launching):
		return
	var bounce := _step_land(delta)
	var wanted := pitch_on_floor(get_floor_normal(), rotation.y)
	rotation.x = lerp_angle(rotation.x, wanted, clampf(PITCH_CATCH * delta, 0.0, 1.0)) + bounce.y


static func pitch_on_floor(floor_normal: Vector3, yaw: float) -> float:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	return atan2(-floor_normal.dot(forward), floor_normal.y)


## Steering scales with how fast the cart is actually rolling, so it cannot spin on
## the spot, and the sign flips in reverse the way a real one does.
static func turn_rate_deg(
	speed: float, steer: float, max_speed := MAX_SPEED, deg_per_sec := TURN_DEG_PER_SEC
) -> float:
	return -clampf(steer, -1.0, 1.0) * deg_per_sec * clampf(speed / maxf(1.0, max_speed), -1.0, 1.0)


## Damage from being hit by the cart. Cruising speed flattens a walker or a runner
## outright; at full tilt a brute goes down in one pass too.
static func crush_damage(speed: float, ram := 1.0, per_speed := CRUSH_DAMAGE_PER_SPEED) -> float:
	if absf(speed) < CRUSH_MIN_SPEED:
		return 0.0
	return absf(speed) * per_speed * ram


func _player_by_peer(peer_id: int) -> Player:
	if peer_id <= 0:
		return null
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		if player != null and player.peer_id == peer_id:
			return player
	return null


func _peer_of(player: Player) -> int:
	return 0 if player == null else player.peer_id


func _hit_is_field(col: KinematicCollision3D) -> bool:
	var other := col.get_collider() as CollisionObject3D
	if other == null:
		return false
	return other.is_in_group("fairway_field") or (other.collision_layer & Layers.FORCEFIELD) != 0


func _field_wall_hit() -> bool:
	for i in get_slide_collision_count():
		if _hit_is_field(get_slide_collision(i)):
			return true
	return false


func _deck_under() -> Dictionary:
	if not is_inside_tree() or get_world_3d() == null:
		return {}
	return _Stance.probe_down(
		get_world_3d().direct_space_state, global_position, [get_rid()], 1.2, 0.8
	)


func _near_deck(current_y: float, hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var deck_y: float = hit.position.y
	return deck_y >= current_y - 0.2 and deck_y <= current_y + _Stance.STEP_MAX


func _clamp_exit_to_fairway(at: Vector3) -> Vector3:
	if not is_inside_tree() or get_world_3d() == null:
		return at
	var space := get_world_3d().direct_space_state
	if space == null:
		return at
	var from := global_position + Vector3.UP * 0.8
	var to := at + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.FORCEFIELD)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return at
	var inward := _field_inward_from(hit.get("collider"), hit.position, hit.normal)
	if inward.length_squared() < 0.0001:
		return global_position
	var inside: Vector3 = hit.position + inward * 0.7
	inside.y = at.y
	return inside


func _field_inward_from(collider: Object, at: Vector3, normal: Vector3) -> Vector3:
	var shape := _field_shape_near(collider, at)
	if shape != null:
		var outward := shape.global_transform.basis.x
		outward.y = 0.0
		if outward.length_squared() > 0.0001:
			return -outward.normalized()
	var n := Vector3(normal.x, 0.0, normal.z)
	if n.length_squared() < 0.0001:
		return Vector3.ZERO
	return n.normalized()


func _field_shape_near(collider: Object, at: Vector3) -> CollisionShape3D:
	var body := collider as Node
	if body == null:
		return null
	var best: CollisionShape3D
	var best_d := INF
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var d := shape.global_position.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = shape
	return best


func _ground_at(at: Vector3) -> Vector3:
	var lift := Vector3.UP * EXIT_LIFT
	if not is_inside_tree() or get_world_3d() == null:
		return at + lift
	var space := get_world_3d().direct_space_state
	if space == null:
		return at + lift
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 8.0, at + Vector3.DOWN * 10.0
	)
	query.collision_mask = Layers.WORLD | Layers.PROP
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return at + lift
	return hit.position + lift


func try_drop_mine(player: Player) -> bool:
	return CartMines.try_drop(self, player)


func _broadcast_seats() -> void:
	if NetSession.is_active() and is_multiplayer_authority():
		_replicate_seats.rpc(_peer_of(driver), _peer_of(passenger))


@rpc("any_peer", "reliable")
func _request_board(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		_do_board(player)
		_broadcast_seats()


@rpc("any_peer", "reliable")
func _request_right(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		_do_right(player)


@rpc("any_peer", "reliable")
func _request_drop_mine(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		CartMines.commit_drop(self, player)


@rpc("any_peer", "reliable")
func _request_eject(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	var player := _player_by_peer(peer_id)
	if player != null:
		_do_eject(player)
		_broadcast_seats()


@rpc("authority", "call_remote", "reliable")
func _replicate_seats(driver_id: int, passenger_id: int) -> void:
	var next_driver := _player_by_peer(driver_id)
	var next_passenger := _player_by_peer(passenger_id)
	if driver != null and driver != next_driver and driver != next_passenger:
		_drop_rider(driver, 1.0)
	if passenger != null and passenger != next_driver and passenger != next_passenger:
		_drop_rider(passenger, -1.0)
	driver = next_driver
	passenger = next_passenger
	_occupy(driver)
	_occupy(passenger)


func _drop_rider(player: Player, side: float) -> void:
	if player.is_riding():
		player.exit_ride()
	player.stand_at(exit_point(side), rad_to_deg(player.rotation.y))


func _occupy(player: Player) -> void:
	if player == null:
		return
	player.cart = self
	if not player.is_riding():
		player.enter_ride()


@rpc("any_peer", "unreliable")
func report_drive(stick: Vector2, boosting: bool, braking := false) -> void:
	if not is_multiplayer_authority() or driver == null:
		return
	if multiplayer.get_remote_sender_id() != driver.peer_id:
		return
	sync_stick = stick_drive(stick)
	sync_boost = boosting
	sync_brake = braking


## A move vector points up the screen as -Y, and drive wants forward throttle to
## be positive. Everything downstream reads (steer, throttle).
static func stick_drive(stick: Vector2) -> Vector2:
	return Vector2(stick.x, -stick.y)


# #region agent log
func _dbg_hit_name(hit: Dictionary) -> String:
	if hit.is_empty():
		return ""
	var node := hit.get("collider") as Node
	return "" if node == null else String(node.name)


func _dbg_slide_info() -> Dictionary:
	var walls := 0
	var names: Array[String] = []
	var min_ny := 1.0
	var floor_dot := _floor_dot()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		min_ny = minf(min_ny, n.y)
		if n.dot(up_direction) < floor_dot:
			walls += 1
		var node := col.get_collider() as Node
		var label := "" if node == null else String(node.name)
		if label != "" and not names.has(label):
			names.append(label)
	return {"walls": walls, "names": names, "min_ny": min_ny}


func _dbg_step_try(lip: Dictionary, look: Dictionary) -> void:
	var f := FileAccess.open(
		"/Users/jamesritchie/golf-zombies/.cursor/debug-61bfc9.log", FileAccess.READ_WRITE
	)
	if f == null:
		f = FileAccess.open(
			"/Users/jamesritchie/golf-zombies/.cursor/debug-61bfc9.log", FileAccess.WRITE
		)
	if f == null:
		return
	f.seek_end()
	var lip_y := float(lip.position.y) if not lip.is_empty() else -999.0
	var look_y := float(look.position.y) if not look.is_empty() else -999.0
	f.store_line(JSON.stringify({
		"sessionId": "61bfc9",
		"runId": "post-fix",
		"hypothesisId": "F",
		"location": "scripts/vehicles/golf_cart.gd:_dbg_step_try",
		"message": "approach step attempt",
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
		"data": {
			"y": snappedf(global_position.y, 0.01),
			"lip_y": snappedf(lip_y, 0.01),
			"look_y": snappedf(look_y, 0.01),
			"lip_ok": _Stance.can_step(global_position.y, lip),
			"look_ok": _Stance.can_step(global_position.y, look),
			"spd": snappedf(drive_speed, 0.01),
		},
	}))
	f.close()


func _dbg_climb(_delta: float) -> void:
	var y := global_position.y
	var pitch := rotation.x
	var dy := y - _dbg_prev_y
	var dp := pitch - _dbg_prev_pitch
	_dbg_prev_y = y
	_dbg_prev_pitch = pitch
	_dbg_n += 1
	var slides := _dbg_slide_info()
	var event := (
		_dbg_stepped or _dbg_bled or not _dbg_planted or not is_on_floor()
		or is_on_wall() or int(slides.walls) > 0 or absf(dy) > 0.08
		or absf(dp) > 0.04
	)
	var climbing := y > 0.8 or _dbg_floor_n.y < 0.995
	if not climbing and not event:
		_dbg_stepped = false
		_dbg_bled = false
		_dbg_bleed_into = 0.0
		return
	if not event and _dbg_n % 3 != 0:
		_dbg_stepped = false
		_dbg_bled = false
		_dbg_bleed_into = 0.0
		return
	var hid := "D"
	if _dbg_stepped or _dbg_bled or int(slides.walls) > 0 or is_on_wall():
		hid = "A"
	elif absf(dy) > 0.08 or absf(_dbg_front_y - _dbg_rear_y) > 1.2:
		hid = "B"
	elif not _dbg_planted or not is_on_floor():
		hid = "C"
	elif not str(slides.names).contains("Spiral") and y > 2.0:
		hid = "E"
	var f := FileAccess.open(
		"/Users/jamesritchie/golf-zombies/.cursor/debug-61bfc9.log", FileAccess.READ_WRITE
	)
	if f == null:
		f = FileAccess.open(
			"/Users/jamesritchie/golf-zombies/.cursor/debug-61bfc9.log", FileAccess.WRITE
		)
	if f == null:
		_dbg_stepped = false
		_dbg_bled = false
		_dbg_bleed_into = 0.0
		return
	f.seek_end()
	f.store_line(JSON.stringify({
		"sessionId": "61bfc9",
		"runId": "post-fix",
		"hypothesisId": hid,
		"location": "scripts/vehicles/golf_cart.gd:_dbg_climb",
		"message": "spiral climb sample",
		"timestamp": int(Time.get_unix_time_from_system() * 1000.0),
		"data": {
			"y": snappedf(y, 0.01),
			"dy": snappedf(dy, 0.001),
			"pitch": snappedf(rad_to_deg(pitch), 0.01),
			"dp": snappedf(rad_to_deg(dp), 0.01),
			"spd": snappedf(drive_speed, 0.01),
			"vy": snappedf(velocity.y, 0.01),
			"planted": _dbg_planted,
			"on_floor": is_on_floor(),
			"on_wall": is_on_wall(),
			"air": _airborne,
			"step_y": snappedf(_step_y, 0.01),
			"stepped": _dbg_stepped,
			"bled": _dbg_bled,
			"bleed_into": snappedf(_dbg_bleed_into, 0.01),
			"fy": snappedf(_dbg_front_y, 0.01),
			"ry": snappedf(_dbg_rear_y, 0.01),
			"fcol": _dbg_front_col,
			"rcol": _dbg_rear_col,
			"fn": [
				snappedf(_dbg_floor_n.x, 0.001),
				snappedf(_dbg_floor_n.y, 0.001),
				snappedf(_dbg_floor_n.z, 0.001),
			],
			"walls": slides.walls,
			"min_ny": snappedf(float(slides.min_ny), 0.001),
			"cols": slides.names,
			"slides": get_slide_collision_count(),
		},
	}))
	f.close()
	_dbg_stepped = false
	_dbg_bled = false
	_dbg_bleed_into = 0.0
# #endregion
