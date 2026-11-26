extends "res://world/ai/voice_hud.gd"
## Keeps the mic icon green while Anon holds push-to-talk during a talk-over, even though
## the HUD stays in the pony's "speaking" state so her caption keeps revealing.

var talkover_hearing := false


func set_talkover_hearing(value: bool) -> void:
	talkover_hearing = value


func _process(delta: float) -> void:
	super(delta)
	if not talkover_hearing: return
	var color: Color = COLORS["hearing"]
	color = color.lerp(Color(1, 1, 1, 1), 0.5 + 0.5 * sin(_time * 12.0))
	if _rect != null: _rect.modulate = color
	if _sprite != null: _sprite.modulate = color
