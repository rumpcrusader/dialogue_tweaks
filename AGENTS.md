# Dialogue Tweaks — agent notes

Home: Equestria mod (`dialogue_tweaks`) for conversation behaviour. The current feature is talk-over.

## Talk-over

When Anon presses T, speaks into the VAD, or sends typed chat while a pony is audibly speaking:

- She stops immediately on the input.
- Keep the part she actually said in history and heard speech.
- Do not commit the cut line's feeling tags, farewell, transport or encounter completion.
- In the last tenth of her line she is allowed to finish and gets no note.

The reply for that turn gets one factual note in `system_prompt()`, before `LENGTH OF WHAT YOU SAY OUT LOUD NOW:`.

- The note uses `[Observed: ...]`, contains no numbers or developer terms, and never says the act was rude.
- The note says she stopped and quotes the truncated line.
- Do not put the note in Anon's text, history, `heard_speech` or world memory.
- Do not write a talk-over world event, use `impressions.commit`, or change mood/friendship from the overlap.

## Addressee

On a talk-over turn, the interrupted pony can answer instead of the base game's follow-up partner.

- World setting: **When I look at the interrupted pony** → `[Base game] [She answers]`.
- `She answers`: only when the player's gaze is exactly the interrupted pony.
- `Base game`: leave `addressee.gd` untouched.
- Names and “everyone” always win in both choices.
- Any other case keeps `addressee.gd`'s result (named > everyone > follow-up partner > gaze > nearest).

## Files

- `mod.json` — extends the director, settings page and voice HUD.
- `overlap.gd` — pure helpers: bucket, truncated quote, note, talk-over listener choice.
- `ext/conversation_director.gd` — capture, yield, note, microphone HUD override, addressee override.
- `ext/settings_page.gd` — World-tab addressee row.
- `ext/voice_hud.gd` — green mic while PTT is held during a talk-over.
- `settings.gd` — global mod settings.
- `tests/test_overlap.gd` — pure helpers and director helpers.
- `tests/test_settings.gd` — World row, persistence and extension checks.

This folder is its own git repository. The parent game repository leaves it untracked; do not add it there.

## Settings

Stored in `user://dialogue_tweaks.cfg`, section `talk_over`:

- `addressing`: `looked_at_interrupted` or `base`.

Default: `looked_at_interrupted` (She answers).

## Build and run

Godot 4.5. Run from this folder or by path:

```bash
./build.sh                         # dist/dialogue_tweaks-<version>.pck
./run.sh                           # game from source, tees to last-run.log
```

`build.sh` needs `godot`, `git`, `python3`, `tar`. It packs tracked and untracked non-ignored files, excluding tests, scripts, docs, logs, `.pck` and `.uid`.

`run.sh` filters `[typing_lock]` lines and writes `last-run.log`. It forces desktop (`--xr-mode off`); run Godot directly for VR.

Tests:

```bash
XDG_DATA_HOME=/tmp/dialogue-tweaks-settings godot --headless --path <project> \
  --script res://mods/dialogue_tweaks/tests/test_settings.gd -- --mod-src dialogue_tweaks
godot --headless --path <project> --script res://mods/dialogue_tweaks/tests/test_overlap.gd
```

## Invariants

- Edit only files under `res://mods/dialogue_tweaks/`.
- The note is current-turn only and is inserted before the solo length rule.
- `_note_in_use` guards the note through the base `handle_text()` interrupt.
- `_stop_for_overlap()` keeps the truncated line and note; its note always reports that she stopped.
- Do not clear `_active_overlap` when her line finishes; her finish releases the held input.
- `_tolerate_release` holds Anon's WAV while she finishes the last tenth; clear it on utterance, interrupt, failure, world reopen and exit.
- Clear `_pending_overlap`, `_active_overlap`, `_active_note`, `_talk_over_reply_speaker` on failure, world reopen and exit.
- `pick_listener()` only replaces the base result when the talk-over hint is set, the setting is `looked_at_interrupted`, the base reason is not `named`/`everyone`, and gaze equals the interrupted pony.
- No `class_name`; preload mod scripts by path so they work from a `.pck`.
- Do not ship `.uid` files or developer docs in the pack.

## Known limits

- Group and multi-beat replies get no group-prompt note; solo first.
- Speaker echo can trigger VAD.
- The base follow-up window is 20 seconds (40 if she asked a question) within 8 m.
- No saved mod state; the addressee choice is global, not per world.
