@tool
class_name CartPathWindmill
extends Node3D
## Giant windmills on the racing line. The sails are thick pillars; get clipped
## and you are thrown off the tarmac, then you explode a beat later.

const _SCRIPT := preload("res://scripts/course/cart_path_windmill.gd")

const TOWER_R := 1.45
const TOWER_H := 8.4
const HUB_Y := 7.5
const PILLAR_LEN := 13.0
const PILLAR_W := 1.85
const PILLAR_T := 0.5
const PILLAR_COUNT := 4
const SPIN_DEG := 32.0
const FLING_SPEED := 34.0
const FLING_LIFT := 14.0
const EXPLODE_DELAY := 1.0
const ALONG: Array[float] = [0.30, 0.50, 0.70]
const END_CLEAR := 90.0
const SPAWN_CLEAR := 5.4


static func dress(path: Node3D) -> void:
	var centerline: Array = path.get("centerline")
	var length := float(path.get("track_length"))
	if centerline.size() < 2 or length < END_CLEAR * 2.0:
		return
	for t in ALONG:
		var dist := length * t
		if dist < END_CLEAR or dist > length - END_CLEAR:
			continue
		var at: Vector3 = CartPathTrack.at(centerline, dist)
		var face: Vector3 = CartPathTrack.heading_at(centerline, dist)
		path.add_child(create(at, face))
	_cull_spawns(path)


static func create(at: Vector3, along: Vector3) -> CartPathWindmill:
	var mill = _SCRIPT.new()
	mill.name = "CartPathWindmill"
	mill.add_to_group("cart_path_windmills")
	mill.position = at
	var face := along
	face.y = 0.0
	if face.length_squared() < 0.01:
		face = Vector3.FORWARD
	face = face.normalized()
	mill.rotation.y = atan2(-face.x, -face.z)
	mill._build()
	return mill


func to_prop() -> Dictionary:
	return {
		"kind": "windmill",
		"position": Vector3(position.x, 0.0, position.z),
		"size": Vector3(TOWER_R * 2.0, TOWER_H, TOWER_R * 2.0),
		"yaw": rad_to_deg(rotation.y),
	}


## Radians around the hub. Auto-spin writes this; a control unit can take over.
@export var sync_rotor := 0.0
@export var sync_driven := false


func _ready() -> void:
	add_to_group("cart_path_windmills")
	if get_child_count() == 0:
		_build()
	if not Engine.is_editor_hint() and NetSession.is_active():
		NetSync.attach(self, PackedStringArray([":sync_rotor", ":sync_driven"]))


func rotor_rad() -> float:
	return sync_rotor


func set_rotor_rad(rad: float) -> void:
	sync_rotor = rad
	_apply_rotor()


func drive(on: bool) -> void:
	sync_driven = on


func is_driven() -> bool:
	return sync_driven


static func shove_from(path: Node3D, body: Node3D, from: Vector3) -> Vector3:
	var at := body.global_position if body.is_inside_tree() else body.position
	var line: Array = path.get("centerline")
	var along := CartPathTrack.heading_at(line, CartPathTrack.along(line, at))
	var right := along.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var side := at - from
	side.y = 0.0
	var sign := signf(side.dot(right))
	if is_zero_approx(sign):
		sign = 1.0
	return right * sign


func _build() -> void:
	add_child(_tower())
	add_child(_mast_hit())
	var nacelle := MeshFactory.box(
		Vector3(2.2, 1.6, 3.4), Palette.WALL, Palette.GLOW_FAINT
	)
	nacelle.position = Vector3(0.0, HUB_Y, 0.35)
	add_child(nacelle)
	var cap := MeshFactory.taper(1.1, 0.15, 1.8, Palette.WALL, Palette.GLOW_FAINT)
	cap.position = Vector3(0.0, TOWER_H + 0.9, 0.0)
	add_child(cap)
	var hub := MeshFactory.cylinder(0.85, 0.7, Palette.CYAN, Palette.GLOW_MEDIUM)
	hub.rotation.x = deg_to_rad(90.0)
	hub.position = Vector3(0.0, HUB_Y, -0.85)
	add_child(hub)
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0.0, HUB_Y, -1.15)
	for i in PILLAR_COUNT:
		rotor.add_child(_pillar(i))
	add_child(rotor)
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.CYAN
	lamp.light_energy = 3.6
	lamp.omni_range = 20.0
	lamp.position = Vector3(0.0, HUB_Y + 0.8, -1.4)
	add_child(lamp)


