class_name CartMine
extends Node3D
## A puck on the turf. Arms after the cart has rolled off, then pops the first
## hostile walker that steps on it.

const COLOR := Palette.LED_RED
const BODY := Color(0.08, 0.09, 0.12)
const GROUP := "cart_mines"

var visual_only := false
var _arm_left := CartMines.ARM_TIME
var _dead := false
var _lamp: OmniLight3D


static func deploy(root: Node, at: Vector3, p_visual_only := false) -> CartMine:
	if root == null:
		return null
	var mine := CartMine.new()
	mine.visual_only = p_visual_only
	mine.add_to_group(GROUP)
	root.add_child(mine)
	mine.global_position = at
	mine._build()
	return mine


func is_armed() -> bool:
	return not _dead and _arm_left <= 0.0


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _arm_left > 0.0:
		_arm_left = maxf(0.0, _arm_left - delta)
	_blink()
	if visual_only or not is_armed():
		return
	if _stepper() != null:
		_explode()


func _stepper() -> Zombie:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not is_instance_valid(zombie) or zombie.is_dying():
			continue
		if zombie.is_allied():
			continue
		var centre := zombie.global_position + Vector3.UP * zombie.stats.height * 0.2
		var flat := Vector2(centre.x - global_position.x, centre.z - global_position.z)
		if flat.length() <= CartMines.TRIGGER:
			return zombie
	return null


func _explode() -> void:
	if _dead:
		return
	_dead = true
	var root := get_tree().get_first_node_in_group("fx_root") if is_inside_tree() else null
	if visual_only:
		HitFx.blast(root, global_position, CartMines.BLAST, COLOR)
		Sfx.play("rocket_explode")
	else:
		Rocket.detonate(
			get_tree(), global_position, CartMines.DAMAGE, CartMines.BLAST, root
		)
	queue_free()


func _blink() -> void:
	if _lamp == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	var rate := 8.0 if is_armed() else 2.4
	_lamp.light_energy = 1.4 + absf(sin(t * rate * TAU)) * (4.2 if is_armed() else 1.8)


func _build() -> void:
	var puck := MeshFactory.cylinder(0.28, 0.08, BODY, Palette.GLOW_FAINT)
	add_child(puck)
	var ring := MeshFactory.torus(0.16, 0.24, COLOR, Palette.GLOW_MEDIUM)
	ring.position.y = 0.05
	add_child(ring)
	var nub := MeshFactory.sphere(0.07, COLOR, Palette.GLOW_STRONG)
	nub.position.y = 0.08
	add_child(nub)
	_lamp = OmniLight3D.new()
	_lamp.light_color = COLOR
	_lamp.light_energy = 2.2
	_lamp.omni_range = 3.4
	_lamp.position.y = 0.12
	add_child(_lamp)
