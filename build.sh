#!/usr/bin/env bash
# Build Dialogue Tweaks into one standalone .pck.
#
#   ./build.sh                 -> dist/dialogue_tweaks-<version>.pck
#   ./build.sh --out FILE.pck  -> FILE.pck
#
# No parent game project, asset import, manifest verifier or network. The pack contains only the
# mod's runtime tree, a generated mod.built.json marker and a minimal Godot project used to pack it.
# A .sha256 is written beside the pack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--out)
			if [ "$#" -lt 2 ]; then echo "--out needs a file path." >&2; exit 1; fi
			OUT="$2"
			shift 2
			;;
		-h|--help)
			sed -n '2,9p' "$0"
			exit 0
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

for tool in godot python3 git tar; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "$tool is needed on PATH." >&2
		exit 1
	fi
done

if [ ! -f "$ROOT/mod.json" ]; then
	echo "Expected mod.json beside build.sh." >&2
	exit 1
fi
if ! git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Run git init in $ROOT first." >&2
	exit 1
fi

ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["id"])' "$ROOT/mod.json")"
VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8"))["version"])' "$ROOT/mod.json")"
GAME_VERSION="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1], encoding="utf-8")).get("game_version",""))' "$ROOT/mod.json")"
if ! [[ "$ID" =~ ^[a-z0-9_]{1,40}$ ]]; then
	echo "mod.json id is not a valid mod id: $ID" >&2
	exit 1
fi
if [ -z "$VERSION" ]; then
	echo "mod.json version is empty." >&2
	exit 1
fi

if [ -z "$OUT" ]; then OUT="$ROOT/dist/$ID-$VERSION.pck"; fi
case "$OUT" in
	/*) ;;
	*) OUT="$(pwd)/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT")"

STAGE="$(mktemp -d)"
FILES=""
cleanup() {
	rm -rf "$STAGE"
	if [ -n "$FILES" ]; then rm -f "$FILES"; fi
}
trap cleanup EXIT

MOD="$STAGE/mods/$ID"
mkdir -p "$MOD"

FILES="$(mktemp)"
git -C "$ROOT" ls-files -z --cached --others --exclude-standard > "$FILES"
if [ ! -s "$FILES" ]; then
	echo "No files to pack." >&2
	exit 1
fi
tar --null -C "$ROOT" \
	--exclude='tests/*' --exclude='build.sh' --exclude='run.sh' --exclude='AGENTS.md' --exclude='.gitignore' \
	--exclude='.github/*' --exclude='dist/*' --exclude='*.pck' --exclude='*.uid' --exclude='*.log' \
	-cf - --files-from="$FILES" \
	| tar -C "$MOD" -xf -
rm -f "$FILES"

python3 - "$ROOT/mod.json" "$MOD/mod.built.json" <<'PY'
import json, sys
src = json.load(open(sys.argv[1], encoding="utf-8"))
json.dump({"id": src["id"], "version": src["version"], "game_version": src.get("game_version", "")},
          open(sys.argv[2], "w", encoding="utf-8"), indent="\t")
PY

cat > "$STAGE/project.godot" <<EOF
config_version=5

[application]

config/name="$ID build"
EOF

cat > "$STAGE/pack.gd" <<'GD'
extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var out := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size(): out = args[i + 1]
	if out.is_empty():
		push_error("missing --out"); quit(1); return
	var ids := DirAccess.get_directories_at("res://mods")
	if ids.size() != 1:
		push_error("expected one mod folder"); quit(1); return
	var id := ids[0]
	var files: Array[String] = []
	_walk("res://mods/" + id, files)
	files.sort()
	var packer := PCKPacker.new()
	if packer.pck_start(out) != OK:
		push_error("cannot write " + out); quit(1); return
	for path: String in files:
		if packer.add_file(path, ProjectSettings.globalize_path(path)) != OK:
			push_error("cannot add " + path); quit(1); return
	if packer.flush() != OK:
		push_error("cannot finish " + out); quit(1); return
	print("MOD_BUILT ", out)
	quit(0)

func _walk(dir: String, files: Array[String]) -> void:
	for name: String in DirAccess.get_files_at(dir):
		if name.begins_with(".") or name.ends_with(".uid"): continue
		files.append(dir.path_join(name))
	for name: String in DirAccess.get_directories_at(dir):
		if name.begins_with("."): continue
		_walk(dir.path_join(name), files)
GD

godot --headless --path "$STAGE" --script res://pack.gd -- --out "$OUT"

checksum() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}
( cd "$(dirname "$OUT")" && checksum "$(basename "$OUT")" > "$(basename "$OUT").sha256" )
echo "Checksum: $OUT.sha256"
