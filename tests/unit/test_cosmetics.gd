extends GutTest
## Cosmetic overlays on the robot: shirts, headbands, and shorts vs pants.

const ShopProps := preload("res://scripts/shop/shop_props.gd")
const InspectScript := preload("res://scripts/shop/shop_inspect.gd")


func test_shorts_and_pants_share_the_bottom_slot() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_bottom("shorts_amber", "shorts", Palette.AMBER)
	assert_eq(body.worn["bottom"], "shorts_amber")
	var shorts := body._bottoms.size()
	assert_gt(shorts, 4, "waist, stripes and hems, not just a box per thigh")
	body.wear_bottom("pants_ice", "pants", Palette.ICE)
	assert_eq(body.worn["bottom"], "pants_ice")
	assert_false(body.is_wearing("shorts_amber"))
	assert_gt(body._bottoms.size(), shorts, "pants keep going down the shin")


func test_shirt_and_headband_are_separate_slots() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	var before := body.cabin.size()
	body.wear_shirt("shirt_cyan", Palette.CYAN)
	body.wear_headband("band_lime", Palette.LIME)
	assert_true(body.is_wearing("shirt_cyan"))
	assert_true(body.is_wearing("band_lime"))
	assert_gt(body.cabin.size(), before)
	assert_false(body._shirts.is_empty())
	assert_false(body._headbands.is_empty())


func test_a_shirt_has_sleeves_and_a_leaning_chevron() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_shirt("shirt_violet", Palette.VIOLET)
	var sleeves := 0
	var tilted := 0
	for mesh in body._shirts:
		if body.arms.has(mesh.get_parent()):
			sleeves += 1
		if absf(mesh.rotation.z) > 0.2:
			tilted += 1
	assert_eq(sleeves, 2, "sleeves have to ride the arms")
	assert_gte(tilted, 2, "the chest chevron has to lean")


func test_a_headband_trails_a_streamer() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_headband("band_cyan", Palette.CYAN)
	var trailing := 0
	for mesh in body._headbands:
		if mesh.position.z > 0.08 and absf(mesh.rotation.x) + absf(mesh.rotation.z) > 0.3:
			trailing += 1
	assert_eq(trailing, 1, "the ribbon has to sit behind the skull and lean")


func test_shorts_keep_a_waist_on_the_hips() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_bottom("shorts_pink", "shorts", Palette.HOT_PINK)
	var on_hips := 0
	for mesh in body._bottoms:
		if mesh.get_parent() == body.hips:
			on_hips += 1
	assert_gte(on_hips, 2, "the waist stays planted while the legs stride")


func test_scrolling_a_shirt_tries_it_on_without_buying() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_shirt("shirt_cyan", Palette.CYAN)
	body.try_on(ShopStock.wear_by_id("shirt_violet"))
	assert_true(body.is_wearing("shirt_cyan"), "the rack is a preview, not a purchase")
	assert_false(body.is_wearing("shirt_violet"))
	assert_true(body.is_trying_on("shirt_violet"))
	assert_eq(_chest_color(body), Palette.VIOLET)
	body.clear_try_on()
	assert_false(body.is_trying_on("shirt_violet"))
	assert_eq(_chest_color(body), Palette.CYAN)


func test_previewing_pants_leaves_the_shirt_on() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.wear_shirt("shirt_cyan", Palette.CYAN)
	var shirts := body._shirts.size()
	body.try_on(ShopStock.wear_by_id("pants_ice"))
	assert_eq(body._shirts.size(), shirts, "a bottom preview should not strip the top")
	assert_true(body.is_trying_on("pants_ice"))
	assert_gt(body._bottoms.size(), 4)


func test_buying_the_preview_keeps_it_when_you_walk_off() -> void:
	var body := PlayerBody.new()
	add_child_autofree(body)
	body.build(Palette.PLAYER_ONE)
	body.try_on(ShopStock.wear_by_id("shirt_violet"))
	body.wear_shirt("shirt_violet", Palette.VIOLET)
	assert_true(body.is_wearing("shirt_violet"))
	assert_false(body.is_trying_on("shirt_violet"))
	body.clear_try_on()
	assert_true(body.is_wearing("shirt_violet"))
	assert_eq(_chest_color(body), Palette.VIOLET)


