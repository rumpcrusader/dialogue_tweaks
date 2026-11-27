extends RefCounted
## Global Dialogue Tweaks preferences, kept out of the game's own settings keys.

const PATH := "user://dialogue_tweaks.cfg"
const SECTION := "talk_over"
const ADDRESSING_KEY := "addressing"
const ADDRESSING_DEFAULT := "looked_at_interrupted"
const ADDRESSING_MODES := ["looked_at_interrupted", "base"]


static func load_addressing() -> String:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return ADDRESSING_DEFAULT
	var mode := str(config.get_value(SECTION, ADDRESSING_KEY, ADDRESSING_DEFAULT))
	return mode if mode in ADDRESSING_MODES else ADDRESSING_DEFAULT


static func save_addressing(mode: String) -> void:
	if mode not in ADDRESSING_MODES: return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, ADDRESSING_KEY, mode)
	config.save(PATH)
