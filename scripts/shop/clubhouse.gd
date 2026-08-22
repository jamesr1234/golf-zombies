class_name Clubhouse
extends Node3D
## Walk-in hall at the next tee. Open the doors, then shop the counters inside.

const DOOR_RANGE := 4.2
const OPEN_ANGLE := 98.0

var doors_open := false
var exit_open := false
var stations: Array[ShopStation] = []
var npcs: Array[ClubhouseNpc] = []
var cashiers: Array[ClubhouseNpc] = []
var door_left: Node3D
var door_right: Node3D
var exit_left: Node3D
var exit_right: Node3D
var plaza: StaticBody3D


static func create(at: Vector3, yaw: float) -> Clubhouse:
	var house := Clubhouse.new()
	house.name = "Clubhouse"
	ClubhouseBuild.assemble(house)
	house.position = at
	house.rotation.y = deg_to_rad(yaw)
	return house


func door_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, ClubhouseBuild.DEPTH * 0.5))


func exit_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, -ClubhouseBuild.DEPTH * 0.5))


func can_open_doors(who: Node3D) -> bool:
	if doors_open or who == null or not is_inside_tree():
		return false
	return _flat_distance(who, door_point()) <= DOOR_RANGE


func open_doors() -> void:
	if doors_open:
		return
	doors_open = true
	if door_left != null:
		door_left.rotation.y = deg_to_rad(OPEN_ANGLE)
	if door_right != null:
		door_right.rotation.y = deg_to_rad(-OPEN_ANGLE)


func can_open_exit(who: Node3D) -> bool:
	if exit_open or who == null or not is_inside_tree():
		return false
	return _flat_distance(who, exit_point()) <= DOOR_RANGE


func open_exit() -> void:
	if exit_open:
		return
	exit_open = true
	if exit_left != null:
		exit_left.rotation.y = deg_to_rad(-OPEN_ANGLE)
	if exit_right != null:
		exit_right.rotation.y = deg_to_rad(OPEN_ANGLE)


func station_for(who: Node3D) -> ShopStation:
	if who == null:
		return null
	for station in stations:
		if is_instance_valid(station) and station.can_use(who):
			return station
	return null


func npc_for(who: Node3D) -> ClubhouseNpc:
	if who == null:
		return null
	for npc in npcs:
		if is_instance_valid(npc) and npc.can_use(who):
			return npc
	for clerk in cashiers:
		if is_instance_valid(clerk) and clerk.can_use(who):
			return clerk
	return null


func inside(who: Node3D) -> bool:
	if who == null or not is_inside_tree():
		return false
	var local := to_local(who.global_position)
	return (
		absf(local.x) <= ClubhouseBuild.WIDTH * 0.5 - 0.4
		and absf(local.z) <= ClubhouseBuild.DEPTH * 0.5 - 0.4
	)


func comedy_count() -> int:
	var total := 0
	for npc in npcs:
		if npc.comedy:
			total += 1
	return total


## Local +Z is the front doors. The plaza covers the hall, the approach, and the
## walk out the back onto the practice green.
func covers_local(at: Vector3) -> bool:
	var half_x := ClubhouseBuild.WIDTH * 0.5 + ClubhouseBuild.PLAZA_SIDE
	var z_min := -ClubhouseBuild.DEPTH * 0.5 - ClubhouseBuild.PLAZA_BACK
	var z_max := ClubhouseBuild.DEPTH * 0.5 + ClubhouseBuild.PLAZA_FRONT
	return absf(at.x) <= half_x and at.z >= z_min and at.z <= z_max


func _flat_distance(who: Node3D, at: Vector3) -> float:
	var offset := who.global_position - at
	offset.y = 0.0
	return offset.length()
