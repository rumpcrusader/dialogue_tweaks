extends SceneTree
## Headless checks for the pure talk-over helpers.
##   godot --headless --path <project> --script res://mods/dialogue_tweaks/tests/test_overlap.gd

const OVERLAP := preload("res://mods/dialogue_tweaks/overlap.gd")
const DIRECTOR := preload("res://mods/dialogue_tweaks/ext/conversation_director.gd")

var _failures := 0


func _initialize() -> void:
	_check_bucket()
	_check_truncation()
	_check_wav()
	_check_note()
	_check_listener()
	_check_extension()
	_check_utterance_hold()
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


func _check_wav() -> void:
	var rate := 16000
	var samples := PackedFloat32Array()
	for i in int(rate * 0.5): samples.append(0.0)
	for i in int(rate * 0.2): samples.append(sin(TAU * 440.0 * float(i) / rate) * 0.5)
	var onset := OVERLAP.wav_onset(_wav(samples, rate))
	_check(bool(onset.get("ok", false)), "wav onset ok")
	_check(absf(float(onset.get("onset", -1.0)) - 0.5) < 0.06, "wav onset near 0.5 s")
	var quiet := PackedFloat32Array()
	for i in int(rate * 0.5): quiet.append(0.0)
	for i in int(rate * 0.2): quiet.append(sin(TAU * 440.0 * float(i) / rate) * 0.012)
	var quiet_onset := OVERLAP.wav_onset(_wav(quiet, rate))
	_check(bool(quiet_onset.get("ok", false)), "quiet wav onset ok")
	_check(absf(float(quiet_onset.get("onset", -1.0)) - 0.5) < 0.06, "quiet wav onset near 0.5 s")
	var silent := PackedFloat32Array()
	for i in int(rate * 0.5): silent.append(0.0)
	_check(not bool(OVERLAP.wav_onset(_wav(silent, rate)).get("ok", true)), "silent wav has no onset")
	_check(not bool(OVERLAP.wav_onset("nope".to_ascii_buffer()).get("ok", true)), "malformed wav rejected")


