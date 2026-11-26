extends RefCounted
## Pure talk-over helpers: bucket, truncated quote, WAV onset and the in-world note.
## No node state lives here.

const IMMEDIATE_LIMIT := 0.25
const MID_LIMIT := 0.60
const TOLERATED_LIMIT := 0.90
const QUOTE_MAX := 160
const ONSET_WINDOW_SECONDS := 0.020
const ONSET_MIN_RMS := 0.005
const ONSET_PEAK_FRACTION := 0.06
const TRAILING_PUNCTUATION := ",.;:!?—–-"


static func bucket(fraction: float) -> String:
	if fraction < IMMEDIATE_LIMIT: return "immediate"
	if fraction < MID_LIMIT: return "mid_sentence"
	if fraction < TOLERATED_LIMIT: return "almost_done"
	return "tolerated"


## The last whole word that had started, with "-" at the cut. "" when no word had started.
static func truncated_line(line: String, cues: Array, elapsed: float) -> String:
	var end_char := 0
	for cue: Variant in cues:
		if not cue is Dictionary: continue
		var start := float((cue as Dictionary).get("start", 0.0))
		if start > elapsed: break
		end_char = int((cue as Dictionary).get("end_char", 0))
	if end_char <= 0: return ""
	var cut := line.left(mini(end_char, line.length())).strip_edges()
	while not cut.is_empty() and TRAILING_PUNCTUATION.find(cut.right(1)) >= 0:
		cut = cut.left(cut.length() - 1).strip_edges()
	if cut.is_empty(): return ""
	if cut.length() > QUOTE_MAX:
		cut = "…" + cut.right(QUOTE_MAX).strip_edges()
	return cut + "-"


## First voiced 20 ms window pair in a mono/stereo PCM16 RIFF/WAVE.
## Returns {ok, rate, duration, onset} or {ok: false, error}.
static func wav_onset(wav: PackedByteArray) -> Dictionary:
	if wav.size() < 44:
		return {"ok": false, "error": "too short"}
	if wav.slice(0, 4).get_string_from_ascii() != "RIFF" or wav.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"ok": false, "error": "not a RIFF/WAVE file"}
	var at := 12
	var audio_format := 0
	var channels := 0
	var rate := 0
	var bits := 0
	var data_offset := -1
	var data_size := 0
	while at + 8 <= wav.size():
		var chunk := wav.slice(at, at + 4).get_string_from_ascii()
		var size := int(wav.decode_u32(at + 4))
		var body := at + 8
		if chunk == "fmt ":
			if body + 16 > wav.size():
				return {"ok": false, "error": "short fmt chunk"}
			audio_format = int(wav.decode_u16(body))
			channels = int(wav.decode_u16(body + 2))
			rate = int(wav.decode_u32(body + 4))
			bits = int(wav.decode_u16(body + 14))
		elif chunk == "data":
			data_offset = body
			data_size = mini(size, wav.size() - body)
		var advance := size + (size % 2)
		if advance <= 0: break
		at = body + advance
	if audio_format != 1 or channels <= 0 or rate <= 0 or bits != 16:
		return {"ok": false, "error": "not mono/stereo PCM16"}
	if data_offset < 0 or data_size <= 0:
		return {"ok": false, "error": "no data chunk"}
	var frame_bytes := channels * 2
	var frames := data_size / frame_bytes
	if frames <= 0:
		return {"ok": false, "error": "no frames"}
	var peak := 0.0
	for i in frames:
		var sample := absf(float(wav.decode_s16(data_offset + i * frame_bytes)) / 32768.0)
		if sample > peak: peak = sample
	var threshold := maxf(ONSET_MIN_RMS, peak * ONSET_PEAK_FRACTION)
	var window := maxi(1, int(rate * ONSET_WINDOW_SECONDS))
	if frames < window:
		return {"ok": false, "error": "shorter than one window"}
	var hits := 0
	var i := 0
	while i + window <= frames:
		var sum := 0.0
		for j in window:
			var sample := float(wav.decode_s16(data_offset + (i + j) * frame_bytes)) / 32768.0
			sum += sample * sample
		var rms := sqrt(sum / window)
		if rms >= threshold:
			hits += 1
			if hits >= 2:
				var onset := maxf(0.0, float(i - window) / float(rate))
				return {"ok": true, "rate": rate, "duration": float(frames) / float(rate), "onset": onset}
		else:
			hits = 0
		i += window
	return {"ok": false, "error": "no voiced window"}


## Talk-over addressee: only replace the base result when he is looking at the pony he interrupted.
## Names and "everyone" always win; every other case stays exactly as the base game resolved it.
static func talk_over_listener(base_id: String, base_reason: String, gazed: String, interrupted: String, addressing: String) -> String:
	if base_id.is_empty() or interrupted.is_empty(): return base_id
	if addressing != "looked_at_interrupted": return base_id
	if base_reason in ["named", "everyone"]: return base_id
	if gazed == interrupted: return interrupted
	return base_id


## The current-turn note. No numbers, no verdict about rudeness, no developer terms.
static func note_for(record: Dictionary, player_name := "Anon") -> String:
	if str(record.get("bucket", "tolerated")) == "tolerated":
		return ""
	var who := player_name.strip_edges()
	if who.is_empty(): who = "Anon"
	var parts: PackedStringArray = []
	parts.append("%s spoke while you were still talking." % who)
	if bool(record.get("stopped", false)):
		parts.append("You stopped when he spoke up.")
	else:
		parts.append("You kept going and finished what you were saying.")
	var quote := str(record.get("cut", "")).strip_edges()
	if quote.is_empty():
		parts.append("At that moment, you had barely started.")
	else:
		parts.append("At that moment, you had said: \"%s\"." % quote)
	var listener_name := str(record.get("listener_name", "")).strip_edges()
	if not listener_name.is_empty() and str(record.get("listener_id", "player")) != "player":
		parts.append("You were talking to %s." % listener_name)
	if bool(record.get("spoken_prefix_has_question", false)):
		parts.append("You had already asked him a question.")
	if str(record.get("source", "")) == "vad":
		parts.append("He may not have meant to interrupt.")
	return "[Observed: " + " ".join(parts) + "]"
