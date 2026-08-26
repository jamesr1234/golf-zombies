class_name DoorShot
extends Node3D
## Shot picks the landing spot immediately. The warp door always opens 0.2s later.

const SPEED := 36.0
const FLIGHT_TIME := 0.2
const COLOR: Color = Palette.DOOR
const _WorldFx := preload("res://scripts/net/world_fx.gd")

var duration := 20.0
var direction := Vector3.FORWARD
var shooter_peer := 0

var visual_only := false
var _age := 0.0
var _born_msec := 0
var _origin := Vector3.ZERO
var _plant_at := Vector3.ZERO
var _plant_normal := Vector3.UP
var _dead := false


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, stats: WeaponStats, peer_id := 0
) -> DoorShot:
	if stats == null:
		return null
	return spawn_flight(root, origin, fly, stats.door_duration, peer_id)


static func spawn_flight(
	root: Node, origin: Vector3, fly: Vector3, hold: float, peer_id := 0,
	p_visual_only := false
) -> DoorShot:
	if root == null:
		return null
	var shot := DoorShot.new()
	shot.duration = hold
	shot.direction = fly.normalized()
	shot.shooter_peer = peer_id
	shot.visual_only = p_visual_only
	shot.add_to_group("door_shots")
	root.add_child(shot)
	shot.global_position = origin
	shot._origin = origin
	shot._born_msec = Time.get_ticks_msec()
	shot._build()
	shot._lock_plant()
	shot._start_timer()
	return shot


static func flight_distance() -> float:
	return SPEED * FLIGHT_TIME


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_physics_process(false)
	var frame := MeshFactory.box(Vector3(0.55, 0.95, 0.06), COLOR, Palette.GLOW_MEDIUM)
	add_child(frame)
	var pane := MeshFactory.box(Vector3(0.38, 0.72, 0.02), Palette.ICE, Palette.GLOW_STRONG)
	pane.position.z = -0.02
	add_child(pane)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 3.0
	lamp.omni_range = 6.5
	add_child(lamp)
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction)


func _lock_plant() -> void:
	var from := global_position
	var to := from + direction * flight_distance()
	_plant_at = to
	_plant_normal = Vector3.UP
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	_stick(hit["position"], hit["normal"])


func _start_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = FLIGHT_TIME
	timer.one_shot = true
	timer.autostart = true
	timer.process_callback = Timer.TIMER_PROCESS_IDLE
	timer.timeout.connect(_open)
	add_child(timer)


func _process(delta: float) -> void:
	_tick(delta)


func _tick(delta: float) -> void:
	if _dead:
		return
	_age += delta
	var t := clampf(_elapsed() / FLIGHT_TIME, 0.0, 1.0)
	global_position = _origin.lerp(_plant_at, t)
	if _elapsed() >= FLIGHT_TIME:
		_open()


func _stick(at: Vector3, normal: Vector3) -> void:
	_plant_at = at
	_plant_normal = normal


func _elapsed() -> float:
	var wall := 0.0
	if _born_msec > 0:
		wall = float(Time.get_ticks_msec() - _born_msec) * 0.001
	return maxf(_age, wall)


func _open() -> void:
	if _dead:
		return
	_dead = true
	if not visual_only:
		var root := get_tree().get_first_node_in_group("fx_root")
		if root == null:
			root = get_parent()
		var door := WarpDoor.spawn(
			root, _plant_at, _plant_normal, direction, duration, shooter_peer
		)
		if door != null:
			_WorldFx.announce_door(
				self, door.global_position, door.facing(), duration, shooter_peer
			)
	queue_free()
