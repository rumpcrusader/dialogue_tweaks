extends "res://world/ui/settings_page.gd"
## Adds the Dialogue Tweaks talk-over mode and addressee choice under World.

const DIALOGUE_SETTINGS := preload("res://mods/dialogue_tweaks/settings.gd")
const ANCHOR_KEY := "ai/freeze_while_thinking"
const OPTIONS := [
	["yield", "Yield"],
	["finish", "Finish"],
]
const ADDRESSING_OPTIONS := [
	["looked_at_interrupted", "She answers"],
	["base", "Base game"],
]

var _talk_over_card: PanelContainer
var _talk_over_pills: Array[Button] = []
var _addressing_card: PanelContainer
var _addressing_pills: Array[Button] = []


func _fill_list(t: int, list: VBoxContainer) -> void:
	super(t, list)
	if str(Settings.TABS[t][0]) == "World":
		_add_talk_over_row(list)


func refresh() -> void:
	super()
	_refresh_talk_over()
	_refresh_addressing()


func _remove_card(card: Control) -> void:
	if not is_instance_valid(card): return
	if card.get_parent() != null: card.get_parent().remove_child(card)
	card.queue_free()


func _card(list: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _row_idle)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _row_hover)
		_redraw())
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _row_idle)
		_redraw())
	list.add_child(card)
	return card


func _line(card: PanelContainer, title: String, note: String) -> HBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	card.add_child(stack)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	stack.add_child(line)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 1)
	line.add_child(texts)
	var label := STYLE.label(title, "", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(label)
	texts.add_child(STYLE.label(note, "Faint", font_size - 5))
	return line


func _add_talk_over_row(list: VBoxContainer) -> void:
	_remove_card(_talk_over_card)
	_remove_card(_addressing_card)
	_talk_over_card = null
	_addressing_card = null
	_talk_over_pills.clear()
	_addressing_pills.clear()

	var card := _card(list)
	_talk_over_card = card
	var line := _line(card, "When Anon talks over a pony", "while she is speaking")

	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	line.add_child(track)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	for option: Array in OPTIONS:
		var mode := str(option[0])
		var pill := _button(pills, str(option[1]), func() -> void:
			DIALOGUE_SETTINGS.save_mode(mode)
			_refresh_talk_over()
			_redraw())
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 4)
		pill.set_meta("value", mode)
		_talk_over_pills.append(pill)

	var anchor: Control = _row_cards.get(ANCHOR_KEY)
	if is_instance_valid(anchor) and anchor.get_parent() == list:
		list.move_child(card, anchor.get_index() + 1)
	_add_addressing_row(list)
	_refresh_talk_over()


func _add_addressing_row(list: VBoxContainer) -> void:
	var card := _card(list)
	_addressing_card = card
	var line := _line(card, "When I look at the interrupted pony", "unnamed replies only")
	var track := PanelContainer.new()
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.add_theme_stylebox_override("panel", STYLE.rounded(STYLE.box(
		Color(0.05, 0.02, 0.09, 0.4), Color(1, 1, 1, 0.1), 1, 99, 4, 4)))
	line.add_child(track)
	var pills := HBoxContainer.new()
	pills.add_theme_constant_override("separation", 4)
	track.add_child(pills)
	for option: Array in ADDRESSING_OPTIONS:
		var mode := str(option[0])
		var pill := _button(pills, str(option[1]), func() -> void:
			DIALOGUE_SETTINGS.save_addressing(mode)
			_refresh_addressing()
			_redraw())
		pill.theme_type_variation = "Segment"
		pill.toggle_mode = true
		pill.custom_minimum_size = Vector2(0, font_size * 1.75)
		pill.add_theme_font_size_override("font_size", font_size - 4)
		pill.set_meta("value", mode)
		_addressing_pills.append(pill)
	if is_instance_valid(_talk_over_card) and _talk_over_card.get_parent() == list:
		list.move_child(card, _talk_over_card.get_index() + 1)
	_refresh_addressing()


func _refresh_talk_over() -> void:
	var chosen := DIALOGUE_SETTINGS.load_mode()
	for pill: Button in _talk_over_pills:
		if is_instance_valid(pill):
			pill.set_pressed_no_signal(str(pill.get_meta("value", "")) == chosen)


func _refresh_addressing() -> void:
	var chosen := DIALOGUE_SETTINGS.load_addressing()
	for pill: Button in _addressing_pills:
		if is_instance_valid(pill):
			pill.set_pressed_no_signal(str(pill.get_meta("value", "")) == chosen)
