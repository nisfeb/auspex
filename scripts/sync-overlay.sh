#!/usr/bin/env bash
# Sync the urmail grubbery-overlay into a grubbery desk root.
#
# urmail runs as a grubbery NEXUS, not a gall agent, and grubbery's sync-gub
# only loads gub/ from its OWN desk. So the canonical source lives in this repo
# under grubbery-overlay/ (version-controlled, tested) and is COPIED into a
# grubbery desk tree. Re-run after every grubbery pull: a grubbery core update
# knows nothing about this overlay, and committing the desk without re-syncing
# culls urmail out of clay.
#
# Layout mapping (overlay -> grubbery desk root):
#   lib/*.hoon         -> gub/lib/   (deployed: the nexus imports it here)
#                         lib/       (so desk-level /tests can import it too)
#   nex/urmail/*       -> gub/nex/urmail/
#   mar/urmail/*.hoon  -> gub/mar/urmail/
#   mar-clay/**        -> gub/mar/clay/   (cross-desk poke marks)
#   mar-core/*.hoon    -> mar/            (desk-level marks a DOJO poke resolves)
#   tests/**           -> tests/          (run via -test /=grubbery=/tests/...)
#
# Idempotent, and NEVER --delete: this writes into trees grubbery owns.
#
# Usage: scripts/sync-overlay.sh <grubbery-desk-root>
#   e.g. scripts/sync-overlay.sh /home/sneagan/software/wex/grubbery
# The target is REQUIRED. An implicit deploy target is how code lands on the
# wrong pier.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OVERLAY="$HERE/../grubbery-overlay"
DEST="${1:?usage: sync-overlay.sh <grubbery-desk-root>}"

[ -d "$OVERLAY" ] || { echo "no overlay at $OVERLAY" >&2; exit 66; }
[ -d "$DEST" ]    || { echo "no grubbery desk root at $DEST" >&2; exit 67; }

