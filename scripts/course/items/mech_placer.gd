class_name MechPlacer
extends Object
## Drops the open suit beside the buyer, just clear of the hall and other props.

const CLEAR := 12.0
const SIDE := 22.0
const BACK := 24.0
const RING_STEP := 14.0
const MIN_FLOOR := 0.55
const WATER := 0.3


static func place(buyer: Player) -> Dictionary:
	var yaw := _yaw_of(buyer)
	var origin := buyer.global_position if buyer != null else Vector3.ZERO
	var house := _clubhouse(buyer)
	var inside := house != null and _inside_hall(house, origin)
	var spots := candidates(origin, yaw, inside, house)
	var hole = _hole(buyer)
	var world: World3D = buyer.get_world_3d() if buyer != null and buyer.is_inside_tree() else null
	for spot in spots:
		var at := _lift(hole, spot)
		if _blocked(world, at, buyer):
			continue
		if hole != null and hole.water_depth_at(at) >= WATER:
			continue
		return {"at": at, "yaw": yaw}
	var fallback := _lift(hole, spots[0] if not spots.is_empty() else origin + Vector3(SIDE, 0.0, 0.0))
	return {"at": fallback, "yaw": yaw}


static func candidates(
	origin: Vector3, yaw_deg: float, inside_hall := false, house: Node3D = null
) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	if inside_hall and house != null:
		spots.append(house.to_global(_plaza_local()))
	var right := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	var back := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(yaw_deg))
	spots.append(origin + right * SIDE)
	spots.append(origin - right * SIDE)
	spots.append(origin + back * BACK)
	for i in 6:
		var angle := float(i) * TAU / 6.0
		spots.append(origin + Vector3(cos(angle), 0.0, sin(angle)) * (SIDE + RING_STEP))
	return spots


static func _plaza_local() -> Vector3:
	return Vector3(0.0, 0.0, -ClubhouseBuild.DEPTH * 0.5 - ClubhouseBuild.PLAZA_BACK * 0.45)


static func _inside_hall(house: Node3D, at: Vector3) -> bool:
	var local := house.to_local(at)
	return (
		absf(local.x) < ClubhouseBuild.WIDTH * 0.5 - 1.0
		and absf(local.z) < ClubhouseBuild.DEPTH * 0.5 - 1.0
	)


static func _blocked(world: World3D, at: Vector3, buyer: Player) -> bool:
	if world == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CLEAR * 2.0, 8.0, CLEAR * 2.0)
	query.shape = box
	query.transform = Transform3D(Basis(), at + Vector3.UP * 4.0)
	query.collision_mask = Layers.WORLD | Layers.PROP | Layers.VEHICLE | Layers.MECH
	query.collide_with_areas = false
	if buyer != null:
		query.exclude = [buyer.get_rid()]
	return not world.direct_space_state.intersect_shape(query, 1).is_empty()


static func _lift(hole, at: Vector3) -> Vector3:
	if hole != null and hole.has_method("lift"):
		return hole.lift(at) + Vector3.UP * 0.05
	return at


static func _yaw_of(buyer: Player) -> float:
	if buyer == null:
		return 0.0
	return rad_to_deg(buyer.rotation.y)


static func _hole(buyer: Player):
	if buyer == null or buyer.flow == null:
		return null
	return buyer.flow.get("hole")


static func _clubhouse(buyer: Player) -> Node3D:
	if buyer == null or buyer.flow == null:
		return null
	var house = buyer.flow.get("clubhouse")
	return house if house is Node3D and is_instance_valid(house) else null
