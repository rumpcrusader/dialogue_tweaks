extends SceneTree
## Headless checks for the pure talk-over helpers.
##   godot --headless --path <project> --script res://mods/dialogue_tweaks/tests/test_overlap.gd

const OVERLAP := preload("res://mods/dialogue_tweaks/overlap.gd")
const DIRECTOR := preload("res://mods/dialogue_tweaks/ext/conversation_director.gd")

var _failures := 0


func _initialize() -> void:
	_check_bucket()
	_check_truncation()
	_check_note()
	_check_listener()
	_check_extension()
	_check_tolerated_hold()
	if _failures == 0:
		print("TEST_OVERLAP ok")
		quit(0)
	else:
		printerr("TEST_OVERLAP failed: %d" % _failures)
		quit(1)


func _check(condition: bool, name: String) -> void:
	if condition: return
	_failures += 1
	printerr("FAIL ", name)


func _check_bucket() -> void:
	_check(OVERLAP.bucket(0.0) == "immediate", "bucket 0")
	_check(OVERLAP.bucket(0.249) == "immediate", "bucket 0.249")
	_check(OVERLAP.bucket(0.25) == "mid_sentence", "bucket 0.25")
	_check(OVERLAP.bucket(0.599) == "mid_sentence", "bucket 0.599")
	_check(OVERLAP.bucket(0.60) == "almost_done", "bucket 0.60")
	_check(OVERLAP.bucket(0.899) == "almost_done", "bucket 0.899")
	_check(OVERLAP.bucket(0.90) == "tolerated", "bucket 0.90")
	_check(OVERLAP.bucket(1.0) == "tolerated", "bucket 1")


func _check_truncation() -> void:
	var line := "Oh, darling, I was just thinking about that new fabric—"
	var cues := [
		{"start": 0.0, "end_char": 3},
		{"start": 0.4, "end_char": 11},
		{"start": 0.9, "end_char": 24},
		{"start": 1.4, "end_char": 36},
	]
	_check(OVERLAP.truncated_line(line, cues, 1.0) == "Oh, darling, I was just-", "cut mid-sentence")
	_check(OVERLAP.truncated_line(line, cues, 0.1) == "Oh-", "cut first word")
	_check(OVERLAP.truncated_line(line, cues, -1.0) == "", "cut before any word")
	_check(OVERLAP.truncated_line("Hello, world!", [{"start": 0.0, "end_char": 13}], 1.0) == "Hello, world-", "strip punctuation")
	var long_line := "word ".repeat(100)
	var long_cut := OVERLAP.truncated_line(long_line, [{"start": 0.0, "end_char": long_line.length()}], 1.0)
	_check(long_cut.begins_with("…"), "long quote ellipsis")
	_check(long_cut.ends_with("-"), "long quote dash")
	_check(long_cut.length() <= OVERLAP.QUOTE_MAX + 2, "long quote cap")


func _check_note() -> void:
	var note := OVERLAP.note_for({
		"bucket": "mid_sentence",
		"cut": "Oh, darling, I was just thinking-",
		"listener_id": "player",
		"source": "ptt",
	}, "Anon")
	_check(note.begins_with("[Observed: "), "note label")
	_check(note.contains("stopped when he spoke up"), "yield sentence")
	_check(note.contains("\"Oh, darling, I was just thinking-\""), "yield quote")
	_check(RegEx.create_from_string("[0-9]").search(note) == null, "note has no digits")
	var bare := OVERLAP.note_for({
		"bucket": "immediate", "cut": "", "listener_id": "player", "source": "ptt",
	}, "Anon")
	_check(bare.contains("barely started"), "barely started")
	var ambient := OVERLAP.note_for({
		"bucket": "almost_done", "cut": "Nearly there-",
		"listener_id": "bon_bon", "listener_name": "Bon Bon", "source": "vad",
		"spoken_prefix_has_question": true,
	}, "Anon")
	_check(ambient.contains("You were talking to Bon Bon."), "ambient listener")
	_check(ambient.contains("already asked him a question"), "spoken question")
	_check(ambient.contains("may not have meant to interrupt"), "vad caution")
	_check(OVERLAP.note_for({
		"bucket": "tolerated", "cut": "Anything-", "listener_id": "player",
	}, "Anon").is_empty(), "tolerated has no note")


