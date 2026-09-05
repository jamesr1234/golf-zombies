class_name PokerCardArt
extends Object
## Felt faces come from the Blender deck in assets/cards; paint is the fallback.

const W := 320
const H := 448
const SS := 1
const DIR := "res://assets/cards/"
const MARK: PackedStringArray = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]

static var _faces: Array[ImageTexture] = []
static var _back: ImageTexture
static var _font_rid: RID


static func face(id: int) -> Texture2D:
	var i := posmod(id, 52)
	if _faces.size() != 52:
		_faces.resize(52)
	if _faces[i] == null:
		_faces[i] = _texture(_paint_face(i))
	return _faces[i]


static func back() -> Texture2D:
	if _back == null:
		_back = _texture(_paint_back())
	return _back


static func image(id: int) -> Image:
	return face(id).get_image()


static func _load_sheet(file_name: String) -> Image:
	var path := DIR + file_name
	var tex := ResourceLoader.load(path) as Texture2D
	if tex != null:
		var baked := tex.get_image()
		if baked != null:
			return baked
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img


static func ink(id: int) -> Color:
	var suit := PokerEval.suit(id)
	return Palette.LED_RED if suit == 1 or suit == 2 else Palette.NIGHT


static func _texture(img: Image) -> ImageTexture:
	if img.get_width() != W or img.get_height() != H:
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _paint_face(id: int) -> Image:
	var baked := _load_sheet("%s.png" % PokerEval.label(id))
	if baked != null:
		return baked
	var pw := W * SS
	var ph := H * SS
	var img := _stock(pw, ph, Palette.LED_WHITE)
	var suit := PokerEval.suit(id)
	var rank := PokerEval.rank(id)
	var color := ink(id)
	var index := _index(pw, rank, suit, color)
	_blit(img, pw, ph, index, Vector2i(int(0.045 * pw), int(0.04 * ph)), false)
	_blit(img, pw, ph, index, Vector2i(int(0.045 * pw), int(0.04 * ph)), true)
	if rank == 12:
		_pip(img, 0.5 * pw, 0.5 * ph, 0.122 * ph, suit, color, false)
	elif rank <= 8:
		_number(img, pw, ph, rank + 2, suit, color)
	else:
		_court(img, pw, ph, rank, suit, color)
	return img


static func _paint_back() -> Image:
	var baked := _load_sheet("back.png")
	if baked != null:
		return baked
	var pw := W * SS
	var ph := H * SS
	var img := _stock(pw, ph, Palette.LED_WHITE)
	for y in ph:
		for x in pw:
			if _sdf_round(x, y, pw, ph, 0.055 * pw) > 0.0:
				continue
			var u := float(x + y)
			var v := float(x - y + ph)
			var cell := posmod(int(u / SS), 14) < 7 and posmod(int(v / SS), 14) < 7
			_plot(img, x, y, Palette.CYAN if cell else Palette.MAGENTA)
	_ring(img, 0.5 * pw, 0.5 * ph, 0.09 * ph, 0.12 * ph, Palette.LED_WHITE)
	_pip(img, 0.5 * pw, 0.5 * ph, 0.055 * ph, 3, Palette.NIGHT, false)
	return img


static func _stock(pw: int, ph: int, fill: Color) -> Image:
	var img := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := 0.055 * pw
	for y in ph:
		for x in pw:
			var d := _sdf_round(x, y, pw, ph, r)
			var a := clampf(0.65 - d, 0.0, 1.0)
			if a <= 0.0:
				continue
			var edge := _sdf_round(x, y, pw, ph, r - 2.4 * SS)
			var shade := fill.darkened(0.04 * clampf((float(y) / ph) * 0.4, 0.0, 1.0))
			var color := Palette.NIGHT if edge > 0.0 else shade
			color.a = a
			img.set_pixel(x, y, color)
	return img


