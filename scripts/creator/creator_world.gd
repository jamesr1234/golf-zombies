class_name CreatorWorld
extends RefCounted
## The hole standing under the builder. It is a real one, laid out by
## CustomLayout and raised by the same HoleBuilder that raises every other hole,
## so what is being walked around here is what gets played.

var data: HoleData

var _host: Node3D
var _built: Node3D


func _init(for_host: Node3D) -> void:
	_host = for_host


## The fairway changed shape, so the ground, the lip walls and the
## out-of-bounds rect all have to be laid out again.
func rebuild(hole: CustomHole) -> void:
	if _built != null and is_instance_valid(_built):
		_built.queue_free()
	data = CustomLayout.build(hole)
	_built = HoleBuilder.build(data)
	_host.add_child(_built)
	CreatorLandings.attach(_built, data)


## Only what was dropped on the hole moved, so the ground stays put and just the
## props are swapped out. Rebuilding the terrain for every block would make
## placing one feel like loading a level.
func refresh_props(hole: CustomHole) -> void:
	var region := nav()
	if region == null:
		rebuild(hole)
		return
	var overlay := region.get_node_or_null(CustomOverlay.NAME)
	if overlay != null:
		region.remove_child(overlay)
		overlay.queue_free()
	CustomOverlay.attach(region, data)


## Neighbours for the snap are read off here, so a piece meets what is already
## standing rather than what was there before the last change.
func nav() -> Node3D:
	if _built == null or not is_instance_valid(_built):
		return null
	return _built.get_node_or_null(HoleBuilder.NAV_NAME) as Node3D
