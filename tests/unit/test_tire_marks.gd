extends GutTest
## Skid ribbons behind the cart. Drawn while the tires are sliding, then they
## fade so a drift does not paint the whole hole.


func test_the_cart_has_a_tire_under_each_corner() -> void:
	assert_eq(CartVisuals.wheel_offsets().size(), 4)


func test_sliding_wheels_leave_a_mark() -> void:
	var marks := TireMarks.new()
	add_child_autofree(marks)
	var first: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0)]
	var second: Array[Vector3] = [Vector3(0.0, 0.0, -0.4), Vector3(1.0, 0.0, -0.4)]
	marks.trace(first, false, 0.016)
	assert_eq(marks.mesh.get_surface_count(), 0, "gripping tires leave the turf clean")
	marks.trace(first, true, 0.016)
	marks.trace(second, true, 0.016)
	assert_gt(marks.mesh.get_surface_count(), 0, "a slide has to show")


func test_marks_sit_above_the_painted_lie() -> void:
	var highest := 0.0
	for height in Surface.DRAW_HEIGHT.values():
		highest = maxf(highest, float(height))
	assert_gt(TireMarks.LIFT, highest, "rubber under the turf cannot be seen")


func test_world_points_stay_put_when_the_cart_moves() -> void:
	var cart := Node3D.new()
	cart.position = Vector3(20.0, 3.0, -12.0)
	add_child_autofree(cart)
	var marks := TireMarks.new()
	cart.add_child(marks)
	assert_true(marks.top_level)
	var first: Array[Vector3] = [Vector3(40.0, 2.2, -30.0)]
	var second: Array[Vector3] = [Vector3(40.0, 2.2, -30.5)]
	marks.trace(first, true, 0.016)
	marks.trace(second, true, 0.016)
	assert_lt(marks.global_position.distance_to(second[0]), 1.0, "the ribbon has to sit by the wheels")


func test_marks_fade_once_the_slide_stops() -> void:
	var marks := TireMarks.new()
	add_child_autofree(marks)
	var first: Array[Vector3] = [Vector3.ZERO]
	var second: Array[Vector3] = [Vector3(0.0, 0.0, -0.4)]
	marks.trace(first, true, 0.016)
	marks.trace(second, true, 0.016)
	assert_gt(marks.mesh.get_surface_count(), 0)
	marks.trace(second, false, TireMarks.LIFE)
	assert_eq(marks.mesh.get_surface_count(), 0, "old rubber has to disappear")
