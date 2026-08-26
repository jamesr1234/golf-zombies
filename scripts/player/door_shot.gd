class_name DoorShot
extends Node3D
## Thrown door frame. Flies one metre, then plants a warp door. Hits a wall or
## the floor sooner? It plants there.

const SPEED := 36.0
const RANGE := 1.0
const COLOR: Color = Palette.DOOR
const _WorldFx := preload("res://scripts/net/world_fx.gd")

var duration := 20.0
var direction := Vector3.FORWARD
var shooter_peer := 0

var visual_only := false
var _travelled := 0.0
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
	shot._build()
	return shot


func _build() -> void:
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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var remain := RANGE - _travelled
	if remain <= 0.0:
		_land(global_position, Vector3.UP)
		return
	var step := minf(SPEED * delta, remain)
	var from := global_position
	var to := from + direction * step
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_land(hit["position"], hit["normal"])
		return
	global_position = to
	rotate_object_local(Vector3.UP, delta * 6.0)
	_travelled += step
	if _travelled >= RANGE:
		_land(to, Vector3.UP)


func _land(at: Vector3, normal: Vector3) -> void:
	if _dead:
		return
	_dead = true
	if not visual_only:
		var root := get_tree().get_first_node_in_group("fx_root")
		if root == null:
			root = get_parent()
		var door := WarpDoor.spawn(root, at, normal, direction, duration, shooter_peer)
		if door != null:
			_WorldFx.announce_door(
				self, door.global_position, door.facing(), duration, shooter_peer
			)
	queue_free()
