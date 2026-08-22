class_name HeightField
extends RefCounted
## Ground height for one hole. The course is a sampled heightmap so the fairway
## can drop away from the tee, the green can sit on a rise, and the rough is
## never a bowling alley.

const CELL := 2.5
const SKIRT := 4.0
const _Ramp := preload("res://scripts/course/jump_ramp.gd")
## How far a pond floor sits below its water line. Deep enough to swim down after
## a sunk ball with room to spare, shallow enough that the banks are not cliffs.
const WATER_DEPTH := 6.0
## Ring of shoreline outside a pond levelled to the water line, so the surface
## meets the land instead of ending in a step.
const WATER_BANK := 6.0
## Shelf inside the rim held at the water line too. The heightmap only stores a
## sample every CELL, so without a flat band either side of the edge the surface
## would end up hanging over interpolated ground.
const WATER_SHELF := 3.0
## Run the floor takes to fall from the shelf to full depth.
const WATER_SLOPE := 4.5
## The landing strip stays playable. Off it, the rough can actually rise and fall.
const NOISE_OFF_FAIRWAY := 3.8
const NOISE_ON_FAIRWAY := 0.22
const HILL_BLEND := 14.0

enum Profile { DOWNHILL, UPHILL, VALLEY, RIDGE, ROLLING }

var origin := Vector2.ZERO
var cell := CELL
var width := 0
var depth := 0
var samples := PackedFloat32Array()
var min_height := 0.0
var max_height := 0.0
## World XZ the visual mesh should leave alone, so a later heightmap (the
## clubhouse woods) never redraws the hole the player is standing on.
var hide := Rect2()


func height_at(x: float, z: float) -> float:
	if width < 2 or depth < 2:
		return 0.0
	var fx := clampf((x - origin.x) / cell, 0.0, float(width - 1) - 0.0001)
	var fz := clampf((z - origin.y) / cell, 0.0, float(depth - 1) - 0.0001)
	var x0 := int(fx)
	var z0 := int(fz)
	return lerpf(
		lerpf(_sample(x0, z0), _sample(x0 + 1, z0), fx - float(x0)),
		lerpf(_sample(x0, z0 + 1), _sample(x0 + 1, z0 + 1), fx - float(x0)),
		fz - float(z0)
	)


func lift(point: Vector3) -> Vector3:
	return Vector3(point.x, height_at(point.x, point.z), point.z)


func make_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.add_child(_heightmap_collision())
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = _visual_mesh()
	mesh_node.material_override = MeshFactory.grid_material(Surface.LOOK[Surface.Type.ROUGH])
	body.add_child(mesh_node)
	var center := origin + Vector2(float(width - 1), float(depth - 1)) * cell * 0.5
	body.position = Vector3(center.x, 0.0, center.y)
	return body


## Triangle-mesh collision catches capsules on every cell edge and makes walkers
## hitch. A heightmap is the same ground without those internal edges.
func _heightmap_collision() -> CollisionShape3D:
	var heightmap := HeightMapShape3D.new()
	heightmap.map_width = width
	heightmap.map_depth = depth
	heightmap.map_data = scaled_collision_heights()
	var node := CollisionShape3D.new()
	node.shape = heightmap
	# Uniform scale so Godot Physics and Jolt both accept it. Heights are stored
	# in cells, then multiplied back to metres by this scale.
	node.scale = Vector3(cell, cell, cell)
	return node


func scaled_collision_heights() -> PackedFloat32Array:
	var scaled := PackedFloat32Array()
	scaled.resize(samples.size())
	var inv := 1.0 / cell
	for i in samples.size():
		scaled[i] = samples[i] * inv
	return scaled


