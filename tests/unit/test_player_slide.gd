extends GutTest
## Sprint + R3 (Shift + Z) drops the hull for a low burst, then stands back up
## once the ceiling is clear.

const PLAYER := preload("res://scenes/players/player.tscn")
const STEP := 1.0 / 60.0


func test_sprint_and_slide_drops_the_hull_and_boosts() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	assert_true(player.is_sliding())
	assert_almost_eq(_hull_height(player), PlayerSlide.SLIDE_HEIGHT, 0.001)
	assert_almost_eq(_shape(player).position.y, PlayerSlide.SLIDE_SHAPE_Y, 0.001)
	var flat := Vector2(player.velocity.x, player.velocity.z)
	assert_gt(flat.length(), PlayerMotion.SPRINT_SPEED)


func test_slide_without_sprint_does_nothing() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.tap("slide")
	player._move(STEP)
	assert_false(player.is_sliding())
	assert_almost_eq(_hull_height(player), PlayerSlide.STAND_HEIGHT, 0.001)


func test_the_hull_stands_back_up_when_the_ceiling_is_clear() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	assert_true(player.is_sliding())
	pad.begin_frame()
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	for _frame in 50:
		player._move(STEP)
	assert_false(player.is_sliding(), "the burst ends and there is room to stand")
	assert_almost_eq(_hull_height(player), PlayerSlide.STAND_HEIGHT, 0.001)


func test_a_low_ledge_keeps_the_hull_down() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	_box(Vector3(6.0, 0.4, 40.0), Vector3(0.0, 1.15, -12.0))
	pad.begin_frame()
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	for _frame in 50:
		player._move(STEP)
	assert_true(player.is_sliding(), "a 1m slab still blocks the stand hull")
	assert_almost_eq(_hull_height(player), PlayerSlide.SLIDE_HEIGHT, 0.001)


func test_sprint_plus_slide_does_not_cycle_zoom() -> void:
	var player := await _on_floor()
	_hold_sniper(player)
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	player._fight(STEP)
	assert_true(player.is_sliding())
	assert_almost_eq(player.weapon.zoom_mult(), 1.0, 0.001)


func test_walking_zoom_still_cycles_the_sniper() -> void:
	var player := await _on_floor()
	_hold_sniper(player)
	var pad := _pad(player)
	pad.tap("zoom")
	player._fight(STEP)
	assert_almost_eq(player.weapon.zoom_mult(), 2.0, 0.001)


func test_a_pawn_sync_includes_slide() -> void:
	var pawn := Node3D.new()
	add_child_autofree(pawn)
	var sync := NetSync.attach_pawn(pawn, 1)
	assert_true(sync.replication_config.has_property(NodePath(":sync_slide")))


func test_a_slide_scrapes_sparks_off_the_hull() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	assert_not_null(player.get_node_or_null("SlideSparks"), "the grind rides the body")
	var spark := SlideSparks.flick(player)
	assert_not_null(spark)
	assert_true(spark.is_in_group(SlideSparks.GROUP))
	assert_gt(spark.global_position.y, player.global_position.y)


func test_sparks_also_kick_from_the_front_foot() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	player.body.slide()
	var spark := SlideSparks.flick_toe(player)
	assert_not_null(spark)
	var ahead := spark.global_position - player.global_position
	ahead.y = 0.0
	var nose := -player.transform.basis.z
	nose.y = 0.0
	assert_gt(ahead.dot(nose.normalized()), 0.2, "the toe grind sits in front of the camera")


func test_standing_up_kills_the_grind() -> void:
	var player := await _on_floor()
	var pad := _pad(player)
	pad.hold("sprint")
	pad.move = Vector2(0.0, -1.0)
	pad.tap("slide")
	player._move(STEP)
	assert_not_null(player.get_node_or_null("SlideSparks"))
	player.slide.cancel(player)
	assert_null(player.get_node_or_null("SlideSparks"))


func test_the_slide_pose_drops_the_hips() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.pose(0.0)
	var stand := body.hips.position.y
	body.slide()
	assert_lt(body.hips.position.y, stand)
	assert_gt(rad_to_deg(body.torso.rotation.x), 20.0)
	assert_gt(rad_to_deg(body.legs[0].rotation.x), 50.0)


func _on_floor() -> Player:
	_box(Vector3(20.0, 0.4, 20.0), Vector3(0.0, -0.2, 0.0))
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	await wait_physics_frames(1)
	for _i in 20:
		player.velocity.y = -12.0
		player._move(STEP)
		if player.is_on_floor():
			break
	assert_true(player.is_on_floor(), "the dummy has to land before it can slide")
	return player


func _hold_sniper(player: Player) -> void:
	var sniper: WeaponStats = preload("res://resources/weapons/sniper.tres")
	if not player.weapon.has_gun(sniper):
		player.weapon.add_gun(sniper)
	player.weapon.index = player.weapon.loadout.find(sniper)
	assert_eq(player.weapon.stats(), sniper)


func _pad(player: Player) -> CpuInput:
	var pad := CpuInput.new("p1", true)
	player.input = pad
	return pad


func _shape(player: Player) -> CollisionShape3D:
	return player.get_node("Shape") as CollisionShape3D


func _hull_height(player: Player) -> float:
	return (_shape(player).shape as CapsuleShape3D).height


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	body.position = at
	add_child_autofree(body)
	return body
