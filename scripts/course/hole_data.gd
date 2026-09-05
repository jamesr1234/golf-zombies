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
## Each entry: {from, to, width, fill}. Speed pads the cart can drive.
var boosts: Array[Dictionary] = []
## Random fairway and rough arrivals, plus any overlay ZombieSpawn markers.
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
## Hole 12: a soccer goal instead of a cup. First ball through the net wins.
var soccer_goal := false
## Hole 11 hoop on the opening straight. INF means this hole has no gate.
var race_hoop := Vector3.INF
var race_hoop_yaw := 0.0
## Playable footprint on the XZ plane. Leaving it is out of bounds.
var bounds := Rect2()
## Set when this hole came out of the hole creator instead of the generator.
## The overlay then reads its props from here rather than from a hole_N scene.
var custom: CustomHole
## Sampled ground. Null only before generation finishes.
var height: HeightField


## Custom holes keep the hole-1 strip even when they sit in another slot, so a
## replacement for hole 10 does not inherit that hole's double-wide fairway.
func layout_index() -> int:
	return FairwayPiece.INDEX if custom != null else index


## How wide the landing strip is. A custom hole uses the size it was built
## with, not the slot it happens to sit in.
func fairway_width() -> float:
	if custom != null:
		return custom.width()
	return HoleGenerator.fairway_width(par, index)


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


func has_soccer_goal() -> bool:
	return soccer_goal


func has_race_hoop() -> bool:
	return race_hoop != Vector3.INF


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
	if custom != null:
		return "%s  Par %d" % [custom.title, par]
	if has_soccer_goal():
		return "Hole %d  Soccer Goal" % [index + 1]
	if RaceHole.applies(self):
		return "Test Hole 2  Par %d" % par
	if ArenaHole.applies(self):
		return "Hole %d  Arena" % [index + 1]
	return "Hole %d  Par %d" % [index + 1, par]


func banner_title() -> String:
	if custom != null:
		return "%s   Par %d" % [custom.title, par]
	if has_soccer_goal():
		return "Hole %d   Soccer Goal" % [index + 1]
	if RaceHole.applies(self):
		return "Test Hole 2   Par %d" % par
	if ArenaHole.applies(self):
		return "Hole %d   Arena" % [index + 1]
	return "Hole %d   Par %d" % [index + 1, par]


## Playing length, the number a tee sign should show.
func yardage() -> int:
	if has_soccer_goal():
		return SoccerHole.YARDS
	if RaceHole.applies(self):
		return RaceHole.YARDS
	return roundi(length())


func yardage_label() -> String:
	if ArenaHole.applies(self):
		return "Arena"
	return "%d yd" % yardage() if has_soccer_goal() or RaceHole.applies(self) else "%d m" % yardage()


func sign_text() -> String:
	if custom != null:
		return "%s\n%s" % [custom.title.to_upper(), yardage_label()]
	if RaceHole.applies(self):
		return "TEST HOLE 2\n%s" % yardage_label()
	return "HOLE %d\n%s" % [index + 1, yardage_label()]


## Facing down the first fairway, not as the crow flies to the cup.
func along_tee() -> Vector3:
	return _along_segment(0, cup - tee)


## Facing off the green along the last fairway.
func along_cup() -> Vector3:
	return _along_segment(centerline.size() - 2, cup - tee)


func _along_segment(i: int, fallback: Vector3) -> Vector3:
	if i >= 0 and i + 1 < centerline.size():
		var d: Vector3 = centerline[i + 1] - centerline[i]
		d.y = 0.0
		if d.length_squared() > 0.0001:
			return d.normalized()
	fallback.y = 0.0
	if fallback.length_squared() < 0.0001:
		return Vector3.FORWARD
	return fallback.normalized()


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
