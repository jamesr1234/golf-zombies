extends GutTest
## A player-made hole has to come out the far side as an ordinary HoleData, or
## none of the rules that keep play on the fairway apply to it.

const CUBE := "res://assets/obstacles/cube_large.glb"
const ARCH := "res://assets/obstacles/arch_large.glb"
const RIFLE := "res://resources/weapons/rifle.tres"
const ZIP := "res://scenes/course/props/zipline.tscn"


func before_each() -> void:
	HoleStore.clear_sandbox()


func after_all() -> void:
	before_each()


func test_a_new_hole_starts_playable_and_named() -> void:
	var hole := CustomHole.create("Test Hole")
	assert_eq(hole.title, "Test Hole")
	assert_false(hole.id.is_empty())
	assert_true(hole.is_playable())
	assert_gt(hole.length(), 0.0)
	assert_gt(hole.width(), 0.0)
	assert_eq(hole.fairway_size, FairwayPiece.Width.SMALL)
	assert_false(hole.needs_width)


func test_a_hole_survives_a_trip_through_json() -> void:
	var hole := CustomHole.create("Round Trip")
	hole.add_placement(CUBE, Vector3(1.35, 0.0, -20.0), 90.0)
	hole.add_placement(ARCH, Vector3(-2.7, 1.35, -30.0), 180.0)
	hole.add_placement(RIFLE, Vector3(0.0, 0.0, -25.0), 0.0, 0.45)
	hole.add_placement(ZIP, Vector3(0.0, 2.7, -40.0), 0.0, CustomHole.NO_GATE, Vector3(5.4, 0.0, -48.0))
	var text := JSON.stringify(hole.to_dict())
	var back := CustomHole.from_dict(JSON.parse_string(text))
	assert_eq(back.id, hole.id)
	assert_eq(back.title, hole.title)
	assert_eq(back.fairway_size, hole.fairway_size)
	assert_eq(Array(back.pieces), Array(hole.pieces))
	assert_eq(back.placements.size(), hole.placements.size())
	for i in hole.placements.size():
		assert_eq(back.placements[i][CustomHole.PATH], hole.placements[i][CustomHole.PATH])
		assert_almost_eq(
			(back.placements[i][CustomHole.POSITION] as Vector3).distance_to(
				hole.placements[i][CustomHole.POSITION]
			), 0.0, 0.01
		)
		assert_almost_eq(
			float(back.placements[i][CustomHole.YAW]), float(hole.placements[i][CustomHole.YAW]), 0.01
		)
		assert_almost_eq(
			float(back.placements[i][CustomHole.GATE]),
			float(hole.placements[i][CustomHole.GATE]), 0.001
		)
		assert_eq(CustomHole.has_end(back.placements[i]), CustomHole.has_end(hole.placements[i]))
		if CustomHole.has_end(hole.placements[i]):
			assert_almost_eq(
				(back.placements[i][CustomHole.END] as Vector3).distance_to(
					hole.placements[i][CustomHole.END]
				), 0.0, 0.01
			)


func test_a_spawn_pack_survives_a_trip_through_json() -> void:
	var hole := CustomHole.create("Packed")
	hole.add_placement(CustomHole.SPAWN, Vector3(0.0, 0.0, -24.0))
	hole.placements[0][CustomHole.RADIUS] = 8.1
	hole.placements[0][CustomHole.AGGRO] = 21.6
	hole.placements[0][CustomHole.COUNTS] = {"walker": 3, "runner": 1, "brute": 0, "gunner": 2}
	var back := CustomHole.from_dict(JSON.parse_string(JSON.stringify(hole.to_dict())))
	assert_true(CustomHole.is_spawn(String(back.placements[0][CustomHole.PATH])))
	assert_almost_eq(float(back.placements[0][CustomHole.RADIUS]), 8.1, 0.001)
	assert_almost_eq(float(back.placements[0][CustomHole.AGGRO]), 21.6, 0.001)
	var counts: Dictionary = back.placements[0][CustomHole.COUNTS]
	assert_eq(int(counts["walker"]), 3)
	assert_eq(int(counts["runner"]), 1)
	assert_eq(int(counts["gunner"]), 2)
	assert_eq(int(counts["brute"]), 0)


