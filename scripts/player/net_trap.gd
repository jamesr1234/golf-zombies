class_name NetTrap
extends Node3D
## One net over a giant circle. Everyone inside is rooted until it expires, or
## until a rocket hits anyone in it and bursts the whole pack.

const COLOR: Color = Palette.NET
const SPOKES := 10

var radius := 20.0
var duration := 10.0
var _caught: Array[Zombie] = []
var _left := 0.0
var _dead := false


static func deploy(root: Node, at: Vector3, span: float, hold: float) -> NetTrap:
	if root == null:
		return null
	var trap := NetTrap.new()
	trap.radius = span
	trap.duration = hold
	trap._left = hold
	trap.add_to_group("net_traps")
	root.add_child(trap)
	trap.global_position = at
	trap._build()
	trap.scoop()
	HitFx.blast(root, at, minf(span, 8.0), COLOR)
	Sfx.play("net_catch")
	return trap


## Horizontal reach, so a net laid on the turf still covers a tower sniper.
static func in_reach(at: Vector3, zombie: Zombie, span: float) -> bool:
	if zombie == null or not is_instance_valid(zombie):
		return false
	var centre: Vector3 = zombie.global_position + Vector3.UP * zombie.stats.height * 0.5
	var flat := Vector2(centre.x - at.x, centre.z - at.z)
	return flat.length() <= span


func scoop() -> int:
	if _dead or not is_inside_tree():
		return 0
	var added := 0
	for node in get_tree().get_nodes_in_group("zombies"):
		var zombie := node as Zombie
		if zombie == null or not in_reach(global_position, zombie, radius):
			continue
		if catch(zombie):
			added += 1
	return added


func catch(zombie: Zombie) -> bool:
	if _dead or zombie == null or zombie.is_dying() or zombie.is_allied():
		return false
	var current := zombie.net_trap() as NetTrap
	if current != null and current != self:
		current.drop(zombie)
	if not zombie.catch_net(self):
		return false
	if not _caught.has(zombie):
		_caught.append(zombie)
	return true


func drop(zombie: Zombie) -> void:
	_caught.erase(zombie)
	if zombie != null and is_instance_valid(zombie) and zombie.net_trap() == self:
		zombie.release_net()


func trapped() -> Array[Zombie]:
	return _caught.duplicate()


func trapped_count() -> int:
	return _caught.size()


## Rocket combo: everyone still in this net dies, even outside the blast sphere.
func burst() -> int:
	if _dead:
		return 0
	_dead = true
	var killed := 0
	var held := _caught.duplicate()
	_caught.clear()
	for zombie in held:
		if zombie == null or not is_instance_valid(zombie):
			continue
		zombie.release_net()
		if zombie.is_dying():
			continue
		var skull: Vector3 = zombie.global_position + Vector3.UP * zombie.stats.height
		zombie.take_damage(10000.0, Vector3.UP, skull)
		killed += 1
	var root := get_tree().get_first_node_in_group("fx_root") if is_inside_tree() else null
	HitFx.blast(root, global_position, minf(radius, 10.0), COLOR)
	Sfx.play("net_burst")
	queue_free()
	return killed


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_left = maxf(0.0, _left - delta)
	scoop()
	if _left <= 0.0:
		_expire()


func _expire() -> void:
	if _dead:
		return
	_dead = true
	var held := _caught.duplicate()
	_caught.clear()
	for zombie in held:
		if zombie != null and is_instance_valid(zombie):
			zombie.release_net()
	queue_free()


func _exit_tree() -> void:
	var held := _caught.duplicate()
	_caught.clear()
	for zombie in held:
		if zombie != null and is_instance_valid(zombie) and zombie.net_trap() == self:
			zombie.release_net()


func _build() -> void:
	var outer := MeshFactory.torus(radius - 0.55, radius, COLOR, Palette.GLOW_MEDIUM)
	outer.position.y = 0.08
	add_child(outer)
	var inner := MeshFactory.torus(radius * 0.42, radius * 0.48, COLOR, Palette.GLOW_SOFT)
	inner.position.y = 1.15
	add_child(inner)
	for i in SPOKES:
		var angle := TAU * float(i) / float(SPOKES)
		var spoke := MeshFactory.box(Vector3(0.05, 0.04, radius), COLOR, Palette.GLOW_FAINT)
		spoke.position = Vector3(sin(angle), 0.7, cos(angle)) * (radius * 0.5)
		spoke.rotation.y = angle
		add_child(spoke)
	var hub := MeshFactory.sphere(0.22, Palette.ICE, Palette.GLOW_MEDIUM)
	hub.position.y = 1.35
	add_child(hub)
	var lamp := OmniLight3D.new()
	lamp.light_color = COLOR
	lamp.light_energy = 4.0
	lamp.omni_range = radius * 0.85
	lamp.position.y = 1.6
	add_child(lamp)
