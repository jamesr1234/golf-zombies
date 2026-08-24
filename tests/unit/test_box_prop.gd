extends GutTest
## Rocks and walls are sparse enough to be real prop nodes.

const _Box := preload("res://scripts/course/box_prop.gd")


func test_a_rock_is_solid_and_sits_on_the_ground() -> void:
	var rock := _Box.create({
		"kind": "rock",
		"position": Vector3(5.0, 1.0, 8.0),
		"size": Vector3(2.0, 1.4, 2.0),
		"yaw": 30.0,
	})
	add_child_autofree(rock)
	assert_eq(rock.collision_layer, Layers.PROP)
	assert_eq(rock.kind, "rock")
	assert_almost_eq(rock.position.y, 1.0, 0.001)
	var shape := rock.get_child(0) as CollisionShape3D
	assert_not_null(shape)
	assert_almost_eq(shape.position.y, 0.7, 0.001)


func test_the_builder_makes_a_rock_from_hole_data() -> void:
	var rock := HoleBuilder.create_prop({
		"kind": "rock",
		"position": Vector3(3.0, 2.0, 5.0),
		"size": Vector3(1.6, 1.0, 1.6),
		"yaw": 15.0,
	})
	add_child_autofree(rock)
	assert_eq(rock.get_script(), _Box)
	assert_eq(String(rock.get("kind")), "rock")
	assert_almost_eq(rock.position.y, 2.0, 0.001)
