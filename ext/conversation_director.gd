extends "res://world/ai/conversation_director.gd"
## Dialogue Tweaks: talk-over prototype.
##
## When Anon starts talking while a pony is audibly speaking, her line is protected.
## "yield" takes the floor as soon as he presses or speaks and keeps the part she actually
## said; "finish" lets her complete it. Either way the player's words are processed normally
## and the reply for that turn gets one short, in-world note about the overlap.

const OVERLAP := preload("res://mods/dialogue_tweaks/overlap.gd")
const MOD_SETTINGS := preload("res://mods/dialogue_tweaks/settings.gd")

## "yield" or "finish". Settings → World chooses it at runtime.
## yield takes the floor as soon as he presses/talks; finish lets her complete the line.
const LENGTH_MARKER := "LENGTH OF WHAT YOU SAY OUT LOUD NOW:"
const OVERLAP_FRESH_SECONDS := 120.0

var _pending_overlap: Dictionary = {}
var _active_overlap: Dictionary = {}
var _active_note := ""
var _active_note_speaker := ""
var _suppress_interrupt := false
var _keep_partial := false
var _note_in_use := false
var _talk_over_reply_speaker := ""


func _on_talk_pressed() -> void:
	if _dictating():
		super()
		return
	if not _is_audibly_speaking():
		super()
		return
	if _talk_over_mode() == "yield":
		if _yield_now("ptt"):
			_set_talkover_mic(true)
			return
		super()
		return
	_capture_overlap("ptt")
	if _pending_overlap.is_empty():
		super()
		return
	_set_talkover_mic(true)
	_suppress_interrupt = true
	super()
	_suppress_interrupt = false


func _on_speech_state(value: String) -> void:
	if _dictating():
		super(value)
		return
	if value == "hearing" and _is_audibly_speaking():
		# _on_talk_pressed already handled the push-to-talk press.
		if not _pending_overlap.is_empty(): return
		if _talk_over_mode() == "yield":
			if _yield_now("vad"):
				_set_talkover_mic(true)
				return
			super(value)
			return
		if _capture_overlap("vad"):
			_set_talkover_mic(true)
			_suppress_interrupt = true
			super(value)
			_suppress_interrupt = false
			return
	super(value)


func _on_utterance(wav: PackedByteArray, seconds: float, is_feedback := false) -> void:
	_set_talkover_mic(false)
	if is_feedback:
		super(wav, seconds, is_feedback)
		return
	if _pending_overlap.is_empty():
		super(wav, seconds, is_feedback)
		return
	var record := _pending_overlap
	_pending_overlap = {}
	var onset := OVERLAP.wav_onset(wav)
	var speech_started_at := -1.0
	if bool(onset.get("ok", false)):
		var duration := float(onset.get("duration", seconds))
		speech_started_at = _now() - duration + float(onset.get("onset", 0.0))
		if debug:
			print("[dialogue_tweaks] wav onset %.3fs of %.3fs" % [float(onset.get("onset", 0.0)), duration])
	else:
		var error := str(onset.get("error", ""))
		if error == "no voiced window" or error == "shorter than one window":
			# A silent press is not an interruption: never cut her and never note it.
			if debug: print("[dialogue_tweaks] %s; no note" % error)
			if _is_audibly_speaking(): _held_utterance = [wav, seconds, is_feedback]
			else: super(wav, seconds, is_feedback)
			return
		push_warning("[dialogue_tweaks] WAV onset unavailable: " + error)
		speech_started_at = _now() - maxf(0.0, seconds)
	var finalized: Dictionary = {}
	if not bool(record.get("suppress_note", false)):
		finalized = _finalize_record(record, speech_started_at)
	if not finalized.is_empty():
		if str(record.get("behaviour", _talk_over_mode())) == "yield" and _is_audibly_speaking():
			_stop_for_overlap(str(finalized.get("cut", "")), finalized)
		else:
			_active_overlap = finalized
	if _is_audibly_speaking():
		_held_utterance = [wav, seconds, is_feedback]
		return
	super(wav, seconds, is_feedback)