static func _sdf_round(x: float, y: float, pw: float, ph: float, r: float) -> float:
	var p := Vector2(absf(x - pw * 0.5), absf(y - ph * 0.5))
	var q := p - Vector2(pw * 0.5 - r, ph * 0.5 - r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _index(pw: int, rank: int, suit: int, color: Color) -> Image:
	var stamp := Image.create(int(0.22 * pw), int(0.30 * pw), false, Image.FORMAT_RGBA8)
	stamp.fill(Color(0, 0, 0, 0))
	var mark := MARK[rank]
	var px := 36 if mark.length() == 1 else 26
	_text(stamp, mark, Vector2(3, 1), px, color)
	_pip(stamp, stamp.get_width() * 0.45, stamp.get_height() * 0.72, stamp.get_width() * 0.24, suit, color, false)
	return stamp


static func _text(img: Image, text: String, origin: Vector2, px: int, color: Color) -> void:
	var ts := TextServerManager.get_primary_interface()
	var rid := _typeface()
	if not rid.is_valid():
		return
	var cursor := origin
	var ascent := ts.font_get_ascent(rid, px)
	for i in text.length():
		var glyph := ts.font_get_glyph_index(rid, px, text.unicode_at(i), 0)
		var contours: Dictionary = ts.font_get_glyph_contours(rid, px, glyph)
		_fill_contours(img, contours, Vector2(cursor.x, cursor.y + ascent), color)
		cursor.x += ts.font_get_glyph_advance(rid, px, glyph).x


static func _typeface() -> RID:
	if _font_rid.is_valid():
		return _font_rid
	var rids := HudStyle.READOUT_FONT.get_rids()
	if rids.is_empty():
		return RID()
	_font_rid = rids[0]
	return _font_rid


static func _fill_contours(img: Image, contours: Dictionary, origin: Vector2, color: Color) -> void:
	var points: PackedVector3Array = contours.get("points", PackedVector3Array())
	var ends: PackedInt32Array = contours.get("contours", PackedInt32Array())
	if points.is_empty() or ends.is_empty():
		return
	var edges: Array[Vector2] = []
	var start := 0
	for stop in ends:
		var last := Vector2(origin.x + points[stop].x, origin.y + points[stop].y)
		for i in range(start, stop + 1):
			var nxt := Vector2(origin.x + points[i].x, origin.y + points[i].y)
			edges.append(last)
			edges.append(nxt)
			last = nxt
		start = stop + 1
	var x0 := img.get_width()
	var y0 := img.get_height()
	var x1 := 0
	var y1 := 0
	for i in range(0, edges.size(), 2):
		x0 = mini(x0, int(floor(edges[i].x)))
		y0 = mini(y0, int(floor(edges[i].y)))
		x1 = maxi(x1, int(ceil(edges[i].x)))
		y1 = maxi(y1, int(ceil(edges[i].y)))
	x0 = clampi(x0 - 1, 0, img.get_width() - 1)
	y0 = clampi(y0 - 1, 0, img.get_height() - 1)
	x1 = clampi(x1 + 1, 0, img.get_width() - 1)
	y1 = clampi(y1 + 1, 0, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cover := 0.0
			for sy in 2:
				for sx in 2:
					if _even_odd(Vector2(x + (sx + 0.5) * 0.5, y + (sy + 0.5) * 0.5), edges):
						cover += 0.25
			if cover > 0.0:
				_blend(img, x, y, color, cover)


static func _even_odd(p: Vector2, edges: Array[Vector2]) -> bool:
	var inside := false
	for i in range(0, edges.size(), 2):
		var a := edges[i]
		var b := edges[i + 1]
		if (a.y > p.y) == (b.y > p.y):
			continue
		var t := (p.y - a.y) / (b.y - a.y)
		if p.x < a.x + t * (b.x - a.x):
			inside = not inside
	return inside


static func _number(img: Image, pw: int, ph: int, count: int, suit: int, color: Color) -> void:
	var cx := 0.5 * pw
	var cy := 0.5 * ph
	var col := 0.22 * pw
	var hi := 0.24 * ph
	var mid := hi * 0.38
	var rad := 0.042 * ph
	var spots: Array[Vector2] = []
	match count:
		2:
			spots = [Vector2(cx, cy - hi), Vector2(cx, cy + hi)]
		3:
			spots = [Vector2(cx, cy - hi), Vector2(cx, cy), Vector2(cx, cy + hi)]
		4:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
		5:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi), Vector2(cx, cy),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
		6:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi),
				Vector2(cx - col, cy), Vector2(cx + col, cy),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
		7:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi), Vector2(cx, cy - hi * 0.5),
				Vector2(cx - col, cy), Vector2(cx + col, cy),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
		8:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi), Vector2(cx, cy - hi * 0.5),
				Vector2(cx - col, cy), Vector2(cx + col, cy), Vector2(cx, cy + hi * 0.5),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
		9, 10:
			spots = [
				Vector2(cx - col, cy - hi), Vector2(cx + col, cy - hi),
				Vector2(cx - col, cy - mid), Vector2(cx + col, cy - mid),
				Vector2(cx - col, cy + mid), Vector2(cx + col, cy + mid),
				Vector2(cx - col, cy + hi), Vector2(cx + col, cy + hi),
			]
			if count == 9:
				spots.append(Vector2(cx, cy))
			else:
				spots.append(Vector2(cx, cy - hi * 0.68))
				spots.append(Vector2(cx, cy + hi * 0.68))
		_:
			return
	for at in spots:
		_pip(img, at.x, at.y, rad, suit, color, at.y > cy + 2.0)


static func _court(img: Image, pw: int, ph: int, rank: int, suit: int, color: Color) -> void:
	var x0 := int(0.22 * pw)
	var y0 := int(0.17 * ph)
	var x1 := int(0.78 * pw)
	var y1 := int(0.83 * ph)
	_frame(img, x0, y0, x1, y1, color)
	_frame(img, x0 + 3 * SS, y0 + 3 * SS, x1 - 3 * SS, y1 - 3 * SS, color)
	var stamp := _royal(pw, rank, suit, color)
	var at := Vector2i(int(0.5 * pw) - stamp.get_width() / 2, int(0.22 * ph))
	_blit(img, pw, ph, stamp, at, false)
	_blit(img, pw, ph, stamp, at, true)


