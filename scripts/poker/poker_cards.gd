class_name PokerCards
extends Node3D
## Hole cards ride in the seated hands. The board sits on the felt and on the HUD.

const FACE := Vector3(0.22, 0.32, 0.012)
const HOLD := 0.7
const FAN_DEG := 10.0
## Well and rail sit at 0.84–0.86; cards have to clear that slab.
const BOARD_Y := 0.94
const BOARD_SCALE := 2.0
const BOARD_GAP := 0.56
## First-person hole cards: glued to the view so they stay face-on and in front of the fists.
const VIEW_DIST := 0.36
const VIEW_DROP := 0.22
const VIEW_FAN := 0.22


var _sig := ""
var _occupants: Array = []


func _process(_delta: float) -> void:
	_snap()


func refresh(hand: PokerHand, _chairs: Array, occupants: Array, phase: int) -> void:
	_occupants = occupants
	var sig := _signature(hand, occupants, phase)
	if sig != _sig:
		_sig = sig
		for child in get_children():
			remove_child(child)
			child.free()
		if hand != null:
			_board(hand.board)
			for seat in 2:
				if not face_up_for(seat, occupants, phase):
					continue
				for slot in hand.hole[seat].size():
					var node := _card(int(hand.hole[seat][slot]), true)
					node.set_meta("seat", seat)
					node.set_meta("slot", slot)
					add_child(node)
	_snap()


static func face_up_for(seat: int, occupants: Array, phase: int) -> bool:
	if phase == PokerTable.Phase.SHOWDOWN:
		return true
	var who = occupants[seat] if seat >= 0 and seat < occupants.size() else null
	if not who is Player:
		return false
	var player := who as Player
	if NetSession.is_active():
		return player.is_multiplayer_authority()
	return not player.is_cpu()


func _signature(hand: PokerHand, occupants: Array, phase: int) -> String:
	if hand == null:
		return ""
	var shown := ""
	for seat in 2:
		shown += "1" if face_up_for(seat, occupants, phase) else "0"
	return "%s:%s:%s:%s:%d" % [
		PokerEval.labels(hand.hole[0]),
		PokerEval.labels(hand.hole[1]),
		PokerEval.labels(hand.board),
		shown,
		phase,
	]


func _board(cards: Array) -> void:
	var n := cards.size()
	if n == 0:
		return
	var span := BOARD_GAP * float(n - 1)
	for i in n:
		var node := _card(int(cards[i]))
		node.position = Vector3(-span * 0.5 + BOARD_GAP * float(i), BOARD_Y, 0.0)
		node.rotation.x = deg_to_rad(90.0)
		add_child(node)


func _snap() -> void:
	for child in get_children():
		if not child.has_meta("seat"):
			continue
		_place(child as Node3D, int(child.get_meta("seat")), int(child.get_meta("slot")))


func _place(node: Node3D, seat: int, slot: int) -> void:
	var cam := _view_xform(seat)
	if cam == Transform3D.IDENTITY:
		node.visible = false
		return
	node.visible = true
	var side := float(slot) - 0.5
	var at := (
		cam.origin
		+ (-cam.basis.z) * VIEW_DIST
		+ (-cam.basis.y) * VIEW_DROP
		+ cam.basis.x * side * VIEW_FAN
	)
	var basis := Basis(-cam.basis.x, cam.basis.y, -cam.basis.z)
	basis = basis.rotated(basis.y, deg_to_rad(side * FAN_DEG))
	node.global_transform = Transform3D(basis.scaled(Vector3.ONE * HOLD), at)


func _view_xform(seat: int) -> Transform3D:
	if seat < 0 or seat >= _occupants.size():
		return Transform3D.IDENTITY
	var who = _occupants[seat]
	if who is Player:
		var player := who as Player
		if player.head != null:
			return player.head.global_transform
	if who is Node3D:
		var node := who as Node3D
		return Transform3D(Basis.IDENTITY, node.global_position + Vector3(0.0, PlayerAnim.SIT_HEAD_HEIGHT, 0.0))
	return Transform3D.IDENTITY


func _card(id: int, held := false) -> Node3D:
	var root := Node3D.new()
	root.scale = Vector3.ONE * (HOLD if held else BOARD_SCALE)
	root.add_child(MeshFactory.box(Vector3(FACE.x * 0.84, FACE.y * 0.88, FACE.z), Palette.LED_WHITE, 0.0))
	var front := _sheet("Face", PokerCardArt.face(id), false)
	front.position.z = -FACE.z * 0.5 - 0.0004
	root.add_child(front)
	var rear := _sheet("Back", PokerCardArt.back(), true)
	rear.position.z = FACE.z * 0.5 + 0.0004
	root.add_child(rear)
	return root


func _sheet(node_name: String, texture: Texture2D, toward_plus_z: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = _card_quad(toward_plus_z)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.roughness = 0.78
	mat.metallic = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	node.material_override = mat
	return node


func _card_quad(toward_plus_z: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := FACE.x * 0.5
	var h := FACE.y * 0.5
	if toward_plus_z:
		_tri(st, Vector3(-w, h, 0), Vector3(w, h, 0), Vector3(w, -h, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_tri(st, Vector3(-w, h, 0), Vector3(w, -h, 0), Vector3(-w, -h, 0), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	else:
		_tri(st, Vector3(w, h, 0), Vector3(-w, h, 0), Vector3(-w, -h, 0), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_tri(st, Vector3(w, h, 0), Vector3(-w, -h, 0), Vector3(w, -h, 0), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))
	st.generate_normals()
	return st.commit()


func _tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2
) -> void:
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)