static func generate(data: HoleData, rng: RandomNumberGenerator) -> HeightField:
	var field := HeightField.new()
	field.origin = data.bounds.position
	field.cell = CELL
	field.width = maxi(2, int(ceil(data.bounds.size.x / CELL)) + 1)
	field.depth = maxi(2, int(ceil(data.bounds.size.y / CELL)) + 1)
	var profile := rng.randi_range(0, 4) as Profile
	var rise := rng.randf_range(1.8, 3.6)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.018
	noise.fractal_octaves = 2
	var tee_h := _profile_at(0.0, profile, rise)
	var cup_h := _profile_at(1.0, profile, rise)
	var fairway := HoleGenerator.fairway_width(data.par) * 0.5
	field.samples.resize(field.width * field.depth)
	for z in field.depth:
		for x in field.width:
			var wx := field.origin.x + float(x) * CELL
			var wz := field.origin.y + float(z) * CELL
			var point := Vector3(wx, 0.0, wz)
			var t := _along_t(data, point)
			var profile_h := _profile_at(t, profile, rise)
			var linear_h := lerpf(tee_h, cup_h, t)
			var off := HoleGenerator.distance_to_centerline(data, point)
			# The fairway still follows the hole's grade, but never walls up in
			# front of a drive the way the rough is allowed to.
			var fairway_w := 1.0 - clampf((off - 2.0) / maxf(4.0, fairway), 0.0, 1.0)
			var h := lerpf(profile_h, linear_h, fairway_w * 0.7)
			var hill := clampf((off - fairway) / HILL_BLEND, 0.0, 1.0)
			var noise_amp := lerpf(NOISE_ON_FAIRWAY, NOISE_OFF_FAIRWAY, hill)
			h += noise.get_noise_2d(wx, wz) * noise_amp
			# Shorter mounds only in the rough, so the fairway does not inherit them.
			h += noise.get_noise_2d(wx * 2.3, wz * 2.3) * NOISE_OFF_FAIRWAY * 0.55 * hill
			field.samples[z * field.width + x] = _flatten(h, point, data, tee_h, cup_h)
	field._sink_ponds(data)
	field._raise_jumps(data)
	field._pave_exit(data)
	field._pave_clubhouse(data)
	field._measure()
	return field


## Ponds are cut once the dry course exists, because each one needs a single flat
## water line taken from the ground it landed on. The bank around it is levelled
## to that line so the surface meets the land, and the floor then bowls away from
## the rim to full depth.
func _sink_ponds(data: HoleData) -> void:
	var ponds: Array[Dictionary] = []
	for patch in data.patches:
		if patch["type"] == Surface.Type.WATER:
			patch["water_y"] = _pond_level(patch)
			ponds.append(patch)
	if ponds.is_empty():
		return
	for z in depth:
		for x in width:
			var at := z * width + x
			var point := Vector3(
				origin.x + float(x) * cell, 0.0, origin.y + float(z) * cell
			)
			samples[at] = _pond_height(ponds, point, samples[at])


## The lowest dry ground the pond and its bank cover. Taking the low point means
## no shoreline is left sitting under the water line with the surface floating
## over it.
func _pond_level(patch: Dictionary) -> float:
	var size: Vector2 = patch["size"]
	var position: Vector3 = patch["position"]
	var reach := Vector2(size.x * 0.5 + WATER_BANK, size.y * 0.5 + WATER_BANK)
	# Walked at the heightmap's own resolution: a coarser sweep can miss the real
	# low sample and leave a scrap of bank under the water line.
	var steps := Vector2i(
		maxi(2, int(ceil(reach.x * 2.0 / cell))), maxi(2, int(ceil(reach.y * 2.0 / cell)))
	)
	var lowest := INF
	for iz in steps.y + 1:
		for ix in steps.x + 1:
			var local := Vector3(
				lerpf(-reach.x, reach.x, float(ix) / float(steps.x)), 0.0,
				lerpf(-reach.y, reach.y, float(iz) / float(steps.y))
			)
			var world := local.rotated(Vector3.UP, deg_to_rad(patch["yaw"]))
			lowest = minf(lowest, height_at(position.x + world.x, position.z + world.z))
	return 0.0 if lowest == INF else lowest


static func _pond_height(ponds: Array[Dictionary], point: Vector3, dry: float) -> float:
	var h := dry
	for patch in ponds:
		var edge := _edge_distance(point, patch)
		if edge < -WATER_BANK:
			continue
		var level: float = patch["water_y"]
		# Ground runs flat at the water line across the rim, then the floor falls
		# away from the inner edge of that shelf.
		var bank := clampf((edge + WATER_BANK) / (WATER_BANK * 0.6), 0.0, 1.0)
		var shore := lerpf(h, level, smoothstep(0.0, 1.0, bank))
		var sink := WATER_DEPTH * smoothstep(
			0.0, _bowl_blend(patch), maxf(edge - WATER_SHELF, 0.0)
		)
		h = minf(h, shore - sink)
	return h


## Carts floor-snap to this heightmap. A jump that is only a mesh on top of a
## pond bowl is something they drive under, so the ground itself has to rise.
func _raise_jumps(data: HoleData) -> void:
	for jump in data.jumps:
		_Ramp.raise_ground(self, jump)


