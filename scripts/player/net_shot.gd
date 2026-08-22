class_name NetShot
extends Node3D
## Thrown hoop. Hitscan guns share one path; this flies until it hits something
## solid, then drops one net over everyone in the trap radius.

const SPEED := 36.0
const COLOR: Color = Palette.NET

var radius := 20.0
var duration := 10.0
var max_range := 80.0
var direction := Vector3.FORWARD

var _travelled := 0.0
var _dead := false


static func spawn(
	root: Node, origin: Vector3, fly: Vector3, stats: WeaponStats
) -> NetShot:
	if root == null:
		return null
	var shot := NetShot.new()
	shot.radius = stats.trap_radius
	shot.duration = stats.trap_duration
	shot.max_range = stats.range_m
	shot.direction = fly.normalized()
	shot.add_to_group("net_shots")
	root.add_child(shot)
	shot.global_position = origin
	shot._build()
	return shot


func _build() -> void:
	var hoop := MeshFactory.torus(0.16, 0.28, COLOR, Palette.GLOW_MEDIUM)
	hoop.rotation.x = deg_to_rad(90.0)
	add_child(hoop)
	var hub := MeshFactory.sphere(0.05, Palette.ICE, Palette.GLOW_SOFT)
	add_child(hub)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 3.2
	lamp.omni_range = 7.0
	add_child(lamp)
	if direction.length_squared() > 0.0001:
		look_at(global_position + direction)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var step := SPEED * delta
	var from := global_position
	var to := from + direction * step
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.BULLET_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_land(hit["position"])
		return
	global_position = to
	rotate_object_local(Vector3.RIGHT, delta * 8.0)
	_travelled += step
	if _travelled >= max_range:
		_land(to)


func _land(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	var root := get_tree().get_first_node_in_group("fx_root")
	if root == null:
		root = get_parent()
	NetTrap.deploy(root, at, radius, duration)
	queue_free()
