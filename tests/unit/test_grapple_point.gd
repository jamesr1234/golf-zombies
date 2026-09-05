extends GutTest
## A post with a bullseye. Fire the claw at the face and ride the rope.

const PLAYER := preload("res://scenes/players/player.tscn")
const SCENE := preload("res://scenes/course/props/grapple_point.tscn")
const _Point := preload("res://scripts/course/grapple_point.gd")


func test_the_scene_is_a_placeable_prop() -> void:
	assert_true(ResourceLoader.exists("res://scenes/course/props/grapple_point.tscn"))
	var point = SCENE.instantiate()
	add_child_autofree(point)
	assert_eq(point.collision_layer, Layers.PROP)
	assert_true(point.is_in_group("grapple_points"))
	assert_not_null(point.get_node_or_null("Target"))


func test_the_target_sits_on_the_front_of_the_post() -> void:
	var point = _Point.create()
	add_child_autofree(point)
	var face := point.get_node("Target") as Node3D
	assert_gt(face.position.y, 2.5, "high enough to swing from")
	assert_gt(face.position.z, 0.0, "the bullseye faces +Z")
	var aim: Vector3 = point.aim_at()
	assert_almost_eq(aim.y, face.global_position.y, 0.001)
	assert_gt(aim.z, point.global_position.z)


func test_the_hook_treats_it_as_a_hitch() -> void:
	var point = _Point.create()
	var bolt := Node3D.new()
	point.add_child(bolt)
	assert_eq(Grappler.hitchable(point), point)
	assert_eq(Grappler.hitchable(bolt), point)
	point.free()


func test_you_can_latch_the_rope_on_the_target() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var point = _Point.create(Vector3(0.0, 0.0, -8.0))
	add_child_autofree(point)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 4.0)
	assert_true(player.begin_grapple(point, point.aim_at()))
	assert_true(player.is_grappling())
	assert_eq(player.grappler.target, point)
	assert_eq(Sfx.last_cue, "grapple_latch")


func test_nearest_finds_a_target_in_range() -> void:
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	var point = _Point.create(Vector3(0.0, 0.0, -6.0))
	add_child_autofree(point)
	dummy.global_position = Vector3(0.0, 1.0, 0.0)
	assert_eq(_Point.nearest(dummy), point)
	dummy.global_position.z = Grappler.RANGE + 8.0
	assert_null(_Point.nearest(dummy))
	assert_eq(_Point.FIND, Grappler.RANGE)


func test_the_pad_is_on_the_deck_under_the_target() -> void:
	var point = _Point.create()
	add_child_autofree(point)
	var pad: Vector3 = point.land_at()
	var aim: Vector3 = point.aim_at()
	assert_lt(pad.y, aim.y - 2.0, "the stand is the deck, not the bullseye")
	assert_almost_eq(pad.y, point.global_position.y, 0.15)
	assert_gt(pad.z, point.global_position.z, "in front of the post")


func test_the_rope_reels_you_up_to_the_target() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var point = _Point.create(Vector3(0.0, 0.0, -10.0))
	add_child_autofree(point)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 4.0)
	assert_true(player.begin_grapple(point, point.aim_at()))
	assert_true(player.grappler.is_point())
	var hanging := player.get_prompt()
	assert_true(hanging.contains("Reel") or hanging.contains("let go"), hanging)
	var start := player.global_position
	var start_slack := player.grappler.slack
	var pad: Vector3 = point.land_at()
	assert_gt(start_slack, 8.0)
	for _frame in 8:
		player._physics_process(1.0 / 60.0)
	assert_true(player.is_grappling())
	assert_lt(player.grappler.slack, start_slack - 4.0, "the cable shortens on its own")
	assert_lt(
		player.global_position.distance_to(pad), start.distance_to(pad) - 4.0,
		"the yank has to close the gap fast"
	)
	for _frame in 40:
		player._physics_process(1.0 / 60.0)
		if not player.is_grappling():
			break
	assert_false(player.is_grappling(), "arrival drops you on your feet")
	assert_lt(player.global_position.distance_to(pad), 0.2, "you finish on the deck")
	assert_almost_eq(player.global_position.y, pad.y, 0.15)


func test_the_prompt_names_the_target() -> void:
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	var point = _Point.create(Vector3(0.0, 0.0, -5.0))
	add_child_autofree(point)
	await wait_physics_frames(1)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	var prompt := player.get_prompt()
	assert_true(prompt.contains("grapple"), prompt)
	assert_true(prompt.contains("target"), prompt)
