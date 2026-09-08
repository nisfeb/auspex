#!/usr/bin/env bash
# deploy.sh <wex|feb> [--install]
# Copies desk/ into the named dev ship's mounted %urmail desk and commits.
set -euo pipefail
SHIP="${1:?usage: deploy.sh <wex|feb> [--install]}"
case "$SHIP" in
  wex) PIER=/home/sneagan/software/wex; PANE=0:0.0 ;;
  feb) PIER=/home/sneagan/software/feb; PANE=0:3.0 ;;
  *) echo "unknown ship $SHIP (expected wex or feb)"; exit 1 ;;
esac
tmux has-session -t "$PANE" 2>/dev/null || { echo "tmux pane $PANE not found"; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)/desk"
[ -z "$(ls -A "$SRC")" ] && { echo "error: $SRC is empty, aborting"; exit 1; }

dojo() { tmux send-keys -t "$PANE" "$1" Enter; sleep 3; }

if [ ! -d "$PIER/urmail" ]; then
  echo ">> creating and mounting %urmail on ~$SHIP"
  dojo '|new-desk %urmail'
  dojo '|mount %urmail'
  _i=0
  until [ -d "$PIER/urmail" ]; do
    sleep 1; _i=$((_i + 1))
    [ "$_i" -ge 30 ] && { echo "error: $PIER/urmail did not appear after 30s"; exit 1; }
  done
fi

rsync -a --delete --exclude='.urb' "$SRC"/ "$PIER/urmail/"
dojo '|commit %urmail'
[ "${2:-}" = "--install" ] && dojo '|install our %urmail'
echo ">> done. Build output:"
tmux capture-pane -t "$PANE" -p | tail -20
