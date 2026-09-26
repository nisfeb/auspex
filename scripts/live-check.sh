#!/usr/bin/env bash
# The kit's LIVE_CHECK for auspex: every route (api-matrix) and mail both
# ways between two ships (xship). Exit 0 all pass, 1 a check failed, 4
# a ship did not answer.
#
#   AUSPEX_URL, AUSPEX_COOKIE  the dev ship running the code under test
#   PEER_URL, PEER_COOKIE      a second dev ship with auspex, for mail
set -uo pipefail
here=$(dirname "$0")
url=${AUSPEX_URL:-http://localhost:8080}
curl -s -m 10 "$url/~/host" >/dev/null || exit 4
timeout 600 node "$here/api-matrix.mjs" "$url" "${AUSPEX_COOKIE:?}" >/dev/null || exit 1
timeout 300 node "$here/xship.mjs" "$url" "$AUSPEX_COOKIE" "${PEER_URL:?}" "${PEER_COOKIE:?}" >/dev/null || exit 1
