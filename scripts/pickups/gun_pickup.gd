class_name GunPickup
extends Area3D
## A gun on the ground. Walk in and it goes in the bag.

const SPIN_SPEED := 1.1


@export var stats: WeaponStats
## Where down the hole this gun stops working, 0 at the tee and 1 at the cup.
## -1 leaves it live the whole way. Set by the hole creator; nothing draws it.
@export var gate := CustomHole.NO_GATE
## Arena loadout: lie on the floor instead of spinning in the air.
var laid_out := false


func _ready() -> void:
	add_to_group("gun_pickups")
	collision_layer = Layers.PICKUP
	collision_mask = Layers.PLAYER
	body_entered.connect(_on_body_entered)
	_build()


func _process(delta: float) -> void:
	if laid_out:
		return
	rotate_y(SPIN_SPEED * delta)


func _on_body_entered(body: Node3D) -> void:
	if NetSession.is_active() and not multiplayer.is_server():
		return
	var player := body as Player
	if player == null or player.weapon == null or stats == null:
		return
	if player.weapon.has_gun(stats):
		return
	if not ArenaHole.can_pick(player):
		return
	if not player.weapon.add_gun(stats, gate):
		return
	Sfx.play("pickup_ammo", player)
	if player.flow != null and player.flow.has_method("note_loadout"):
		player.flow.note_loadout(player)
	queue_free()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.85 if laid_out else 1.1
	shape.shape = sphere
	add_child(shape)
	if stats == null:
		return
	var vis := Node3D.new()
	vis.name = "Mesh"
	add_child(vis)
	if stats.visual == "rocket":
		Raygun.build_rocket(vis, Palette.PLAYER_ONE)
		vis.scale = Vector3.ONE * 3.0
	else:
		ShopProps.preview(vis, {"id": stats.visual})
	if laid_out:
		vis.rotation.z = deg_to_rad(90.0)