func test_the_try_on_camera_stands_in_front_of_the_robot() -> void:
	var origin := Vector3(5.0, 0.0, 10.0)
	var view := InspectScript.view_transform(origin, 0.0)
	assert_lt(view.origin.z, origin.z, "facing -Z, the camera sits on the chest side")
	assert_lt(view.origin.x, origin.x, "slid left so the robot sits on the right")
	assert_gt(view.origin.y, origin.y + 1.2, "pulled up so the whole robot is in frame")
	assert_gt((-view.basis.z).dot(Vector3.BACK), 0.7, "looking at the chest")


func test_the_apparel_wall_hangs_garments_not_boxes() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	ShopFront.wall_display(host, Shop.Dept.APPAREL, Vector3.ZERO, 0.0)
	var tilted := 0
	var rings := 0
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if absf(mesh.rotation.z) > 0.2:
			tilted += 1
		if mesh.mesh is TorusMesh:
			rings += 1
	assert_gte(tilted, 6, "sleeves, chevrons and streamers have to lean")
	assert_eq(rings, 2, "headbands hang as rings")


func test_the_armory_wall_hangs_guns_not_boxes() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	ShopFront.wall_display(host, Shop.Dept.WEAPONS, Vector3.ZERO, 0.0)
	var counts := _mesh_counts(host)
	assert_gte(counts["tilted"], 8, "barrels, grips and mounts have to lean")
	assert_gte(counts["cylinders"], 8, "barrels and coils, not slabs")
	assert_gte(counts["spheres"], 3, "muzzles and a warhead")
	assert_eq(counts["tori"], 1, "the net hangs as a hoop")
	assert_eq(_bobs(host), 8, "every gun turns on its hook")


func test_the_items_wall_shows_kits_not_boxes() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	ShopFront.wall_display(host, Shop.Dept.ITEMS, Vector3.ZERO, 0.0)
	var counts := _mesh_counts(host)
	assert_gte(counts["tilted"], 8, "a lid, a strap, clock hands and hex bars lean")
	assert_gte(counts["cylinders"], 3, "clock faces and a revive mast")
	assert_gte(counts["spheres"], 1, "the revive beacon")
	assert_eq(_bobs(host), 7, "every kit turns on its hook")


func test_the_cart_wall_shows_a_cart_not_boxes() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	ShopFront.wall_display(host, Shop.Dept.CART, Vector3.ZERO, 0.0)
	var counts := _mesh_counts(host)
	assert_gte(counts["wheels"], 4, "the display cart has to roll")
	assert_gte(counts["tilted"], 4, "ram, armor and jets lean off the deck")
	assert_gte(counts["spheres"], 2, "turbo exhaust")
	assert_eq(_bobs(host), 1, "the cart turns so you can read the upgrades")


func _bobs(host: Node3D) -> int:
	var n := 0
	for node in host.get_tree().get_nodes_in_group(ShopProps.BOB_GROUP):
		if host.is_ancestor_of(node):
			n += 1
	return n


func _chest_color(body: PlayerBody) -> Color:
	for mesh in body._shirts:
		if body.arms.has(mesh.get_parent()):
			continue
		var mat := mesh.material_override as StandardMaterial3D
		if mat != null:
			return mat.albedo_color
	return Color.BLACK


func _mesh_counts(host: Node3D) -> Dictionary:
	var counts := {"tilted": 0, "cylinders": 0, "spheres": 0, "tori": 0, "wheels": 0}
	for node in host.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		if (
			absf(mesh.rotation.x) > 0.2
			or absf(mesh.rotation.y) > 0.2
			or absf(mesh.rotation.z) > 0.2
		):
			counts["tilted"] += 1
		if mesh.mesh is CylinderMesh:
			counts["cylinders"] += 1
			if absf(mesh.rotation.z) > 1.2:
				counts["wheels"] += 1
		elif mesh.mesh is SphereMesh:
			counts["spheres"] += 1
		elif mesh.mesh is TorusMesh:
			counts["tori"] += 1
	return counts
