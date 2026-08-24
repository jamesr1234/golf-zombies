class_name MechSuit
extends CharacterBody3D
## Clubhouse mech. Parked open with stairs; Circle in the cockpit seals it.
## After that the pilot is in until it is wrecked or the hole ends.

const SCENE := preload("res://scenes/course/items/mech_suit.tscn")
const _WorldFx := preload("res://scripts/net/world_fx.gd")
const WALK := 16.0
const SPRINT := 24.0
const JUMP := 10.0
const ACCEL := 14.0
const MAX_HP := 8
const EXIT_SIDE := 12.0
const GOLF_RANGE := 18.0
const GOLF_SIDE := 6.0
const STANCE_YAW := 0.0
const FLOOR_SNAP := 0.45
const FLOOR_MAX_DEG := 55.0
const PITCH_LIMIT := 85.0
const CHASE_DISTANCE := 28.0
const CHASE_HEIGHT := 14.0
const CHASE_LOOK_HEIGHT := 10.0
const CHASE_LOOK_AHEAD := 6.0
const CHASE_FOV := 88.0
const BOARD_REACH := 2.4

var owner_player: Player
var owner_peer := 0
var pilot: Player
var combat := MechCombat.new()
var _visuals: MechVisuals
var _net_interp := NetInterp.new()
var _seen_jumps := 0
var _net_yaw := 0.0
var _want_fire := false
var _want_reload := false
var _drawn_closed := false
var _wire_left := 0.0

@export var closed := false
@export var hp := MAX_HP
@export var sync_stick := Vector2.ZERO
@export var sync_sprint := false
@export var sync_jumps := 0
@export var sync_pitch := 0.0
@export var sync_mag := MechCombat.MAG_SIZE
@export var sync_reload := false
@export var sync_xform := Transform3D.IDENTITY:
	set(value):
		sync_xform = value
		if is_inside_tree() and _watching():
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
	var at: Vector3 = pose["at"]
	var yaw := float(pose["yaw"])
	if NetSession.is_active():
		var spawner := _vs_spawner(buyer)
		if spawner != null:
			var mech := spawner.spawn_mech(at, yaw, buyer.peer_id)
			if mech != null:
				mech.bind_owner(buyer)
			return mech
	return spawn(_parent_of(buyer), at, yaw, buyer)


static func _vs_spawner(buyer: Player) -> VsSpawner:
	if buyer == null or buyer.flow == null:
		return null
	return buyer.flow.get("vs_spawner") as VsSpawner


static func spawn(parent: Node, at: Vector3, yaw_deg: float, buyer: Player = null) -> MechSuit:
	if parent == null:
		return null
	var mech: MechSuit = SCENE.instantiate()
	parent.add_child(mech)
	mech.global_position = at
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
	return spawn(parent, hole.mech_pad + Vector3.UP * 0.05, hole.mech_yaw)


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
	HitFx.blast(root, at, 12.0, Palette.MECH)
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
	if view == null:
		return global_transform
	var xform := view.global_transform
	xform.basis = Basis.from_euler(Vector3(deg_to_rad(pitch_deg), rotation.y, 0.0))
	return xform


func _park_if_watched() -> void:
	if not _watching():
		return
	collision_mask = 0


func _physics_process(delta: float) -> void:
	if _watching():
		return
	combat.tick(delta)
	sync_mag = combat.mag
	sync_reload = combat.is_reloading()
	if not closed:
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
	var pace := 0.0
	if closed:
		if _watching():
			var stick := sync_stick.length()
			pace = stick if sync_sprint else stick * (WALK / SPRINT)
		else:
			pace = Vector2(velocity.x, velocity.z).length() / SPRINT
	_visuals.animate(delta, pace)


func _drive(delta: float) -> void:
	if pilot == null or not is_instance_valid(pilot) or not pilot.health.is_alive():
		return
	if pilot.is_golfing():
		velocity = Vector3.ZERO
		_want_fire = false
		_want_reload = false
		return
	var stick := _stick()
	var wish := (transform.basis * Vector3(stick.x, 0.0, stick.y))
	wish.y = 0.0
	var speed := SPRINT if _sprinting() else WALK
	if wish.length_squared() > 0.0001:
		wish = wish.normalized() * minf(1.0, stick.length()) * speed
	if not is_on_floor():
		velocity += get_gravity() * delta
	if _jumped() and is_on_floor():
		velocity.y = JUMP
		Sfx.play("jump", self)
	velocity.x = move_toward(velocity.x, wish.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, wish.z, ACCEL * delta)
	move_and_slide()
	_aim()
	_fight()


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
		combat.try_fire(self, pilot_view_transform(sync_pitch), pilot)


func _reads_local_input() -> bool:
	if pilot == null:
		return false
	if not NetSession.is_active():
		return true
	return not (pilot.net_driven and pilot.peer_id != multiplayer.get_unique_id())


func _stick() -> Vector2:
	if _reads_local_input():
		return pilot.input.move_vector()
	return sync_stick


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
	if cockpit == null or player == null:
		return false
	return cockpit.overlaps_body(player) or player.global_position.distance_to(
		cockpit.global_position
	) <= BOARD_REACH


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
	MechVisuals.set_stairs_solid(self, not closed)


func _broadcast_pilot() -> void:
	if NetSession.is_active() and is_multiplayer_authority():
		_replicate_pilot.rpc(_peer_of(pilot))


func _peer_of(player: Player) -> int:
	return 0 if player == null else player.peer_id


func apply_pilot_report(
	stick: Vector2, sprint: bool, yaw: float, pitch: float, jumped: bool
) -> void:
	sync_stick = stick
	sync_sprint = sprint
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
	stick: Vector2, sprint: bool, yaw: float, pitch: float, jumped: bool
) -> void:
	if not _accept_pilot_rpc():
		return
	apply_pilot_report(stick, sprint, yaw, pitch, jumped)


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
