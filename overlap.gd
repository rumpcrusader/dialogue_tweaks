extends RefCounted
## Pure talk-over helpers: bucket, truncated quote, WAV onset and the in-world note.
## No node state lives here.

const IMMEDIATE_LIMIT := 0.25
const MID_LIMIT := 0.60
const TOLERATED_LIMIT := 0.90
const QUOTE_MAX := 160
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
	parts.append("You stopped when he spoke up.")
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