## Flat cart lane from just past the green to the fence, so the drive off the
## hole is not a climb through the rough.
func _pave_exit(data: HoleData) -> void:
	var along := data.cup - data.tee
	along.y = 0.0
	if along.length_squared() < 0.0001:
		return
	along = along.normalized()
	var half := 16.0
	var deck := height_at(data.cup.x, data.cup.z)
	var end := Vector3(data.cup.x, 0.0, data.cup.z)
	var span := 0.0
	while data.bounds.has_point(Vector2(end.x, end.z)) and span < 240.0:
		end += along * cell
		span += cell
	var pad := maxf(half, span) + cell
	var x0 := maxi(0, int(floor((data.cup.x - pad - origin.x) / cell)))
	var z0 := maxi(0, int(floor((data.cup.z - pad - origin.y) / cell)))
	var x1 := mini(width - 1, int(ceil((data.cup.x + pad - origin.x) / cell)))
	var z1 := mini(depth - 1, int(ceil((data.cup.z + pad - origin.y) / cell)))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := origin.x + float(x) * cell
			var wz := origin.y + float(z) * cell
			var local := Vector3(wx, 0.0, wz) - Vector3(data.cup.x, 0.0, data.cup.z)
			var along_m := local.dot(along)
			if along_m < data.green_radius or along_m > span:
				continue
			if (local - along * along_m).length() > half:
				continue
			samples[z * width + x] = deck


## Shelf under the hall at tee height, so a mound in the rough cannot poke
## through the floor. Paved after ponds so a water cut cannot leave a bowl
## inside the rooms.
func _pave_clubhouse(data: HoleData) -> void:
	var forward := data.cup - data.tee
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	var house := ClubhouseBuild.at_exit(data.practice_tee, forward)
	var yaw := ClubhouseBuild.yaw_at_exit(forward)
	var deck := height_at(data.tee.x, data.tee.z)
	var blend := ClubhouseBuild.PAD_BLEND
	var hz := maxf(absf(ClubhouseBuild.PAD_Z_MIN), absf(ClubhouseBuild.PAD_Z_MAX))
	var reach := sqrt(ClubhouseBuild.PAD_HALF_X * ClubhouseBuild.PAD_HALF_X + hz * hz) + blend + cell
	var x0 := maxi(0, int(floor((house.x - reach - origin.x) / cell)))
	var z0 := maxi(0, int(floor((house.z - reach - origin.y) / cell)))
	var x1 := mini(width - 1, int(ceil((house.x + reach - origin.x) / cell)))
	var z1 := mini(depth - 1, int(ceil((house.z + reach - origin.y) / cell)))
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var wx := origin.x + float(x) * cell
			var wz := origin.y + float(z) * cell
			var edge := ClubhouseBuild.pad_edge(house, yaw, Vector3(wx, 0.0, wz))
			if edge < -blend:
				continue
			var t := 1.0 if edge >= 0.0 else 1.0 - (-edge / blend)
			samples[z * width + x] = lerpf(samples[z * width + x], deck, t)


## Metres the floor takes to reach full depth once past the shelf. Clamped so a
## small pond still has a floor instead of being all wall.
static func _bowl_blend(patch: Dictionary) -> float:
	var size: Vector2 = patch["size"]
	return clampf(minf(size.x, size.y) * 0.5 - WATER_SHELF, 1.5, WATER_SLOPE)


## Positive inside the patch, negative outside, measured to the nearest edge.
static func _edge_distance(point: Vector3, patch: Dictionary) -> float:
	var position: Vector3 = patch["position"]
	var size: Vector2 = patch["size"]
	var local := (point - position).rotated(Vector3.UP, -deg_to_rad(patch["yaw"]))
	if patch["round"]:
		return size.x * 0.5 - Vector2(local.x, local.z).length()
	return minf(size.x * 0.5 - absf(local.x), size.y * 0.5 - absf(local.z))


func _measure() -> void:
	min_height = INF
	max_height = -INF
	for h in samples:
		min_height = minf(min_height, h)
		max_height = maxf(max_height, h)


## 0 at the tee, 1 at the cup, measured along the hole rather than as the crow flies.
static func along_t(data: HoleData, point: Vector3) -> float:
	return _along_t(data, point)


static func profile_at(t: float, profile: Profile, rise: float) -> float:
	return _profile_at(t, profile, rise)


