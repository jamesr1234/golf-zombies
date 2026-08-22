class_name ClubhouseShell
extends Object
## Outer walls, inner rooms, the raised hall and the stairs that reach it.

static func build(host: Clubhouse) -> void:
	_floors(host)
	_outer(host)
	_inner(host)
	_stairs(host)
	_columns(host)
	_roof(host)


static func _floors(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var thick := ClubhouseBuild.THICK
	var raise := ClubhouseBuild.RAISE
	var split := ClubhouseBuild.SPLIT_FRONT
	var floor := MeshFactory.box(Vector3(w, 0.08, d), Palette.WALL, Palette.GLOW_FAINT)
	floor.position.y = ClubhouseBuild.FLOOR_Y
	host.add_child(floor)
	var z0 := -d * 0.5 + thick
	var z1 := split
	var pad := MeshFactory.box_body(
		Vector3(w - thick * 2.0, raise, z1 - z0), Palette.WALL, Layers.WORLD, true, Palette.GLOW_FAINT
	)
	pad.position = Vector3(0.0, ClubhouseBuild.PLAZA_TOP + raise * 0.5, (z0 + z1) * 0.5)
	MeshFactory.apply_grid(pad, {
		"base": Color(0.07, 0.03, 0.02), "line": Color(0.45, 0.28, 0.08),
		"cell": 1.6, "energy": 0.55, "scroll": 0.0, "fill": 0.16,
	})
	host.add_child(pad)


static func _outer(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var h := ClubhouseBuild.WALL
	var thick := ClubhouseBuild.THICK
	var door := ClubhouseBuild.DOOR
	_wall(host, Vector3(-w * 0.5 + thick * 0.5, h * 0.5, 0.0), Vector3(thick, h, d))
	_wall(host, Vector3(w * 0.5 - thick * 0.5, h * 0.5, 0.0), Vector3(thick, h, d))
	var wing := (w - door) * 0.5
	var wing_x := w * 0.5 - wing * 0.5
	for z_sign in [1.0, -1.0]:
		var door_z := float(z_sign) * (d * 0.5 - thick * 0.5)
		_wall(host, Vector3(-wing_x, h * 0.5, door_z), Vector3(wing, h, thick))
		_wall(host, Vector3(wing_x, h * 0.5, door_z), Vector3(wing, h, thick))
		var lintel := MeshFactory.box_body(
			Vector3(door + 0.3, 0.45, thick), Palette.BABY_BLUE, Layers.PROP, true, Palette.GLOW_FAINT
		)
		lintel.position = Vector3(0.0, h - 0.28, door_z)
		host.add_child(lintel)
	for corner in [-1.0, 1.0]:
		_wall(
			host,
			Vector3(corner * (w * 0.5 - 0.28), h * 0.5, d * 0.5 - 0.28),
			Vector3(0.55, h, 0.55)
		)
		_wall(
			host,
			Vector3(corner * (w * 0.5 - 0.28), h * 0.5, -d * 0.5 + 0.28),
			Vector3(0.55, h, 0.55)
		)


static func _inner(host: Clubhouse) -> void:
	var h := ClubhouseBuild.WALL
	var hall := ClubhouseBuild.HALL
	var front := ClubhouseBuild.SPLIT_FRONT
	var back := ClubhouseBuild.SPLIT_BACK
	var d := ClubhouseBuild.DEPTH
	var w := ClubhouseBuild.WIDTH
	var open := ClubhouseBuild.OPEN
	# Hall walls: apparel and armory off the foyer, clubs and items off the lounge.
	_gate_z(host, -hall, 10.0, d * 0.5 - front, h, open, 3.3)
	_gate_z(host, hall, 10.0, d * 0.5 - front, h, open, 3.3)
	_gate_z(host, -hall, -1.0, front - back, h, open, 3.3)
	_gate_z(host, hall, -1.0, front - back, h, open, 3.3)
	_gate_z(host, -hall, -11.0, front - back, h, open, 3.3)
	_gate_z(host, hall, -11.0, front - back, h, open, 3.3)
	# Front of the raised hall stays closed in the wings so you take the stairs.
	var wing := (w * 0.5 - hall)
	_wall(host, Vector3(-(hall + wing * 0.5), h * 0.5, front), Vector3(wing, h, ClubhouseBuild.THICK))
	_wall(host, Vector3(hall + wing * 0.5, h * 0.5, front), Vector3(wing, h, ClubhouseBuild.THICK))
	_arch(host, Vector3(0.0, h * 0.5, front), hall * 2.0, h)
	_gate_x(host, 0.0, back, hall * 2.0, h, 4.6, 3.4)
	_wall(host, Vector3(-(hall + wing * 0.5), h * 0.5, back), Vector3(wing, h, ClubhouseBuild.THICK))
	_wall(host, Vector3(hall + wing * 0.5, h * 0.5, back), Vector3(wing, h, ClubhouseBuild.THICK))


## A wall on X=const with a doorway punched at `open_z`.
static func _gate_z(
	host: Clubhouse, x: float, open_z: float, length: float, height: float, open_w: float, open_h: float
) -> void:
	var side := maxf(0.6, (length - open_w) * 0.5)
	_wall(host, Vector3(x, height * 0.5, open_z - (open_w + side) * 0.5), Vector3(ClubhouseBuild.THICK, height, side))
	_wall(host, Vector3(x, height * 0.5, open_z + (open_w + side) * 0.5), Vector3(ClubhouseBuild.THICK, height, side))
	var lintel_h := maxf(0.35, height - open_h)
	_wall(host, Vector3(x, open_h + lintel_h * 0.5, open_z), Vector3(ClubhouseBuild.THICK, lintel_h, open_w + 0.2))


## A wall on Z=const with a doorway punched at `open_x`.
static func _gate_x(
	host: Clubhouse, open_x: float, z: float, length: float, height: float, open_w: float, open_h: float
) -> void:
	var side := maxf(0.6, (length - open_w) * 0.5)
	_wall(host, Vector3(open_x - (open_w + side) * 0.5, height * 0.5, z), Vector3(side, height, ClubhouseBuild.THICK))
	_wall(host, Vector3(open_x + (open_w + side) * 0.5, height * 0.5, z), Vector3(side, height, ClubhouseBuild.THICK))
	var lintel_h := maxf(0.35, height - open_h)
	_wall(host, Vector3(open_x, open_h + lintel_h * 0.5, z), Vector3(open_w + 0.2, lintel_h, ClubhouseBuild.THICK))


static func _arch(host: Clubhouse, at: Vector3, width: float, height: float) -> void:
	var lintel_h := 0.5
	_wall(
		host,
		Vector3(at.x, height - lintel_h * 0.5, at.z),
		Vector3(width, lintel_h, ClubhouseBuild.THICK)
	)
	for side in [-1.0, 1.0]:
		_wall(
			host,
			Vector3(at.x + side * (width * 0.5 - 0.18), height * 0.5, at.z),
			Vector3(0.36, height, ClubhouseBuild.THICK)
		)


static func _stairs(host: Clubhouse) -> void:
	var raise := ClubhouseBuild.RAISE
	var run := 3.5
	var z1 := ClubhouseBuild.SPLIT_FRONT
	var z0 := z1 + run
	var angle := atan(raise / run)
	var hyp := sqrt(run * run + raise * raise)
	var ramp := MeshFactory.box_body(
		Vector3(5.2, 0.18, hyp), Palette.WALL, Layers.WORLD, false
	)
	ramp.rotation.x = angle
	ramp.position = Vector3(
		0.0, ClubhouseBuild.PLAZA_TOP + raise * 0.5, (z0 + z1) * 0.5
	)
	host.add_child(ramp)
	var steps := 6
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var tread := MeshFactory.box(Vector3(5.0, 0.1, 0.48), Palette.BABY_BLUE, Palette.GLOW_FAINT)
		tread.position = Vector3(
			0.0, ClubhouseBuild.PLAZA_TOP + raise * t + 0.07, lerpf(z0, z1, t)
		)
		tread.add_to_group("clubhouse_stairs")
		host.add_child(tread)
	for side in [-1.0, 1.0]:
		var rail := MeshFactory.box_body(
			Vector3(0.12, 0.7, run), Palette.WALL, Layers.PROP, true, Palette.GLOW_FAINT
		)
		rail.position = Vector3(side * 2.7, ClubhouseBuild.PLAZA_TOP + raise * 0.5 + 0.4, (z0 + z1) * 0.5)
		host.add_child(rail)


static func _columns(host: Clubhouse) -> void:
	var h := ClubhouseBuild.WALL - 0.4
	for at in [
		Vector3(-4.6, 0.0, 12.2), Vector3(4.6, 0.0, 12.2),
		Vector3(-4.6, 0.0, 6.4), Vector3(4.6, 0.0, 6.4),
		Vector3(-4.6, ClubhouseBuild.RAISE, -3.4), Vector3(4.6, ClubhouseBuild.RAISE, -3.4)
	]:
		var col := MeshFactory.cylinder_body(0.28, h, Palette.WALL, Layers.PROP, Palette.GLOW_FAINT)
		col.position = at + Vector3.UP * (h * 0.5)
		var cap := MeshFactory.box(Vector3(0.7, 0.12, 0.7), Palette.BABY_BLUE, Palette.GLOW_FAINT)
		cap.position.y = h * 0.5
		col.add_child(cap)
		host.add_child(col)


static func _roof(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var h := ClubhouseBuild.WALL
	var roof := MeshFactory.box(Vector3(w + 0.8, 0.28, d + 0.8), Palette.WALL, Palette.GLOW_FAINT)
	roof.position.y = h + 0.28
	host.add_child(roof)
	var step := 2.2
	var x := -w * 0.5
	while x <= w * 0.5 + 0.01:
		for z_side in [-1.0, 1.0]:
			var merlon := MeshFactory.box(Vector3(0.7, 0.7, 0.4), Palette.WALL, Palette.GLOW_FAINT)
			merlon.position = Vector3(x, h + 0.7, z_side * (d * 0.5 + 0.15))
			host.add_child(merlon)
		x += step


static func _wall(host: Clubhouse, at: Vector3, size: Vector3) -> void:
	var body := MeshFactory.box_body(size, Palette.WALL, Layers.PROP)
	body.position = at
	# Cove LED along the ceiling line, so the hall reads as rooms instead of a box.
	var strip := MeshFactory.box(
		Vector3(size.x * 1.02, size.y * 0.06, size.z * 1.02), Palette.AMBER, Palette.GLOW_FAINT
	)
	strip.position.y = size.y * 0.5 - size.y * 0.04
	strip.add_to_group("clubhouse_ceiling_led")
	body.add_child(strip)
	host.add_child(body)
