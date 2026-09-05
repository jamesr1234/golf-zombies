class_name ClubhouseElevator
extends Node3D
## Stationary cabins at each stop. Interact rides: doors close, wait, teleport.

const _SCRIPT := preload("res://scripts/shop/clubhouse_elevator.gd")
const CABIN := Vector3(2.45, 2.55, 2.2)
const DOOR_W := 1.15
const DOOR_H := 2.15
const DOOR_SEC := 0.28
const RIDE_SEC := 0.8
const OPEN_Z := 0.95
const SHUT_Z := 0.32
const STOPS: Array[Dictionary] = [
	{"name": "Lobby", "story": 0},
	{"name": "Upper", "story": 1},
]

var riding := false
var _door_l: Array[Node3D] = []
var _door_r: Array[Node3D] = []


static func shaft_origin() -> Vector3:
	return Vector3(
		ClubhouseBuild.WIDTH * 0.5 - ClubhouseBuild.THICK - CABIN.x * 0.5 - 0.4,
		0.0,
		-11.0
	)


## Half-extents of the hole punched in the upper slab.
static func shaft_hole() -> Vector3:
	return Vector3(CABIN.x * 0.5 + 0.16, 0.0, CABIN.z * 0.5 + 0.16)


static func create():
	var lift = _SCRIPT.new()
	lift.name = "Elevator"
	lift.position = shaft_origin()
	lift._build()
	return lift


static func nearest(who: Node3D):
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("clubhouse_elevators"):
		if node.has_method("can_use") and node.can_use(who):
			return node
	return null


func dest_index(from: int) -> int:
	if STOPS.size() <= 1:
		return from
	if STOPS.size() == 2:
		return 1 - from
	return (from + 1) % STOPS.size()


func dest_name(who: Node3D) -> String:
	var from := stop_for(who)
	if from < 0:
		return String(STOPS[1]["name"])
	return String(STOPS[dest_index(from)]["name"])


func stop_for(who: Node3D) -> int:
	if who == null or not is_inside_tree():
		return -1
	var local := to_local(who.global_position)
	for i in STOPS.size():
		var floor := ClubhouseBuild.story_floor_y(int(STOPS[i]["story"]))
		if local.x < -CABIN.x * 0.5 - 0.25 or local.x > CABIN.x * 0.5 - 0.05:
			continue
		if absf(local.z) > CABIN.z * 0.5 - 0.05:
			continue
		if local.y < floor - 0.35 or local.y > floor + CABIN.y:
			continue
		return i
	return -1


func can_use(who: Node3D) -> bool:
	if riding or who == null or not is_inside_tree():
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	if who.has_method("is_poker_seated") and who.is_poker_seated():
		return false
	return stop_for(who) >= 0


func try_ride(who: Node3D) -> void:
	if not can_use(who):
		return
	var from := stop_for(who)
	var to := dest_index(from)
	if NetSession.is_active() and not multiplayer.is_server():
		_request_ride.rpc_id(1, int(who.get("peer_id")))
		return
	if NetSession.is_active():
		_ride_net.rpc(from, to)
		return
	_ride(from, to, who)


func _ride(from: int, to: int, extra: Node3D) -> void:
	if riding:
		return
	riding = true
	_tween_doors(from, false)
	_tween_doors(to, false)
	await get_tree().create_timer(DOOR_SEC + RIDE_SEC).timeout
	if not is_inside_tree():
		return
	_teleport_stop(from, to, extra)
	_tween_doors(to, true)
	Sfx.play("elevator_bell", self)
	riding = false


@rpc("authority", "call_local", "reliable")
func _ride_net(from: int, to: int) -> void:
	_ride(from, to, null)


@rpc("any_peer", "reliable")
func _request_ride(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var who := _player_for(peer_id)
	if who != null and can_use(who):
		_ride_net.rpc(stop_for(who), dest_index(stop_for(who)))


func _teleport_stop(from: int, to: int, extra: Node3D) -> void:
	var from_y := ClubhouseBuild.story_floor_y(int(STOPS[from]["story"]))
	var to_y := ClubhouseBuild.story_floor_y(int(STOPS[to]["story"]))
	var lift := to_y - from_y
	var riders: Array[Node3D] = []
	if extra != null:
		riders.append(extra)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("players"):
			var body := node as Node3D
			if body != null and stop_for(body) == from and not riders.has(body):
				riders.append(body)
	for who in riders:
		var dest := who.global_position + Vector3.UP * lift
		var yaw := rad_to_deg(who.rotation.y)
		if who.has_method("look_yaw"):
			yaw = who.look_yaw()
		if who.has_method("spawn_at"):
			who.spawn_at(dest, yaw)
		else:
			who.global_position = dest


func _player_for(peer_id: int) -> Node:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			return node
	return null


func _tween_doors(stop: int, open: bool) -> void:
	if stop < 0 or stop >= _door_l.size():
		return
	var z := OPEN_Z if open else SHUT_Z
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_door_l[stop], "position:z", -z, DOOR_SEC)
	tween.tween_property(_door_r[stop], "position:z", z, DOOR_SEC)


