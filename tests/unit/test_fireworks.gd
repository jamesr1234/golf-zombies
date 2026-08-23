extends GutTest
## A kill streak that keeps every burst alive is what buried Computer 2.


func after_each() -> void:
	for node in get_tree().get_nodes_in_group("fireworks"):
		node.remove_from_group("fireworks")
		node.queue_free()


func test_a_new_burst_culls_the_oldest_once_the_cap_is_full() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	for _i in Fireworks.MAX_LIVE:
		assert_not_null(Fireworks.spawn(root, Vector3.ZERO, Palette.LIME))
	assert_eq(get_tree().get_nodes_in_group("fireworks").size(), Fireworks.MAX_LIVE)
	assert_not_null(Fireworks.spawn(root, Vector3.UP, Palette.MAGENTA))
	assert_eq(
		get_tree().get_nodes_in_group("fireworks").size(), Fireworks.MAX_LIVE,
		"a massacre must not stack every burst"
	)


func test_cull_drops_the_oldest_first() -> void:
	var first := Fireworks.new()
	add_child_autofree(first)
	first.add_to_group("fireworks")
	var second := Fireworks.new()
	add_child_autofree(second)
	second.add_to_group("fireworks")
	assert_eq(Fireworks.cull_oldest(get_tree(), 1), 1)
	assert_false(first.is_in_group("fireworks"))
	assert_true(second.is_in_group("fireworks"))
