class_name AmmoPickup
extends Area3D
## Dropped by dead zombies, since ammo is the only resource the players cannot
## get any other way.

const LIFETIME := 45.0
const SPIN_SPEED := 1.5
const _WorldFx := preload("res://scripts/net/world_fx.gd")

var amount := 24
var drop_id := 0
var visual_only := false


static func spawn(
	parent: Node, position: Vector3, amount: int, p_drop_id := 0, p_visual_only := false
) -> AmmoPickup:
	if parent == null:
		return null
	var pickup := AmmoPickup.new()
	pickup.amount = amount
	pickup.drop_id = p_drop_id
	pickup.visual_only = p_visual_only
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	pickup.add_child(shape)
	pickup.add_child(
		MeshFactory.box(Vector3(0.5, 0.28, 0.34), Palette.PICKUP, Palette.GLOW_STRONG)
	)
	parent.add_child(pickup)
	pickup.global_position = position
	return pickup


func _ready() -> void:
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	monitoring = not visual_only
	if not visual_only:
		body_entered.connect(_on_body_entered)
	var timer := get_tree().create_timer(LIFETIME)
	timer.timeout.connect(_expire)


func _process(delta: float) -> void:
	rotate_y(SPIN_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	if visual_only:
		return
	if NetSession.is_active() and not multiplayer.is_server():
		return
	var player := body as Player
	if player == null or player.weapon == null:
		return
	player.weapon.add_ammo(amount)
	Sfx.play("pickup_ammo", player)
	_WorldFx.announce_ammo_gone(self, drop_id)
	queue_free()


func _expire() -> void:
	if not visual_only:
		_WorldFx.announce_ammo_gone(self, drop_id)
	queue_free()
