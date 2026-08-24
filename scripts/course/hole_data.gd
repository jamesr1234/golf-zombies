class_name HoleData
extends RefCounted
## Plain description of one generated hole. Contains no nodes, so the generator
## stays testable and the builder stays the only thing touching the scene tree.

const DEFAULT_GREEN_RADIUS := 9.0

var index := 0
var par := 4
var tee := Vector3.ZERO
var cup := Vector3.ZERO
## Warm-up green behind the tee, on the line of the hole. Free to putt before
## the hole is started.
var practice_tee := Vector3.ZERO
var practice_cup := Vector3.ZERO
var green_radius := DEFAULT_GREEN_RADIUS
var centerline: Array[Vector3] = []
## Each entry: {type, position, size (Vector2 extents on XZ), yaw, round}
var patches: Array[Dictionary] = []
## Each entry: {kind, position, size (Vector3), yaw}
var props: Array[Dictionary] = []
## Each entry: {position, yaw, width, length, angle_deg, role}
var jumps: Array[Dictionary] = []
var spawn_points: Array[Vector3] = []
## Mesa on hole 3. INF means this hole has no mountain.
var mountain := Vector3.INF
## Culvert mouth on hole 2. INF means this hole has no pipe.
var culvert := Vector3.INF
## Carts wait here instead of beside the tee when set.
var cart_pad := Vector3.INF
var cart_yaw := 0.0
## Open suit parked on this hole. INF means the overlay did not place one.
var mech_pad := Vector3.INF
var mech_yaw := 0.0
## Playable footprint on the XZ plane. Leaving it is out of bounds.
var bounds := Rect2()
## Sampled ground. Null only before generation finishes.
var height: HeightField


func has_mountain() -> bool:
	return mountain != Vector3.INF


func has_culvert() -> bool:
	return culvert != Vector3.INF


func is_setpiece() -> bool:
	return has_mountain() or has_culvert()


func has_cart_pad() -> bool:
	return cart_pad != Vector3.INF


func has_mech_pad() -> bool:
	return mech_pad != Vector3.INF


func lift(point: Vector3) -> Vector3:
	if height == null:
		return point
	return height.lift(point)


func length() -> float:
	var total := 0.0
	for i in range(1, centerline.size()):
		total += centerline[i].distance_to(centerline[i - 1])
	return total


func tee_to_cup() -> float:
	return tee.distance_to(cup)


func practice_center() -> Vector3:
	return practice_tee.lerp(practice_cup, 0.5)


func green_span() -> float:
	return green_radius * 2.0


func sniper_perches() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for prop in props:
		if String(prop.get("kind", "")) != "tower":
			continue
		var origin: Vector3 = prop["position"]
		spots.append(origin + Vector3.UP * float(prop["size"].y))
	return spots


func label() -> String:
	return "Hole %d  Par %d" % [index + 1, par]


## Playing length, the number a tee sign should show.
func yardage() -> int:
	return roundi(length())


func sign_text() -> String:
	return "HOLE %d\n%d m" % [index + 1, yardage()]


## The pond covering this spot, or an empty dictionary on dry ground.
func water_patch_at(point: Vector3) -> Dictionary:
	for patch in patches:
		if patch["type"] == Surface.Type.WATER and HoleGenerator.patch_covers(patch, point):
			return patch
	return {}


## One flat level for the whole pond, which is also the height of the land around
## its bank. The floor bowls away below it.
func water_surface_y(point: Vector3) -> float:
	var patch := water_patch_at(point)
	if patch.is_empty():
		return point.y
	return float(patch.get("water_y", point.y))


func water_floor_y(point: Vector3) -> float:
	if height == null:
		return point.y
	return height.height_at(point.x, point.z)


## How much water is over the ground here: zero on dry land, and only past a
## wading depth is it deep enough to swim in.
func water_depth_at(point: Vector3) -> float:
	var patch := water_patch_at(point)
	if patch.is_empty() or height == null:
		return 0.0
	return maxf(0.0, float(patch.get("water_y", 0.0)) - height.height_at(point.x, point.z))
