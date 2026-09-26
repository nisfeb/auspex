#!/usr/bin/env bash
# The kit's LIVE_DEPLOY for auspex: put one code file on a dev ship's auspex
# desk and say whether the instance built it.
#
#   LIVE_FILE  the file to deploy (a mutant, or the clean source)
#   LIVE_SRC   its repo path, e.g. code/nex/auspex/app.hoon
#   AUSPEX_URL, AUSPEX_COOKIE  the dev ship and a cookie jar for it
#                              (scripts/hoon-test-kit/ship-cookie.sh)
#
# write-text answers only once the desk has rebuilt and the nexus has
# reloaded (about 20 s), so when it returns the instance runs the file, or
# failed to build it. Exit 0 built, 3 did not build, 4 no answer.
set -uo pipefail
url=${AUSPEX_URL:-http://localhost:8080}
jar=${AUSPEX_COOKIE:?AUSPEX_COOKIE: a cookie jar for the dev ship}
code=$url/grubbery/ball/apps/shell.shell/desks/auspex.desk/desk/code
dest=${LIVE_SRC#code/}
out=$(curl -s -m 300 -b "$jar" -X POST --data-urlencode action=write-text \
  --data-urlencode "content@$LIVE_FILE" "$code/$dest") || exit 4
[[ "$out" == saved* ]] || { echo "write-text: $out" >&2; exit 4; }
status=$(curl -s -m 60 -b "$jar" "$code/$dest?info=1" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["build"]["status"])' 2>/dev/null) || exit 4
[[ "$status" == vase ]] && exit 0
echo "$dest did not build: $status" >&2
exit 3
