class_name HoleMap
extends Control
## Top-down of the hole you are standing on. Stationary course features plus
## you and the ball. No zombies.

const MARGIN := 18.0
const TITLE_BAND := 34.0
const LEGEND_BAND := 22.0
const PIN_RADIUS := 5.0
const YOU_RADIUS := 4.5
const BALL_RADIUS := 3.5
const BALL_COLOR := Color.WHITE
const MIN_PROP := 2.2
const BACK := Color(Palette.NIGHT, 0.9)
const FRAME := Color(Palette.CYAN, 0.7)

var hole: HoleData
var you := Vector3.ZERO
var you_color := Palette.CYAN
var ball := Vector3.ZERO
var has_ball := false

var _origin := Vector2.ZERO
var _scale := 1.0
var _local_rect := Rect2()


func _draw() -> void:
	if hole == null or size.x < 8.0 or size.y < 8.0:
		return
	_fit()
	draw_rect(Rect2(Vector2.ZERO, size), BACK)
	draw_rect(_playable_rect(), _fill(Surface.Type.ROUGH))
	for patch in _sorted_patches():
		_draw_patch(patch)
	for prop in hole.props:
		_draw_prop(prop)
	_draw_ball()
	_draw_pin()
	_draw_you()
	draw_rect(Rect2(Vector2.ZERO, size), FRAME, false, 2.0)
	_draw_title()
	_draw_legend()


## Screen position of a world point on this map. Tee sits toward the bottom,
## cup toward the top, so the hole reads the way you play it.
func project(point: Vector3) -> Vector2:
	_fit()
	return _to_screen(to_local(hole, point))


static func to_local(data: HoleData, point: Vector3) -> Vector2:
	var along := _along(data)
	var across := Vector2(-along.y, along.x)
	var offset := Vector2(point.x - data.tee.x, point.z - data.tee.z)
	return Vector2(offset.dot(across), offset.dot(along))


## Names of everything this overlay paints. Spawn points stay off on purpose.
static func drawn_kinds(data: HoleData) -> PackedStringArray:
	var kinds: PackedStringArray = ["tee", "cup"]
	for patch in data.patches:
		_append_unique(kinds, Surface.name_of(patch["type"]))
	for prop in data.props:
		_append_unique(kinds, String(prop["kind"]))
	return kinds


static func _along(data: HoleData) -> Vector2:
	var along := Vector2(data.cup.x - data.tee.x, data.cup.z - data.tee.z)
	if along.length_squared() < 0.0001:
		return Vector2.UP
	return along.normalized()


static func _append_unique(kinds: PackedStringArray, kind: String) -> void:
	if not kinds.has(kind):
		kinds.append(kind)


func _fit() -> void:
	if hole == null:
		return
	_local_rect = local_bounds(hole)
	var inner := _inner_rect()
	if _local_rect.size.x < 0.001 or _local_rect.size.y < 0.001 or inner.size.x < 1.0:
		_origin = inner.position
		_scale = 1.0
		return
	_scale = minf(inner.size.x / _local_rect.size.x, inner.size.y / _local_rect.size.y)
	var drawn := _local_rect.size * _scale
	_origin = inner.position + (inner.size - drawn) * 0.5


func _inner_rect() -> Rect2:
	return Rect2(
		Vector2(MARGIN, MARGIN + TITLE_BAND),
		size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + TITLE_BAND + LEGEND_BAND)
	)


func _playable_rect() -> Rect2:
	var top_left := _to_screen(Vector2(_local_rect.position.x, _local_rect.end.y))
	return Rect2(top_left, _local_rect.size * _scale)


func _to_screen(local: Vector2) -> Vector2:
	return Vector2(
		_origin.x + (local.x - _local_rect.position.x) * _scale,
		_origin.y + (_local_rect.end.y - local.y) * _scale
	)


static func local_bounds(data: HoleData) -> Rect2:
	var rect := Rect2(to_local(data, data.tee), Vector2.ZERO)
	rect = rect.expand(to_local(data, data.cup))
	var corners := [
		data.bounds.position,
		Vector2(data.bounds.end.x, data.bounds.position.y),
		data.bounds.end,
		Vector2(data.bounds.position.x, data.bounds.end.y),
	]
	for corner in corners:
		rect = rect.expand(to_local(data, Vector3(corner.x, 0.0, corner.y)))
	return rect.grow(4.0)


func _sorted_patches() -> Array:
	var patches := hole.patches.duplicate()
	patches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return Surface.PRIORITY[a["type"]] < Surface.PRIORITY[b["type"]]
	)
	return patches


