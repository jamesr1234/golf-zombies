extends GutTest
## Shambling golfers: hunched, lopsided, and dressed so the three types do not
## look like the same cylinder in three colours.

const STEP := 1.0 / 60.0
const WALKER := preload("res://resources/zombies/walker.tres")
const RUNNER := preload("res://resources/zombies/runner.tres")
const BRUTE := preload("res://resources/zombies/brute.tres")
const GUNNER := preload("res://resources/zombies/gunner.tres")


func test_the_name_picks_the_silhouette() -> void:
	assert_eq(ZombieBody.kind_of(WALKER), ZombieBody.Kind.WALKER)
	assert_eq(ZombieBody.kind_of(RUNNER), ZombieBody.Kind.RUNNER)
	assert_eq(ZombieBody.kind_of(BRUTE), ZombieBody.Kind.BRUTE)
	assert_eq(ZombieBody.kind_of(GUNNER), ZombieBody.Kind.GUNNER)
	assert_eq(ZombieBody.kind_of(preload("res://resources/zombies/sniper.tres")), ZombieBody.Kind.SNIPER)


func test_a_standing_zombie_stays_hunched() -> void:
	var body := _built(WALKER)
	body.pose(0.0)
	assert_almost_eq(rad_to_deg(body.torso.rotation.x), body.hunch_deg, 0.01)
	assert_eq(ZombieBody.leg_angle_deg(1.2, 0.0, true), 0.0)
	assert_eq(absf(rad_to_deg(body.legs[0].rotation.x)), 0.0)


func test_the_dragging_leg_never_takes_a_full_step() -> void:
	var healthy := absf(ZombieBody.leg_angle_deg(PI * 0.5, 1.0, true))
	var limp := absf(ZombieBody.leg_angle_deg(PI * 0.5, 1.0, false))
	assert_almost_eq(healthy, ZombieBody.LEG_SWING_DEG, 0.01)
	assert_lt(limp, healthy)
	assert_almost_eq(limp, ZombieBody.LEG_SWING_DEG * ZombieBody.LIMP, 0.01)


func test_the_three_types_read_apart_at_a_glance() -> void:
	var walker := _built(WALKER)
	var runner := _built(RUNNER)
	var brute := _built(BRUTE)
	assert_not_null(walker.club, "walkers drag a club")
	assert_null(runner.club, "runners sprint empty-handed")
	assert_not_null(brute.club)
	assert_not_null(brute.bag, "brutes still have the bag on")
	assert_null(walker.bag)
	assert_null(runner.bag)
	assert_gt(brute.chest_width(), walker.chest_width())
	assert_gt(walker.chest_width(), runner.chest_width())
	assert_gt(runner.hunch_deg, walker.hunch_deg, "runners lean into the chase")
	assert_gt(walker.hunch_deg, brute.hunch_deg, "brutes stand more upright")


func test_a_built_zombie_is_made_of_many_pieces() -> void:
	var body := _built(WALKER)
	assert_gt(body.meshes.size(), 12, "a golfer should not be three primitives")
	assert_gt(_built(BRUTE).meshes.size(), body.meshes.size(), "the bag adds bulk")


func test_a_hit_flash_covers_every_piece() -> void:
	var body := _built(WALKER)
	var flash := MeshFactory.material(Color.WHITE, false, Palette.GLOW_STRONG)
	body.set_flash(flash)
	for mesh in body.meshes:
		assert_eq(mesh.material_overlay, flash)
	body.set_flash(null)
	for mesh in body.meshes:
		assert_eq(mesh.material_overlay, null)


func test_the_shamble_moves_without_snapping() -> void:
	var body := _built(WALKER)
	var previous := 0.0
	var worst := 0.0
	for _frame in 180:
		body.animate(STEP, 1.0)
		var angle := rad_to_deg(body.legs[1].rotation.x)
		worst = maxf(worst, absf(angle - previous))
		previous = angle
	assert_gt(worst, 1.0, "at a full shamble the legs should actually be moving")
	assert_lt(worst, 8.0, "no single frame should snap the leg across the stride")


