extends RefCounted
## Global Dialogue Tweaks preferences, kept out of the game's own settings keys.

const PATH := "user://dialogue_tweaks.cfg"
const SECTION := "talk_over"
const KEY := "mode"
const DEFAULT := "yield"
const MODES := ["yield", "finish"]
const ADDRESSING_KEY := "addressing"
const ADDRESSING_DEFAULT := "looked_at_interrupted"
const ADDRESSING_MODES := ["looked_at_interrupted", "base"]


static func load_mode() -> String:
	var config := ConfigFile.new()
	if config.load(PATH) != OK: return DEFAULT
	var mode := str(config.get_value(SECTION, KEY, DEFAULT))
	return mode if mode in MODES else DEFAULT


static func save_mode(mode: String) -> void:
	if mode not in MODES: return
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value(SECTION, KEY, mode)
	config.save(PATH)


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
