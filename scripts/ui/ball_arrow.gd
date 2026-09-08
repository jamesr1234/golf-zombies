class_name BallArrow
extends Control
## Neon waypoint for your ball. Sits on the screen edge when the lie is off
## camera or hidden behind scenery. Same night knockout and ice core as the
## swing meter, tinted with the seat colour.

const MARGIN := 32.0
const CHEVRON := 18.0
const BLOCKS := Layers.WORLD | Layers.PROP | Layers.BARRIER

var color := Palette.CYAN
var at := Vector3.ZERO
var camera: Camera3D
var tracking := false


func _draw() -> void:
	if not tracking or camera == null:
		return
	var local := camera.global_transform.affine_inverse() * at
	var dir := screen_dir(local)
	_waypoint(edge_point(Rect2(Vector2.ZERO, size), dir, MARGIN), dir)


static func allowed(player: Player, ball: GolfBall) -> bool:
	if player == null or ball == null or not ball.visible:
		return false
	if ball.is_holed() or ball.is_stowed() or ball.is_closed():
		return false
	if player.is_golfing() or player.wants_map() or player.shopping or player.talking:
		return false
	return ball.carrier() != player


static func on_screen(rect: Rect2, screen_pos: Vector2, behind: bool) -> bool:
	return not behind and rect.has_point(screen_pos)


static func occluded(world: World3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, BLOCKS, exclude)
	return not world.direct_space_state.intersect_ray(query).is_empty()


static func screen_dir(local: Vector3) -> Vector2:
	var dir := Vector2(local.x, -local.y)
	if dir.length_squared() < 0.0001:
		return Vector2.UP
	return dir.normalized()


static func edge_point(rect: Rect2, dir: Vector2, margin: float) -> Vector2:
	var inset := rect.grow(-margin)
	var center := inset.get_center()
	if dir.length_squared() < 0.0001:
		return center
	dir = dir.normalized()
	var half := inset.size * 0.5
	var tx := half.x / absf(dir.x) if absf(dir.x) > 0.0001 else INF
	var ty := half.y / absf(dir.y) if absf(dir.y) > 0.0001 else INF
	return center + dir * minf(tx, ty)


func _waypoint(tip: Vector2, dir: Vector2) -> void:
	var back := -dir
	var side := Vector2(-dir.y, dir.x)
	var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU)
	draw_circle(tip + back * 6.0, 16.0 + beat * 3.0, Color(color, 0.16 + beat * 0.1))
	_chevron(tip, dir, 1.18, Palette.NIGHT)
	_chevron(tip, dir, 1.0, Color(color, 0.95))
	_chevron(tip + dir * 1.2, dir, 0.58, Palette.ICE)
	var pip := tip + back * (CHEVRON * 0.72)
	draw_circle(pip, 4.2, Palette.NIGHT)
	draw_circle(pip, 2.6, color)
	draw_circle(pip, 1.1, Palette.ICE)


func _chevron(tip: Vector2, dir: Vector2, scale: float, tint: Color) -> void:
	var reach := CHEVRON * scale
	var back := -dir
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([
		tip,
		tip + back * reach + side * (reach * 0.55),
		tip + back * reach - side * (reach * 0.55),
	]), tint)
