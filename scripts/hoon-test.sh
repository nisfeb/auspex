#!/usr/bin/env bash
# Run the Hoon suites on a running fake ship, on a desk that holds nothing
# but the libs under test and their tests. See docs/hoon-testing.md.
#
#   scripts/hoon-test.sh <pier> setup          once per ship
#   scripts/hoon-test.sh <pier> [suite ...]    sync, commit, test
#
# A suite is a file under tests/lib without .hoon (auspex-chain); none runs
# all of them. Exits 0 when every test passes, 1 when one fails, 3 when a lib
# does not build, 4 when the ship does not answer. Per-test OK/FAILED lines are
# slogged to the ship's terminal: the socket only carries the verdict.
set -euo pipefail

DESK=auspex-test
LIBS=(auspex-chain auspex-web)
VERE=${VERE:-$(ls -d "$(dirname "$0")"/../../../vere-*-linux-x86_64 2>/dev/null | sort -V | tail -1)}
root=$(cd "$(dirname "$0")/.." && pwd)
pier=$(cd "${1:?usage: hoon-test.sh <pier> [setup | suite ...]}" && pwd); shift
sock="$pier/.urb/conn.sock"

# repo file -> desk path. The libs are import-free, so this is all a test
# build reaches; anything else it needs comes from %base at setup.
sync() {
  local d="$pier/$DESK"
  mkdir -p "$d/lib" "$d/tests/lib" "$d/protocol/vectors"
  for l in "${LIBS[@]}"; do rsync -ci "$root/code/lib/$l.hoon" "$d/lib/"; done
  rsync -ci "$root"/tests/lib/*.hoon "$d/tests/lib/"
  rsync -ci "$root/protocol/vectors/v1.json" "$d/protocol/vectors/"
}

# Run hoon (a strand producing a vase) in a khan thread over conn.sock and
# print the product noun. The hoon rides as a cord, so it holds no ', and
# on one line, so every newline becomes a two-space gap: one space is not
# a gap, and the parse fails.
# No answer at all is exit 4, never a test verdict: a ship that crashed
# mid-run must not read as a failing suite (or a killed mutant).
ted() {
  local hoon out; hoon=$(sed ':a;N;$!ba;s/\n/  /g')
  out=$(printf '%s\n' "[0 %fyrd [%base %khan-eval %noun [%ted-eval '$hoon']]]" |
    "$VERE" eval --jam -n 2>/dev/null |
    socat -T "${T:-60}" -,ignoreeof UNIX-CONNECT:"$sock" 2>/dev/null |
    "$VERE" eval --cue -n 2>/dev/null | tail -1 |
    sed -E 's/^\[0 %avow 0 %noun (.*)\]$/\1/' |
    # a failed thread's tang arrives as [%leaf <bytes> 0]: make it text
    perl -pe 's/\[%leaf ((?:\d+ )*)0\]/join "", map chr, split " ", $1/ge') || true
  [[ -n "$out" ]] || { echo "the ship at $pier did not answer" >&2; return 4; }
  echo "$out"
}

hash() { ted <<EOF
=/  m  (strand ,vase)
;<  h=@uvI  bind:m  (scry @uvI /cz/$DESK)
(pure:m !>(h))
EOF
}

if [[ "${1:-}" == setup ]]; then
  # |new-desk %$DESK and |mount %$DESK in the dojo first: both are one
  # line there. This copies the test harness and the marks the suites
  # need in from the ship's own %base, so they always match its kelvin;
  # a file already on the desk is left alone, so setup can be rerun.
  # %json builds through its grad mark, %mime: without it a /* of a json
  # file fails the whole suite as a build error.
  ted <<EOF
=/  m  (strand ,vase)
=/  paz=(list path)  ~[/lib/test/hoon /mar/json/hoon /mar/mime/hoon]
=|  fil=soba:clay
|-
?^  paz
  ;<  has=?  bind:m  (scry ? (weld /cu/$DESK i.paz))
  ?:  has  \$(paz t.paz)
  ;<  t=@t  bind:m  (scry @t (weld /cx/base i.paz))
  \$(paz t.paz, fil [[i.paz %ins %hoon !>(t)] fil])
;<  ~  bind:m  (send-raw-card [%pass /setup %arvo %c %info %$DESK %& fil])
(pure:m !>(%ok))
EOF
  exit
fi

# NOSYNC=1 commits the mount as it stands: how hoon-mutate.py runs the
# suites against a mutant it wrote there, which a sync would overwrite.
if [[ -n "${NOSYNC:-}" || -n "$(sync)" ]]; then
  before=$(hash)
  ted >/dev/null <<EOF
=/  m  (strand ,vase)
;<  =bowl  bind:m  get-bowl
;<  ~  bind:m  (poke [our.bowl %hood] kiln-commit+!>([%$DESK |]))
(pure:m !>(%ok))
EOF
  # the commit lands as a later event than the poke's ack
  for _ in $(seq 60); do [[ "$(hash)" != "$before" ]] && break; sleep 1; done
fi

libs=""
for l in "${LIBS[@]}"; do libs+=" /lib/$l/hoon"; done
paths=""
for s in "${@:-}"; do paths+=" [(scot %p our.bowl) %$DESK (scot %da now.bowl) %tests %lib${s:+ %$s} ~]"; done
# the libs are built first, so a lib that does not compile is its own
# answer rather than one more FAILED test file
ok=$(T=${TEST_T:-600} ted <<EOF
=/  m  (strand ,vase)
;<  =bowl  bind:m  get-bowl
=/  libs=(list path)  ~[${libs# }]
|-
?^  libs
  ;<  v=(unit vase)  bind:m  (build-file [[our.bowl %$DESK da+now.bowl] i.libs])
  ?~  v  (pure:m !>(2))
  \$(libs t.libs)
;<  r=thread-result  bind:m  (await-thread %test !>([~ \`(list path)\`~[${paths# }]]))
?:  ?=(%| -.r)  (pure:m !>(%crash))
(pure:m !>(!<(? p.r)))
EOF
)
case "$ok" in
  0) echo "hoon tests passed" ;;
  1) echo "hoon tests FAILED (names are in the ship's terminal)"; exit 1 ;;
  2) echo "a lib did not build"; exit 3 ;;
  *) echo "hoon test run did not complete: $ok"; exit 2 ;;
esac
