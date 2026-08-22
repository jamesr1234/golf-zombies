extends GutTest
## The clubhouse is a castle of rooms, not one neon box with counters in it.


func test_shops_live_in_their_own_rooms() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	assert_eq(house.stations.size(), 5)
	var apparel := house.stations[0]
	var armory := house.stations[1]
	var clubs := house.stations[2]
	var items := house.stations[3]
	var cart := house.stations[4]
	assert_lt(apparel.position.x, -ClubhouseBuild.HALL)
	assert_gt(armory.position.x, ClubhouseBuild.HALL)
	assert_gt(apparel.position.z, ClubhouseBuild.SPLIT_FRONT)
	assert_gt(armory.position.z, ClubhouseBuild.SPLIT_FRONT)
	assert_lt(clubs.position.z, ClubhouseBuild.SPLIT_FRONT)
	assert_lt(items.position.z, ClubhouseBuild.SPLIT_FRONT)
	assert_gt(clubs.position.y, apparel.position.y + 0.5, "clubs is up the stairs")
	assert_gt(items.position.y, armory.position.y + 0.5, "items is up the stairs")
	assert_lt(cart.position.x, -ClubhouseBuild.HALL)
	assert_lt(cart.position.z, ClubhouseBuild.SPLIT_BACK, "cart upgrades sit in a back room")
	assert_eq(cart.dept, Shop.Dept.CART)


func test_the_back_hall_is_clear_to_the_exit() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	for child in house.get_children():
		assert_false(child is SurfacePatch, "no indoor green in the way of the exit")
		assert_false(child is Cup, "no indoor cup in the back hall")
	for npc in house.npcs:
		assert_gt(absf(npc.position.x) + absf(npc.position.z + ClubhouseBuild.DEPTH * 0.5), 6.0)
	assert_gt(house.exit_point().distance_to(house.door_point()), ClubhouseBuild.DEPTH - 1.0)


func test_room_signs_sit_on_the_lintels() -> void:
	assert_eq(ClubhouseDecor.DOOR_SIGNS.size(), 7)
	for entry in ClubhouseDecor.DOOR_SIGNS:
		var at: Vector3 = entry["where"]
		assert_gt(at.y, 3.3, "%s belongs above the opening, not in the walk" % entry["title"])
		assert_lt(at.y, 5.3, "%s should still be on the wall, not the roof" % entry["title"])
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	assert_gte(house.get_tree().get_nodes_in_group("clubhouse_stairs").size(), 5)
	assert_eq(house.get_tree().get_nodes_in_group("clubhouse_art").size(), ClubhouseDecor.PLAQUES.size() + 2)
	assert_eq(house.get_tree().get_nodes_in_group("shop_stock").size(), 5)
	assert_gt(ClubhouseBuild.WALL, 5.0, "tall enough to read as a hall, not a shed")
	assert_gt(ClubhouseBuild.WIDTH, 30.0)
	assert_gt(ClubhouseBuild.DEPTH, 28.0)


func test_the_entrance_wears_the_crest() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var signs := house.get_tree().get_nodes_in_group("clubhouse_sign")
	assert_eq(signs.size(), 1)
	var sign: Node3D = signs[0]
	assert_gt(sign.position.z, ClubhouseBuild.DEPTH * 0.5, "the crest sits on the outside, facing the plaza")
	assert_gt(sign.position.y, ClubhouseBuild.WALL, "above the doors, not in the walk")
	for child in house.get_children():
		var copy := child as Label3D
		if copy != null:
			assert_ne(copy.text, "CLUBHOUSE", "the old word sign is gone")


