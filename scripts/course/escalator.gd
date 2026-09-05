class_name Escalator
extends Area3D
## Belt on a placed escalator_*.glb. Frame is the mesh; this carries and reverses.

const SPEED := 1.575
const USE_RANGE := 2.8
const COOL := 0.8
const STEP_PITCH := 0.4
const DETECT_H := 2.2

@export var sync_dir := 1

var _host: Node3D
var _box := AABB()
var _button_local := Vector3.ZERO
var _cool := 0.0
var _scroll := 0.0
var _steps: Array[Node3D] = []
var _cap: GeometryInstance3D


static func is_escalator(node: Node) -> bool:
	if node == null:
		return false
	return String(node.get("scene_file_path")).contains("/escalator_")


static func adopt(root: Node) -> void:
	if root == null or root.has_meta("_escalators_bound"):
		return
	root.set_meta("_escalators_bound", true)
	_walk(root)


static func attach(host: Node3D) -> Escalator:
	if host == null or not is_escalator(host):
		return null
	var existing := host.get_node_or_null("Escalator") as Escalator
	if existing != null:
		return existing
	var box := _local_aabb(host)
	if box.size.y < 0.8 or box.size.z < 1.0:
		return null
	var lift := Escalator.new()
	lift.name = "Escalator"
	lift._host = host
	lift._box = box
	host.add_child(lift)
	lift._setup()
	return lift


static func nearest(who: Node3D) -> Escalator:
	var best: Escalator
	var best_d := INF
	if who == null or not who.is_inside_tree():
		return null
	for node in who.get_tree().get_nodes_in_group("escalators"):
		var lift := node as Escalator
		if lift == null or not lift.can_use(who):
			continue
		var d := who.global_position.distance_to(lift.button_at())
		if d < best_d:
			best = lift
			best_d = d
	return best


static func _walk(node: Node) -> void:
	if node is Node3D and is_escalator(node):
		attach(node as Node3D)
	for child in node.get_children():
		_walk(child)


func _ready() -> void:
	add_to_group("escalators")
	collision_layer = 0
	collision_mask = Layers.PLAYER
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	if NetSession.is_active():
		NetSync.attach(self, PackedStringArray([":sync_dir"]))


func carry_along() -> Vector3:
	return _up() * float(sync_dir) * SPEED


func button_at() -> Vector3:
	if _host == null:
		return global_position
	return _host.to_global(_button_local)


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree() or _host == null:
		return false
	if who.get("health") != null and who.health.has_method("is_alive"):
		if not who.health.is_alive():
			return false
	if who.get("shopping") == true or who.get("talking") == true:
		return false
	if who.get("state") != null and int(who.state) != 0:
		return false
	return who.global_position.distance_to(button_at()) <= USE_RANGE


func try_reverse(player: Node) -> void:
	if not Engine.is_editor_hint() and NetSession.is_active() and not multiplayer.is_server():
		_request_reverse.rpc_id(1, int(player.get("peer_id")))
		return
	_flip(player)


func _flip(player: Node = null) -> void:
	if player != null and not can_use(player):
		return
	if _cool > 0.0:
		return
	sync_dir = -sync_dir
	_cool = COOL
	_paint_button()
	Sfx.play("escalator_reverse", self)


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	_scroll = fmod(_scroll + float(sync_dir) * SPEED * delta, STEP_PITCH)
	if _scroll < 0.0:
		_scroll += STEP_PITCH
	_pose_steps()
	_paint_button()


func _setup() -> void:
	position = _box.position + _box.size * 0.5
	var rise := _box.size.y
	var run := _box.size.z
	var hyp := sqrt(rise * rise + run * run)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_box.size.x * 0.62, DETECT_H, hyp)
	shape.shape = box
	shape.rotation.x = atan2(rise, run)
	add_child(shape)
	_button_local = _find_button()
	_build_switch()
	_build_steps()
	_paint_button()


func _up() -> Vector3:
	if _host == null:
		return Vector3.UP
	var bottom := _host.to_global(Vector3(
		_box.position.x + _box.size.x * 0.5, _box.position.y, _box.end.z
	))
	var top := _host.to_global(Vector3(
		_box.position.x + _box.size.x * 0.5, _box.end.y, _box.position.z
	))
	var delta := top - bottom
	if delta.length_squared() < 0.0001:
		return Vector3.UP
	return delta.normalized()