static func _profile_at(t: float, profile: Profile, rise: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	match profile:
		Profile.DOWNHILL:
			return (1.0 - u) * rise
		Profile.UPHILL:
			return u * rise
		Profile.VALLEY:
			return rise * absf(u - 0.5) * 2.0
		Profile.RIDGE:
			return rise * (1.0 - absf(u - 0.5) * 2.0)
		_:
			return rise * 0.5 * (1.0 + sin(u * PI))


static func _along_t(data: HoleData, point: Vector3) -> float:
	var total := data.length()
	if total <= 0.0:
		return 0.0
	var best := 0.0
	var closest := INF
	var travelled := 0.0
	for i in range(1, data.centerline.size()):
		var a: Vector3 = data.centerline[i - 1]
		var b: Vector3 = data.centerline[i]
		var on := Geometry3D.get_closest_point_to_segment(point, a, b)
		var d := point.distance_to(on)
		if d < closest:
			closest = d
			best = (travelled + a.distance_to(on)) / total
		travelled += a.distance_to(b)
	return clampf(best, 0.0, 1.0)


## Tee, practice green, green and fringe stay locally flat so a drive and a putt
## do not sit on a slope. The warm-up green is held at tee height, which keeps
## the whole tee complex one level shelf.
static func _flatten(
	h: float, point: Vector3, data: HoleData, tee_h: float, cup_h: float
) -> float:
	var tee_d := point.distance_to(data.tee)
	if tee_d < 10.0:
		h = tee_h
	else:
		h = lerpf(h, tee_h, 1.0 - clampf((tee_d - 10.0) / 8.0, 0.0, 1.0))
	var practice_d := point.distance_to(data.practice_center())
	if practice_d < PracticeGreen.FLAT:
		h = tee_h
	else:
		h = lerpf(h, tee_h, 1.0 - clampf((practice_d - PracticeGreen.FLAT) / 6.0, 0.0, 1.0))
	var green_d := point.distance_to(data.cup)
	var green_flat := data.green_radius + HoleGenerator.FRINGE_WIDTH
	if green_d < green_flat:
		h = cup_h
	else:
		h = lerpf(h, cup_h, 1.0 - clampf((green_d - green_flat) / 6.0, 0.0, 1.0))
	return h


func _sample(x: int, z: int) -> float:
	return samples[mini(depth - 1, maxi(0, z)) * width + mini(width - 1, maxi(0, x))]


func _hidden(x: int, z: int) -> bool:
	if hide.size.x <= 0.0 or hide.size.y <= 0.0:
		return false
	return hide.has_point(origin + Vector2(float(x) * cell, float(z) * cell))


func _visual_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := float(width - 1) * 0.5
	var hz := float(depth - 1) * 0.5
	for z in range(depth - 1):
		for x in range(width - 1):
			if _hidden(x, z) or _hidden(x + 1, z) or _hidden(x, z + 1) or _hidden(x + 1, z + 1):
				continue
			var a := _vert(x, z, hx, hz)
			var b := _vert(x + 1, z, hx, hz)
			var c := _vert(x, z + 1, hx, hz)
			var d := _vert(x + 1, z + 1, hx, hz)
			_tri(st, a, b, c)
			_tri(st, b, d, c)
	_skirt(st, hx, hz)
	st.generate_normals()
	st.index()
	return st.commit()


func _vert(x: int, z: int, hx: float, hz: float) -> Vector3:
	return Vector3((float(x) - hx) * cell, _sample(x, z), (float(z) - hz) * cell)


func _skirt(st: SurfaceTool, hx: float, hz: float) -> void:
	var floor_y := min_height - SKIRT
	for x in range(width - 1):
		_wall(st, _vert(x, 0, hx, hz), _vert(x + 1, 0, hx, hz), floor_y)
		_wall(st, _vert(x + 1, depth - 1, hx, hz), _vert(x, depth - 1, hx, hz), floor_y)
	for z in range(depth - 1):
		_wall(st, _vert(0, z + 1, hx, hz), _vert(0, z, hx, hz), floor_y)
		_wall(st, _vert(width - 1, z, hx, hz), _vert(width - 1, z + 1, hx, hz), floor_y)


func _wall(st: SurfaceTool, a: Vector3, b: Vector3, floor_y: float) -> void:
	var a2 := Vector3(a.x, floor_y, a.z)
	var b2 := Vector3(b.x, floor_y, b.z)
	# a->b is the edge walked so the skirt faces outward.
	_tri(st, a, b, b2)
	_tri(st, a, b2, a2)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