func test_every_spawn_pack_keeps_its_own_yard() -> void:
	var hole := CustomHole.create("Three Yards")
	for i in 3:
		var at := Vector3(0.0, 12.0 + float(i), -20.0 - float(i) * 12.0)
		hole.add_placement(CustomHole.SPAWN, at)
		hole.placements[i][CustomHole.RADIUS] = SpawnPack.DEFAULT_RADIUS
		hole.placements[i][CustomHole.COUNTS] = {"walker": 1, "runner": 0, "brute": 0, "gunner": 0}
	var data := CustomLayout.build(hole)
	assert_eq(data.spawn_packs.size(), 3)
	var seen: Array[float] = []
	for pack in data.spawn_packs:
		var at: Vector3 = pack["position"]
		assert_false(seen.has(at.z), "each pack stays where it was dropped")
		seen.append(at.z)
		assert_almost_eq(at.y, data.height.height_at(at.x, at.z), 0.05, "they stand on the grass")


func test_the_layout_copies_authored_spawn_packs() -> void:
	var hole := CustomHole.create("Yard")
	hole.add_placement(CustomHole.SPAWN, Vector3(0.0, 0.0, -24.0))
	hole.placements[0][CustomHole.RADIUS] = SpawnPack.DEFAULT_RADIUS
	hole.placements[0][CustomHole.COUNTS] = {"walker": 2, "runner": 0, "brute": 1, "gunner": 0}
	var data := CustomLayout.build(hole)
	assert_eq(data.spawn_packs.size(), 1)
	assert_eq(int(data.spawn_packs[0]["counts"]["walker"]), 2)
	assert_eq(int(data.spawn_packs[0]["counts"]["brute"]), 1)
	assert_almost_eq(float(data.spawn_packs[0]["radius"]), SpawnPack.DEFAULT_RADIUS, 0.001)
	assert_almost_eq(float(data.spawn_packs[0]["aggro"]), SpawnPack.DEFAULT_AGGRO, 0.001)
	var at: Vector3 = data.spawn_packs[0]["position"]
	assert_almost_eq(at.x, 0.0, 0.01)
	assert_almost_eq(at.z, -24.0, 0.01)


func test_a_spawn_saved_without_a_chase_range_gets_the_default() -> void:
	var legacy := {
		"version": 1, "id": "old_swarm", "title": "Old Swarm", "created_at": 0,
		"pieces": [0, 0],
		"placements": [{
			"path": CustomHole.SPAWN, "position": [0.0, 0.0, -20.0], "yaw": 0.0,
			"radius": 8.1,
			"counts": {"walker": 2, "runner": 0, "brute": 0, "gunner": 0},
		}],
	}
	var hole := CustomHole.from_dict(legacy)
	assert_almost_eq(float(hole.placements[0][CustomHole.AGGRO]), CustomHole.DEFAULT_AGGRO, 0.001)
	var packs := SpawnPack.from_hole(hole)
	assert_almost_eq(float(packs[0]["aggro"]), SpawnPack.DEFAULT_AGGRO, 0.001)


func test_a_spawn_does_not_stand_on_the_played_hole() -> void:
	var hole := CustomHole.create("Invisible")
	hole.add_placement(CustomHole.SPAWN, Vector3(0.0, 0.0, -20.0))
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.get_child_count(), 0)


## A hole saved before weapons existed has no gate written down, and every piece
## in it has to keep working.
func test_a_hole_saved_without_lines_still_loads() -> void:
	var legacy := {
		"version": 1, "id": "old_hole", "title": "Legacy", "created_at": 0,
		"pieces": [0, 0],
		"placements": [{"path": CUBE, "position": [0.0, 0.0, -18.0], "yaw": 0.0}],
	}
	var hole := CustomHole.from_dict(legacy)
	assert_eq(hole.placements.size(), 1)
	assert_eq(float(hole.placements[0][CustomHole.GATE]), CustomHole.NO_GATE)
	assert_eq(hole.fairway_size, FairwayPiece.Width.SMALL, "an old save is the regular strip")


func test_a_chosen_width_survives_a_trip_through_json() -> void:
	var hole := CustomHole.create("Wide Lane")
	hole.fairway_size = FairwayPiece.Width.LARGE
	var back := CustomHole.from_dict(JSON.parse_string(JSON.stringify(hole.to_dict())))
	assert_eq(back.fairway_size, FairwayPiece.Width.LARGE)
	assert_almost_eq(back.width(), hole.width(), 0.01)
	assert_almost_eq(back.width(), FairwayPiece.width_for(hole.pieces) * 2.0, 0.01)
	hole.fairway_size = FairwayPiece.Width.GIGANTIC
	var giant := CustomHole.from_dict(JSON.parse_string(JSON.stringify(hole.to_dict())))
	assert_eq(giant.fairway_size, FairwayPiece.Width.GIGANTIC)
	assert_almost_eq(giant.width(), FairwayPiece.width_for(hole.pieces) * 4.0, 0.01)


