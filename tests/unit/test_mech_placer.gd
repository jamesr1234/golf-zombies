extends GutTest
## Mech placer: drop beside the buyer, plaza when they are in the hall.


func test_candidates_start_beside_the_buyer() -> void:
	var spots := MechPlacer.candidates(Vector3.ZERO, 0.0)
	assert_gt(spots.size(), 4)
	assert_almost_eq(spots[0].x, MechPlacer.SIDE, 0.01)
	assert_almost_eq(spots[1].x, -MechPlacer.SIDE, 0.01)


func test_the_hall_prefers_the_exit_plaza() -> void:
	var house := Node3D.new()
	add_child_autofree(house)
	var spots := MechPlacer.candidates(Vector3.ZERO, 180.0, true, house)
	assert_gt(spots[0].distance_to(Vector3.ZERO), 8.0)
	assert_lt(spots[0].z, -ClubhouseBuild.DEPTH * 0.25)


func test_place_without_a_world_returns_a_lifted_offset() -> void:
	var pose := MechPlacer.place(null)
	assert_true(pose.has("at"))
	assert_true(pose.has("yaw"))
