#!/usr/bin/env bash
# Run Home: Equestria with Dialogue Tweaks unpacked from this checkout.
#
#   ./run.sh [game arguments...]
#
# The mod source is used directly (--mod-src), so there is no pack to rebuild while testing.
# Godot 4.5 must be on PATH. Set DISPLAY_DRIVER to override the desktop display driver.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$ROOT/../.." && pwd)"

if ! command -v godot >/dev/null 2>&1; then
	echo "godot is needed on PATH." >&2
	exit 1
fi

display="${DISPLAY_DRIVER:-}"
if [[ -z "$display" ]]; then
	if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then display=wayland; else display=x11; fi
fi

LOG="$ROOT/last-run.log"
echo "Starting Home: Equestria with dialogue_tweaks from source..."
printf 'Run log: %s\n' "$LOG"

# typing_lock is an installed mod outside this repository; its per-frame lines bury the run log.
godot --xr-mode off --display-driver "$display" --path "$PROJECT_ROOT" \
	-- --mod-src dialogue_tweaks "$@" \
	2>&1 | sed -u '/^\[typing_lock\]/d' | tee "$LOG"
