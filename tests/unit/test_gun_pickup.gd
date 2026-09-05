extends GutTest
## World guns go in the bag on contact and stay off the maze pack.

const PLAYER := preload("res://scenes/players/player.tscn")
const SCENE := preload("res://scenes/course/props/gun_pickup.tscn")
const ROCKET: WeaponStats = preload("res://resources/weapons/rocket.tres")
const RIFLE: WeaponStats = preload("res://resources/weapons/rifle.tres")
const _Overlay := preload("res://scripts/course/hole_overlay.gd")


func test_the_scene_is_a_placeable_rocket() -> void:
	assert_true(ResourceLoader.exists("res://scenes/course/props/gun_pickup.tscn"))
	var pickup: GunPickup = SCENE.instantiate()
	add_child_autofree(pickup)
	assert_eq(pickup.stats, ROCKET)
	assert_eq(pickup.collision_layer, Layers.PICKUP)
	assert_eq(pickup.collision_mask, Layers.PLAYER)
	assert_gt(pickup.get_child_count(), 1, "the rocket mesh has to be visible")
	var mark := Node3D.new()
	add_child_autofree(mark)
	Raygun.build_rocket(mark, Palette.PLAYER_ONE)
	var vis: Node3D = null
	for child in pickup.get_children():
		if child is Node3D and child.get_child_count() == mark.get_child_count():
			vis = child
			break
	assert_not_null(vis)
	assert_eq(vis.get_child_count(), mark.get_child_count())
	for i in mark.get_child_count():
		var want := mark.get_child(i) as MeshInstance3D
		var got := vis.get_child(i) as MeshInstance3D
		assert_not_null(want)
		assert_not_null(got)
		assert_eq(want.mesh.get_class(), got.mesh.get_class())
		assert_eq(want.position, got.position)


func test_walking_in_puts_the_rocket_in_the_bag() -> void:
	var pickup: GunPickup = SCENE.instantiate()
	add_child_autofree(pickup)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	assert_false(player.weapon.has_weapon())
	pickup._on_body_entered(player)
	assert_true(player.weapon.has_gun(ROCKET))
	assert_eq(player.weapon.stats(), ROCKET)
	assert_true(pickup.is_queued_for_deletion())


func test_a_second_touch_leaves_it_for_someone_else() -> void:
	var pickup: GunPickup = SCENE.instantiate()
	add_child_autofree(pickup)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	assert_true(player.weapon.add_gun(ROCKET))
	pickup._on_body_entered(player)
	assert_false(pickup.is_queued_for_deletion(), "the partner still needs a shot at it")


func test_a_different_gun_still_takes_the_rocket() -> void:
	var pickup: GunPickup = SCENE.instantiate()
	add_child_autofree(pickup)
	var player: Player = PLAYER.instantiate()
	add_child_autofree(player)
	assert_true(player.weapon.add_gun(RIFLE))
	pickup._on_body_entered(player)
	assert_true(player.weapon.has_gun(RIFLE))
	assert_true(player.weapon.has_gun(ROCKET))
	assert_eq(player.weapon.stats(), ROCKET)
	assert_true(pickup.is_queued_for_deletion())


func test_hole_ten_leaves_the_rocket_outside_the_maze() -> void:
	var packed := load("res://scenes/course/holes/hole_10.tscn") as PackedScene
	var root: Node3D = packed.instantiate()
	add_child_autofree(root)
	var maze := root.find_child("Maze", true, false) as Maze
	assert_not_null(maze)
	var guns := root.find_children("*", "GunPickup", true, false)
	assert_eq(guns.size(), 1)
	var pickup := guns[0] as GunPickup
	assert_eq(pickup.stats, ROCKET)
	assert_false(
		maze.roam_aabb().has_point(pickup.global_position),
		"the launcher sits outside the pack yard"
	)


func test_overlay_harvest_skips_the_pickup() -> void:
	var overlay := Node3D.new()
	add_child_autofree(overlay)
	var pickup: GunPickup = SCENE.instantiate()
	pickup.name = "GunPickup"
	pickup.position = Vector3(4.0, 1.0, -12.0)
	overlay.add_child(pickup)
	var data := HoleData.new()
	_Overlay.collect_into(data, overlay)
	assert_eq(data.props.size(), 0)
	assert_eq(data.jumps.size(), 0)
