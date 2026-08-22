class_name CartPathGate
extends Node3D
## Giant neon gantry at the mouth of the clubhouse circuit, so the way off the
## green is obvious from the cart.

const COPY := "TO THE CLUBHOUSE"
const PILLAR_H := 10.0
const PILLAR_R := 0.48
const BEAM_Y := 8.35
const SPAN := 28.4


static func create(at: Vector3, along: Vector3) -> CartPathGate:
	var gate := CartPathGate.new()
	gate.name = "ClubhouseGate"
	gate.add_to_group("clubhouse_gate")
	gate.position = at
	var face := -along
	face.y = 0.0
	if face.length_squared() < 0.01:
		face = Vector3.BACK
	face = face.normalized()
	# Local +Z is the readable face, same as TeeSign.
	gate.rotation.y = atan2(face.x, face.z)
	gate._build()
	return gate


func _build() -> void:
	var half := SPAN * 0.5
	for side in [-1.0, 1.0]:
		var pillar := MeshFactory.cylinder(PILLAR_R, PILLAR_H, Palette.WALL, Palette.GLOW_FAINT)
		pillar.position = Vector3(side * half, PILLAR_H * 0.5, 0.0)
		add_child(pillar)
		var ring := MeshFactory.cylinder(PILLAR_R + 0.12, 0.18, Palette.CYAN, Palette.GLOW_STRONG)
		ring.position = Vector3(side * half, BEAM_Y - 0.55, 0.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	var beam := MeshFactory.box(
		Vector3(SPAN + PILLAR_R * 2.0, 0.55, 0.7), Palette.WALL, Palette.GLOW_FAINT
	)
	beam.position = Vector3(0.0, BEAM_Y, 0.0)
	add_child(beam)
	var board := MeshFactory.box(
		Vector3(SPAN * 0.92, 2.15, 0.18), Palette.NIGHT, 0.35
	)
	board.position = Vector3(0.0, BEAM_Y + 0.15, 0.12)
	add_child(board)
	var frame := MeshFactory.box(
		Vector3(SPAN * 0.96, 2.45, 0.08), Palette.CYAN, Palette.GLOW_STRONG
	)
	frame.position = Vector3(0.0, BEAM_Y + 0.15, 0.18)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(frame)
	var copy := Label3D.new()
	copy.name = "GateCopy"
	copy.text = COPY
	copy.font_size = 96
	copy.pixel_size = 0.014
	copy.modulate = Palette.CYAN
	copy.outline_size = 16
	copy.outline_modulate = Palette.NIGHT
	copy.position = Vector3(0.0, BEAM_Y + 0.18, 0.28)
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(copy)
	var lamp := OmniLight3D.new()
	lamp.light_color = Palette.CYAN
	lamp.light_energy = 3.4
	lamp.omni_range = 22.0
	lamp.position = Vector3(0.0, BEAM_Y + 0.4, 1.2)
	add_child(lamp)