func _check_listener() -> void:
	var base := "fluttershy"
	var reason := "follow_up"
	var interrupted := "twilight_sparkle"
	var mode := "looked_at_interrupted"
	_check(OVERLAP.talk_over_listener(base, reason, interrupted, interrupted, mode) == interrupted, "gaze at interrupted wins")
	_check(OVERLAP.talk_over_listener(base, reason, base, interrupted, mode) == base, "gaze elsewhere keeps base")
	_check(OVERLAP.talk_over_listener(base, reason, "", interrupted, mode) == base, "no gaze keeps base")
	_check(OVERLAP.talk_over_listener(base, "named", interrupted, interrupted, mode) == base, "named keeps base")
	_check(OVERLAP.talk_over_listener(base, "everyone", interrupted, interrupted, mode) == base, "everyone keeps base")
	_check(OVERLAP.talk_over_listener(base, reason, interrupted, interrupted, "base") == base, "base setting keeps base")
	_check(OVERLAP.talk_over_listener(base, reason, interrupted, "", mode) == base, "no interrupted pony keeps base")


func _check_extension() -> void:
	var director = DIRECTOR.new()
	var record := {
		"line": "Oh, darling, I was just thinking about that new fabric—",
		"line_started_at": 100.0,
		"line_ends_at": 104.0,
		"duration_s": 4.0,
		"word_cues": [
			{"start": 0.0, "end_char": 3},
			{"start": 0.4, "end_char": 11},
			{"start": 0.9, "end_char": 24},
			{"start": 1.4, "end_char": 36},
		],
		"captured_at": 100.0,
	}
	var mid: Dictionary = director._finalize_record(record, 101.0)
	_check(str(mid.get("bucket", "")) == "mid_sentence", "extension bucket")
	_check(str(mid.get("cut", "")) == "Oh, darling, I was just-", "extension cut")
	_check(not bool(mid.get("spoken_prefix_has_question", true)), "extension question")
	_check(director._finalize_record(record, 103.7).is_empty(), "extension tolerates 90%+")
	_check(director._finalize_record(record, 104.5).is_empty(), "extension tolerates after line")
	var fake := GDScript.new()
	fake.source_code = "extends Node\nfunc speech_progress() -> Dictionary:\n\treturn {\"time\": 1.0, \"duration\": 4.0}\n"
	_check(fake.reload() == OK, "fake speaker parses")
	var node = fake.new()
	director.set("_current", "rarity")
	director.set("_listener_id", "player")
	director.set("_pending_text", "[face:happy] Oh, darling, I was just thinking about that new fabric—")
	director.set("_pending_word_cues", [])
	director.set("characters", {"rarity": {"node": node, "profile": {"name": "Rarity"}, "history": [], "spoken": [], "heard": []}})
	_check(director._capture_overlap("ptt"), "capture overlap")
	var captured: Dictionary = director._pending_overlap
	_check(str(captured.get("line", "")) == "Oh, darling, I was just thinking about that new fabric—", "capture strips tags")
	_check(absf(float(captured.get("duration_s", 0.0)) - 4.0) < 0.001, "capture duration")
	_check(str(captured.get("source", "")) == "ptt", "capture source")
	node.free()
	var note := "[Observed: Anon spoke while you were still talking. You stopped when he spoke up. At that moment, you had said: \"Oh, darling, I was just thinking-\".]"
	var base := "HEAD\n\nSituation: here\n\nLENGTH OF WHAT YOU SAY OUT LOUD NOW: tail"
	var prompt: String = DIRECTOR.insert_note(base, note)
	_check(prompt.find(note) >= 0, "note in prompt")
	_check(prompt.find(note) < prompt.find("LENGTH OF WHAT YOU SAY OUT LOUD NOW:"), "note before length")
	var plain: String = DIRECTOR.insert_note(base, "")
	_check(plain.find("[Observed:") < 0, "no note when inactive")
	director.free()


func _check_tolerated_hold() -> void:
	var director = DIRECTOR.new()
	director.state = "speaking"
	director._recorded = true
	director._tolerate_release = true
	director._held_utterance = []
	director._on_utterance(PackedByteArray(), 0.5)
	_check(director._held_utterance.size() == 3, "tolerated release holds while she speaks")
	_check(not director._tolerate_release, "tolerated release remembers once")
	director.free()