func _draw_patch(patch: Dictionary) -> void:
	var type: Surface.Type = patch["type"]
	var practice := bool(patch.get("practice", false))
	var fill := _fill(type, practice)
	if patch["round"]:
		var center := project(patch["position"])
		var size: Vector2 = patch["size"]
		var edge := project(patch["position"] + Vector3(size.x * 0.5, 0.0, 0.0))
		var radius := maxf(2.0, center.distance_to(edge))
		draw_circle(center, radius, fill)
		if type == Surface.Type.GREEN and not practice:
			draw_arc(center, radius, 0.0, TAU, 32, Palette.LIME, 2.2)
		return
	var poly := _patch_polygon(patch)
	draw_colored_polygon(poly, fill)
	if type == Surface.Type.GREEN and not practice:
		var loop := PackedVector2Array(poly)
		loop.append(poly[0])
		draw_polyline(loop, Palette.LIME, 2.2)


func _patch_polygon(patch: Dictionary) -> PackedVector2Array:
	var size: Vector2 = patch["size"]
	var position: Vector3 = patch["position"]
	var yaw := deg_to_rad(patch["yaw"])
	var locals: Array[Vector3] = [
		Vector3(-size.x * 0.5, 0.0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0.0, -size.y * 0.5),
		Vector3(size.x * 0.5, 0.0, size.y * 0.5),
		Vector3(-size.x * 0.5, 0.0, size.y * 0.5),
	]
	var points := PackedVector2Array()
	for local in locals:
		var world: Vector3 = local.rotated(Vector3.UP, yaw) + position
		points.append(project(world))
	return points


func _draw_prop(prop: Dictionary) -> void:
	var kind: String = prop["kind"]
	var position: Vector3 = prop["position"]
	var size: Vector3 = prop["size"]
	var center := project(position)
	match kind:
		"tree":
			draw_circle(center, _prop_radius(size.x), Palette.TREE_CANOPY)
		"rock":
			var reach := Vector2(_prop_radius(size.x), _prop_radius(size.z))
			draw_rect(Rect2(center - reach, reach * 2.0), Palette.ROCK_TRIM)
		"tower":
			var reach := Vector2(_prop_radius(size.x * 0.7), _prop_radius(size.z * 0.7))
			draw_rect(Rect2(center - reach, reach * 2.0), Palette.TOWER_TRIM)
		"culvert":
			draw_colored_polygon(_wall_polygon(prop), Palette.AMBER)
		_:
			draw_colored_polygon(_wall_polygon(prop), Palette.WALL_TRIM)


func _wall_polygon(prop: Dictionary) -> PackedVector2Array:
	var size: Vector3 = prop["size"]
	var position: Vector3 = prop["position"]
	var yaw := deg_to_rad(prop["yaw"])
	var locals: Array[Vector3] = [
		Vector3(-size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, size.z * 0.5),
		Vector3(-size.x * 0.5, 0.0, size.z * 0.5),
	]
	var points := PackedVector2Array()
	for local in locals:
		points.append(project(local.rotated(Vector3.UP, yaw) + position))
	return points


func _prop_radius(metres: float) -> float:
	return maxf(MIN_PROP, metres * _scale)


func _draw_ball() -> void:
	if not has_ball:
		return
	var at := project(ball)
	draw_circle(at, BALL_RADIUS + 1.5, Palette.NIGHT)
	draw_circle(at, BALL_RADIUS, BALL_COLOR)


func _draw_pin() -> void:
	var at := project(hole.cup)
	draw_circle(at, PIN_RADIUS + 1.5, Palette.NIGHT)
	draw_circle(at, PIN_RADIUS, Palette.FLAG)


func _draw_you() -> void:
	var at := project(you)
	draw_circle(at, YOU_RADIUS + 1.5, Palette.NIGHT)
	draw_circle(at, YOU_RADIUS, you_color)


func _draw_title() -> void:
	var settings := HudStyle.banner(Palette.CYAN, 22)
	draw_string(
		settings.font, Vector2(0.0, 26.0), HudStyle.chrome(hole.label()),
		HORIZONTAL_ALIGNMENT_CENTER, size.x, settings.font_size, settings.font_color
	)


func _draw_legend() -> void:
	var settings := HudStyle.readout(Palette.ICE, 13)
	var y := size.y - 14.0
	var x := MARGIN + 4.0
	x = _legend_swatch(x, y, _fill(Surface.Type.BUNKER), "sand", settings)
	x = _legend_swatch(x, y, _fill(Surface.Type.WATER), "water", settings)
	x = _legend_swatch(x, y, _fill(Surface.Type.FRINGE), "fringe", settings)
	_legend_swatch(x, y, _fill(Surface.Type.GREEN), "green", settings)


func _legend_swatch(
	x: float, y: float, color: Color, label: String, settings: LabelSettings
) -> float:
	draw_rect(Rect2(x, y - 8.0, 10.0, 10.0), color)
	var text := HudStyle.chrome(label)
	draw_string(
		settings.font, Vector2(x + 14.0, y + 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, settings.font_size, settings.font_color
	)
	return x + 28.0 + settings.font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, settings.font_size
	).x


func _fill(type: Surface.Type, practice := false) -> Color:
	var look: Dictionary = Surface.look_of(type, practice)
	var color: Color = look["base"]
	color.a = 0.95
	return color.lerp(look["line"], 0.4)
