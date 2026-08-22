class_name ShopStation
extends Node3D
## A counter inside the clubhouse. Walk up and interact to open that department.

const USE_RANGE := 2.6
const COUNTER := Vector3(2.2, 1.05, 0.85)

var dept := 0
var title := "Shop"
var cashier: ClubhouseNpc


static func create(p_dept: int, p_title: String, at: Vector3, yaw := 0.0) -> ShopStation:
	var station := ShopStation.new()
	station.dept = p_dept
	station.title = p_title
	station.name = p_title
	station.position = at
	station.rotation.y = deg_to_rad(yaw)
	station._build()
	return station


func can_use(who: Node3D) -> bool:
	if who == null or not is_inside_tree():
		return false
	var offset := who.global_position - global_position
	offset.y = 0.0
	return offset.length() <= USE_RANGE


func _build() -> void:
	var desk := MeshFactory.box_body(COUNTER, Palette.WALL, Layers.PROP, true, Palette.GLOW_FAINT)
	desk.position.y = COUNTER.y * 0.5
	add_child(desk)
	var top := MeshFactory.box(Vector3(COUNTER.x + 0.08, 0.06, COUNTER.z + 0.08), Palette.AMBER, Palette.GLOW_FAINT)
	top.position.y = COUNTER.y + 0.04
	add_child(top)
	var sign := Label3D.new()
	sign.text = title.to_upper()
	sign.font_size = 22
	sign.modulate = Color(0.62, 0.42, 0.16)
	sign.outline_size = 3
	sign.outline_modulate = Palette.NIGHT
	sign.position = Vector3(0.0, COUNTER.y + 0.18, COUNTER.z * 0.5 + 0.02)
	add_child(sign)
