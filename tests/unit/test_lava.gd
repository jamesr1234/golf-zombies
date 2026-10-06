extends GutTest
## Lava tiles send you back to the stand-back the builder set. A tile with no
## point is only scenery, and a respawn sitting on lava is refused.

const PLAYER := preload("res://scenes/players/player.tscn")
const LAVA := "res://scenes/course/props/lava.tscn"


func before_each() -> void:
	Sfx.clear_log()


func test_the_scene_is_a_placeable_prop() -> void:
	assert_true(ResourceLoader.exists(LAVA))
	assert_true(PieceCatalog.entries(PieceCatalog.PROPS).has(LAVA))
	var tile := CustomOverlay.instantiate(LAVA) as Lava
	add_child_autofree(tile)
	assert_not_null(tile)
	assert_true(tile.is_in_group("lava"))
	assert_eq(tile.collision_layer, Layers.LAVA)
	assert_eq(tile.collision_mask, 0)
	assert_eq(Layers.BALL_MASK & Layers.LAVA, Layers.LAVA)
	assert_eq(Layers.PLAYER_MASK & Layers.LAVA, 0, "the player falls in, the ball does not")
	assert_not_null(tile.get_node_or_null("Surface"))
	var kill := tile.get_node_or_null("Kill") as Area3D
	assert_not_null(kill)
	assert_eq(kill.collision_mask, Layers.PLAYER | Layers.VEHICLE | Layers.MECH)
	var hull := GridSnap.local_aabb(tile)
	var rim := Surface.DRAW_HEIGHT[Surface.Type.FAIRWAY]
	assert_gt(hull.size.x, 1.2)
	assert_gt(hull.size.z, 1.2)
	assert_gt(hull.size.y, 0.3, "the well still has visible layers")
	assert_gt(tile.get_node("Surface").get_child_count(), 2, "stacked terraces")
	assert_lt(hull.position.y + hull.size.y, rim + 0.06, "the top sits flush with the turf")
	assert_gt(hull.position.y + hull.size.y, rim - 0.04, "and is not buried under it")


func test_an_unarmed_tile_does_not_move_anyone() -> void:
	var tile := _tile(Vector3.INF)
	var player := _player_at(Vector3.ZERO)
	assert_false(tile.try_dunk(player))
	assert_almost_eq(player.global_position.distance_to(Vector3.ZERO), 0.0, 0.05)
	assert_ne(Sfx.last_cue, "hazard")


func test_falling_in_a_merged_pool_stands_you_on_the_respawn() -> void:
	var back := Vector3(5.4, 0.0, -8.1)
	var pool := Lava.from_cells([Vector3.ZERO, Vector3(GridSnap.CELL, 0.0, 0.0)], back)
	add_child_autofree(pool)
	var player := _player_at(Vector3(GridSnap.CELL, 0.0, 0.0))
	assert_true(pool.try_dunk(player))
	assert_true(player.is_burning())
	_finish_burn(player)
	assert_almost_eq(player.global_position.distance_to(back), 0.0, 0.05)


func test_falling_in_shows_the_body_then_stands_you_back() -> void:
	var back := Vector3(5.4, 0.0, -8.1)
	var tile := _tile(back)
	var player := _player_at(Vector3.ZERO)
	assert_true(tile.try_dunk(player))
	assert_true(player.is_burning())
	assert_true(player.body.is_limp(), "the body has to flop while the lens watches")
	player.anim.tick(player, 0.016)
	assert_true(player.body.is_limp(), "an alive burn must not snap the ragdoll off")
	assert_gt(player.global_position.distance_to(back), 1.0, "the dunk is a death, not a blink")
	var view := player.get_view_transform()
	assert_gt(view.origin.distance_to(player.global_position), 2.0, "the lens pulls off the body")
	assert_eq(Sfx.last_cue, "hazard")
	_finish_burn(player)
	assert_false(player.is_burning())
	assert_almost_eq(player.global_position.distance_to(back), 0.0, 0.05)


