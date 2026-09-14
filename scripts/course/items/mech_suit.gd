class_name MechSuit
extends CharacterBody3D
## Clubhouse mech. Parked open with stairs; Circle in the cockpit seals it.
## After that the pilot is in until it is wrecked or the hole ends.

const SCENE := preload("res://scenes/course/items/mech_suit.tscn")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const JUMP := 10.0
const STEP_TIME := 0.28
const SPRINT_STEP_TIME := 0.18
const STEP_PLANT := 0.1
const STEP_STICK := 0.35
const MAX_HP := 8
const EXIT_SIDE := 3.0
const GOLF_RANGE := 18.0
const GOLF_SIDE := 1.5
const STANCE_YAW := 0.0
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 55.0
const PITCH_LIMIT := 85.0
const CHASE_DISTANCE := 7.0
const CHASE_HEIGHT := 3.5
const CHASE_LOOK_HEIGHT := 2.5
const CHASE_LOOK_AHEAD := 1.5
const CHASE_FOV := 88.0
const PILOT_FOV := 102.0
const BOARD_REACH := 3.2
## Feet sit a hair above the heightmap so the soles do not clip the turf.
const STAND_LIFT := 0.28

var owner_player: Player
var owner_peer := 0
var pilot: Player
var combat := MechCombat.new()
var _visuals: MechVisuals
var _net_interp := NetInterp.new()
var _predict := NetPredict.new()
var _seen_jumps := 0
var _net_yaw := 0.0
var _want_fire := false
var _want_reload := false
var _drawn_closed := false
var _wire_left := 0.0
var _predicting := false
var _step_left := 0.0
var _step_dur := 0.0
var _step_t := 0.0
var _step_to := Vector3.ZERO
var _step_moving := false
var _left_swing := false
var _plant_left := 0.0
var _queued := Vector2.ZERO

## Meters the suit lunges on one tap. Hold the stick to keep stomping.
@export_range(0.5, 12.0, 0.1) var step_distance := 3.5
@export var closed := false
@export var hp := MAX_HP
@export var sync_stick := Vector2.ZERO
@export var sync_sprint := false
@export var sync_jumps := 0
@export var sync_pitch := 0.0
@export var sync_mag := MechCombat.MAG_SIZE
@export var sync_reload := false
@export var sync_strafe := 0.0
@export var sync_xform := Transform3D.IDENTITY:
	set(value):
		sync_xform = value
		if is_inside_tree() and _watching() and not _predicting:
			_net_interp.arrive(value)

@onready var crush: Area3D = $Crush
@onready var cockpit: Area3D = $Cockpit
@onready var seat: Node3D = $PilotSeat
@onready var view: Node3D = $PilotView


func _ready() -> void:
	collision_layer = Layers.MECH
	collision_mask = Layers.VEHICLE_MASK
	floor_snap_length = FLOOR_SNAP
	floor_max_angle = deg_to_rad(FLOOR_MAX_DEG)
	add_to_group("mechs")
	_visuals = MechVisuals.attach(self)
	_apply_closed()
	_drawn_closed = closed
	if NetSession.is_active():
		NetSync.attach_mech(self)
		set_multiplayer_authority(1)
	if sync_xform == Transform3D.IDENTITY:
		sync_xform = global_transform
	if owner_player == null and owner_peer > 0:
		var who := _player_with_peer(owner_peer)
		if who != null:
			bind_owner(who)
	crush.collision_layer = 0
	crush.collision_mask = Layers.ZOMBIE | Layers.PLAYER
	crush.body_exited.connect(func(body: Node): combat.forget(body))
	cockpit.collision_layer = 0
	cockpit.collision_mask = Layers.PLAYER
	_park_if_watched()


static func spawn_near(buyer: Player) -> MechSuit:
	if buyer == null:
		return null
	var pose := MechPlacer.place(buyer)
	return drop(buyer, pose["at"], float(pose["yaw"]))


static func drop(buyer: Player, at: Vector3, yaw_deg: float) -> MechSuit:
	if buyer == null:
		return null
	if NetSession.is_active():
		var spawner := _vs_spawner(buyer)
		if spawner != null:
			var mech := spawner.spawn_mech(at, yaw_deg, buyer.peer_id)
			if mech != null:
				mech.bind_owner(buyer)
			return mech
	return spawn(_parent_of(buyer), at, yaw_deg, buyer)


static func _vs_spawner(buyer: Player) -> VsSpawner:
	if buyer == null or buyer.flow == null:
		return null
	return buyer.flow.get("vs_spawner") as VsSpawner


