#!/usr/bin/env bash
# offline-tests.sh: run the Hoon suites that can run with no ship, through
# vere eval (scripts/hoon-test-kit/offline-test.py), all at once.
#
# Only auspex-web runs offline. auspex-chain, auspex-vectors and
# auspex-fibers all build lib/auspex-chain, which signs with
# cric:crypto, an arm of kelvin 408's zuse that vere eval's own zuse
# (vere 4.6) lacks: they stop at -find.cric. They run on the ship
# (TESTING.md), which stays the verdict.
#
#   scripts/offline-tests.sh            the offline suites
#   scripts/offline-tests.sh NAME ...   by name, no .hoon
set -uo pipefail
cd "$(dirname "$0")/.."
if (($#)); then names=("$@"); else names=(auspex-web); fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pids=()
for n in "${names[@]}"; do
  python3 scripts/hoon-test-kit/offline-test.py "tests/lib/$n.hoon" > "$tmp/$n" 2>&1 &
  pids+=($!)
done
fail=0
for i in "${!names[@]}"; do
  n=${names[i]}; wait "${pids[i]}"; rc=$?
  printf '%-16s %s\n' "$n" "$(tail -1 "$tmp/$n")"
  ((rc == 0)) || { fail=1; sed -n '1,40p' "$tmp/$n"; }
done
exit $fail