func test_a_zipline_over_lava_does_not_dunk() -> void:
	var tile := _tile(Vector3(5.4, 0.0, -8.1))
	var player := _player_at(Vector3(0.0, 2.4, 0.0))
	player.state = Player.State.ZIPLINING
	assert_false(tile.try_dunk(player), "the cable is over the pool, not in it")
	assert_false(player.is_burning())


func test_a_shot_skips_on_the_lava() -> void:
	var back := Vector3(-2.7, 0.0, 4.05)
	var tile := _tile(back)
	await wait_physics_frames(2)
	var ball := GolfBall.new()
	var hull := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = GolfBall.RADIUS
	hull.shape = sphere
	ball.add_child(hull)
	add_child_autofree(ball)
	assert_eq(ball.collision_mask & Layers.LAVA, Layers.LAVA)
	ball.place_at(Vector3(0.0, 0.8, 0.0))
	ball.linear_velocity = Vector3(2.4, -1.2, 0.0)
	await wait_physics_frames(30)
	assert_false(tile.try_dunk(ball), "shots skip, they are not sent back")
	assert_gt(ball.global_position.y, 0.12)
	assert_gt(ball.last_safe_position.distance_to(back), 1.0)


func test_a_pool_outline_follows_the_tiles() -> void:
	var marks := CreatorMarks.create()
	add_child_autofree(marks)
	marks.begin()
	marks.footprint([
		Vector3.ZERO,
		Vector3(GridSnap.CELL, 0.0, 0.0),
		Vector3(0.0, 0.0, GridSnap.CELL),
	], Palette.LAVA)
	marks.finish()
	assert_gt(marks.get_aabb().size.length(), GridSnap.CELL)


func test_a_drag_lists_every_cell_between_the_corners() -> void:
	var cells := Lava.cells_between(Vector3.ZERO, Vector3(GridSnap.CELL, 0.0, GridSnap.CELL))
	assert_eq(cells.size(), 4)
	assert_true(cells.has(Vector3.ZERO))
	assert_true(cells.has(Vector3(GridSnap.CELL, 0.0, GridSnap.CELL)))
	assert_eq(Lava.cells_between(Vector3.ZERO, Vector3.ZERO).size(), 1)


func test_a_tile_covers_its_own_cell_and_nothing_beside_it() -> void:
	var at := Vector3(0.0, 0.0, -20.0)
	assert_true(Lava.tile_covers(at, at))
	assert_true(Lava.tile_covers(at, at + Vector3(0.4, 2.0, -0.4)))
	assert_false(Lava.tile_covers(at, at + Vector3(GridSnap.CELL, 0.0, 0.0)))
	assert_true(Lava.covers_stand(at, at + Vector3(0.0, 0.4, 0.0)))
	assert_false(
		Lava.covers_stand(at, at + Vector3.UP * Lava.DETECT_HEIGHT),
		"a perch above the pool is not a loop"
	)


func test_a_hole_with_unfinished_lava_is_open() -> void:
	var hole := CustomHole.create("Open Pit")
	hole.add_placement(LAVA, Vector3(0.0, 0.0, -20.0))
	assert_true(hole.has_open_lava())
	hole.placements[0][CustomHole.RESPAWN] = Vector3(2.7, 0.0, -16.2)
	assert_false(hole.has_open_lava())
	assert_true(CustomHole.has_respawn(hole.placements[0]))


func test_the_overlay_hands_the_respawn_to_the_tile() -> void:
	var hole := CustomHole.create("Armed")
	hole.add_placement(LAVA, Vector3(0.0, 0.0, -20.0))
	hole.placements[0][CustomHole.RESPAWN] = Vector3(5.4, 0.0, -12.15)
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.get_child_count(), 1)
	var tile := overlay.get_child(0) as Lava
	assert_not_null(tile)
	assert_almost_eq(tile.respawn.distance_to(Vector3(5.4, 0.0, -12.15)), 0.0, 0.01)


