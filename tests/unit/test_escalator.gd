extends GutTest
## An escalator carries you up until someone at the top reverses the belt.

const CELL := 1.35
const GLB := "res://assets/obstacles/escalator_large.glb"
const _Escalator := preload("res://scripts/course/escalator.gd")


func test_attach_binds_the_glb() -> void:
	var host: Node3D = _spawn(GLB)
	var lift := _Escalator.attach(host)
	assert_not_null(lift)
	assert_true(lift.is_in_group("escalators"))
	assert_eq(lift.sync_dir, 1)
	assert_gt(lift.carry_along().y, 0.0, "default belt runs up")


func test_reverse_flips_the_carry() -> void:
	var host: Node3D = _spawn(GLB)
	var lift := _Escalator.attach(host)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = lift.button_at()
	assert_true(lift.can_use(dummy))
	var up := lift.carry_along()
	lift.try_reverse(dummy)
	var down := lift.carry_along()
	assert_eq(lift.sync_dir, -1)
	assert_almost_eq(down.x, -up.x, 0.001)
	assert_almost_eq(down.y, -up.y, 0.001)
	assert_almost_eq(down.z, -up.z, 0.001)
	assert_lt(down.y, 0.0)


func test_the_button_is_only_at_the_top() -> void:
	var host: Node3D = _spawn(GLB)
	var lift := _Escalator.attach(host)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = lift.button_at()
	assert_true(lift.can_use(dummy))
	dummy.global_position = host.to_global(Vector3(CELL, 0.2, 0.0))
	assert_false(lift.can_use(dummy), "the latch is at the top, not the toe")


func test_a_press_out_of_range_is_ignored() -> void:
	var host: Node3D = _spawn(GLB)
	var lift := _Escalator.attach(host)
	var dummy := Node3D.new()
	add_child_autofree(dummy)
	dummy.global_position = host.to_global(Vector3(CELL, 0.2, 0.0))
	assert_eq(lift.sync_dir, 1)
	lift.try_reverse(dummy)
	assert_eq(lift.sync_dir, 1)


func test_adopt_finds_placed_escalators() -> void:
	var host: Node3D = _spawn(GLB)
	host.remove_meta("_escalators_bound")
	_Escalator.adopt(host)
	assert_not_null(host.get_node_or_null("Escalator"))


func test_attach_works_before_the_host_is_in_the_tree() -> void:
	var host: Node3D = (load(GLB) as PackedScene).instantiate()
	var lift := _Escalator.attach(host)
	assert_not_null(lift)
	add_child_autofree(host)
	assert_gt(lift.carry_along().y, 0.0)


func _spawn(path: String) -> Node3D:
	var node: Node3D = (load(path) as PackedScene).instantiate()
	add_child_autofree(node)
	return node
