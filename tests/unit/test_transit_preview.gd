extends GutTest
## The transit flyover follows the cart path and can be skipped.


func test_the_camera_follows_the_centerline() -> void:
	var preview := TransitPreview.new()
	var line := _line()
	preview.start(line)
	assert_true(preview.is_active())
	var start_at := preview.view().origin
	preview.tick(TransitPreview.DURATION * 0.5)
	assert_true(preview.is_active())
	var mid_at := preview.view().origin
	assert_gt(start_at.distance_to(mid_at), 8.0, "the lens should travel along the path")
	var along := line[line.size() - 1] - line[0]
	along.y = 0.0
	var travel := mid_at - start_at
	travel.y = 0.0
	assert_gt(travel.dot(along.normalized()), 0.0, "it looks down the path, not back at the cup")


func test_the_flyover_ends_at_the_tee() -> void:
	var preview := TransitPreview.new()
	var line := _line()
	preview.start(line)
	preview.tick(TransitPreview.DURATION)
	assert_false(preview.is_active())
	preview.start(line)
	preview.tick(TransitPreview.DURATION - 0.05)
	var at := preview.view().origin
	var tee: Vector3 = line[line.size() - 1]
	assert_lt(Vector2(at.x, at.z).distance_to(Vector2(tee.x, tee.z)), 40.0)


func test_skip_finishes_the_preview() -> void:
	var preview := TransitPreview.new()
	preview.start(_line())
	assert_true(preview.is_active())
	preview.skip()
	assert_false(preview.is_active())
	assert_false(preview.tick(0.16))


func _line() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for i in 8:
		points.append(Vector3(float(i) * 12.0, 0.4, float(i) * 2.0))
	return points