func handle_text(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty(): return
	if floor_held():
		_held_text = text
		return
	if _is_audibly_speaking():
		# A voice press already owns this overlap: let its WAV finish the capture.
		if not _pending_overlap.is_empty() and str(_pending_overlap.get("source", "")) != "typed":
			if _now() - float(_pending_overlap.get("captured_at", 0.0)) <= 30.0:
				_held_text = text
				return
			_pending_overlap = {}
		_capture_overlap("typed")
		if _pending_overlap.is_empty():
			_held_text = text
			return
		var record := _pending_overlap
		_pending_overlap = {}
		var finalized := _finalize_record(record, _now())
		if _talk_over_mode() == "yield":
			if finalized.is_empty():
				_held_text = text
				return
			_stop_for_overlap(str(finalized.get("cut", "")), finalized)
		else:
			if not finalized.is_empty(): _active_overlap = finalized
			_held_text = text
			return
	if not _active_overlap.is_empty():
		if float(_active_overlap.get("captured_at", -1e9)) + OVERLAP_FRESH_SECONDS < _now():
			_active_overlap = {}
		else:
			var record := _active_overlap
			_active_overlap = {}
			var speaker_id := str(record.get("speaker_id", ""))
			_talk_over_reply_speaker = speaker_id
			var target := pick_listener(text)
			if target.is_empty() or target != speaker_id:
				# He is answering somepony else; the overlap note belongs to the pony
				# who was talking, not to the new listener.
				if debug:
					print("[dialogue_tweaks] note dropped: speaker %s, listener %s" % [speaker_id, target])
				super(text)
				_talk_over_reply_speaker = ""
				return
			_active_note = OVERLAP.note_for(record, _player_name())
			_active_note_speaker = speaker_id
			if debug and not _active_note.is_empty():
				print("[dialogue_tweaks] note %s %s %.0f%% %s cut=\"%s\"" % [
					str(record.get("speaker_id", "")), str(record.get("source", "")),
					float(record.get("fraction_spoken", 0.0)) * 100.0,
					str(record.get("bucket", "")), str(record.get("cut", ""))])
			if not _active_note.is_empty():
				_note_in_use = true
				super(text)
				_note_in_use = false
				_talk_over_reply_speaker = ""
				if state == "idle":
					_active_note = ""
					_active_note_speaker = ""
				return
	super(text)
	_talk_over_reply_speaker = ""


func system_prompt(id: String) -> String:
	if not _active_note.is_empty() and not _active_note_speaker.is_empty() and id != _active_note_speaker:
		_active_note = ""
		_active_note_speaker = ""
		return super(id)
	return insert_note(super(id), _active_note)


## Pure placement helper: the note is live context, before the reply-length rule.
static func insert_note(base: String, note: String) -> String:
	if note.is_empty(): return base
	var at := base.rfind(LENGTH_MARKER)
	if at < 0: return base + "\n" + note
	return base.left(at) + note + "\n" + base.substr(at)


func interrupt() -> void:
	if _suppress_interrupt:
		_suppress_interrupt = false
		return
	_set_talkover_mic(false)
	if not _note_in_use:
		_active_note = ""
		_active_note_speaker = ""
	_pending_overlap = {}
	_active_overlap = {}
	super()


func _discard_unfinished_history() -> void:
	if _keep_partial and not _history_record.is_empty():
		_history_record = {}
		_recorded = false
		return
	super()


func _on_speech_finished(id: String = "") -> void:
	var owned := id == "" or _current == "" or id == _current
	var was_speaking := state == "speaking"
	super(id)
	if owned and was_speaking:
		_active_note = ""
		_active_note_speaker = ""


func _fail(why: String) -> void:
	_set_talkover_mic(false)
	_talk_over_reply_speaker = ""
	_pending_overlap = {}
	_active_overlap = {}
	_active_note = ""
	_active_note_speaker = ""
	super(why)


func _on_world_reopened(world_id: String) -> void:
	_set_talkover_mic(false)
	_talk_over_reply_speaker = ""
	_pending_overlap = {}
	_active_overlap = {}
	_active_note = ""
	_active_note_speaker = ""
	super(world_id)


func _exit_tree() -> void:
	_set_talkover_mic(false)
	_talk_over_reply_speaker = ""
	_pending_overlap = {}
	_active_overlap = {}
	_active_note = ""
	_active_note_speaker = ""
	super()


func _is_audibly_speaking() -> bool:
	return state == "speaking" and _recorded and not floor_held()


func _talk_over_mode() -> String:
	return MOD_SETTINGS.load_mode()


## Only when he is looking at the pony he interrupted: she answers instead of a stale follow-up
## partner. Names and "everyone" still win, and every other case is the base game's choice.
func pick_listener(text := "") -> String:
	var id := super(text)
	if _talk_over_reply_speaker.is_empty(): return id
	var chosen := OVERLAP.talk_over_listener(
		id, str(_address.get("reason", "")), _gazed_listener(),
		_talk_over_reply_speaker, MOD_SETTINGS.load_addressing())
	if chosen == id or not _can_answer(chosen): return id
	var addressed: Array[String] = [chosen]
	_address = {"id": chosen, "reason": "gaze", "addressed": addressed, "everyone": false}
	return chosen


func _can_answer(id: String) -> bool:
	if not characters.has(id): return false
	var node: Variant = characters[id].node
	return is_instance_valid(node) and is_instance_valid(player_head) and awareness.can_hear(node, player_head, _earshot(id))


func _set_talkover_mic(value: bool) -> void:
	if is_instance_valid(hud) and hud.has_method("set_talkover_hearing"):
		hud.call("set_talkover_hearing", value)


func _dictating() -> bool:
	return _speech_input != null and _speech_input.has_method("dictating") and bool(_speech_input.dictating())


func _player_name() -> String:
	var name := str(config.get_value("player_name", "Anon")).strip_edges()
	return name if not name.is_empty() else "Anon"


func _capture_overlap(source: String) -> bool:
	if not _pending_overlap.is_empty():
		if _now() - float(_pending_overlap.get("captured_at", 0.0)) <= 30.0: return true
		_pending_overlap = {}
	if not characters.has(_current): return false
	var node: Variant = characters[_current].node
	if not is_instance_valid(node): return false
	var raw_line := _strip_tag(_pending_text)
	var line := raw_line.strip_edges()
	if line.is_empty(): return false
	var progress: Dictionary = node.speech_progress() if node.has_method("speech_progress") else {}
	var elapsed := maxf(0.0, float(progress.get("time", 0.0)))
	var duration := float(progress.get("duration", 0.0))
	var approximate := false
	if not is_finite(duration) or duration <= 0.0:
		duration = maxf(0.1, line.length() * 0.065)
		approximate = true
	var cues: Array = _pending_word_cues.duplicate(true) if not _pending_word_cues.is_empty() else SENTENCES.timed_words(raw_line, duration)
	var listener_name := ""
	if _listener_id != "player" and characters.has(_listener_id):
		listener_name = str(characters[_listener_id].profile.get("name", _listener_id))
	var now := _now()
	_pending_overlap = {
		"speaker_id": _current,
		"turn_id": _turn_id,
		"voice_id": _voice_id,
		"source": source,
		"behaviour": _talk_over_mode(),
		"line": raw_line,
		"duration_s": duration,
		"duration_approximate": approximate,
		"line_started_at": now - elapsed,
		"line_ends_at": now - elapsed + duration,
		"word_cues": cues,
		"listener_id": _listener_id,
		"listener_name": listener_name,
		"ambient": bool(group.active() and group.ambient),
		"group": group.active(),
		"group_members": group.members.duplicate(),
		"captured_at": now,
	}
	if debug:
		print("[dialogue_tweaks] overlap capture %s %s turn %d elapsed %.2fs of %.2fs" % [source, _current, _turn_id, elapsed, duration])
	return true


func _finalize_record(record: Dictionary, speech_started_at: float) -> Dictionary:
	var line_started := float(record.get("line_started_at", speech_started_at))
	var duration := maxf(0.1, float(record.get("duration_s", 0.1)))
	var line_ends := float(record.get("line_ends_at", line_started + duration))
	if speech_started_at >= line_ends: return {}
	var fraction := clampf((speech_started_at - line_started) / duration, 0.0, 1.0)
	if fraction >= OVERLAP.TOLERATED_LIMIT: return {}
	var cut := OVERLAP.truncated_line(str(record.get("line", "")), record.get("word_cues", []), maxf(0.0, speech_started_at - line_started))
	var out := record.duplicate(true)
	out["speech_started_at"] = speech_started_at
	out["fraction_spoken"] = fraction
	out["bucket"] = OVERLAP.bucket(fraction)
	out["cut"] = cut
	out["spoken_prefix_has_question"] = cut.contains("?")
	return out


func _yield_now(source: String) -> bool:
	if not _capture_overlap(source): return false
	var speech_started_at := _now()
	var record := _pending_overlap.duplicate(true)
	record["source"] = source
	record["behaviour"] = "yield"
	var line_started := float(record.get("line_started_at", speech_started_at))
	var duration := maxf(0.1, float(record.get("duration_s", 0.1)))
	var fraction := clampf((speech_started_at - line_started) / duration, 0.0, 1.0)
	if fraction >= OVERLAP.TOLERATED_LIMIT:
		if debug: print("[dialogue_tweaks] yield tolerated %.0f%%; letting her finish" % (fraction * 100.0))
		_pending_overlap = record
		_pending_overlap["behaviour"] = "finish"
		_pending_overlap["suppress_note"] = true
		return true
	var finalized := _finalize_record(record, speech_started_at)
	_pending_overlap = {}
	if finalized.is_empty():
		if debug: print("[dialogue_tweaks] yield produced no note")
		return false
	if debug:
		print("[dialogue_tweaks] yield %s %.0f%% cut=\"%s\"" % [
			source, float(finalized.get("fraction_spoken", 0.0)) * 100.0, str(finalized.get("cut", ""))])
	_stop_for_overlap(str(finalized.get("cut", "")), finalized)
	return true


func _stop_for_overlap(cut: String, record: Dictionary) -> void:
	record["stopped"] = true
	if debug:
		print("[dialogue_tweaks] yield stop %s %s %.0f%% cut=\"%s\"" % [
			_current, str(record.get("source", "")),
			float(record.get("fraction_spoken", 0.0)) * 100.0, cut])
	if not characters.has(_current):
		_active_overlap = record
		return
	var entry: Dictionary = characters[_current]
	var node: Variant = entry.get("node")
	var listener := _listener_id
	var audience: Array[String] = []
	if is_instance_valid(node): audience = _audience(node)
	if not _history_record.is_empty():
		if cut.strip_edges().is_empty():
			if not entry.history.is_empty() and entry.history[entry.history.size() - 1] == _history_record:
				entry.history.pop_back()
			if not entry.spoken.is_empty(): entry.spoken.pop_back()
			_history_record = {}
		else:
			_history_record["content"] = cut
			if not entry.spoken.is_empty(): entry.spoken[entry.spoken.size() - 1] = cut
	_pending_text = cut
	_keep_partial = true
	interrupt()
	_keep_partial = false
	_set_talkover_mic(str(record.get("source", "")) != "typed" and speech != null and speech.state == "hearing")
	if not cut.strip_edges().is_empty(): _record_heard(_current, listener, cut, audience)
	if hud != null and hud.has_method("finish_line"): hud.finish_line()
	_active_overlap = record
