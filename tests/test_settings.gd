extends SceneTree
## Headless check for the World → talk-over addressee row.
##   XDG_DATA_HOME=<isolated dir> godot --headless --path <project> \
##     --script res://mods/dialogue_tweaks/tests/test_settings.gd -- --mod-src dialogue_tweaks

const MOD_SETTINGS := preload("res://mods/dialogue_tweaks/settings.gd")

var _failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").contains("dialogue-tweaks-settings"):
		printerr("TEST_SETTINGS_REFUSED: use an isolated XDG_DATA_HOME")
		quit(1)
		return
	var previous_addressing := MOD_SETTINGS.load_addressing()
	MOD_SETTINGS.save_addressing(MOD_SETTINGS.ADDRESSING_DEFAULT)
	var page_script := load("res://world/ui/settings_page.gd") as Script
	_check(page_script != null, "settings page script loads")
	if page_script == null:
		quit(1)
		return
	var page = page_script.new()
	page.setup(Vector2(1280, 800), 20, "Back")
	root.add_child(page)
	page.show_tab("World")
	var world := -1
	for i in Settings.TABS.size():
		if str(Settings.TABS[i][0]) == "World": world = i
	_check(world >= 0, "World tab exists")
	var lists: Array = page.get("_lists")
	var pills: Array = page.get("_addressing_pills")
	_check(pills.size() == 2, "two addressing pills")
	_check(pills.size() == 2 and str(pills[0].get_meta("value", "")) == "base" and pills[0].text == "Base game", "Base game first")
	_check(pills.size() == 2 and str(pills[1].get_meta("value", "")) == "looked_at_interrupted" and pills[1].text == "She answers", "She answers second")
	_check(_has_label(lists[world], "When I look at the interrupted pony"), "addressing row in World")
	var card: Control = page.get("_addressing_card")
	var anchor: Control = page.get("_row_cards").get("ai/freeze_while_thinking")
	_check(is_instance_valid(card) and is_instance_valid(anchor), "addressing row and anchor exist")
	if is_instance_valid(card) and is_instance_valid(anchor):
		_check(card.get_index() == anchor.get_index() + 1, "addressing row follows the freeze checkbox")
	var selected := 0
	for pill: Button in pills:
		if pill.button_pressed:
			selected += 1
			_check(str(pill.get_meta("value", "")) == "looked_at_interrupted", "She answers selected by default")
	_check(selected == 1, "one addressing pill selected")
	for pill: Button in pills:
		if str(pill.get_meta("value", "")) == "base":
			pill.emit_signal("pressed")
	_check(MOD_SETTINGS.load_addressing() == "base", "Base game writes the setting")
	for pill: Button in pills:
		if str(pill.get_meta("value", "")) == "looked_at_interrupted":
			pill.emit_signal("pressed")
	_check(MOD_SETTINGS.load_addressing() == "looked_at_interrupted", "She answers writes the setting")
	var hud_script := load("res://world/ai/voice_hud.gd") as Script
	var hud = hud_script.new() if hud_script != null else null
	_check(hud != null and hud.has_method("set_talkover_hearing"), "voice HUD extension")
	if hud != null: hud.free()
	MOD_SETTINGS.save_addressing(previous_addressing)
	page.free()
	if _failures == 0:
		print("TEST_SETTINGS ok")
		quit(0)
	else:
		printerr("TEST_SETTINGS failed: %d" % _failures)
		quit(1)


func _check(condition: bool, label: String) -> void:
	if condition: return
	_failures += 1
	printerr("FAIL ", label)


func _has_label(node: Node, text: String) -> bool:
	if node is Node and node is Label and (node as Label).text == text: return true
	for child: Node in node.get_children():
		if _has_label(child, text): return true
	return false