func _physics_process(delta: float) -> void:
	if not sync_driven and (Engine.is_editor_hint() or NetSession.should_simulate(self)):
		sync_rotor += deg_to_rad(SPIN_DEG) * delta
	_apply_rotor()
	if Engine.is_editor_hint():
		return
	var rotor := get_node_or_null("Rotor") as Node3D
	if rotor != null:
		for child in rotor.get_children():
			_scan(child as Area3D)
	_scan(get_node_or_null("MastHit") as Area3D)


func _apply_rotor() -> void:
	var rotor := get_node_or_null("Rotor") as Node3D
	if rotor != null:
		rotor.rotation.z = sync_rotor


func _scan(area: Area3D) -> void:
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		_on_pillar_hit(body)


func _on_pillar_hit(body: Node3D) -> void:
	var victim := _victim(body)
	if victim == null:
		return
	var path := get_parent()
	if path != null and path.has_method("fling_off"):
		path.fling_off(victim, global_position)


static func _victim(body: Node3D) -> Node3D:
	var cart := body as GolfCart
	if cart != null:
		return cart
	var player := body as Player
	if player == null:
		return null
	if player.is_riding() and player.cart != null:
		return player.cart
	return player


func _tower() -> StaticBody3D:
	var mast := MeshFactory.cylinder_body(
		TOWER_R, TOWER_H, Palette.WALL, Layers.PROP, Palette.GLOW_FAINT
	)
	mast.position.y = TOWER_H * 0.5
	var ring := MeshFactory.cylinder(TOWER_R + 0.16, 0.22, Palette.CYAN, Palette.GLOW_STRONG)
	ring.position.y = HUB_Y - TOWER_H * 0.5 - 0.7
	mast.add_child(ring)
	return mast


func _mast_hit() -> Area3D:
	var zone := Area3D.new()
	zone.name = "MastHit"
	zone.collision_layer = 0
	zone.collision_mask = Layers.PLAYER | Layers.VEHICLE
	zone.monitoring = true
	zone.monitorable = false
	zone.position.y = TOWER_H * 0.5
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = TOWER_R + 0.35
	cylinder.height = TOWER_H
	shape.shape = cylinder
	zone.add_child(shape)
	zone.body_entered.connect(_on_pillar_hit)
	return zone


func _pillar(index: int) -> Area3D:
	var arm := Area3D.new()
	arm.collision_layer = 0
	arm.collision_mask = Layers.PLAYER | Layers.VEHICLE
	arm.monitoring = true
	arm.monitorable = false
	arm.rotation.z = float(index) * TAU / float(PILLAR_COUNT)
	var size := Vector3(PILLAR_W, PILLAR_LEN, PILLAR_T)
	var at := Vector3(0.0, PILLAR_LEN * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = at
	arm.add_child(shape)
	var beam := MeshFactory.box(size, Palette.WALL, Palette.GLOW_FAINT)
	beam.position = at
	arm.add_child(beam)
	var edge := MeshFactory.box(
		Vector3(PILLAR_W * 0.18, PILLAR_LEN * 0.96, PILLAR_T + 0.08),
		Palette.CYAN, Palette.GLOW_STRONG
	)
	edge.position = at + Vector3(PILLAR_W * 0.38, 0.0, 0.0)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm.add_child(edge)
	arm.body_entered.connect(_on_pillar_hit)
	return arm


static func _cull_spawns(path: Node3D) -> void:
	var points: Array = path.get("spawn_points")
	if points.is_empty():
		return
	var kept: Array[Vector3] = []
	for point in points:
		var at: Vector3 = point
		if _near_mill(path, at):
			continue
		kept.append(at)
	path.set("spawn_points", kept)


static func _near_mill(path: Node3D, at: Vector3) -> bool:
	for child in path.get_children():
		if not child.is_in_group("cart_path_windmills"):
			continue
		var mill := child as Node3D
		if Vector2(at.x - mill.position.x, at.z - mill.position.z).length() < SPAWN_CLEAR:
			return true
	return false
