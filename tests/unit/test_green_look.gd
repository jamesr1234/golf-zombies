extends GutTest
## The putting surface has to read as a lime disk from the tee, not just once
## you are already standing on it.

const SEED := 20260816


func test_the_green_is_hotter_and_tighter_than_the_fairway() -> void:
	var green: Dictionary = Surface.LOOK[Surface.Type.GREEN]
	var fairway: Dictionary = Surface.LOOK[Surface.Type.FAIRWAY]
	var fringe: Dictionary = Surface.LOOK[Surface.Type.FRINGE]
	assert_gt(float(green["fill"]), float(fairway["fill"]), "fill is what still glows at range")
	assert_gt(float(green["fill"]), float(fringe["fill"]), "the collar cannot outshine the green")
	assert_gt(float(green["energy"]), float(fringe["energy"]))
	assert_lt(float(green["cell"]), float(fringe["cell"]), "the dance floor is the tightest grid")
	assert_gt(Color(green["base"]).g, Color(fairway["base"]).g)
	assert_gt(Color(green["line"]).g, Color(green["line"]).r + 0.15)
	assert_true(Surface.looks_like_green(Surface.Type.GREEN))
	assert_true(Surface.looks_like_green(Surface.Type.FRINGE))
	assert_false(Surface.looks_like_green(Surface.Type.FAIRWAY))


func test_the_green_grid_holds_together_from_the_tee() -> void:
	var look: Dictionary = Surface.LOOK[Surface.Type.GREEN]
	assert_gt(float(look["fade_end"]), Shot.max_carry() * 2.5,
		"a par five tee is farther than the default grid fade")
	var mat := MeshFactory.grid_material(look)
	assert_almost_eq(float(mat.get_shader_parameter("fade_end")), float(look["fade_end"]), 0.001)
	assert_almost_eq(float(mat.get_shader_parameter("fill_energy")), float(look["fill"]), 0.001)


func test_the_map_paints_the_green_brighter_than_the_fairway() -> void:
	var map := HoleMap.new()
	add_child_autofree(map)
	var green: Color = map._fill(Surface.Type.GREEN)
	var fairway: Color = map._fill(Surface.Type.FAIRWAY)
	var fringe: Color = map._fill(Surface.Type.FRINGE)
	assert_gt(green.g, fairway.g, "the overlay has to show where you putt")
	assert_gt(green.g, fringe.g)


func test_every_green_patch_wears_a_fog_proof_rim() -> void:
	var hole := HoleGenerator.generate(0, SEED)
	var built := HoleBuilder.build(hole)
	add_child_autofree(built)
	var rims := built.find_children("GreenRim", "Node3D", true, false)
	assert_eq(rims.size(), 2, "the hole green and the practice green both need a lip")
	var round_rims := 0
	var rect_rims := 0
	for rim in rims:
		assert_eq(rim.name, "GreenRim")
		var lamp := rim.get_node_or_null("GreenLamp") as OmniLight3D
		if _has_torus(rim):
			round_rims += 1
			assert_not_null(lamp, "the hole green needs a lamp once the grid has faded")
			assert_eq(lamp.light_color, Palette.LIME)
		else:
			rect_rims += 1
			assert_null(lamp, "a lamp on the practice green blows out the tee")
		for mesh in _meshes(rim):
			var mat := mesh.material_override as StandardMaterial3D
			assert_not_null(mat)
			assert_eq(mat.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
			assert_true(mat.disable_fog, "fog is what ate the pin on long holes")
	assert_eq(round_rims, 1, "the hole green is a round hoop")
	assert_eq(rect_rims, 1, "the practice green is a rectangular frame")


func test_the_practice_green_is_dimmer_than_the_hole_green() -> void:
	var practice: Dictionary = Surface.look_of(Surface.Type.GREEN, true)
	var hole: Dictionary = Surface.look_of(Surface.Type.GREEN, false)
	assert_lt(float(practice["fill"]), float(hole["fill"]) * 0.4,
		"the warm-up green sits under your feet")
	assert_lt(float(practice["energy"]), float(hole["energy"]))
	assert_gt(float(practice["fill"]), float(Surface.LOOK[Surface.Type.FAIRWAY]["fill"]),
		"it still has to read as a putting surface")
	var hole_data := HoleGenerator.generate(0, SEED)
	var tagged := 0
	for patch in hole_data.patches:
		if bool(patch.get("practice", false)):
			tagged += 1
			assert_eq(
				Surface.look_for(patch),
				Surface.look_of(patch["type"], true)
			)
	assert_eq(tagged, 2, "the practice green and its collar are the dim pair")


func test_a_round_green_sits_the_rim_on_its_edge() -> void:
	var patch := {
		"type": Surface.Type.GREEN,
		"position": Vector3(4.0, 2.0, -3.0),
		"size": Vector2(18.0, 18.0),
		"yaw": 0.0,
		"round": true,
	}
	var node := SurfacePatch.create(patch)
	add_child_autofree(node)
	var rim := node.get_node("GreenRim") as Node3D
	assert_not_null(rim)
	assert_almost_eq(
		rim.position.y,
		2.0 + Surface.DRAW_HEIGHT[Surface.Type.GREEN] + SurfacePatch.RIM_LIFT,
		0.001
	)
	var torus := _first_torus(rim)
	assert_not_null(torus)
	assert_almost_eq(torus.outer_radius, 9.0 + SurfacePatch.RIM_THICK * 0.6, 0.001)


func _has_torus(root: Node) -> bool:
	return _first_torus(root) != null


func _first_torus(root: Node) -> TorusMesh:
	for mesh in _meshes(root):
		var torus := mesh.mesh as TorusMesh
		if torus != null:
			return torus
	return null


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in root.find_children("*", "MeshInstance3D", true, false):
		found.append(child)
	return found
