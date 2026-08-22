extends GutTest
## The cup is a cavity, not a flat sticker. The ball has to be able to fall in.


func test_the_cup_is_a_well() -> void:
	var cup := Cup.create(Vector3.ZERO)
	add_child_autofree(cup)
	var well := cup.get_node("Well") as StaticBody3D
	assert_not_null(well, "walls and a floor so the ball can drop")
	assert_eq(well.collision_layer, Layers.CUP)
	assert_eq(well.collision_mask, 0)
	assert_gt(Cup.DEPTH, GolfBall.RADIUS * 2.0, "the ball has to fit below the lip")
	assert_lt(Cup.floor_top(), -GolfBall.RADIUS)


func test_players_do_not_collide_with_the_well() -> void:
	assert_eq(Layers.PLAYER_MASK & Layers.CUP, 0)
	assert_eq(Layers.BALL_MASK & Layers.CUP, 0, "the green still holds a fast putt")
