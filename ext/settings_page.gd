extends "res://world/ui/settings_page.gd"
## Adds the Dialogue Tweaks talk-over addressee choice under World.

const DIALOGUE_SETTINGS := preload("res://mods/dialogue_tweaks/settings.gd")
const ANCHOR_KEY := "ai/freeze_while_thinking"
const ADDRESSING_OPTIONS := [
	["base", "Base game"],
	["looked_at_interrupted", "She answers"],
]

var _addressing_card: PanelContainer
var _addressing_pills: Array[Button] = []


func _fill_list(t: int, list: VBoxContainer) -> void:
	super(t, list)
	if str(Settings.TABS[t][0]) == "World":
		_add_addressing_row(list)


func refresh() -> void:
	super()
	_refresh_addressing()


func _remove_card(card: Control) -> void:
	if not is_instance_valid(card): return
	if card.get_parent() != null: card.get_parent().remove_child(card)
	card.queue_free()


func _add_addressing_row(list: VBoxContainer) -> void:
	_remove_card(_addressing_card)
	_addressing_card = null
	_addressing_pills.clear()

	var card := PanelContainer.new()
	_addressing_card = card
	card.add_theme_stylebox_override("panel", _row_idle)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.mouse_entered.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _row_hover)
		_redraw())
	card.mouse_exited.connect(func() -> void:
		card.add_theme_stylebox_override("panel", _row_idle)
		_redraw())

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
	var title := STYLE.label("When I look at the interrupted pony", "", font_size)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(title)
	texts.add_child(STYLE.label("unnamed replies only", "Faint", font_size - 5))

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

	list.add_child(card)
	var anchor: Control = _row_cards.get(ANCHOR_KEY)
	if is_instance_valid(anchor) and anchor.get_parent() == list:
		list.move_child(card, anchor.get_index() + 1)
	_refresh_addressing()


func _refresh_addressing() -> void:
	var chosen := DIALOGUE_SETTINGS.load_addressing()
	for pill: Button in _addressing_pills:
		if is_instance_valid(pill):
			pill.set_pressed_no_signal(str(pill.get_meta("value", "")) == chosen)
