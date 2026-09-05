class_name ClubhouseDecor
extends Object
## Plaques, rugs, hanging lights, wall posters, and the neon crest over the doors.

const BRASS := Color(0.58, 0.4, 0.16)
const FAIRWAY_DREAMS := preload("res://assets/clubhouse/fairway_dreams.jpg")
const COSMIC_COURSE := preload("res://assets/clubhouse/cosmic_course.jpg")
const BOTSHOTS_CREST := preload("res://assets/clubhouse/botshots_crest.jpg")
const PLAQUES: Array[Dictionary] = [
	{"title": "Hole In One\n2084", "where": Vector3(-2.4, 2.2, 15.72), "yaw": 0.0},
	{"title": "Club Champion\nBogey Bill", "where": Vector3(2.4, 2.2, 15.72), "yaw": 0.0},
	{"title": "Course Record\n29  ·  Nine Holes", "where": Vector3(0.0, 3.4, 3.82), "yaw": 0.0},
	{"title": "Members Only\nAfter Dark", "where": Vector3(-12.0, 2.3, 15.72), "yaw": 0.0},
]
## Brass plates on the lintels, facing the room you are walking from.
const DOOR_SIGNS: Array[Dictionary] = [
	{"title": "Apparel", "where": Vector3(-5.78, 3.48, 10.0), "yaw": -90.0},
	{"title": "Armory", "where": Vector3(5.78, 3.48, 10.0), "yaw": 90.0},
	{"title": "Clubs", "where": Vector3(-5.78, 3.48, -1.0), "yaw": -90.0},
	{"title": "Items", "where": Vector3(5.78, 3.48, -1.0), "yaw": 90.0},
	{"title": "Cart", "where": Vector3(-5.78, 3.48, -11.0), "yaw": -90.0},
	{"title": "Elevator", "where": Vector3(5.78, 3.48, -11.0), "yaw": 90.0},
	{"title": "Lounge", "where": Vector3(0.0, 5.02, 4.22), "yaw": 0.0},
	{"title": "Next Hole", "where": Vector3(0.0, 5.05, -15.72), "yaw": 0.0},
]


static func build(host: Clubhouse) -> void:
	for entry in PLAQUES:
		_plaque(host, entry)
	for entry in DOOR_SIGNS:
		_door_sign(host, entry)
	_rug(host, Vector3(0.0, ClubhouseBuild.PLAZA_TOP + 0.03, 9.4), Vector2(6.4, 8.0), Color(0.18, 0.08, 0.22))
	_rug(
		host,
		Vector3(0.0, ClubhouseBuild.floor_y(true) + 0.03, -1.6),
		Vector2(7.2, 6.4), Color(0.22, 0.06, 0.1)
	)
	_rug(
		host,
		Vector3(-12.0, ClubhouseBuild.floor_y(true) + 0.03, -11.0),
		Vector2(6.4, 6.0), Color(0.06, 0.16, 0.14)
	)
	_chandelier(host, Vector3(0.0, 4.4, 9.0))
	_chandelier(host, Vector3(0.0, 4.8, -1.4))
	_chandelier(host, Vector3(0.0, 4.6, -11.0))
	_trophy(host, Vector3(-3.5, ClubhouseBuild.floor_y(true), -4.4))
	_hearth(host, Vector3(3.6, ClubhouseBuild.floor_y(true), -4.5))
	_bench(host, Vector3(-3.6, 0.0, 12.4), 0.0)
	_bench(host, Vector3(3.6, 0.0, 12.4), 180.0)
	_windows(host)
	_sconces(host)
	_clock(host, Vector3(0.0, 4.1, 15.72))
	var hall_face := ClubhouseBuild.HALL - ClubhouseBuild.THICK * 0.5 - 0.12
	var lounge_face := ClubhouseBuild.SPLIT_BACK + ClubhouseBuild.THICK * 0.5 + 0.12
	# Right-hand wall of the foyer, between the armory door and the entrance.
	_poster(host, FAIRWAY_DREAMS, Vector3(hall_face, 2.55, 13.8), -90.0, 3.7)
	# Across the lounge, above the opening to the exit hall.
	_poster(host, COSMIC_COURSE, Vector3(0.0, 4.5, lounge_face), 0.0, 7.6)
	_entrance_sign(host)


