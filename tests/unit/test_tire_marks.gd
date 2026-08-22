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
