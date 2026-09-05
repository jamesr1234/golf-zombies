class_name ClubhouseUpper
extends Object
## Second story: one open hall, a shaft hole for the elevator, and the roof.

const _Elevator := preload("res://scripts/shop/clubhouse_elevator.gd")
const _Poker := preload("res://scripts/shop/clubhouse_poker.gd")

const WOOD := {
	"base": Color(0.07, 0.03, 0.02), "line": Color(0.45, 0.28, 0.08),
	"cell": 1.6, "energy": 0.55, "scroll": 0.0, "fill": 0.16,
}


static func build(host: Clubhouse) -> void:
	_floor(host)
	_outer(host)
	_windows(host)
	_lights(host)
	_rug(host)
	_Poker.build(host)
	_roof(host)


static func _floor(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var thick := ClubhouseBuild.THICK
	var origin := _Elevator.shaft_origin()
	var hole := _Elevator.shaft_hole()
	var xmin := -w * 0.5 + thick
	var xmax := w * 0.5 - thick
	var zmin := -d * 0.5 + thick
	var zmax := d * 0.5 - thick
	var hx0 := origin.x - hole.x
	var hx1 := minf(origin.x + hole.x, xmax)
	var hz0 := origin.z - hole.z
	var hz1 := origin.z + hole.z
	var y := ClubhouseBuild.story_floor_y(1) - ClubhouseBuild.SLAB * 0.5
	_slab(host, xmin, hx0, zmin, zmax, y)
	_slab(host, hx1, xmax, zmin, zmax, y)
	_slab(host, hx0, hx1, zmin, hz0, y)
	_slab(host, hx0, hx1, hz1, zmax, y)


static func _slab(host: Clubhouse, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	var size := Vector3(x1 - x0, ClubhouseBuild.SLAB, z1 - z0)
	if size.x < 0.2 or size.z < 0.2:
		return
	var body := MeshFactory.box_body(size, Palette.WALL, Layers.WORLD, true, Palette.GLOW_FAINT)
	body.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
	body.add_to_group("clubhouse_upper_floor")
	MeshFactory.apply_grid(body, WOOD)
	host.add_child(body)


static func _outer(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var h := ClubhouseBuild.STORY_H
	var thick := ClubhouseBuild.THICK
	var mid := h + h * 0.5
	_wall(host, Vector3(-w * 0.5 + thick * 0.5, mid, 0.0), Vector3(thick, h, d))
	_wall(host, Vector3(w * 0.5 - thick * 0.5, mid, 0.0), Vector3(thick, h, d))
	_wall(host, Vector3(0.0, mid, d * 0.5 - thick * 0.5), Vector3(w, h, thick))
	_wall(host, Vector3(0.0, mid, -d * 0.5 + thick * 0.5), Vector3(w, h, thick))
	for corner in [-1.0, 1.0]:
		_wall(
			host,
			Vector3(corner * (w * 0.5 - 0.28), mid, d * 0.5 - 0.28),
			Vector3(0.55, h, 0.55)
		)
		_wall(
			host,
			Vector3(corner * (w * 0.5 - 0.28), mid, -d * 0.5 + 0.28),
			Vector3(0.55, h, 0.55)
		)


static func _windows(host: Clubhouse) -> void:
	var d := ClubhouseBuild.DEPTH
	var w := ClubhouseBuild.WIDTH
	var y := ClubhouseBuild.story_floor_y(1) + 2.15
	for z in [11.0, 6.0, -2.0, -11.0]:
		for side in [-1.0, 1.0]:
			var pane := MeshFactory.box(Vector3(0.08, 1.6, 1.1), Color(0.08, 0.18, 0.28), Palette.GLOW_FAINT)
			pane.position = Vector3(side * (w * 0.5 - 0.22), y, z)
			host.add_child(pane)
	var rear := MeshFactory.box(Vector3(2.4, 1.4, 0.08), Color(0.08, 0.18, 0.28), Palette.GLOW_FAINT)
	rear.position = Vector3(0.0, y, -d * 0.5 + 0.22)
	host.add_child(rear)


static func _lights(host: Clubhouse) -> void:
	var y := ClubhouseBuild.story_floor_y(1) + 3.4
	for at in [
		Vector3(0.0, y, 9.0), Vector3(-12.0, y, 9.0), Vector3(12.0, y, 9.0),
		Vector3(0.0, y, -1.0), Vector3(-12.0, y, -1.0), Vector3(12.0, y, -1.0),
		Vector3(0.0, y, -11.0), Vector3(-12.0, y, -11.0),
	]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.62, 0.28)
		lamp.light_energy = 0.7 if absf(at.x) > 8.0 else 0.42
		lamp.omni_range = 8.0
		lamp.position = at
		host.add_child(lamp)


static func _rug(host: Clubhouse) -> void:
	var at := Vector3(0.0, ClubhouseBuild.story_floor_y(1) + 0.03, -1.0)
	var rug := MeshFactory.box(Vector3(14.0, 0.04, 18.0), Color(0.16, 0.05, 0.12), 0.12)
	rug.position = at
	host.add_child(rug)
	var trim := MeshFactory.box(Vector3(14.16, 0.02, 18.16), ClubhouseDecor.BRASS, 0.2)
	trim.position = at + Vector3.DOWN * 0.01
	host.add_child(trim)


static func _roof(host: Clubhouse) -> void:
	var w := ClubhouseBuild.WIDTH
	var d := ClubhouseBuild.DEPTH
	var h := ClubhouseBuild.STORY_H * 2.0
	var roof := MeshFactory.box(Vector3(w + 0.8, ClubhouseBuild.SLAB, d + 0.8), Palette.WALL, Palette.GLOW_FAINT)
	roof.position.y = h + ClubhouseBuild.SLAB
	roof.add_to_group("clubhouse_roof")
	host.add_child(roof)
	var step := 2.2
	var x := -w * 0.5
	while x <= w * 0.5 + 0.01:
		for z_side in [-1.0, 1.0]:
			var merlon := MeshFactory.box(Vector3(0.7, 0.7, 0.4), Palette.WALL, Palette.GLOW_FAINT)
			merlon.position = Vector3(x, h + 0.7, z_side * (d * 0.5 + 0.15))
			merlon.add_to_group("clubhouse_roof")
			host.add_child(merlon)
		x += step


static func _wall(host: Clubhouse, at: Vector3, size: Vector3) -> void:
	var body := MeshFactory.box_body(size, Palette.WALL, Layers.PROP)
	body.position = at
	var strip := MeshFactory.box(
		Vector3(size.x * 1.02, size.y * 0.06, size.z * 1.02), Palette.AMBER, Palette.GLOW_FAINT
	)
	strip.position.y = size.y * 0.5 - size.y * 0.04
	strip.add_to_group("clubhouse_ceiling_led")
	body.add_child(strip)
	host.add_child(body)