func _find_button() -> Vector3:
	var cap := _named_ending(_host, "Button")
	if cap is GeometryInstance3D:
		_cap = cap as GeometryInstance3D
	var mark := _named_in(_host, "ButtonMark")
	var found := Vector3(_box.position.x + _box.size.x * 0.5, _box.end.y, _box.position.z + 1.2)
	if mark != null:
		found = _local_xf(_host, mark).origin
	elif cap != null:
		found = _local_xf(_host, cap).origin
	return found


func _build_switch() -> void:
	var post := MeshFactory.box(Vector3(0.16, 1.2, 0.16), Palette.CART_FRAME)
	post.name = "SwitchPost"
	post.position = _button_local + Vector3(0.0, 0.6, 0.0)
	_host.add_child(post)
	var lever := MeshFactory.box(Vector3(0.12, 0.12, 0.62), Palette.CYAN, 1.1)
	lever.name = "SwitchLever"
	lever.position = _button_local + Vector3(0.0, 1.12, 0.22)
	lever.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_host.add_child(lever)
	_cap = lever
	_button_local += Vector3(0.0, 1.12, 0.0)


func _build_steps() -> void:
	var rise := _box.size.y
	var run := _box.size.z
	var hyp := sqrt(rise * rise + run * run)
	var n := maxi(8, roundi(hyp / STEP_PITCH))
	var belt := Node3D.new()
	belt.name = "Belt"
	_host.add_child(belt)
	for i in n:
		var color := Palette.AMBER if i % 2 == 0 else Palette.LED_WHITE
		var step := MeshFactory.box(Vector3(_box.size.x * 0.58, 0.05, 0.24), color, 0.12)
		step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		belt.add_child(step)
		_steps.append(step)
	_pose_steps()


func _pose_steps() -> void:
	var rise := _box.size.y
	var run := _box.size.z
	var hyp := sqrt(rise * rise + run * run)
	var n := _steps.size()
	if n == 0 or _host == null:
		return
	var normal := Vector3(0.0, run, rise).normalized()
	for i in n:
		var d := fmod(float(i) * STEP_PITCH + _scroll, hyp)
		var t := d / hyp
		var along := Vector3(
			_box.position.x + _box.size.x * 0.5,
			lerpf(_box.position.y, _box.end.y, t),
			lerpf(_box.end.z, _box.position.z, t)
		)
		_steps[i].position = along + normal * 0.06
		_steps[i].rotation.x = atan2(rise, run)


func _paint_button() -> void:
	if _cap == null:
		return
	var color := Palette.CYAN if sync_dir > 0 else Palette.MAGENTA
	_cap.material_override = MeshFactory.material(color, false, 0.8)


func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_escalator"):
		body.enter_escalator(self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_escalator"):
		body.exit_escalator(self)


func _named_in(node: Node, token: String) -> Node3D:
	if node is Node3D and String(node.name).contains(token) and node != self:
		return node as Node3D
	for child in node.get_children():
		var found := _named_in(child, token)
		if found != null:
			return found
	return null


func _named_ending(node: Node, token: String) -> Node3D:
	if node is Node3D and String(node.name).ends_with(token) and node != self:
		return node as Node3D
	for child in node.get_children():
		var found := _named_ending(child, token)
		if found != null:
			return found
	return null


@rpc("any_peer", "reliable")
func _request_reverse(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("players"):
		if int(node.get("peer_id")) == peer_id:
			_flip(node)
			return


## Transform of a descendant in host space. Built from local transforms because
## attach runs before the hole joins the tree, where global_transform is unset.
static func _local_xf(host: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != host:
		if at is Node3D:
			xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


static func _local_aabb(host: Node3D) -> AABB:
	var box := AABB()
	var started := false
	var stack: Array[Node] = [host]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Escalator or ObstacleLeds.is_led(current):
			continue
		var mesh_node := current as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			var local := mesh_node.mesh.get_aabb()
			var xf := _local_xf(host, mesh_node)
			for i in 8:
				var point: Vector3 = xf * local.get_endpoint(i)
				if not started:
					box = AABB(point, Vector3.ZERO)
					started = true
				else:
					box = box.expand(point)
		for child in current.get_children():
			stack.append(child)
	return box