func test_the_stride_fades_out_when_they_stop() -> void:
	var body := _built(RUNNER)
	for _frame in 30:
		body.animate(STEP, 1.0)
	var running := absf(rad_to_deg(body.legs[1].rotation.x))
	body.animate(STEP, 0.0)
	assert_eq(absf(rad_to_deg(body.legs[1].rotation.x)), 0.0)
	assert_gt(running, 0.0)


func test_a_gunner_reads_as_a_cannon_not_a_club() -> void:
	var gunner := _built(GUNNER)
	assert_not_null(gunner.club, "the cannon hangs off the arm")
	assert_null(gunner.bag)
	assert_lt(gunner.hunch_deg, _built(WALKER).hunch_deg, "they stand up to aim")


func test_a_converted_zombie_wears_a_bright_blue_backwards_cap() -> void:
	var body := _built(WALKER)
	body.wear_ally_cap()
	assert_not_null(body._ally_cap)
	var brim: MeshInstance3D
	for child in body._ally_cap.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var box := mesh.mesh as BoxMesh
		if box != null and box.size.z < box.size.x:
			brim = mesh
	assert_not_null(brim, "the brim is the thin box")
	assert_gt(brim.position.z, 0.0, "brim sits on the back of the skull")
	var mat := brim.material_override as StandardMaterial3D
	assert_eq(mat.albedo_color, Palette.ALLY_CAP)


func test_a_sip_raises_the_can_to_the_mouth() -> void:
	assert_eq(ZombieBody.drink_lift(0.0), 0.0)
	assert_eq(ZombieBody.drink_lift(0.4), 1.0)
	assert_lt(ZombieBody.drink_lift(1.0), 0.05)
	var body := _built(WALKER)
	var rest := body.arms[1].rotation.x
	body.drink(0.0)
	assert_almost_eq(body.arms[1].rotation.x, rest, 0.01)
	body.drink(0.4)
	assert_gt(
		rad_to_deg(body.arms[1].rotation.x), 90.0,
		"the drinking arm has to come up to the mouth, not swing behind them"
	)
	assert_lt(body.head.rotation.x, -0.1, "the head tips back")
	assert_gt(rad_to_deg(body.jaw.rotation.x), ZombieBody.JAW_OPEN_DEG)


func test_a_walker_chops_with_the_club_hand() -> void:
	var body := _built(WALKER)
	body.pose(0.0)
	var rest := body.arms[0].rotation.x
	body.start_melee()
	body.pose(0.0)
	body.tick_melee(Melee.SWING_TIME * Melee.CONTACT_T)
	assert_gt(rad_to_deg(body.arms[0].rotation.x), 80.0, "the club comes through in front")
	assert_gt(absf(body.arms[0].rotation.x - rest), 0.4)
	assert_gt(absf(rad_to_deg(body.club.rotation.x - body._club_rest_x)), 5.0)
	for _frame in 30:
		body.pose(0.0)
		body.tick_melee(STEP)
	assert_false(body.is_meleeing())
	assert_almost_eq(body.arms[0].rotation.x, rest, 0.002)
	assert_almost_eq(body.club.rotation.x, body._club_rest_x, 0.002)


func test_a_runner_still_swipes_without_a_club() -> void:
	var body := _built(RUNNER)
	body.pose(0.0)
	var rest := body.arms[1].rotation.x
	body.start_melee()
	body.pose(0.0)
	body.tick_melee(Melee.SWING_TIME * Melee.CONTACT_T)
	assert_gt(absf(body.arms[1].rotation.x - rest), 0.3, "the empty reach arm still chops")
	assert_ne(body.torso.rotation.y, 0.0)


func test_the_club_connects_after_the_windup() -> void:
	var body := _built(WALKER)
	body.start_melee()
	assert_lt(body.melee_progress(), Melee.CONTACT_T, "the first pose is the wind-up")
	body.tick_melee(Melee.SWING_TIME * Melee.CONTACT_T)
	assert_gte(body.melee_progress(), Melee.CONTACT_T)


func _built(stats: ZombieStats) -> ZombieBody:
	var body := ZombieBody.new()
	add_child_autofree(body)
	body.build(stats)
	return body
