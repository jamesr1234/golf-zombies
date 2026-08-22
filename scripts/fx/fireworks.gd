class_name Fireworks
extends Node3D
## Neon burst left behind when a zombie is destroyed. A fat flash, a shell of
## streaks, and a second crackle of sparks: no particles system, just the same
## primitives everything else is built from, turned up loud.

const LIFE := 1.7
const SPARK_COUNT := 28
const STREAK_COUNT := 22
const CRACKLE_COUNT := 16
const SPEED := 24.0
const STREAK_SPEED := 18.0
const CRACKLE_SPEED := 10.0
const GRAVITY := 8.0
const FLASH_PEAK := 2.8
const FLASH_GROW := 0.1
const CRACKLE_AT := 0.16
const GLOW := 8.0

const COLORS: Array[Color] = [
	Palette.MAGENTA, Palette.LIME, Palette.CYAN,
	Palette.AMBER, Palette.VIOLET, Palette.ICE, Palette.HOT_PINK,
]


static func spawn(root: Node, at: Vector3, tint: Color) -> Fireworks:
	var host := root
	if host == null or not host.is_inside_tree():
		return null
	var burst := Fireworks.new()
	host.add_child(burst)
	burst.global_position = at
	burst._build(tint)
	return burst


## Evenly spaced directions around a sphere, with a slight upward bias so the
## burst reads as fireworks rather than a ground splash.
static func spark_velocity(index: int, total: int, speed := SPEED) -> Vector3:
	var golden := PI * (3.0 - sqrt(5.0))
	var y := 1.0 - (float(index) / float(maxi(1, total - 1))) * 2.0
	var radius := sqrt(maxf(0.0, 1.0 - y * y))
	var theta := golden * float(index)
	var dir := Vector3(cos(theta) * radius, y + 0.35, sin(theta) * radius).normalized()
	return dir * speed


var _age := 0.0
var _tint: Color
var _flash: MeshInstance3D
var _lamp: OmniLight3D
var _sparks: Array[Node3D] = []
var _vel: Array[Vector3] = []
var _streaks: Array[Node3D] = []
var _crackled := false


func piece_count() -> int:
	return _sparks.size() + (1 if _flash != null else 0)


func _build(tint: Color) -> void:
	add_to_group("fireworks")
	_tint = tint
	_flash = MeshFactory.sphere(0.7, tint, GLOW)
	add_child(_flash)
	_lamp = OmniLight3D.new()
	_lamp.light_color = tint.lerp(Color.WHITE, 0.35)
	_lamp.light_energy = 18.0
	_lamp.omni_range = 28.0
	add_child(_lamp)
	_add_sparks(SPARK_COUNT, SPEED, 0.22)
	for i in STREAK_COUNT:
		var color: Color = COLORS[i % COLORS.size()] if i % 2 != 0 else tint
		var streak := MeshFactory.box(Vector3(0.07, 0.07, 1.35), color, GLOW)
		add_child(streak)
		_streaks.append(streak)
		_sparks.append(streak)
		_vel.append(spark_velocity(i, STREAK_COUNT, STREAK_SPEED))


func _add_sparks(count: int, speed: float, size: float) -> void:
	for i in count:
		var color: Color = COLORS[i % COLORS.size()] if i % 3 != 0 else _tint
		var spark: MeshInstance3D
		if i % 2 == 0:
			spark = MeshFactory.box(Vector3(size, size, size), color, GLOW)
		else:
			spark = MeshFactory.sphere(size * 0.7, color, GLOW)
		add_child(spark)
		_sparks.append(spark)
		_vel.append(spark_velocity(i, count, speed))


func _process(delta: float) -> void:
	_age += delta
	var fade := 1.0 - clampf(_age / LIFE, 0.0, 1.0)
	if not _crackled and _age >= CRACKLE_AT:
		_crackled = true
		_add_sparks(CRACKLE_COUNT, CRACKLE_SPEED, 0.14)
	_pose_flash(fade)
	for i in _sparks.size():
		_vel[i].y -= GRAVITY * delta
		_sparks[i].position += _vel[i] * delta
		_sparks[i].scale = Vector3.ONE * maxf(0.08, fade)
	for streak in _streaks:
		_point_streak(streak)
	if _age >= LIFE:
		queue_free()


func _pose_flash(fade: float) -> void:
	var grow := ease(clampf(_age / FLASH_GROW, 0.0, 1.0), 0.3)
	_flash.scale = Vector3.ONE * (0.4 + FLASH_PEAK * grow) * maxf(0.05, fade)
	_lamp.light_energy = 18.0 * fade * (1.0 + 0.35 * sin(_age * 42.0) * fade)
	_lamp.omni_range = 28.0 * maxf(0.2, fade)


func _point_streak(streak: Node3D) -> void:
	var index := _sparks.find(streak)
	if index < 0 or _vel[index].length_squared() < 0.04:
		return
	var dir := _vel[index]
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.98:
		up = Vector3.RIGHT
	var tip := streak.global_position + dir
	if tip.is_equal_approx(streak.global_position):
		return
	streak.look_at(tip, up)