static func _door_sign(host: Clubhouse, entry: Dictionary) -> void:
	var root := Node3D.new()
	root.position = entry["where"]
	root.rotation.y = deg_to_rad(float(entry["yaw"]))
	var plate := MeshFactory.box(Vector3(1.45, 0.28, 0.05), Palette.WALL, 0.15)
	root.add_child(plate)
	var copy := Label3D.new()
	copy.text = String(entry["title"]).to_upper()
	copy.font_size = 20
	copy.modulate = BRASS
	copy.outline_size = 2
	copy.outline_modulate = Palette.NIGHT
	copy.position.z = 0.04
	root.add_child(copy)
	host.add_child(root)


static func _plaque(host: Clubhouse, entry: Dictionary) -> void:
	var root := Node3D.new()
	root.position = entry["where"]
	root.rotation.y = deg_to_rad(float(entry["yaw"]))
	root.add_to_group("clubhouse_art")
	var plate := MeshFactory.box(Vector3(1.15, 0.7, 0.06), BRASS, Palette.GLOW_FAINT)
	root.add_child(plate)
	var copy := Label3D.new()
	copy.text = String(entry["title"]).to_upper()
	copy.font_size = 20
	copy.modulate = Palette.NIGHT
	copy.position = Vector3(0.0, 0.0, 0.04)
	root.add_child(copy)
	host.add_child(root)


static func _rug(host: Clubhouse, at: Vector3, size: Vector2, color: Color) -> void:
	var rug := MeshFactory.box(Vector3(size.x, 0.04, size.y), color, 0.12)
	rug.position = at
	host.add_child(rug)
	var trim := MeshFactory.box(
		Vector3(size.x + 0.16, 0.02, size.y + 0.16), BRASS, 0.2
	)
	trim.position = at + Vector3.DOWN * 0.01
	host.add_child(trim)


static func _chandelier(host: Clubhouse, at: Vector3) -> void:
	var chain := MeshFactory.cylinder(0.03, 0.9, BRASS, Palette.GLOW_FAINT)
	chain.position = at + Vector3.UP * 0.45
	host.add_child(chain)
	var bowl := MeshFactory.cylinder(0.55, 0.16, BRASS, Palette.GLOW_FAINT)
	bowl.position = at
	host.add_child(bowl)
	for i in 5:
		var angle := TAU * float(i) / 5.0
		var lamp := MeshFactory.sphere(0.08, Color(1.0, 0.78, 0.45), Palette.GLOW_SOFT)
		lamp.position = at + Vector3(cos(angle) * 0.38, -0.18, sin(angle) * 0.38)
		host.add_child(lamp)


static func _trophy(host: Clubhouse, at: Vector3) -> void:
	var case := MeshFactory.box_body(
		Vector3(1.6, 1.5, 0.7), Color(0.12, 0.16, 0.18), Layers.PROP, true, 0.12
	)
	case.position = at + Vector3.UP * 0.75
	host.add_child(case)
	var cup := MeshFactory.cylinder(0.16, 0.45, BRASS, Palette.GLOW_SOFT)
	cup.position = at + Vector3.UP * 0.95
	host.add_child(cup)
	var plaque := Label3D.new()
	plaque.text = "CLUB CUP"
	plaque.font_size = 16
	plaque.modulate = BRASS
	plaque.position = at + Vector3(0.0, 1.7, 0.4)
	host.add_child(plaque)


static func _hearth(host: Clubhouse, at: Vector3) -> void:
	var mantle := MeshFactory.box_body(
		Vector3(1.8, 1.15, 0.55), Palette.WALL, Layers.PROP, true, Palette.GLOW_FAINT
	)
	mantle.position = at + Vector3.UP * 0.58
	host.add_child(mantle)
	var fire := MeshFactory.box(Vector3(0.9, 0.45, 0.2), Palette.AMBER, Palette.GLOW_SOFT)
	fire.position = at + Vector3(0.0, 0.38, 0.12)
	host.add_child(fire)
	var grate := MeshFactory.box(Vector3(1.05, 0.08, 0.28), Palette.NIGHT, 0.0)
	grate.position = at + Vector3(0.0, 0.12, 0.12)
	host.add_child(grate)


static func _bench(host: Clubhouse, at: Vector3, yaw: float) -> void:
	var seat := MeshFactory.box_body(
		Vector3(1.8, 0.38, 0.55), Palette.WALL, Layers.PROP, true, 0.1
	)
	seat.position = at + Vector3.UP * 0.22
	seat.rotation.y = deg_to_rad(yaw)
	host.add_child(seat)
	var back := MeshFactory.box(Vector3(1.8, 0.45, 0.08), BRASS, Palette.GLOW_FAINT)
	back.position = Vector3(0.0, 0.4, 0.22)
	seat.add_child(back)


