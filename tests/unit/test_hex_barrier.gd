extends GutTest
## Hex fort: six grey faces, three hits to open one side, placement camera.

const HexBarrierScript := preload("res://scripts/player/hex_barrier.gd")
const FaceScript := preload("res://scripts/player/hex_barrier_face.gd")
const PLAYER_SCENE := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func before_each() -> void:
	var fx := Node3D.new()
	fx.add_to_group("fx_root")
	add_child_autofree(fx)


func after_each() -> void:
	for child in get_children():
		if child.name == "HexBarrier":
			child.queue_free()


func test_a_placed_hex_is_a_lit_outline() -> void:
	var hex = HexBarrierScript.spawn(self, Vector3.ZERO, 0.0)
	assert_eq(hex.face_count(), HexBarrierScript.SIDE_COUNT)
	var bars := 0
	for child in hex.find_children("*", "MeshInstance3D", true, false):
		var box := (child as MeshInstance3D).mesh as BoxMesh
		if box == null:
			continue
		var size := box.size
		assert_true(
			size.x <= FaceScript.FRAME * 1.5 or size.y <= FaceScript.FRAME * 1.5,
			"outline is built from bars"
		)
		var mat := (child as MeshInstance3D).material_override as StandardMaterial3D
		assert_not_null(mat)
		assert_eq(mat.albedo_color, Palette.CYAN)
		assert_gt(mat.emission_energy_multiplier, Palette.GLOW_MEDIUM)
		bars += 1
	assert_eq(bars, HexBarrierScript.SIDE_COUNT * 4)
	assert_eq(hex.find_children("*", "OmniLight3D", true, false).size(), HexBarrierScript.SIDE_COUNT)
	var face = hex.face_at(0)
	assert_eq(face.collision_layer, Layers.FORT)
	assert_eq(face.collision_mask, 0)
	assert_false(face.pane_lit())


func test_the_attacked_side_is_the_one_facing_the_hit() -> void:
	assert_eq(HexBarrierScript.face_index_from_direction(Vector3(0.0, 0.0, 1.0)), 0)
	assert_eq(HexBarrierScript.face_index_from_direction(Vector3(1.0, 0.0, 0.0)), 1)
	assert_eq(HexBarrierScript.face_index_from_direction(Vector3(0.0, 0.0, -1.0)), 3)


func test_three_hits_open_only_that_face() -> void:
	var hex = HexBarrierScript.spawn(self, Vector3.ZERO, 0.0)
	var face = hex.face_at(0)
	var other = hex.face_at(2)
	assert_false(face.take_hit(face.global_position))
	assert_false(face.take_hit(face.global_position))
	assert_eq(hex.hits_left(0), 1)
	assert_eq(hex.hits_left(2), HexBarrierScript.HITS_TO_BREAK)
	assert_true(face.take_hit(face.global_position))
	assert_true(hex.is_face_open(0))
	assert_false(hex.is_face_open(2))
	assert_eq(hex.hits_left(2), HexBarrierScript.HITS_TO_BREAK)
	assert_false(face.visible)
	assert_true(other.visible)


func test_a_broken_face_ignores_extra_hits() -> void:
	var hex = HexBarrierScript.spawn(self, Vector3.ZERO, 0.0)
	var face = hex.face_at(1)
	for _i in HexBarrierScript.HITS_TO_BREAK:
		face.take_hit(face.global_position)
	assert_true(hex.is_face_open(1))
	assert_false(face.take_hit(face.global_position))
	assert_eq(hex.hits_left(1), 0)


func test_a_hit_lights_only_the_struck_face_grid() -> void:
	var hex = HexBarrierScript.spawn(self, Vector3.ZERO, 0.0)
	var struck = hex.face_at(0)
	var other = hex.face_at(2)
	assert_false(struck.pane_lit())
	assert_false(other.pane_lit())
	struck.take_hit(struck.global_position)
	assert_true(struck.pane_lit())
	assert_false(other.pane_lit())
	assert_false(hex.is_face_open(0))


func test_breaking_a_face_spawns_a_small_blast() -> void:
	var hex = HexBarrierScript.spawn(self, Vector3.ZERO, 0.0)
	var face = hex.face_at(0)
	var fx := get_tree().get_first_node_in_group("fx_root")
	var before: int = fx.get_child_count()
	for _i in HexBarrierScript.HITS_TO_BREAK:
		face.take_hit(face.global_position)
	assert_gt(fx.get_child_count(), before, "blast leaves a flash under fx_root")


func test_placement_camera_pulls_well_behind_the_robot() -> void:
	var origin := Vector3(0.0, 0.0, 0.0)
	var target := Vector3(0.0, 0.0, -6.0)
	var view := HexBarrierScript.view_transform(origin, 0.0, target)
	assert_gt(view.origin.z, origin.z, "facing -Z, the camera sits on +Z")
	assert_gt(view.origin.y, origin.y + 6.0, "high enough to read the hex")
	assert_gt(view.origin.distance_to(origin), 10.0, "zoomed out past the shield cam")


func test_swapping_onto_a_barrier_keeps_the_gun_in_hand() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.stand_at(Vector3.ZERO, 0.0)
	var score := GameState.new(PackedInt32Array([4]))
	score.add_barrier_charges(2)
	player.flow = _Flow.new(score)
	player.weapon.index = 0
	var fps := player.get_view_transform()
	player._swap_gear()
	assert_true(player.is_placing())
	assert_eq(player.weapon.index, 0, "gear is a separate slot")
	var tps := player.get_view_transform()
	assert_gt(fps.origin.distance_to(tps.origin), 8.0, "the lens leaves the head")
	assert_eq(player.get_view_fov(), HexBarrierScript.CAM_FOV)
	player._animate(STEP)
	assert_false(player.raygun.visible)
	player._cancel_place()
	assert_false(player.is_placing())
	assert_eq(player.weapon.index, 0)


func test_placing_walks_and_cancel_returns_to_first_person() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child_autofree(player)
	player.input = CpuInput.new(player.input_prefix, false)
	var score := GameState.new(PackedInt32Array([4]))
	score.add_barrier_charges(1)
	player.flow = _Flow.new(score)
	player.state = Player.State.PLACING
	var pad := player.input as CpuInput
	pad.begin_frame()
	pad.move = Vector2(0.0, -1.0)
	player._move(STEP)
	assert_lt(player.velocity.z, -0.1, "placement is not rooted")
	player._cancel_place()
	assert_false(player.is_placing())
	assert_eq(player.state, Player.State.NORMAL)


class _Flow extends RefCounted:
	var score: GameState
	var hole = null

	func _init(p_score: GameState) -> void:
		score = p_score

	func hole_node() -> Node3D:
		return null