func test_a_saved_hole_comes_back_off_disk() -> void:
	var hole := CustomHole.create("Saved")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -18.0))
	assert_true(HoleStore.save_hole(hole))
	var back := HoleStore.load_hole(hole.id)
	assert_not_null(back)
	assert_eq(back.title, "Saved")
	assert_eq(back.placements.size(), 1)
	var rows := HoleStore.list_holes()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["title"], "Saved")
	assert_true(bool(rows[0]["playable"]))
	assert_true(HoleStore.delete_hole(hole.id))
	assert_null(HoleStore.load_hole(hole.id))


func test_a_missing_hole_reads_as_nothing() -> void:
	assert_null(HoleStore.load_hole("nothing_here"))
	assert_false(HoleStore.delete_hole("nothing_here"))


## A title is turned into a file name, so a path in it must not escape the
## holes folder.
func test_a_title_cannot_write_outside_the_holes_folder() -> void:
	var path := HoleStore.structure_path("../../evil name")
	assert_true(path.begins_with(HoleStore.STRUCTURE_ROOT), path)
	assert_false(path.contains(".."), path)


func test_the_layout_produces_a_hole_that_plays_by_the_normal_rules() -> void:
	var hole := CustomHole.create("Playable")
	var data := CustomLayout.build(hole)
	assert_not_null(data.height, "a hole needs ground")
	assert_eq(data.centerline.size(), hole.pieces.size() + 1)
	assert_eq(data.par, hole.par())
	assert_gt(data.bounds.size.x, 0.0)
	assert_gt(data.bounds.size.y, 0.0)
	assert_true(data.bounds.has_point(Vector2(data.tee.x, data.tee.z)), "the tee is in bounds")
	assert_true(data.bounds.has_point(Vector2(data.cup.x, data.cup.z)), "the cup is in bounds")
	assert_almost_eq(data.tee.distance_to(data.centerline[0]), 0.0, 0.01)
	assert_almost_eq(data.cup.distance_to(data.centerline[data.centerline.size() - 1]), 0.0, 0.01)
	assert_false(data.is_setpiece())
	assert_false(data.has_soccer_goal())


func test_the_layout_paints_a_fairway_a_tee_and_a_green() -> void:
	var hole := CustomHole.create("Surfaces")
	var data := CustomLayout.build(hole)
	var kinds := {}
	for patch in data.patches:
		kinds[patch["type"]] = int(kinds.get(patch["type"], 0)) + 1
	assert_eq(int(kinds.get(Surface.Type.FAIRWAY, 0)), hole.pieces.size() + 1)
	assert_gte(int(kinds.get(Surface.Type.TEE, 0)), 1)
	assert_gte(int(kinds.get(Surface.Type.GREEN, 0)), 1)
	assert_gte(int(kinds.get(Surface.Type.FRINGE, 0)), 1)
	var along := data.along_cup()
	var end := HoleGenerator.exit_end(data)
	var past := data.cup + along * (data.cup.distance_to(end) * 0.6)
	var covered := false
	for patch in data.patches:
		if patch["type"] == Surface.Type.FAIRWAY and HoleGenerator.patch_covers(patch, past):
			covered = true
			break
	assert_true(covered, "the strip has to keep going past the pin to the fence")


func test_a_wide_custom_hole_paints_a_wider_strip() -> void:
	var small := CustomHole.create("Narrow")
	var wide := CustomHole.create("Wide")
	wide.fairway_size = FairwayPiece.Width.LARGE
	var small_data := CustomLayout.build(small)
	var wide_data := CustomLayout.build(wide)
	assert_almost_eq(wide_data.fairway_width(), small_data.fairway_width() * 2.0, 0.01)
	assert_almost_eq(wide.width(), small.width() * 2.0, 0.01)
	var small_patch := _first_fairway(small_data)
	var wide_patch := _first_fairway(wide_data)
	assert_almost_eq(float(wide_patch["size"].x), float(small_patch["size"].x) * 2.0, 0.01)


func test_a_wide_strip_stays_flat_past_the_regular_lip() -> void:
	var hole := CustomHole.create("Deck")
	hole.fairway_size = FairwayPiece.Width.LARGE
	var data := CustomLayout.build(hole)
	var line := hole.centerline()
	var along: Vector3 = line[1] - line[0]
	along.y = 0.0
	var right := Vector3.UP.cross(along.normalized())
	var mid: Vector3 = line[0].lerp(line[1], 0.5)
	var past_small := FairwayPiece.width_for(hole.pieces, FairwayPiece.Width.SMALL) * 0.5 + 4.0
	var spot := mid + right * past_small
	assert_almost_eq(data.height.height_at(spot.x, spot.z), HeightField.DECK, 0.15)