func test_posters_hang_in_the_rooms() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var posters := house.get_tree().get_nodes_in_group("clubhouse_posters")
	assert_eq(posters.size(), 2)
	var foyer := 0
	var lounge := 0
	for poster in posters:
		assert_lt(absf(poster.position.z), ClubhouseBuild.DEPTH * 0.5 - ClubhouseBuild.THICK, "in the room, not the outer wall")
		assert_lt(absf(poster.position.x), ClubhouseBuild.HALL + 0.05, "on a hall wall, not a side room")
		var canvas := poster.get_node("Canvas") as MeshInstance3D
		assert_not_null(canvas)
		var mat := canvas.material_override as StandardMaterial3D
		assert_not_null(mat)
		assert_not_null(mat.albedo_texture)
		var quad := canvas.mesh as QuadMesh
		assert_not_null(quad)
		var px := mat.albedo_texture.get_size()
		assert_almost_eq(
			quad.size.x / quad.size.y, px.x / px.y, 0.01,
			"the board keeps the photo's full aspect, nothing cropped"
		)
		if poster.position.z > ClubhouseBuild.SPLIT_FRONT:
			foyer += 1
			assert_gt(absf(poster.position.z - 10.0), 2.0, "clear of the armory door")
		else:
			lounge += 1
			assert_gt(poster.position.y, 3.5, "course map sits above the lounge opening")
	assert_eq(foyer, 1)
	assert_eq(lounge, 1)


func test_the_ceiling_leds_are_orange() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var leds := house.get_tree().get_nodes_in_group("clubhouse_ceiling_led")
	assert_gt(leds.size(), 10, "every room wall should carry a cove strip")
	for led in leds:
		var mesh := led as MeshInstance3D
		assert_not_null(mesh)
		var mat := mesh.material_override as StandardMaterial3D
		assert_eq(mat.albedo_color, Palette.AMBER)
		assert_eq(mat.emission, Palette.AMBER)


func test_the_other_trim_is_baby_blue() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	var treads := house.get_tree().get_nodes_in_group("clubhouse_stairs")
	assert_gt(treads.size(), 4)
	for tread in treads:
		var mesh := tread as MeshInstance3D
		assert_not_null(mesh)
		var mat := mesh.material_override as StandardMaterial3D
		assert_eq(mat.albedo_color, Palette.BABY_BLUE)
		assert_eq(mat.emission, Palette.BABY_BLUE)


func test_regulars_chat_in_pairs_until_you_speak() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	assert_eq(house.npcs.size(), 6)
	for npc in house.npcs:
		assert_true(npc.is_paired(), npc.npc_name)
		assert_false(npc.is_addressing())
	await wait_process_frames(4)
	assert_gt(absf(house.npcs[0].gesture_deg()), 8.0, "they should already be talking with their hands")
	var who := Marker3D.new()
	house.add_child(who)
	who.position = house.npcs[0].position + Vector3(2.0, 0.0, 0.0)
	house.npcs[0].address(who)
	assert_true(house.npcs[0].is_addressing())
	house.npcs[0].stop_address()
	assert_false(house.npcs[0].is_addressing())


func test_each_shop_is_a_storefront_with_a_cashier() -> void:
	var house := Clubhouse.create(Vector3.ZERO, 0.0)
	add_child_autofree(house)
	assert_eq(house.cashiers.size(), 5)
	assert_eq(house.npcs.size(), 6, "cashiers are staff, not lounge regulars")
	assert_eq(house.comedy_count(), 2)
	for station in house.stations:
		assert_not_null(station.cashier, station.title)
		assert_gt(station.get_child_count(), 4, "%s should have a till and a cashier" % station.title)
		var to_wall := station.to_global(Vector3(0.0, 0.0, -2.0)) - station.global_position
		to_wall.y = 0.0
		var from_room := station.global_position
		from_room.y = 0.0
		assert_gt(
			(from_room + to_wall).length(), from_room.length(),
			"%s stock should sit against the outer wall" % station.title
		)
	assert_false(house.exit_open)
	assert_gt(house.door_point().distance_to(house.exit_point()), ClubhouseBuild.DEPTH - 1.0)
	var who := Marker3D.new()
	house.add_child(who)
	who.position = Vector3(0.0, 0.9, -ClubhouseBuild.DEPTH * 0.5)
	assert_true(house.can_open_exit(who))
	house.open_exit()
	assert_true(house.exit_open)
	assert_false(house.can_open_exit(who))
