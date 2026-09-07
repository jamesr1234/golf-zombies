extends GutTest
## Authored spawn yards clamp, serialize as packs, and refuse an empty swarm.


func test_counts_clamp_and_total() -> void:
	var raw := {"walker": 99, "runner": -2, "brute": 3, "other": 8}
	var counts := SpawnPack.clamp_counts(raw)
	assert_eq(int(counts["walker"]), SpawnPack.MAX_EACH)
	assert_eq(int(counts["runner"]), 0)
	assert_eq(int(counts["brute"]), 3)
	assert_eq(int(counts["gunner"]), 0)
	assert_eq(SpawnPack.total(counts), SpawnPack.MAX_EACH + 3)
	assert_eq(SpawnPack.total(SpawnPack.empty_counts()), 0)


func test_the_chase_range_clamps() -> void:
	assert_almost_eq(SpawnPack.clamp_aggro(0.1), SpawnPack.AGGRO_MIN, 0.001)
	assert_almost_eq(SpawnPack.clamp_aggro(99.0), SpawnPack.AGGRO_MAX, 0.001)
	assert_almost_eq(SpawnPack.clamp_aggro(16.2), SpawnPack.DEFAULT_AGGRO, 0.001)


func test_a_saved_pack_keeps_its_chase_range() -> void:
	var hole := CustomHole.create("Chase")
	hole.add_placement(CustomHole.SPAWN, Vector3(0.0, 0.0, -24.0))
	hole.placements[0][CustomHole.RADIUS] = 8.1
	hole.placements[0][CustomHole.AGGRO] = 24.3
	hole.placements[0][CustomHole.COUNTS] = {"walker": 1, "runner": 0, "brute": 0, "gunner": 0}
	var packs := SpawnPack.from_hole(hole)
	assert_eq(packs.size(), 1)
	assert_almost_eq(float(packs[0]["aggro"]), 24.3, 0.001)


func test_the_yard_is_centered_on_the_point() -> void:
	var at := Vector3(4.0, 1.0, -10.0)
	var roam := SpawnPack.roam_at(at, 8.1)
	assert_almost_eq(roam.get_center().x, at.x, 0.001)
	assert_almost_eq(roam.get_center().z, at.z, 0.001)
	assert_gt(roam.size.x, 15.0)


func test_the_count_dialog_needs_at_least_one_enemy() -> void:
	var dialog := CreatorSpawn.create()
	add_child_autofree(dialog)
	await wait_frames(1)
	dialog.open()
	await wait_frames(1)
	var got: Array = []
	dialog.picked.connect(func(counts: Dictionary) -> void: got.append(counts))
	dialog.confirm()
	assert_true(dialog.is_open(), "an empty yard stays on the pad")
	assert_eq(got.size(), 0)
	dialog.nudge(2)
	dialog.confirm()
	assert_false(dialog.is_open())
	assert_eq(got.size(), 1)
	assert_eq(int(got[0]["walker"]), 2)