func _check_note() -> void:
	var finish := {
		"bucket": "mid_sentence",
		"behaviour": "finish",
		"cut": "Oh, darling, I was just thinking-",
		"listener_id": "player",
		"source": "ptt",
	}
	var note := OVERLAP.note_for(finish, "Anon")
	_check(note.begins_with("[Observed: "), "note label")
	_check(note.contains("kept going and finished"), "finish sentence")
	_check(note.contains("\"Oh, darling, I was just thinking-\""), "finish quote")
	_check(RegEx.create_from_string("[0-9]").search(note) == null, "note has no digits")
	var yield_note := OVERLAP.note_for({
		"bucket": "immediate", "behaviour": "yield", "stopped": true, "cut": "Oh-", "listener_id": "player", "source": "ptt",
	}, "Anon")
	_check(yield_note.contains("stopped when he spoke up"), "yield sentence")
	var missed_yield := OVERLAP.note_for({
		"bucket": "mid_sentence", "behaviour": "yield", "cut": "Oh, darling-", "listener_id": "player", "source": "ptt",
	}, "Anon")
	_check(missed_yield.contains("kept going and finished"), "yield that missed the onset reports finish")
	var bare := OVERLAP.note_for({
		"bucket": "immediate", "behaviour": "finish", "cut": "", "listener_id": "player", "source": "ptt",
	}, "Anon")
	_check(bare.contains("barely started"), "barely started")
	var ambient := OVERLAP.note_for({
		"bucket": "almost_done", "behaviour": "finish", "cut": "Nearly there-",
		"listener_id": "bon_bon", "listener_name": "Bon Bon", "source": "vad",
		"spoken_prefix_has_question": true,
	}, "Anon")
	_check(ambient.contains("You were talking to Bon Bon."), "ambient listener")
	_check(ambient.contains("already asked him a question"), "spoken question")
	_check(ambient.contains("may not have meant to interrupt"), "vad caution")
	_check(OVERLAP.note_for({
		"bucket": "tolerated", "behaviour": "finish", "cut": "Anything-", "listener_id": "player",
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
	var note := "[Observed: Anon spoke while you were still talking. You kept going and finished what you were saying. At that moment, you had said: \"Oh, darling, I was just thinking-\".]"
	var base := "HEAD\n\nSituation: here\n\nLENGTH OF WHAT YOU SAY OUT LOUD NOW: tail"
	var prompt: String = DIRECTOR.insert_note(base, note)
	_check(prompt.find(note) >= 0, "note in prompt")
	_check(prompt.find(note) < prompt.find("LENGTH OF WHAT YOU SAY OUT LOUD NOW:"), "note before length")
	var plain: String = DIRECTOR.insert_note(base, "")
	_check(plain.find("[Observed:") < 0, "no note when inactive")
	director.free()


func _check_utterance_hold() -> void:
	var director = DIRECTOR.new()
	director.state = "speaking"
	director._recorded = true
	var now: float = DIRECTOR._now()
	var samples := PackedFloat32Array()
	for i in int(16000 * 0.5): samples.append(0.0)
	for i in int(16000 * 0.2): samples.append(sin(TAU * 440.0 * float(i) / 16000.0) * 0.5)
	var wav := _wav(samples, 16000)
	var cues := [
		{"start": 0.0, "end_char": 3},
		{"start": 0.4, "end_char": 11},
		{"start": 0.9, "end_char": 24},
		{"start": 1.4, "end_char": 36},
	]
	director._pending_overlap = {
		"line": "Oh, darling, I was just thinking about that new fabric—",
		"line_started_at": now - 1.0, "line_ends_at": now + 3.0, "duration_s": 4.0,
		"word_cues": cues, "captured_at": now, "behaviour": "finish", "source": "ptt",
	}
	director._active_overlap = {}
	director._held_utterance = []
	director._on_utterance(wav, 0.7)
	_check(not director._active_overlap.is_empty(), "utterance sets active overlap")
	_check(director._held_utterance.size() == 3, "utterance holds while she speaks")
	_check(str(director._active_overlap.get("bucket", "")) == "immediate", "utterance bucket")
	director._pending_overlap = {
		"line": "Oh, darling, I was just thinking about that new fabric—",
		"line_started_at": now - 3.85, "line_ends_at": now + 0.15, "duration_s": 4.0,
		"word_cues": cues, "captured_at": now, "behaviour": "finish", "source": "ptt",
	}
	director._active_overlap = {}
	director._held_utterance = []
	director._on_utterance(wav, 0.7)
	_check(director._active_overlap.is_empty(), "utterance tolerates 90%+")
	_check(director._held_utterance.size() == 3, "tolerated still holds while she speaks")
	var silent := PackedFloat32Array()
	for i in int(16000 * 0.5): silent.append(0.0)
	director._pending_overlap = {
		"line": "Oh, darling, I was just thinking about that new fabric—",
		"line_started_at": now - 1.0, "line_ends_at": now + 3.0, "duration_s": 4.0,
		"word_cues": cues, "captured_at": now, "behaviour": "finish", "source": "ptt",
	}
	director._active_overlap = {}
	director._held_utterance = []
	director._on_utterance(_wav(silent, 16000), 0.5)
	_check(director._active_overlap.is_empty(), "silence makes no note")
	_check(director._held_utterance.size() == 3, "silence still holds while she speaks")
	director.free()


func _wav(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for i in samples.size():
		pcm.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	out.resize(8)
	out.encode_u32(4, 36 + pcm.size())
	out.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var size := PackedByteArray()
	size.resize(4)
	size.encode_u32(0, pcm.size())
	out.append_array(size)
	out.append_array(pcm)
	return out