static func _windows(host: Clubhouse) -> void:
	var d := ClubhouseBuild.DEPTH
	var w := ClubhouseBuild.WIDTH
	for z in [11.0, 6.0, -2.0, -11.0]:
		for side in [-1.0, 1.0]:
			var pane := MeshFactory.box(Vector3(0.08, 1.6, 1.1), Color(0.08, 0.18, 0.28), Palette.GLOW_FAINT)
			pane.position = Vector3(side * (w * 0.5 - 0.22), 2.4, z)
			host.add_child(pane)
	var rear := MeshFactory.box(Vector3(2.4, 1.4, 0.08), Color(0.08, 0.18, 0.28), Palette.GLOW_FAINT)
	rear.position = Vector3(-8.0, 2.6, -d * 0.5 + 0.22)
	host.add_child(rear)


static func _sconces(host: Clubhouse) -> void:
	for at in [
		Vector3(-5.78, 2.2, 11.4), Vector3(-5.78, 2.2, 8.6),
		Vector3(5.78, 2.2, 11.4), Vector3(5.78, 2.2, 8.6),
		Vector3(-5.78, 3.1, 0.4), Vector3(5.78, 3.1, 0.4),
		Vector3(-5.78, 3.1, -9.6), Vector3(-5.78, 3.1, -12.4),
		Vector3(-2.6, 3.1, -5.78), Vector3(2.6, 3.1, -5.78)
	]:
		var arm := MeshFactory.box(Vector3(0.08, 0.08, 0.22), BRASS, Palette.GLOW_FAINT)
		arm.position = at
		host.add_child(arm)
		var lamp := MeshFactory.sphere(0.09, Color(1.0, 0.72, 0.4), Palette.GLOW_SOFT)
		lamp.position = at + Vector3(0.0, -0.12, 0.0)
		host.add_child(lamp)


static func _clock(host: Clubhouse, at: Vector3) -> void:
	var face := MeshFactory.cylinder(0.42, 0.08, Palette.WALL, Palette.GLOW_FAINT)
	face.rotation.x = deg_to_rad(90.0)
	face.position = at
	host.add_child(face)
	var ring := MeshFactory.cylinder(0.46, 0.04, BRASS, Palette.GLOW_FAINT)
	ring.rotation.x = deg_to_rad(90.0)
	ring.position = at + Vector3(0.0, 0.0, 0.02)
	host.add_child(ring)
	var hand := MeshFactory.box(Vector3(0.04, 0.28, 0.03), BRASS, Palette.GLOW_FAINT)
	hand.position = at + Vector3(0.0, 0.08, 0.05)
	host.add_child(hand)


static func _photo_size(texture: Texture2D, width: float) -> Vector2:
	var px := texture.get_size()
	return Vector2(width, width * px.y / maxf(px.x, 1.0))


static func _poster(
	host: Clubhouse, texture: Texture2D, at: Vector3, yaw: float, width: float
) -> void:
	var size := _photo_size(texture, width)
	var root := Node3D.new()
	root.position = at
	root.rotation.y = deg_to_rad(yaw)
	root.add_to_group("clubhouse_art")
	root.add_to_group("clubhouse_posters")
	var frame := MeshFactory.box(Vector3(size.x + 0.16, size.y + 0.16, 0.06), BRASS, Palette.GLOW_FAINT)
	frame.position.z = -0.04
	root.add_child(frame)
	var quad := QuadMesh.new()
	quad.size = size
	var canvas := MeshInstance3D.new()
	canvas.name = "Canvas"
	canvas.mesh = quad
	canvas.position.z = 0.04
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = texture
	canvas.material_override = mat
	root.add_child(canvas)
	host.add_child(root)


static func _entrance_sign(host: Clubhouse) -> void:
	var width := 4.8
	var size := _photo_size(BOTSHOTS_CREST, width)
	var root := Node3D.new()
	root.name = "EntranceSign"
	root.add_to_group("clubhouse_sign")
	root.position = Vector3(
		0.0,
		ClubhouseBuild.WALL + size.y * 0.42,
		ClubhouseBuild.DEPTH * 0.5 + 0.55
	)
	var quad := QuadMesh.new()
	quad.size = size
	var canvas := MeshInstance3D.new()
	canvas.mesh = quad
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
uniform sampler2D tex : source_color;
void fragment() {
	vec4 c = texture(tex, UV);
	float glow = max(max(c.r, c.g), c.b);
	ALBEDO = c.rgb;
	EMISSION = c.rgb;
	ALPHA = smoothstep(0.05, 0.2, glow);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tex", BOTSHOTS_CREST)
	canvas.material_override = mat
	root.add_child(canvas)
	host.add_child(root)