func test_a_pool_is_one_node_on_the_hole() -> void:
	var hole := CustomHole.create("Merged")
	var back := Vector3(5.4, 0.0, -12.15)
	var cells := [
		Vector3(0.0, 0.0, -20.0),
		Vector3(GridSnap.CELL, 0.0, -20.0),
		Vector3(0.0, 0.0, -20.0 - GridSnap.CELL),
		Vector3(GridSnap.CELL, 0.0, -20.0 - GridSnap.CELL),
	]
	for cell in cells:
		hole.add_placement(LAVA, cell)
		hole.placements[hole.placements.size() - 1][CustomHole.RESPAWN] = back
	var overlay := CustomOverlay.build(hole)
	add_child_autofree(overlay)
	assert_eq(overlay.get_child_count(), 1, "one confirmed pool is one light and one area")
	var pool := overlay.get_child(0) as Lava
	assert_not_null(pool)
	assert_almost_eq(pool.respawn.distance_to(back), 0.0, 0.01)
	assert_not_null(pool.get_node_or_null("Surface"))
	assert_eq(pool.find_children("*", "OmniLight3D", true, false).size(), 1)
	assert_eq(pool.get_node("Kill").get_child_count(), 4)
	assert_not_null(pool.get_node_or_null("Bubbles"))


func test_two_pools_stay_two_nodes() -> void:
	var hole := CustomHole.create("Split")
	hole.add_placement(LAVA, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(LAVA, Vector3(0.0, 0.0, -24.0))
	hole.placements[0][CustomHole.RESPAWN] = Vector3(5.4, 0.0, -12.15)
	hole.placements[1][CustomHole.RESPAWN] = Vector3(-5.4, 0.0, -12.15)
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.get_child_count(), 2)


func test_the_fairway_opens_over_lava_so_the_layers_show() -> void:
	var hole := CustomHole.create("Well")
	var line := hole.centerline()
	var at := GridSnap.to_grid(line[0].lerp(line[1], 0.5))
	at.y = 0.0
	hole.add_placement(LAVA, at)
	assert_eq(CustomHole.lava_spots(hole.placements).size(), 1)
	var data := CustomLayout.build(hole)
	var patch := {}
	for row in data.patches:
		if row["type"] == Surface.Type.FAIRWAY:
			patch = row
			break
	assert_false(patch.is_empty())
	var spots := CustomHole.lava_spots(hole.placements)
	var fine := SurfacePatch.create(patch, data.height, [Vector3(9999.0, 0.0, 9999.0)])
	var opened := SurfacePatch.create(patch, data.height, spots)
	add_child_autofree(fine)
	add_child_autofree(opened)
	assert_true(SurfacePatch.cut_covers(at, spots))
	assert_gt(
		_face_count(fine), _face_count(opened),
		"the painted lie leaves a hole so the well is visible"
	)


func test_unfinished_lava_is_scenery_on_the_played_hole() -> void:
	var hole := CustomHole.create("Draft")
	hole.add_placement(LAVA, Vector3(0.0, 0.0, -20.0))
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	var tile := overlay.get_child(0) as Lava
	assert_not_null(tile)
	assert_false(tile.respawn.is_finite())


func _tile(respawn: Vector3) -> Lava:
	var tile := CustomOverlay.instantiate(LAVA) as Lava
	add_child_autofree(tile)
	tile.respawn = respawn
	return tile


func _finish_burn(player: Player) -> void:
	player.look.lava_burn_left = 0.01
	player.look.tick_lava_burn(player, 0.02)


func _player_at(at: Vector3) -> Player:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.global_position = at
	return player


func _face_count(node: SurfacePatch) -> int:
	for child in node.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			return mesh_node.mesh.get_faces().size()
	return 0
