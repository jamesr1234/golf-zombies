class_name VehicleLot
extends Node3D
## Extra rideables parked beside the assigned cart so they stay on the hole.

const GAP := 4.4
const SIDE := 5.0


static func park_beside(lead: Node3D, lot: Node3D) -> void:
	if lead == null or lot == null:
		return
	var yaw := rad_to_deg(lead.rotation.y)
	var facing := Vector3(-sin(lead.rotation.y), 0.0, -cos(lead.rotation.y))
	var lateral := facing.cross(Vector3.UP)
	if lateral.length_squared() < 0.0001:
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	var i := 0
	for child in lot.get_children():
		var extra := child as GolfCart
		if extra == null:
			continue
		var spot := lead.global_position + lateral * (SIDE + float(i) * GAP)
		extra.place_at(spot, yaw)
		i += 1


func park_with(lead: Node3D) -> void:
	park_beside(lead, self)