func test_a_custom_hole_keeps_the_width_it_was_built_with() -> void:
	var hole := CustomHole.create("Hole 10")
	var data := CustomLayout.build(hole, 0, HoleGenerator.WIDE_HOLE)
	assert_eq(data.index, HoleGenerator.WIDE_HOLE)
	assert_almost_eq(data.fairway_width(), hole.width(), 0.01)
	assert_almost_eq(
		data.fairway_width(),
		HoleGenerator.fairway_width(hole.par(), FairwayPiece.INDEX), 0.01
	)
	hole.fairway_size = FairwayPiece.Width.LARGE
	var wide := CustomLayout.build(hole, 0, HoleGenerator.WIDE_HOLE)
	assert_almost_eq(wide.fairway_width(), hole.width(), 0.01)
	assert_gt(wide.fairway_width(), HoleGenerator.fairway_width(hole.par(), FairwayPiece.INDEX))


func test_a_custom_hole_only_gets_a_practice_tee_after_a_clubhouse() -> void:
	var hole := CustomHole.create("Warm Up")
	var opening := CustomLayout.build(hole)
	assert_true(opening.has_practice(), "playtest and hole 1 open behind the tee")
	var mid := CustomLayout.build(hole, 0, 1)
	assert_false(mid.has_practice(), "a hole-2 slot has no warm-up green")
	var after_shop := CustomLayout.build(hole, 0, 3)
	assert_true(after_shop.has_practice(), "hole 4 follows the clubhouse")


## The fairway has to be the flat deck obstacle blocks snap onto, exactly as it
## is on a generated hole.
func test_the_middle_of_the_fairway_is_flat() -> void:
	var data := CustomLayout.build(CustomHole.create("Flat"))
	for i in range(1, data.centerline.size()):
		var mid: Vector3 = data.centerline[i - 1].lerp(data.centerline[i], 0.5)
		assert_almost_eq(data.height.height_at(mid.x, mid.z), HeightField.DECK, 0.01)


func test_a_placement_off_the_strip_is_dropped() -> void:
	var hole := CustomHole.create("Reach")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	hole.add_placement(CUBE, Vector3(400.0, 0.0, -20.0))
	assert_true(hole.covers(hole.placements[0][CustomHole.POSITION]))
	assert_false(hole.covers(hole.placements[1][CustomHole.POSITION]))
	hole.prune_placements()
	assert_eq(hole.placements.size(), 1)


func test_erasing_a_hole_keeps_its_name_and_width() -> void:
	var hole := CustomHole.create("Wipe Me")
	hole.fairway_size = FairwayPiece.Width.LARGE
	hole.append_piece(FairwayPiece.index_of("straight"))
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -20.0))
	var id := hole.id
	var start := FairwayPiece.starter()
	hole.erase()
	assert_eq(hole.id, id)
	assert_eq(hole.title, "Wipe Me")
	assert_eq(hole.fairway_size, FairwayPiece.Width.LARGE)
	assert_eq(Array(hole.pieces), Array(start))
	assert_eq(hole.placements.size(), 0)


func test_dropping_the_last_piece_takes_its_props_with_it() -> void:
	var hole := CustomHole.create("Undo")
	var line := hole.centerline()
	hole.add_placement(CUBE, line[line.size() - 1])
	assert_eq(hole.placements.size(), 1)
	hole.pop_piece()
	assert_eq(hole.pieces.size(), 1)
	assert_eq(hole.placements.size(), 0, "a prop out on the removed piece has nowhere to stand")


func test_the_overlay_instances_what_was_placed() -> void:
	var hole := CustomHole.create("Overlay")
	hole.add_placement(CUBE, Vector3(0.0, 0.0, -18.0))
	hole.add_placement(ARCH, Vector3(2.7, 0.0, -24.0), 90.0)
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.name, CustomOverlay.NAME)
	assert_eq(overlay.get_child_count(), 2)
	assert_eq((overlay.get_child(0) as Node3D).scene_file_path, CUBE)
	assert_almost_eq((overlay.get_child(1) as Node3D).rotation.y, deg_to_rad(90.0), 0.01)


