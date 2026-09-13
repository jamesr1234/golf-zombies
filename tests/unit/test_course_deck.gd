extends GutTest
## The host's titled Hole 1..12 travel with the match start so joiners play
## that course, even when their own user:// folder is empty or different.

const CUBE := "res://assets/obstacles/cube_large.glb"
const ARCH := "res://assets/obstacles/arch_large.glb"
const SEED := 20260816


func before_each() -> void:
	HoleStore.clear_sandbox()
	GameSettings.reset()


func after_all() -> void:
	before_each()


func test_a_packed_hole_6_wins_over_a_different_local_save() -> void:
	var host := CustomHole.create("Hole 6")
	assert_true(HoleStore.save_hole(host))
	var packed := CourseDeck.pack()
	HoleStore.clear_sandbox()
	var local := CustomHole.create("Hole 6")
	assert_true(HoleStore.save_hole(local))
	CourseDeck.apply(packed)
	var found := HoleStore.course_hole(5)
	assert_not_null(found)
	assert_eq(found.id, host.id)
	assert_eq(HoleStore.disk_course_hole(5).id, local.id)
	var data := HoleStore.layout(5, SEED)
	assert_not_null(data.custom)
	assert_eq(data.custom.id, host.id)
	assert_eq(data.index, 5)
	assert_eq(data.par, host.par())
	assert_eq(HoleStore.course_pars()[5], host.par())


func test_an_empty_pack_leaves_generated_holes() -> void:
	CourseDeck.apply([])
	var data := HoleStore.layout(1, SEED)
	assert_null(data.custom)
	assert_eq(data.index, 1)
	assert_true(data.has_culvert())
	assert_eq(HoleStore.course_pars()[1], HoleGenerator.pars()[1])


func test_flatten_drops_user_structure_paths() -> void:
	var path := HoleStore.save_structure("Tower Block", [
		CustomHole.placement(CUBE, Vector3(0.0, 0.0, -10.0)),
		CustomHole.placement(CUBE, Vector3(1.35, 0.0, -10.0)),
		CustomHole.placement(ARCH, Vector3(2.7, 0.0, -10.0), 90.0),
	])
	assert_false(path.is_empty())
	var host := CustomHole.create("Hole 6")
	host.add_placement(path, Vector3(0.0, 0.0, -20.0))
	assert_true(HoleStore.save_hole(host))
	var packed := CourseDeck.pack()
	HoleStore.clear_sandbox()
	assert_eq(HoleStore.list_structures().size(), 0)
	CourseDeck.apply(packed)
	var found := HoleStore.course_hole(5)
	assert_not_null(found)
	assert_eq(found.placements.size(), 3)
	for entry in found.placements:
		assert_false(
			String(entry[CustomHole.PATH]).begins_with("user://"),
			"a joiner cannot look up the host's grouped structure"
		)


func test_clear_restores_the_disk_slot() -> void:
	var disk := CustomHole.create("Hole 1")
	assert_true(HoleStore.save_hole(disk))
	var other := CustomHole.create("Hole 1")
	CourseDeck.apply([{CourseDeck.INDEX: 0, CourseDeck.HOLE: other.to_dict()}])
	assert_eq(HoleStore.course_hole(0).id, other.id)
	CourseDeck.clear()
	assert_eq(HoleStore.course_hole(0).id, disk.id)


func test_reset_and_close_drop_the_session() -> void:
	var host := CustomHole.create("Hole 6")
	CourseDeck.apply([{CourseDeck.INDEX: 5, CourseDeck.HOLE: host.to_dict()}])
	assert_eq(CourseDeck.hole(5).id, host.id)
	GameSettings.reset()
	assert_null(CourseDeck.hole(5))
	CourseDeck.apply([{CourseDeck.INDEX: 5, CourseDeck.HOLE: host.to_dict()}])
	NetSession.close()
	assert_null(CourseDeck.hole(5))


func test_begin_match_installs_the_host_pack() -> void:
	var host := CustomHole.create("Hole 6")
	assert_true(HoleStore.save_hole(host))
	var packed := CourseDeck.pack()
	HoleStore.clear_sandbox()
	assert_null(HoleStore.course_hole(5))
	NetSession._begin_match(
		SEED, int(GameSettings.Kind.MEDIUM), PackedInt32Array([1]), PackedInt32Array([0]),
		int(GameSettings.Mode.ONLINE_VS), packed
	)
	assert_eq(HoleStore.course_hole(5).id, host.id)
	NetSession.close()


func test_pack_reads_disk_not_the_session() -> void:
	var disk := CustomHole.create("Hole 6")
	assert_true(HoleStore.save_hole(disk))
	var session := CustomHole.create("Hole 6")
	CourseDeck.apply([{CourseDeck.INDEX: 5, CourseDeck.HOLE: session.to_dict()}])
	var packed := CourseDeck.pack()
	CourseDeck.apply(packed)
	assert_eq(HoleStore.course_hole(5).id, disk.id)
