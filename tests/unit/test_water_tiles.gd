extends GutTest
## Custom water: ponds are tiles locked with one depth, and a tunnel is a line
## dug between two of them. The dig never touches the ground, so the fairway
## over it stays whole and the run costs a point per corner.

const WATER := "res://scenes/course/props/water.tscn"
const LAVA := "res://scenes/course/props/lava.tscn"
const CELL := GridSnap.CELL


func test_the_scene_is_a_placeable_prop() -> void:
	assert_true(ResourceLoader.exists(WATER))
	assert_true(PieceCatalog.entries(PieceCatalog.PROPS).has(WATER))
	var tile := CustomOverlay.instantiate(WATER) as WaterTile
	add_child_autofree(tile)
	assert_not_null(tile)
	assert_true(tile.is_in_group("water"))
	assert_not_null(tile.get_node_or_null("Surface"))


func test_the_catalog_never_offers_a_tunnel() -> void:
	for path in PieceCatalog.entries(PieceCatalog.PROPS):
		assert_false(CustomHole.is_tunnel(path), path)


func test_cells_between_fills_the_rectangle() -> void:
	var cells := WaterTile.cells_between(Vector3.ZERO, Vector3(CELL, 0.0, CELL))
	assert_eq(cells.size(), 4)


func test_unfinished_tiles_are_one_pool_and_depth_splits_them() -> void:
	var hole := CustomHole.create("Ponds")
	hole.add_placement(WATER, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(WATER, Vector3(CELL, 0.0, -20.0))
	assert_true(hole.has_open_water())
	assert_eq(CustomHole.water_pool(hole.placements, 0), [0, 1])
	_finish(hole.placements[0], Vector3(0.0, 0.0, -20.0))
	_finish(hole.placements[1], Vector3(0.0, 0.0, -20.0))
	assert_false(hole.has_open_water())
	hole.add_placement(WATER, Vector3(0.0, 0.0, -28.0))
	_finish(hole.placements[2], Vector3(0.0, 0.0, -28.0))
	assert_eq(CustomHole.water_pool(hole.placements, 0), [0, 1])
	assert_eq(CustomHole.water_pool(hole.placements, 2), [2])
	assert_eq(CustomHole.water_groups(hole.placements).size(), 2)


func test_a_pond_is_a_swim_and_dry_rock_is_not() -> void:
	var listed: Array[Dictionary] = [_tile(Vector3.ZERO)]
	assert_almost_eq(WaterTile.depth_at(listed, Vector3.ZERO), 3.0, 0.001)
	assert_almost_eq(WaterTile.depth_at(listed, Vector3(CELL * 2.0, -2.0, 0.0)), -1.0, 0.001)


func test_water_refuses_to_sit_on_lava() -> void:
	var listed: Array = [
		{CustomHole.PATH: LAVA, CustomHole.POSITION: Vector3.ZERO},
	]
	assert_true(Lava.covers_any(listed, Vector3.ZERO))
	assert_false(WaterTile.covers_any(listed, Vector3.ZERO))


func test_a_bore_is_a_swim_only_inside_the_dug_line() -> void:
	var listed: Array = [_tunnel([Vector3.ZERO, Vector3(0.0, 0.0, -20.0)], 2.6)]
	assert_almost_eq(WaterTunnel.depth_at(listed, Vector3(0.0, 0.0, -10.0)), 2.6, 0.001)
	assert_gt(WaterTunnel.depth_at(listed, Vector3(0.0, 0.0, -10.0)), PlayerSwim.WADE_DEPTH)
	assert_almost_eq(WaterTunnel.depth_at(listed, Vector3(6.0, 0.0, -10.0)), -1.0, 0.001)
	assert_almost_eq(WaterTunnel.depth_at(listed, Vector3(0.0, 0.0, 9.0)), -1.0, 0.001)


## Corners are the point of the polyline: the swim follows the turn without a
## record per metre of it.
func test_a_dig_turns_a_corner_and_stays_one_placement() -> void:
	var entry := _tunnel(
		[Vector3.ZERO, Vector3(0.0, 0.0, -20.0), Vector3(14.0, 0.0, -20.0)], 2.6
	)
	var listed: Array = [entry]
	assert_eq(WaterTunnel.nodes_of(entry).size(), 3)
	assert_gt(WaterTunnel.depth_at(listed, Vector3(7.0, 0.0, -20.0)), 0.0, "past the turn")
	assert_almost_eq(WaterTunnel.depth_at(listed, Vector3(7.0, 0.0, -6.0)), -1.0, 0.001)


func test_a_swimmer_is_pulled_back_inside_the_bore() -> void:
	var listed: Array = [_tunnel([Vector3.ZERO, Vector3(0.0, 0.0, -20.0)], 2.6)]
	var held := WaterTunnel.hold(listed, Vector3(1.6, 0.0, -10.0), 0.45)
	assert_almost_eq(held.z, -10.0, 0.001, "along the run is free")
	assert_lt(held.x, 0.9, "across it you are held off the wall")
	var inside := Vector3(0.2, 0.1, -10.0)
	assert_almost_eq(WaterTunnel.hold(listed, inside, 0.45).x, inside.x, 0.001)
	var away := Vector3(40.0, 0.0, -10.0)
	assert_almost_eq(WaterTunnel.hold(listed, away, 0.45).x, away.x, 0.001, "open water is free")
	var out := Vector3(0.0, 0.0, 1.6)
	var let_go := WaterTunnel.hold(listed, out, 0.35)
	assert_almost_eq(let_go.z, out.z, 0.001, "a mouth is open, not a wall")


func test_a_wider_bore_is_a_wider_swim() -> void:
	var narrow: Array = [_tunnel([Vector3.ZERO, Vector3(0.0, 0.0, -20.0)], WaterTunnel.BORE_MIN)]
	var wide: Array = [_tunnel([Vector3.ZERO, Vector3(0.0, 0.0, -20.0)], WaterTunnel.BORE_MAX)]
	var off := Vector3(2.0, 0.0, -10.0)
	assert_almost_eq(WaterTunnel.depth_at(narrow, off), -1.0, 0.001)
	assert_gt(WaterTunnel.depth_at(wide, off), 0.0)
	assert_almost_eq(WaterTunnel.clamp_bore(99.0), WaterTunnel.BORE_MAX, 0.001)
	assert_almost_eq(WaterTunnel.clamp_bore(0.1), WaterTunnel.BORE_MIN, 0.001)


func test_a_tunnel_leaves_the_ground_over_it_alone() -> void:
	var hole := CustomHole.create("Buried")
	hole.add_placement(WATER, Vector3(0.0, 0.0, -20.0))
	_finish(hole.placements[0], Vector3(0.0, 0.0, -20.0))
	var mid := Vector3(0.0, -2.0, -26.0)
	hole.add_placement(CustomHole.TUNNEL, Vector3(0.0, -2.0, -20.0))
	hole.placements[1][CustomHole.NODES] = [Vector3(0.0, -2.0, -20.0), mid]
	hole.placements[1][CustomHole.BORE] = 2.6
	hole.placements[1][CustomHole.DONE] = true
	var data := CustomLayout.build(hole)
	assert_lt(data.height.height_at(0.0, -20.0), HeightField.DECK - 1.0, "the pond is a swim")
	assert_almost_eq(
		data.height.height_at(mid.x, mid.z), HeightField.DECK, 0.35,
		"the fairway over the run is untouched"
	)
	assert_gt(data.water_depth_at(mid), PlayerSwim.WADE_DEPTH, "but the bore is water")
	assert_almost_eq(
		data.water_depth_at(Vector3(0.0, HeightField.DECK, -26.0)), 0.0, 0.001,
		"and walking over the top is dry"
	)
	assert_gt(data.height.mouth_banks(), 0, "the lake wall is open at the mouth")


func test_an_unfinished_dig_is_a_dead_end() -> void:
	var hole := CustomHole.create("Dead End")
	hole.add_placement(CustomHole.TUNNEL, Vector3(0.0, -2.0, -20.0))
	hole.placements[0][CustomHole.NODES] = [Vector3(0.0, -2.0, -20.0), Vector3(0.0, -2.0, -26.0)]
	assert_true(hole.has_open_tunnel())
	hole.placements[0][CustomHole.DONE] = true
	assert_false(hole.has_open_tunnel())


func test_a_tunnel_survives_a_trip_through_json() -> void:
	var hole := CustomHole.create("Saved Dig")
	var line: Array[Vector3] = [
		Vector3(0.0, -2.0, -20.0), Vector3(0.0, -2.0, -30.0), Vector3(8.0, -3.0, -30.0)
	]
	hole.add_placement(CustomHole.TUNNEL, line[0])
	hole.placements[0][CustomHole.NODES] = line
	hole.placements[0][CustomHole.BORE] = 3.2
	hole.placements[0][CustomHole.DONE] = true
	var back := CustomHole.from_dict(JSON.parse_string(JSON.stringify(hole.to_dict())))
	var entry: Dictionary = back.placements[0]
	assert_true(CustomHole.is_tunnel(String(entry[CustomHole.PATH])))
	assert_eq(WaterTunnel.nodes_of(entry).size(), 3)
	assert_almost_eq((WaterTunnel.nodes_of(entry)[2] as Vector3).x, 8.0, 0.001)
	assert_almost_eq(WaterTunnel.bore_of(entry), 3.2, 0.001)
	assert_true(WaterTunnel.is_done(entry))


## Inside a tunnel you are looking at the ground it was cut through, so the
## walls are opaque rock wound to face the swimmer. A mouth is framed by a
## collar square to the run, which is what makes it read as a hole in the bank.
func test_the_bore_is_walled_in_ground_you_see_from_inside() -> void:
	var tunnel := WaterTunnel.create(
		_tunnel([Vector3(0.0, -4.0, 0.0), Vector3(0.0, -4.0, -20.0)], 2.6)
	)
	add_child_autofree(tunnel)
	var mesh := tunnel.get_node("Bore") as MeshInstance3D
	var mat := mesh.material_override as ShaderMaterial
	assert_eq(mat.shader, MeshFactory.GRID_SHADER, "the walls are ground, not more water")
	var arrays := (mesh.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var walls := 0
	var facing := 0
	var collars := 0
	for i in verts.size():
		# The run lies down local -Z from the origin, so a wall normal has no
		# length along Z and a collar normal is almost all Z.
		if absf(normals[i].z) > 0.5:
			collars += 1
			continue
		walls += 1
		var toward_axis := Vector3(-verts[i].x, -verts[i].y, 0.0).normalized()
		if normals[i].dot(toward_axis) > 0.3:
			facing += 1
	assert_gt(walls, 0)
	assert_gt(collars, 0, "both mouths are framed")
	assert_eq(facing, walls, "every wall faces in, so the rock hides it from outside")


## The dug ends sit in the bank. The visible hole has to stand in the pond, or
## the heightmap wall hides it and you swim around guessing.
func test_each_mouth_sits_in_the_pond() -> void:
	var tunnel := WaterTunnel.create(
		_tunnel([Vector3.ZERO, Vector3(0.0, 0.0, -20.0)], 2.6)
	)
	add_child_autofree(tunnel)
	var mesh := tunnel.get_node("Bore") as MeshInstance3D
	var verts: PackedVector3Array = (mesh.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var into_start := 0
	var into_end := 0
	for at in verts:
		if at.z > WaterTunnel.LIP * 0.5:
			into_start += 1
		if at.z < -20.0 - WaterTunnel.LIP * 0.5:
			into_end += 1
	assert_gt(into_start, 0, "the opening is in the water you start from")
	assert_gt(into_end, 0, "and in the water you finish in")


func test_a_planted_pond_is_still_found_in_world_space() -> void:
	var hole := CustomHole.create("Planted Pond")
	hole.add_placement(WATER, Vector3(0.0, 0.0, -20.0))
	_finish(hole.placements[0], Vector3(0.0, 0.0, -20.0))
	var data := CustomLayout.build(hole)
	var node := Node3D.new()
	add_child_autofree(node)
	data.face_arrival(node, Vector3.RIGHT, Vector3(40.0, 0.0, 80.0))
	var local := Vector3(0.0, 0.0, -20.0)
	var world := data.from_custom(local)
	assert_gt(data.water_depth_at(world), PlayerSwim.WADE_DEPTH)
	assert_true(data.in_open_water(world))
	assert_gt(world.distance_to(local), 1.0, "the hole has to have moved")
	assert_almost_eq(data.water_depth_at(local), 0.0, 0.001, "old hole space is dry ground now")


func test_the_built_tunnel_is_one_mesh_and_no_collider() -> void:
	var tunnel := WaterTunnel.create(
		_tunnel([Vector3(0.0, -2.0, 0.0), Vector3(0.0, -2.0, -20.0)], 2.6)
	)
	add_child_autofree(tunnel)
	assert_eq(tunnel.get_child_count(), 1, "a run draws as a single mesh")
	assert_not_null(tunnel.get_node_or_null("Bore"))
	assert_eq(tunnel.find_children("*", "CollisionShape3D", true, false).size(), 0)
	assert_eq(tunnel.find_children("*", "StaticBody3D", true, false).size(), 0)


func _tile(at: Vector3) -> Dictionary:
	return {
		CustomHole.PATH: WATER,
		CustomHole.POSITION: at,
		CustomHole.DEPTH: 3.0,
		CustomHole.POOL: Vector3.ZERO,
		CustomHole.SURFACE: 0.0,
	}


func _tunnel(line: Array, bore: float) -> Dictionary:
	return {
		CustomHole.PATH: CustomHole.TUNNEL,
		CustomHole.POSITION: line[0],
		CustomHole.NODES: line,
		CustomHole.BORE: bore,
		CustomHole.DONE: true,
	}


func _finish(entry: Dictionary, pool: Vector3) -> void:
	entry[CustomHole.DEPTH] = 3.0
	entry[CustomHole.POOL] = pool
	entry[CustomHole.SURFACE] = 0.0