# ---------------------------------------------------------------------------
# PREFIX CHECK. gub/lib is SHARED with grubbery's own libraries and with every
# other overlay's (lattice ships nineteen files into it). rsync has no
# --delete here, so an overlay file silently overwrites a grubbery file of the
# same name and no later sync ever puts it back. This is not hypothetical: on
# lattice a 28-line lib/obelisk-ast.hoon clobbered grubbery's real 1208-line
# one on every sync and broke obelisk on every ship it touched. Nothing
# reported it, because the overwritten file compiles fine on its own.
#
# So the namespace, not just the collision, is the invariant: everything this
# overlay puts in a shared tree is named urmail-*.
# ---------------------------------------------------------------------------
BAD=0
for f in "$OVERLAY"/lib/*.hoon; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  case "$b" in
    urmail-*) ;;
    *) echo "REFUSING: lib/$b has no urmail- prefix; gub/lib is shared" >&2; BAD=1 ;;
  esac
done
[ "$BAD" -eq 0 ] || exit 69

# ---------------------------------------------------------------------------
# SHADOW CHECK. Belt to the prefix check's braces, and the only guard for the
# trees where urmail cannot own the filename: mar-clay/ and mar-core/ carry
# kernel-named marks (handle-http-request, gall-leave) that lattice and
# grubbery also ship. A file this overlay would land ON TOP OF a DIFFERENT
# existing file is a collision, and a collision must be deliberate: refuse and
# make a human look.
#
# Owned = basename starts with urmail-, or the path sits under a urmail/ dir.
# ---------------------------------------------------------------------------
shadow_scan() {  # <overlay subdir> <dest subdir>
  local src="$1" dst="$2" rel
  [ -d "$src" ] || return 0
  while IFS= read -r -d '' rel; do
    rel="${rel#"$src"/}"
    case "$rel" in
      urmail-*|*/urmail-*|urmail/*|*/urmail/*) continue ;;
    esac
    if [ -e "$dst/$rel" ] && ! cmp -s "$src/$rel" "$dst/$rel"; then
      echo "REFUSING: overlay ${src#"$OVERLAY"/}/$rel would overwrite a different $dst/$rel" >&2
      echo "  If that file belongs to grubbery or another overlay, we must not ship it." >&2
      BAD=1
    fi
  done < <(find "$src" -type f -print0)
}
shadow_scan "$OVERLAY/lib"       "$DEST/gub/lib"
shadow_scan "$OVERLAY/lib"       "$DEST/lib"
shadow_scan "$OVERLAY/nex"       "$DEST/gub/nex"
shadow_scan "$OVERLAY/mar"       "$DEST/gub/mar"
shadow_scan "$OVERLAY/mar-clay"  "$DEST/gub/mar/clay"
shadow_scan "$OVERLAY/mar-core"  "$DEST/mar"
shadow_scan "$OVERLAY/tests"     "$DEST/tests"
[ "$BAD" -eq 0 ] || exit 69

mkdir -p "$DEST/gub/lib" "$DEST/lib" "$DEST/tests/lib" "$DEST/mar"

# Pure libs: into gub/lib for the nexus, and into desk-level lib so -test can
# build them. The SAME file has to compile in both, which is why an overlay lib
# imports nothing: desk builds use ford runes (/- /+), gub builds use /<, and
# the two syntaxes are not interchangeable.
rsync -a "$OVERLAY/lib/" "$DEST/gub/lib/"
rsync -a "$OVERLAY/lib/" "$DEST/lib/"
# Nexus + marcs: the gub tree only.
if [ -d "$OVERLAY/nex/urmail" ]; then
  mkdir -p "$DEST/gub/nex/urmail"
  rsync -a "$OVERLAY/nex/urmail/" "$DEST/gub/nex/urmail/"
fi
if [ -d "$OVERLAY/mar/urmail" ]; then
  mkdir -p "$DEST/gub/mar/urmail"
  rsync -a "$OVERLAY/mar/urmail/" "$DEST/gub/mar/urmail/"
fi
# Cross-desk poke marks, for building a poke vase from another desk.
if [ -d "$OVERLAY/mar-clay" ]; then
  mkdir -p "$DEST/gub/mar/clay"
  rsync -a "$OVERLAY/mar-clay/" "$DEST/gub/mar/clay/"
fi
# Desk-level clay marks: $DEST/mar, NOT gub/mar. Different tree: these are what
# a DOJO poke resolves against.
if [ -d "$OVERLAY/mar-core" ]; then
  rsync -a --exclude 'README.md' "$OVERLAY/mar-core/" "$DEST/mar/"
fi
# Tests: desk-level.
rsync -a "$OVERLAY/tests/" "$DEST/tests/"

# Print what actually landed. Zero counts mean the overlay did not deploy and
# the next |commit will take urmail down; do not commit on a warning.
count() { [ -d "$1" ] || { echo 0; return 0; }; find "$1" "${@:2}" | wc -l; }
LIB=$(count "$DEST/gub/lib" -maxdepth 1 -name 'urmail-*.hoon')
TST=$(count "$DEST/tests" -name 'urmail-*.hoon')
NEX=$(count "$DEST/gub/nex/urmail" -type f)
MAR=$(count "$DEST/gub/mar/urmail" -type f)
echo "synced overlay -> $DEST (urmail libs: $LIB, tests: $TST, nex: $NEX, marcs: $MAR)"
if [ "$LIB" -eq 0 ]; then
  echo "WARNING: overlay did not land - do NOT commit the desk" >&2
  exit 68
fi

# The deploy is not finished when the files land. Clay has to commit them, and
# a recompile does NOT respawn long-lived fibers: they keep running old code,
# silently. Every deploy bounces. These are dojo commands, so they are printed
# rather than driven: sending keystrokes into the user's dojo while an event is
# running loses them, and a half-typed |suspend is worse than none.
cat <<'NEXT'

next, in the ~<ship> dojo - one command at a time, verify each echo:
  |commit %grubbery
  |suspend %grubbery
  |revive %grubbery
  -test /=grubbery=/tests/lib/urmail-chain ~
NEXT