static func spawn(parent: Node, at: Vector3, yaw_deg: float, buyer: Player = null) -> MechSuit:
	if parent == null:
		return null
	var mech: MechSuit = SCENE.instantiate()
	parent.add_child(mech)
	mech.global_position = stand_point(at)
	mech.rotation.y = deg_to_rad(yaw_deg)
	mech.bind_owner(buyer)
	Sfx.play("place_barrier", mech)
	return mech


static func plant_on_hole(parent: Node, hole: HoleData) -> MechSuit:
	if parent == null or hole == null or not hole.has_mech_pad():
		return null
	if parent.is_inside_tree():
		for node in parent.get_tree().get_nodes_in_group("mechs"):
			if node is MechSuit and parent.is_ancestor_of(node):
				return node as MechSuit
	return spawn(parent, hole.mech_stand(), hole.mech_face())


static func release_all(tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group("mechs"):
		var mech := node as MechSuit
		if mech != null:
			mech.release_pilot()


func bind_owner(buyer: Player) -> void:
	owner_player = buyer
	owner_peer = 0 if buyer == null else buyer.peer_id


func is_closed() -> bool:
	return closed


func hp_fraction() -> float:
	return clampf(float(hp) / float(MAX_HP), 0.0, 1.0)


func shells() -> int:
	if _watching():
		return sync_mag
	return combat.mag


func is_reloading() -> bool:
	if _watching():
		return sync_reload
	return combat.is_reloading()


func can_close(player: Player) -> bool:
	if closed or player == null or not player.health.is_alive():
		return false
	return _in_cockpit(player)


func try_close(player: Player) -> void:
	if NetSession.is_active() and not is_multiplayer_authority():
		_request_close.rpc_id(1, player.peer_id)
		return
	_do_close(player)


func release_pilot() -> void:
	if pilot == null:
		return
	var who := pilot
	var drop := exit_point()
	var yaw := rad_to_deg(who.rotation.y)
	pilot = null
	who.eject_from_mech(drop, yaw)
	_broadcast_pilot()


func wreck() -> void:
	var at := global_position + Vector3.UP * MechVisuals.HEIGHT * 0.45
	release_pilot()
	var root := get_tree().get_first_node_in_group("fx_root") if is_inside_tree() else null
	HitFx.blast(root, at, 4.0, Palette.MECH)
	Sfx.play("rocket_explode", self)
	queue_free()


func take_rocket(from: Player = null) -> void:
	if not is_foe(from) or hp <= 0:
		return
	hp -= 1
	if hp <= 0:
		wreck()


func is_foe(from: Player) -> bool:
	if from == null:
		return true
	if from == owner_player or from == pilot:
		return false
	if owner_player != null and from.partner == owner_player:
		return false
	if pilot != null and from.partner == pilot:
		return false
	return true


func allies() -> Array:
	var list: Array = []
	if owner_player != null:
		list.append(owner_player)
		if owner_player.partner != null:
			list.append(owner_player.partner)
	if pilot != null and not list.has(pilot):
		list.append(pilot)
		if pilot.partner != null and not list.has(pilot.partner):
			list.append(pilot.partner)
	return list


static func stand_point(at: Vector3) -> Vector3:
	return at + Vector3.UP * STAND_LIFT


func stand_at(at: Vector3, yaw_deg: float) -> void:
	global_position = at
	rotation.y = deg_to_rad(yaw_deg)
	velocity = Vector3.ZERO


func exit_point() -> Vector3:
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	return global_position + right * EXIT_SIDE + Vector3.UP * 0.3


func chase_view_transform() -> Transform3D:
	return chase_cam(global_position, rotation.y)


static func chase_cam(origin: Vector3, yaw: float) -> Transform3D:
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye := origin - facing * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT
	var target := origin + Vector3.UP * CHASE_LOOK_HEIGHT + facing * CHASE_LOOK_AHEAD
	var xform := Transform3D(Basis(), eye)
	return xform.looking_at(target, Vector3.UP)


func blast_point() -> Vector3:
	return global_position + Vector3.UP * MechVisuals.HEIGHT * 0.4


func golf_claim_origin() -> Vector3:
	return global_position


func golf_claim_range() -> float:
	return GOLF_RANGE


func golf_stance_point(lie: Vector3, aim_yaw_deg: float) -> Vector3:
	var right := Shot.aim_direction(aim_yaw_deg, STANCE_YAW).cross(Vector3.UP)
	return lie - Vector3.UP * GolfBall.RADIUS - right * GOLF_SIDE


func pilot_view_transform(pitch_deg: float) -> Transform3D:
	return _eye_view(MechVisuals.view_local(), pitch_deg)


func scope_view_transform(pitch_deg: float) -> Transform3D:
	return _eye_view(MechVisuals.scope_local(), pitch_deg)


func look_view(pitch_deg: float, scoped: bool) -> Transform3D:
	return scope_view_transform(pitch_deg) if scoped else pilot_view_transform(pitch_deg)


func _eye_view(local: Vector3, pitch_deg: float) -> Transform3D:
	var xform := global_transform
	xform.origin += global_transform.basis * local
	xform.basis = Basis.from_euler(Vector3(deg_to_rad(pitch_deg), rotation.y, 0.0))
	return xform


func _park_if_watched() -> void:
	if not _watching() or predicts_locally():
		collision_mask = Layers.VEHICLE_MASK
		return
	collision_mask = 0


func _physics_process(delta: float) -> void:
	var predicting := predicts_locally()
	if predicting != _predicting:
		_predicting = predicting
		_predict.clear()
		_park_if_watched()
	if _watching() and not predicting:
		return
	if predicting:
		_drive(delta)
		_predict.remember(global_position)
		_seat_pilot()
		_tick_visuals(delta)
		return
	combat.tick(delta)
	sync_mag = combat.mag
	sync_reload = combat.is_reloading()
	if not closed:
		sync_strafe = 0.0
		velocity = Vector3.ZERO
		_tick_visuals(delta)
		sync_xform = global_transform
		_publish_pose(delta)
		return
	_drive(delta)
	combat.stomp(self, crush, allies())
	_seat_pilot()
	_tick_visuals(delta)
	sync_xform = global_transform
	_publish_pose(delta)


## Watchers draw here so the capsule is never slid across the heightmap. Doing
## that in physics is how a parked suit stayed glued to the plaza after the host
## walked away.
func _process(delta: float) -> void:
	if not _watching():
		return
	if _predicting:
		_predict.correct(self, sync_xform, delta)
	else:
		_net_interp.follow(self, sync_xform, delta, NetSync.CART_HZ, NetSync.WATCH_DELAY)
	_seat_pilot()
	_tick_visuals(delta)


func net_interp() -> NetInterp:
	return _net_interp


func take_wire(
	pose: Transform3D, stick: Vector2, sprint: bool, sealed: bool, pilot_id: int
) -> void:
	sync_stick = stick
	sync_sprint = sprint
	sync_xform = pose
	closed = sealed
	_tick_visuals(0.0)
	var next := _player_with_peer(pilot_id)
	if next == null:
		return
	pilot = next
	if not next.is_in_mech():
		next.enter_mech(self)


func _publish_pose(delta: float) -> void:
	if not NetSession.is_active():
		return
	_wire_left -= delta
	if _wire_left > 0.0:
		return
	_wire_left = NetSync.CART_HZ
	_WorldFx.announce_mech(
		self, owner_peer, global_position, rotation.y, sync_stick, sync_sprint, closed, _peer_of(pilot)
	)


func _watching() -> bool:
	if not NetSession.is_active():
		return false
	if not multiplayer.is_server():
		return true
	return not is_multiplayer_authority()


## A sealed suit with this peer at the stick is driven here, the same way a
## cart is: the stick is the cause, the host pose only corrects. Watchers
## still glide, because they do not have the wheel.
func predicts_locally() -> bool:
	return closed and _watching() and _reads_local_input()


static func find_net(tree: SceneTree, owner_peer: int) -> MechSuit:
	if tree == null:
		return null
	var fallback: MechSuit
	for node in tree.get_nodes_in_group("mechs"):
		var mech := node as MechSuit
		if mech == null:
			continue
		if owner_peer > 0 and mech.owner_peer == owner_peer:
			return mech
		fallback = mech
	return fallback


func _tick_visuals(delta: float) -> void:
	if _visuals == null:
		return
	if _drawn_closed != closed:
		_drawn_closed = closed
		_apply_closed()
	if _watching() and not _predicting:
		_watch_stride(delta)
	if closed:
		_visuals.stride(delta, _step_t, _left_swing, _step_moving)
	else:
		_visuals.stride(delta, 0.0, _left_swing, false)
	_visuals.show_strafe(sync_strafe if closed else 0.0)


func _drive(delta: float) -> void:
	if pilot == null or not is_instance_valid(pilot) or not pilot.health.is_alive():
		return
	if pilot.is_golfing():
		velocity = Vector3.ZERO
		_want_fire = false
		_want_reload = false
		sync_strafe = 0.0
		_clear_step()
		return
	if not is_on_floor():
		velocity += get_gravity() * delta
	if _jumped() and is_on_floor():
		velocity.y = JUMP
		Sfx.play("jump", self)
	if is_stepping():
		_advance_step(delta)
	elif _plant_left > 0.0:
		_plant_left -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_queue_step(_stick())
	elif try_step(_stick()):
		_advance_step(delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	_aim()
	_fight()


func is_stepping() -> bool:
	return _step_left > 0.0


func try_step(stick: Vector2) -> bool:
	_queue_step(stick)
	if is_stepping() or _plant_left > 0.0:
		return false
	var dir := stick if stick.length() >= STEP_STICK else _queued
	_queued = Vector2.ZERO
	if dir.length() < STEP_STICK:
		return false
	return _begin_step(dir)


func _begin_step(stick: Vector2) -> bool:
	var wish := transform.basis * Vector3(stick.x, 0.0, stick.y)
	wish.y = 0.0
	if wish.length_squared() < 0.0001:
		return false
	_step_to = global_position + wish.normalized() * step_distance
	_step_dur = SPRINT_STEP_TIME if _sprinting() else STEP_TIME
	_step_left = _step_dur
	_step_t = 0.0
	_left_swing = not _left_swing
	_step_moving = true
	return true


func _advance_step(delta: float) -> void:
	var remain := _step_to - global_position
	remain.y = 0.0
	if _step_left <= delta or remain.length() <= 0.02:
		velocity.x = remain.x / maxf(delta, 0.001)
		velocity.z = remain.z / maxf(delta, 0.001)
		_step_t = 1.0
		_step_left = 0.0
		_step_moving = false
		_plant_left = STEP_PLANT
		return
	var speed := remain.length() / _step_left
	var toward := remain / remain.length()
	velocity.x = toward.x * speed
	velocity.z = toward.z * speed
	_step_t = clampf(1.0 - _step_left / maxf(_step_dur, 0.001), 0.0, 1.0)
	_step_left -= delta


func _queue_step(stick: Vector2) -> void:
	if stick.length() >= STEP_STICK:
		_queued = stick


func _clear_step() -> void:
	_step_left = 0.0
	_step_t = 0.0
	_step_moving = false
	_plant_left = 0.0
	_queued = Vector2.ZERO


func _watch_stride(delta: float) -> void:
	if not closed:
		_clear_step()
		return
	if sync_stick.length() < STEP_STICK:
		_step_moving = false
		return
	if is_stepping():
		_step_t = clampf(_step_t + delta / maxf(_step_dur, 0.001), 0.0, 1.0)
		_step_left -= delta
		if _step_left > 0.0:
			return
		_step_t = 1.0
		_step_left = 0.0
		_step_moving = false
		_plant_left = STEP_PLANT
		return
	if _plant_left > 0.0:
		_plant_left -= delta
		if _plant_left > 0.0:
			return
	_step_dur = SPRINT_STEP_TIME if sync_sprint else STEP_TIME
	_step_left = _step_dur
	_step_t = 0.0
	_left_swing = not _left_swing
	_step_moving = true


func _aim() -> void:
	if pilot == null or pilot.is_golfing():
		return
	var yaw := _net_yaw
	var pitch := sync_pitch
	if _reads_local_input():
		yaw = pilot.look_yaw()
		pitch = pilot.look_pitch()
		sync_stick = _stick()
		sync_sprint = _sprinting()
	rotation.y = deg_to_rad(yaw)
	sync_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	_net_yaw = yaw


func _fight() -> void:
	if _predicting:
		return
	if pilot == null or pilot.is_golfing():
		return
	var reload := false
	var fire := false
	if _reads_local_input():
		reload = pilot.input.just_pressed("reload")
		fire = pilot.input.just_pressed("shoot")
	else:
		reload = _want_reload
		fire = _want_fire
		_want_reload = false
		_want_fire = false
	if reload:
		combat.try_reload()
	if fire:
		combat.try_fire(self, look_view(sync_pitch, pilot.aiming), pilot)


func _reads_local_input() -> bool:
	if pilot == null:
		return false
	if not NetSession.is_active():
		return true
	return not (pilot.net_driven and pilot.peer_id != multiplayer.get_unique_id())


func _stick() -> Vector2:
	var stick := sync_stick
	if _reads_local_input():
		stick = pilot.input.move_vector()
	var strafe := _strafe()
	if absf(strafe) > 0.01:
		stick.x += strafe
		if stick.length() > 1.0:
			stick = stick.normalized()
	return stick


func _strafe() -> float:
	if pilot != null and _reads_local_input() and not pilot.is_golfing():
		var left := 1.0 if pilot.input.pressed("melee") else 0.0
		var right := 1.0 if pilot.input.pressed("shield") else 0.0
		sync_strafe = right - left
	return sync_strafe


func _sprinting() -> bool:
	if _reads_local_input():
		return pilot.input.pressed("sprint")
	return sync_sprint


func _jumped() -> bool:
	if _reads_local_input():
		if not pilot.input.just_pressed("jump"):
			return false
		sync_jumps += 1
		return true
	if sync_jumps == _seen_jumps:
		return false
	_seen_jumps = sync_jumps
	return true


func _seat_pilot() -> void:
	if pilot == null or seat == null:
		return
	pilot.sit_in_mech(seat.global_position, rad_to_deg(rotation.y), sync_pitch)


func _in_cockpit(player: Player) -> bool:
	if player == null:
		return false
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() <= BOARD_REACH:
		return true
	return cockpit != null and cockpit.overlaps_body(player)


func _do_close(player: Player) -> void:
	if not can_close(player):
		return
	closed = true
	pilot = player
	_apply_closed()
	_drawn_closed = true
	_net_yaw = player.look_yaw()
	sync_pitch = player.look_pitch()
	player.enter_mech(self)
	_seat_pilot()
	Sfx.play("board", self)
	_broadcast_pilot()
	_WorldFx.announce_mech(
		self, owner_peer, global_position, rotation.y, sync_stick, sync_sprint, true, _peer_of(pilot), true
	)


func _apply_closed() -> void:
	if _visuals == null:
		return
	MechVisuals.set_closed(_visuals, closed)


func _broadcast_pilot() -> void:
	if NetSession.is_active() and is_multiplayer_authority():
		_replicate_pilot.rpc(_peer_of(pilot))


func _peer_of(player: Player) -> int:
	return 0 if player == null else player.peer_id


func apply_pilot_report(
	stick: Vector2, sprint: bool, yaw: float, pitch: float, jumped: bool, strafe := 0.0
) -> void:
	sync_stick = stick
	sync_sprint = sprint
	sync_strafe = strafe
	_net_yaw = yaw
	sync_pitch = clampf(pitch, -PITCH_LIMIT, PITCH_LIMIT)
	if jumped:
		sync_jumps += 1


func _accept_pilot_rpc() -> bool:
	if not is_multiplayer_authority() or pilot == null:
		return false
	return multiplayer.get_remote_sender_id() == pilot.peer_id


@rpc("any_peer", "reliable")
func _request_close(peer_id: int) -> void:
	if not is_multiplayer_authority():
		return
	if not NetSession.rpc_speaks_for(multiplayer.get_remote_sender_id(), peer_id):
		return
	var who := _player_with_peer(peer_id)
	if who != null:
		_do_close(who)


@rpc("authority", "call_remote", "reliable")
func _replicate_pilot(peer_id: int) -> void:
	var next := _player_with_peer(peer_id)
	if pilot != null and pilot != next:
		if pilot.is_in_mech():
			pilot.eject_from_mech(exit_point(), rad_to_deg(pilot.rotation.y))
	pilot = next
	if next == null:
		return
	closed = true
	if not next.is_in_mech():
		next.enter_mech(self)
	_seat_pilot()


@rpc("any_peer", "unreliable")
func report_pilot(
	stick: Vector2, sprint: bool, yaw: float, pitch: float, jumped: bool, strafe := 0.0
) -> void:
	if not _accept_pilot_rpc():
		return
	apply_pilot_report(stick, sprint, yaw, pitch, jumped, strafe)


@rpc("any_peer", "reliable")
func report_fire() -> void:
	if _accept_pilot_rpc():
		_want_fire = true


@rpc("any_peer", "reliable")
func report_reload() -> void:
	if _accept_pilot_rpc():
		_want_reload = true


func _player_with_peer(id: int) -> Player:
	if id <= 0 or not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("players"):
		var other := node as Player
		if other != null and other.peer_id == id:
			return other
	return null


static func _parent_of(buyer: Player) -> Node:
	if buyer != null and buyer.flow != null and buyer.flow.has_method("hole_node"):
		var node: Node = buyer.flow.hole_node()
		if node != null:
			return node
	return buyer.get_parent() if buyer != null else null
