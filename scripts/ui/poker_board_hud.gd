class_name PokerBoardHud
extends VBoxContainer
## Right-side community cards, plus the other seat at showdown.

const CARD := Vector2(160, 224)

var _sig := ""


func refresh(player: Player) -> void:
	if player == null or player.poker == null:
		show_rows([], [])
		return
	show_rows(player.poker.board_ids(player), player.poker.reveal_ids(player))


func show_ids(ids: Array) -> void:
	show_rows(ids, [])


func show_rows(board: Array, villain: Array) -> void:
	var sig := "%s|%s" % [PokerEval.labels(board), PokerEval.labels(villain)]
	if sig == _sig:
		return
	_sig = sig
	for child in get_children():
		remove_child(child)
		child.free()
	visible = not board.is_empty() or not villain.is_empty()
	if not board.is_empty():
		add_child(_row(board))
	if not villain.is_empty():
		var tag := Label.new()
		tag.text = HudStyle.chrome("Their hand")
		tag.label_settings = HudStyle.readout(Palette.AMBER, 16)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tag)
		add_child(_row(villain))


func card_count() -> int:
	var n := 0
	for child in get_children():
		if child is HBoxContainer:
			n += child.get_child_count()
	return n


func _row(ids: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for card in ids:
		var face := TextureRect.new()
		face.texture = PokerCardArt.face(int(card))
		face.custom_minimum_size = CARD
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(face)
	return row
