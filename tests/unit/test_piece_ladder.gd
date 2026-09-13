extends GutTest
## Odd-cell ladder and the remap that keeps an old flush pair flush.


func test_the_live_ladder_is_all_odd() -> void:
	assert_eq(PieceLadder.CELLS["extra_small"], 1.0)
	assert_eq(PieceLadder.CELLS["small"], 3.0)
	assert_eq(PieceLadder.CELLS["medium"], 5.0)
	assert_eq(PieceLadder.CELLS["large"], 7.0)
	assert_eq(PieceLadder.CELLS["extra_large"], 9.0)
	for n in PieceLadder.CELLS.values():
		assert_eq(int(n) % 2, 1)


func test_two_flush_small_cubes_stay_flush_after_the_remap() -> void:
	var a := CustomHole.placement(
		"res://assets/obstacles/cube_small.glb", Vector3.ZERO
	)
	var b := CustomHole.placement(
		"res://assets/obstacles/cube_small.glb", Vector3(GridSnap.CELL * 2.0, 0.0, 0.0)
	)
	PieceLadder.remap_centers([a, b])
	var at: Vector3 = b[CustomHole.POSITION]
	assert_almost_eq(at.x, GridSnap.CELL * 3.0, 0.01)
	assert_almost_eq(at.z, 0.0, 0.01)


func test_a_legacy_hole_is_stretched_once() -> void:
	var body := {
		"version": 1,
		"id": "old",
		"title": "Old",
		"created_at": 0,
		"pieces": [0, 0],
		"placements": [
			{"path": "res://assets/obstacles/cube_small.glb", "position": [0.0, 0.0, 0.0], "yaw": 0.0},
			{"path": "res://assets/obstacles/cube_small.glb", "position": [2.7, 0.0, 0.0], "yaw": 0.0},
		],
	}
	var hole := CustomHole.from_dict(body)
	assert_almost_eq((hole.placements[1][CustomHole.POSITION] as Vector3).x, GridSnap.CELL * 3.0, 0.01)
	var again := CustomHole.from_dict(hole.to_dict())
	assert_almost_eq((again.placements[1][CustomHole.POSITION] as Vector3).x, GridSnap.CELL * 3.0, 0.01)