func _build() -> void:
	add_to_group("clubhouse_elevators")
	_well()
	for i in STOPS.size():
		_cabin(i)


func _well() -> void:
	var y0 := ClubhouseBuild.story_floor_y(0)
	var y1 := ClubhouseBuild.story_floor_y(1)
	var h := y1 - y0
	var mid := y0 + h * 0.5
	_box(Vector3(CABIN.x, h, 0.1), Vector3(0.0, mid, CABIN.z * 0.5), Layers.PROP)
	_box(Vector3(CABIN.x, h, 0.1), Vector3(0.0, mid, -CABIN.z * 0.5), Layers.PROP)
	_box(Vector3(0.1, h, CABIN.z), Vector3(CABIN.x * 0.5, mid, 0.0), Layers.PROP)


func _cabin(stop: int) -> void:
	var story := int(STOPS[stop]["story"])
	var floor := ClubhouseBuild.story_floor_y(story)
	var mid := floor + CABIN.y * 0.5
	_box(Vector3(CABIN.x + 0.45, 0.08, CABIN.z + 0.45), Vector3(0.0, floor + 0.04, 0.0), Layers.WORLD)
	_box(Vector3(CABIN.x, 0.08, CABIN.z), Vector3(0.0, floor + CABIN.y, 0.0), Layers.PROP)
	_box(Vector3(0.1, CABIN.y, CABIN.z), Vector3(CABIN.x * 0.5, mid, 0.0), Layers.PROP)
	_box(Vector3(CABIN.x, CABIN.y, 0.1), Vector3(0.0, mid, CABIN.z * 0.5), Layers.PROP)
	_box(Vector3(CABIN.x, CABIN.y, 0.1), Vector3(0.0, mid, -CABIN.z * 0.5), Layers.PROP)
	var door_x := -CABIN.x * 0.5
	var side := (CABIN.z - DOOR_W) * 0.5
	_box(Vector3(0.1, CABIN.y, side), Vector3(door_x, mid, (DOOR_W + side) * 0.5), Layers.PROP)
	_box(Vector3(0.1, CABIN.y, side), Vector3(door_x, mid, -(DOOR_W + side) * 0.5), Layers.PROP)
	var lintel_h := CABIN.y - DOOR_H
	_box(Vector3(0.1, lintel_h, DOOR_W + 0.1), Vector3(door_x, floor + DOOR_H + lintel_h * 0.5, 0.0), Layers.PROP)
	_door_l.append(_leaf(door_x, floor, -OPEN_Z))
	_door_r.append(_leaf(door_x, floor, OPEN_Z))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.4)
	lamp.light_energy = 0.35
	lamp.omni_range = 3.2
	lamp.position = Vector3(0.0, floor + CABIN.y - 0.2, 0.0)
	add_child(lamp)
	var plate := Label3D.new()
	plate.text = String(STOPS[stop]["name"]).to_upper()
	plate.font_size = 18
	plate.modulate = ClubhouseDecor.BRASS
	plate.position = Vector3(CABIN.x * 0.5 - 0.08, floor + 1.7, 0.0)
	plate.rotation.y = deg_to_rad(-90.0)
	add_child(plate)


func _leaf(door_x: float, floor: float, z: float) -> Node3D:
	var slab := MeshFactory.box_body(
		Vector3(0.08, DOOR_H - 0.08, DOOR_W * 0.5 - 0.04),
		Palette.BABY_BLUE, Layers.PROP, true, Palette.GLOW_FAINT
	)
	slab.position = Vector3(door_x, floor + DOOR_H * 0.5, z)
	add_child(slab)
	return slab


func _box(size: Vector3, at: Vector3, layer: int) -> void:
	var body := MeshFactory.box_body(size, Palette.WALL, layer, true, Palette.GLOW_FAINT)
	body.position = at
	add_child(body)
