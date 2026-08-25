extends GutTest
## A cart jump is a real ramp: a solid wedge, a glowing lip, and a launch
## that actually clears the pond in front of it.


func test_the_ramp_is_solid_ground_the_cart_can_drive() -> void:
	var ramp := JumpRamp.create(_jump())
	add_child_autofree(ramp)
	assert_eq(ramp.collision_layer, Layers.WORLD)
	assert_eq(ramp.collision_mask, 0)
	var box := _box(ramp)
	assert_not_null(box, "the takeoff has to be a collider, not a deco")
	assert_gt(box.size.y, 6.0, "thick enough that the pond cannot swallow it")


func test_you_cannot_drive_under_the_ramp() -> void:
	var ramp := JumpRamp.create(_jump())
	add_child_autofree(ramp)
	await wait_physics_frames(2)
	var space := ramp.get_world_3d().direct_space_state
	var run := JumpRamp.ground_run()
	var rise := JumpRamp.lip_height()
	var through := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, rise * 0.35, run * 0.7),
		Vector3(0.0, rise * 0.35, -run * 0.7)
	)
	through.collision_mask = Layers.WORLD
	assert_false(
		space.intersect_ray(through).is_empty(),
		"the volume under the slope is solid, not a gap"
	)
	var onto := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, rise * 0.5 + 2.0, 0.0),
		Vector3(0.0, rise * 0.5 - 0.5, 0.0)
	)
	onto.collision_mask = Layers.WORLD
	assert_false(space.intersect_ray(onto).is_empty(), "the slope itself is driveable")


func test_the_lip_sits_above_the_ground() -> void:
	assert_gt(JumpRamp.lip_height(), 3.0)
	assert_lt(JumpRamp.lip_height(), 6.0, "it should launch, not be a ski jump")


func test_slow_speed_drops_short_of_a_swimming_pond() -> void:
	var range := JumpRamp.flight_distance(8.0, JumpRamp.ANGLE_DEG, JumpRamp.lip_height())
	assert_lt(range, HoleGenerator.WATER_MIN_SPAN, "you have to send it")


func test_the_builder_puts_the_ramp_on_the_hole() -> void:
	var hole := HoleGenerator.generate(2, 20260816)
	var root := HoleBuilder.build(hole)
	add_child_autofree(root)
	var ramps := root.find_children("*", "JumpRamp", true, false)
	assert_eq(ramps.size(), 1)


func test_the_ground_rises_to_the_lip() -> void:
	var hole := HoleGenerator.generate(2, 20260816)
	var jump: Dictionary = hole.jumps[0]
	var origin: Vector3 = jump["position"]
	var yaw: float = deg_to_rad(jump["yaw"])
	var run := JumpRamp.ground_run(jump["length"], jump["angle_deg"])
	var rear := origin + Vector3.BACK.rotated(Vector3.UP, yaw) * (run * 0.5)
	var mid := origin + Vector3.FORWARD.rotated(Vector3.UP, yaw) * (run * 0.15)
	var lip := origin + Vector3.FORWARD.rotated(Vector3.UP, yaw) * (run * 0.45)
	var rear_h := hole.height.height_at(rear.x, rear.z)
	var mid_h := hole.height.height_at(mid.x, mid.z)
	var lip_h := hole.height.height_at(lip.x, lip.z)
	assert_almost_eq(rear_h, origin.y, 0.8, "the approach stays on the bank")
	assert_gt(mid_h, rear_h + 0.8, "the slope starts before the water")
	assert_gt(
		lip_h - rear_h, JumpRamp.lip_height(jump["length"], jump["angle_deg"]) * 0.6,
		"the heightmap itself is the takeoff, not a deco on a pond bowl"
	)


func _box(ramp: JumpRamp) -> BoxShape3D:
	for child in ramp.get_children():
		var node := child as CollisionShape3D
		if node != null:
			return node.shape as BoxShape3D
	return null


func _jump() -> Dictionary:
	return {
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
		"width": JumpRamp.WIDTH,
		"length": JumpRamp.LENGTH,
		"angle_deg": JumpRamp.ANGLE_DEG,
		"role": "takeoff",
	}
