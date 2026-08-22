class_name PracticeGreen
extends Object
## Warm-up hole behind every tee, on the line of the drive. Putting here is free:
## the hole itself does not start, and the swarm does not arrive, until someone
## steps on the tee.

## A short par-three of a green sitting between the clubhouse exit and the tee.
const WIDTH := 14.0
const LENGTH := 22.0
const PUTT := 16.0
const GAP_TO_TEE := 7.0
const FLAG_HEIGHT := 2.6
## Flat ground the green needs, measured from its centre.
const FLAT := LENGTH * 0.5 + HoleGenerator.FRINGE_WIDTH


static func span() -> float:
	return maxf(WIDTH, LENGTH)


## Behind the tee, on the hole axis, so the real hole sits just beyond it.
static func center(tee: Vector3, heading_deg: float) -> Vector3:
	var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading_deg))
	return tee - forward * (LENGTH * 0.5 + GAP_TO_TEE)


## Tee mark at the back of the green, cup toward the real tee.
static func putt_ends(at: Vector3, heading_deg: float) -> Array[Vector3]:
	var forward := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(heading_deg))
	return [at - forward * PUTT * 0.5, at + forward * PUTT * 0.5]


static func create(data: HoleData) -> Node3D:
	var root := Node3D.new()
	root.name = "PracticeGreen"
	root.add_child(Cup.create(data.practice_cup))
	var mark := MeshFactory.disk(0.45, Palette.CYAN, Palette.GLOW_MEDIUM)
	mark.position = data.practice_tee + Vector3.UP * 0.18
	root.add_child(mark)
	root.add_child(_stick(data.practice_cup))
	root.add_child(_sign(data.practice_tee))
	return root


## A short stick so the practice cup reads from the tee. No sky beam: only the
## real pin gets one, or you would not know which hole you were looking at.
static func _stick(cup: Vector3) -> Node3D:
	var root := Node3D.new()
	var pole := MeshFactory.cylinder(0.07, FLAG_HEIGHT, Palette.FLAGPOLE, Palette.GLOW_SOFT)
	pole.position = cup + Vector3.UP * FLAG_HEIGHT * 0.5
	root.add_child(pole)
	var flag := MeshFactory.box(Vector3(0.85, 0.5, 0.04), Palette.LIME, Palette.GLOW_MEDIUM)
	flag.position = cup + Vector3(0.42, FLAG_HEIGHT - 0.35, 0.0)
	root.add_child(flag)
	return root


static func _sign(at: Vector3) -> Label3D:
	var sign := Label3D.new()
	sign.text = "PRACTICE GREEN"
	sign.font_size = 44
	sign.modulate = Palette.LIME
	sign.outline_size = 10
	sign.outline_modulate = Palette.NIGHT
	sign.position = at + Vector3.UP * 2.8
	return sign