static func _royal(pw: int, rank: int, suit: int, color: Color) -> Image:
	var stamp := Image.create(int(0.32 * pw), int(0.36 * pw), false, Image.FORMAT_RGBA8)
	stamp.fill(Color(0, 0, 0, 0))
	var mark := MARK[rank]
	_text(stamp, mark, Vector2(stamp.get_width() * 0.18, stamp.get_height() * 0.02), int(stamp.get_height() * 0.42), color)
	_pip(stamp, stamp.get_width() * 0.5, stamp.get_height() * 0.72, stamp.get_width() * 0.16, suit, color, false)
	return stamp
	return stamp


static func _pip(img: Image, cx: float, cy: float, rad: float, suit: int, color: Color, flip: bool) -> void:
	var r := ceili(rad) + 2
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var cover := 0.0
			for sy in 3:
				for sx in 3:
					var u := (float(x) + (sx + 0.5) / 3.0) / rad
					var v := -(float(y) + (sy + 0.5) / 3.0) / rad
					if flip:
						v = -v
					if _in_suit(u, v, suit):
						cover += 1.0 / 9.0
			if cover > 0.0:
				_blend(img, int(round(cx + x)), int(round(cy + y)), color, cover)


static func _in_suit(u: float, v: float, suit: int) -> bool:
	match suit:
		0:
			return _in_club(u, v)
		1:
			return absf(u) + absf(v) < 0.95
		2:
			return _in_heart(u, v)
		_:
			return _in_heart(u, -v * 0.92 - 0.06) \
				or (absf(u) < 0.12 and v < 0.12 and v > -1.05) \
				or (absf(u) < 0.38 and v < -0.7 and v > -1.08)


static func _in_heart(u: float, v: float) -> bool:
	var p := Vector2(u, v)
	return p.distance_to(Vector2(-0.32, 0.28)) <= 0.46 \
		or p.distance_to(Vector2(0.32, 0.28)) <= 0.46 \
		or _in_tri(p, Vector2(0.0, -0.98), Vector2(-0.8, 0.2), Vector2(0.8, 0.2))


static func _in_club(u: float, v: float) -> bool:
	var p := Vector2(u, v)
	return p.distance_to(Vector2(0.0, 0.4)) <= 0.42 \
		or p.distance_to(Vector2(-0.4, -0.1)) <= 0.42 \
		or p.distance_to(Vector2(0.4, -0.1)) <= 0.42 \
		or (absf(u) < 0.12 and v < 0.12 and v > -1.02) \
		or (absf(u) < 0.36 and v < -0.68 and v > -1.08)


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if is_zero_approx(den):
		return false
	var aa := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
	var bb := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
	return aa >= 0.0 and bb >= 0.0 and aa + bb <= 1.0


static func _blit(dst: Image, pw: int, ph: int, src: Image, at: Vector2i, flip: bool) -> void:
	for y in src.get_height():
		for x in src.get_width():
			var color := src.get_pixel(x, y)
			if color.a < 0.05:
				continue
			var px := at.x + x
			var py := at.y + y
			if flip:
				px = pw - 1 - px
				py = ph - 1 - py
			_blend(dst, px, py, color, color.a)


static func _frame(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	_dot_rect(img, x0, y0, x1 - x0 + 1, 2 * SS, color)
	_dot_rect(img, x0, y1 - 2 * SS, x1 - x0 + 1, 2 * SS, color)
	_dot_rect(img, x0, y0, 2 * SS, y1 - y0 + 1, color)
	_dot_rect(img, x1 - 2 * SS, y0, 2 * SS, y1 - y0 + 1, color)


static func _ring(img: Image, cx: float, cy: float, inner: float, outer: float, color: Color) -> void:
	var r := ceili(outer) + 2
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := Vector2(x, y).length()
			var a := clampf(outer + 0.65 - d, 0.0, 1.0) * clampf(d - inner + 0.65, 0.0, 1.0)
			if a > 0.0:
				_blend(img, int(round(cx + x)), int(round(cy + y)), color, a)


static func _dot_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for py in h:
		for px in w:
			_plot(img, x + px, y + py, color)


static func _plot(img: Image, x: int, y: int, color: Color) -> void:
	_blend(img, x, y, color, color.a)


static func _blend(img: Image, x: int, y: int, color: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or a <= 0.0:
		return
	var dst := img.get_pixel(x, y)
	var t := clampf(a, 0.0, 1.0)
	img.set_pixel(
		x,
		y,
		Color(
			lerpf(dst.r, color.r, t),
			lerpf(dst.g, color.g, t),
			lerpf(dst.b, color.b, t),
			maxf(dst.a, t * color.a)
		)
	)
