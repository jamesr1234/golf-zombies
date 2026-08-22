class_name AmmoPickup
extends Area3D
## Dropped by dead zombies, since ammo is the only resource the players cannot
## get any other way.

const LIFETIME := 45.0
const SPIN_SPEED := 1.5

var amount := 24


static func spawn(parent: Node, position: Vector3, amount: int) -> void:
	if parent == null:
		return
	var pickup := AmmoPickup.new()
	pickup.amount = amount
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


func _ready() -> void:
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	monitoring = true
	body_entered.connect(_on_body_entered)
	var timer := get_tree().create_timer(LIFETIME)
	timer.timeout.connect(queue_free)


func _process(delta: float) -> void:
	rotate_y(SPIN_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	player.weapon.add_ammo(amount)
	Sfx.play("pickup_ammo", player)
	queue_free()
