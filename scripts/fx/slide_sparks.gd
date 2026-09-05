class_name SlideSparks
extends Node3D
## Friction specks scraped off the hull while sliding. Same primitives as HitFx,
## flying backward along the body like the shell is getting wrung.

const GROUP := "slide_sparks"
const RATE := 34.0
const LIFE := 0.2


var _debt := 0.0


func _process(delta: float) -> void:
	var player := get_parent() as Player
	if player == null or not player.is_sliding():
		queue_free()
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_debt += RATE * clampf(speed / PlayerSlide.SLIDE_SPEED, 0.35, 1.0) * delta
	while _debt >= 1.0:
		_debt -= 1.0
		flick(player)
		flick_toe(player)


static func attach(player: Player) -> SlideSparks:
	var live := player.get_node_or_null("SlideSparks") as SlideSparks
	if live != null:
		return live
	var fx := SlideSparks.new()
	fx.name = "SlideSparks"
	player.add_child(fx)
	return fx


static func detach(player: Player) -> void:
	var live := player.get_node_or_null("SlideSparks")
	if live != null:
		player.remove_child(live)
		live.free()


static func flick(player: Player) -> MeshInstance3D:
	var along := _along(player)
	var side := _side(player, along)
	return _emit(player, _scrape_at(player, along, side), along, side)


static func flick_toe(player: Player) -> MeshInstance3D:
	var along := _along(player)
	var side := _side(player, along)
	return _emit(player, _toe_at(player, along, side), along, side)


static func _emit(
	player: Player, at: Vector3, along: Vector3, side: Vector3
) -> MeshInstance3D:
	var host := player.get_parent()
	if host == null:
		return null
	var fly := -along * randf_range(0.45, 1.1) + side * randf_range(-0.55, 0.55)
	fly.y += randf_range(0.12, 0.42)
	var hot := randf() > 0.55
	var color := Palette.LED_WHITE if hot else Palette.AMBER
	var size := 0.05 if hot else 0.07
	var spark := MeshFactory.box(Vector3(size, size, 0.2), color, Palette.GLOW_STRONG)
	spark.add_to_group(GROUP)
	host.add_child(spark)
	spark.global_position = at
	if fly.length_squared() > 0.0001:
		spark.look_at(at + fly, Vector3.UP)
	var tween := spark.create_tween()
	tween.set_parallel()
	tween.tween_property(spark, "global_position", at + fly, LIFE)
	tween.tween_property(spark, "scale", Vector3(0.05, 0.05, 1.0), LIFE)
	tween.chain().tween_callback(spark.queue_free)
	return spark


static func _scrape_at(player: Player, along: Vector3, side: Vector3) -> Vector3:
	var t := randf()
	var at := player.global_position + Vector3.UP * lerpf(0.06, 0.52, t)
	if player.body != null and player.body.hips != null:
		at = player.body.hips.global_position
		if player.body.torso != null:
			at = at.lerp(player.body.torso.global_position, t)
	at += side * randf_range(-0.26, 0.26)
	at -= along * lerpf(0.05, 0.4, t)
	at.y = maxf(player.global_position.y + 0.04, at.y)
	return at


static func _toe_at(player: Player, along: Vector3, side: Vector3) -> Vector3:
	var at := player.global_position + along * 0.62 + Vector3.UP * 0.08
	if player.body != null:
		var toe := player.body.slide_toe()
		if toe != Vector3.INF:
			at = toe
	at += side * randf_range(-0.1, 0.1)
	at += along * randf_range(0.04, 0.14)
	at.y = maxf(player.global_position.y + 0.05, at.y)
	return at


static func _side(player: Player, along: Vector3) -> Vector3:
	var side := along.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = player.transform.basis.x
	return side.normalized()


static func _along(player: Player) -> Vector3:
	var dir := player.slide.along
	if dir.length_squared() < 0.04:
		dir = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if dir.length_squared() < 0.04:
		dir = -player.transform.basis.z
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