func test_the_race_hole_hides_its_speed_pads() -> void:
	var pad := CustomOverlay.SPEED_PAD
	var race := CustomHole.create("RACE")
	race.add_placement(pad, Vector3(0.0, 0.0, -18.0))
	race.add_placement(CUBE, Vector3(0.0, 0.0, -24.0))
	var hidden := CustomOverlay.build(race)
	autofree(hidden)
	assert_eq(hidden.get_child_count(), 1)
	assert_eq((hidden.get_child(0) as Node3D).scene_file_path, CUBE)
	assert_eq(race.placements.size(), 2, "the pads stay on the record")
	var other := CustomHole.create("Sprint")
	other.add_placement(pad, Vector3(0.0, 0.0, -18.0))
	var shown := CustomOverlay.build(other)
	autofree(shown)
	assert_eq(shown.get_child_count(), 1)
	assert_eq((shown.get_child(0) as Node3D).scene_file_path, pad)


func test_a_piece_the_catalog_does_not_know_is_never_loaded() -> void:
	var hole := CustomHole.create("Untrusted")
	hole.add_placement("res://scenes/ui/main_menu.tscn", Vector3.ZERO)
	hole.add_placement("res://nothing/at/all.glb", Vector3.ZERO)
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.get_child_count(), 0)


func test_a_saved_group_drops_back_as_the_pieces_it_was_made_from() -> void:
	var parts: Array[Dictionary] = [
		CustomHole.placement(CUBE, Vector3(0.0, 0.0, -10.0)),
		CustomHole.placement(CUBE, Vector3(1.35, 0.0, -10.0)),
		CustomHole.placement(ARCH, Vector3(2.7, 0.0, -10.0), 90.0),
	]
	var path := HoleStore.save_structure("Tower Block", parts)
	assert_false(path.is_empty())
	assert_eq(HoleStore.structure_parts(path).size(), 3)
	assert_eq(HoleStore.structure_title(path), "TOWER BLOCK")
	assert_true(HoleStore.list_structures().has(path))

	var hole := CustomHole.create("With Group")
	hole.add_placement(path, Vector3(0.0, 0.0, -20.0))
	var overlay := CustomOverlay.build(hole)
	autofree(overlay)
	assert_eq(overlay.get_child_count(), 3, "the group expands into its own pieces")


## A group stores its parts around its own middle, so dropping it somewhere
## else moves the whole thing rather than scattering it.
func test_a_group_is_stored_around_its_own_middle() -> void:
	var parts: Array[Dictionary] = [
		CustomHole.placement(CUBE, Vector3(100.0, 0.0, 0.0)),
		CustomHole.placement(CUBE, Vector3(102.7, 0.0, 0.0)),
	]
	var path := HoleStore.save_structure("Offset Pair", parts)
	var stored := HoleStore.structure_parts(path)
	var middle := Vector3.ZERO
	for part in stored:
		middle += part[CustomHole.POSITION] as Vector3
	assert_almost_eq((middle / float(stored.size())).length(), 0.0, 0.01)


func test_a_grouped_zipline_keeps_its_end() -> void:
	var start := Vector3(0.0, 2.7, 0.0)
	var finish := Vector3(5.4, 0.0, 0.0)
	var path := HoleStore.save_structure("Zip Pair", [
		CustomHole.placement(CUBE, Vector3(0.0, 0.0, 0.0)),
		CustomHole.placement(ZIP, start, 0.0, CustomHole.NO_GATE, finish),
	])
	var origin := Vector3(10.0, 0.0, -20.0)
	var flat := CustomOverlay.expand(CustomHole.placement(path, origin, 90.0))
	var zip_row: Dictionary = {}
	for part in flat:
		if CustomHole.is_zipline(String(part[CustomHole.PATH])):
			zip_row = part
			break
	assert_false(zip_row.is_empty())
	assert_true(CustomHole.has_end(zip_row))
	var moved_start: Vector3 = zip_row[CustomHole.POSITION]
	var moved_end: Vector3 = zip_row[CustomHole.END]
	assert_almost_eq((moved_end - moved_start).y, (finish - start).y, 0.01)
	assert_gt((moved_end - moved_start).length(), 4.0)


func test_a_group_that_names_itself_cannot_spin_forever() -> void:
	var path := HoleStore.save_structure("Loop", [CustomHole.placement(CUBE, Vector3.ZERO)])
	var looped: Array = HoleStore.structure_parts(path)
	looped.append({
		CustomHole.PATH: path, CustomHole.POSITION: [0.0, 0.0, 0.0], CustomHole.YAW: 0.0,
	})
	HoleStore._write(path, {"version": HoleStore.VERSION, "title": "Loop", HoleStore.PARTS: looped})
	var flat := CustomOverlay.expand(CustomHole.placement(path, Vector3.ZERO))
	assert_lt(flat.size(), 64, "a self-referencing group has to bottom out")


func _first_fairway(data: HoleData) -> Dictionary:
	for patch in data.patches:
		if patch["type"] == Surface.Type.FAIRWAY:
			return patch
	return {}
