class_name CustomLayout
extends Object
## Turns a player-made hole into the same HoleData the generator produces, so a
## custom hole gets the flat fairway deck, the lip walls that keep play on the
## strip, the out-of-bounds rect and the zombie nav bake for free.

## Overrun on a fairway patch so two segments meet without a seam at the corner.
const SEAM := 4.0


static func build(custom: CustomHole, base_seed := 0, index := FairwayPiece.INDEX) -> HoleData:
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed
	var data := HoleData.new()
	data.custom = custom
	# Lay the strip out as hole 1 so setpieces stay off the heightmap. Width
	# comes from the hole's own size, not from a wide-fairway slot. The slot
	# is stamped on after, so the clubhouse can tell which hole this is.
	data.index = FairwayPiece.INDEX
	data.par = custom.par()
	data.green_radius = HoleData.DEFAULT_GREEN_RADIUS

	var line := custom.centerline()
	var turned := FairwayPiece.headings(custom.pieces)
	var run := FairwayPiece.lengths(custom.pieces)
	var width := custom.width()
	data.centerline.assign(line)
	for i in run.size():
		data.patches.append(HoleGenerator.surface_patch(
			Surface.Type.FAIRWAY,
			line[i].lerp(line[i + 1], 0.5),
			Vector2(width, run[i] + SEAM),
			turned[i]
		))

	data.tee = line[0]
	data.cup = line[line.size() - 1]
	var opening: float = turned[0] if not turned.is_empty() else 0.0
	data.patches.append(HoleGenerator.surface_patch(
		Surface.Type.TEE, data.tee, Vector2(8.0, 10.0), opening
	))
	var fringe := data.green_radius + HoleGenerator.FRINGE_WIDTH
	data.patches.append(HoleGenerator.surface_patch(
		Surface.Type.FRINGE, data.cup, Vector2(fringe * 2.0, fringe * 2.0), 0.0, true
	))
	data.patches.append(HoleGenerator.surface_patch(
		Surface.Type.GREEN, data.cup,
		Vector2(data.green_radius * 2.0, data.green_radius * 2.0), 0.0, true
	))
	HoleGenerator.add_practice_green(data, opening)

	data.bounds = HoleGenerator.bounds_of(data)
	HoleGenerator.add_spawn_points(data, rng, width)
	data.height = HeightField.generate(data, rng)
	HoleGenerator.lift_to_ground(data)
	data.index = index
	return data
