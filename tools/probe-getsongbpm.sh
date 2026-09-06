#!/bin/bash
# Dumps the raw GetSongBPM response so the parser in BPMLookup.swift can be
# checked against the real schema. Their docs page is behind Cloudflare, so the
# field names in the parser are educated guesses until this is run once.
#
#   ./tools/probe-getsongbpm.sh YOUR_API_KEY "Homeward Bound" "Simon & Garfunkel"
set -euo pipefail

KEY="${1:?usage: probe-getsongbpm.sh API_KEY TITLE [ARTIST]}"
TITLE="${2:?usage: probe-getsongbpm.sh API_KEY TITLE [ARTIST]}"
ARTIST="${3:-}"

LOOKUP="song:$TITLE"
[ -n "$ARTIST" ] && LOOKUP="$LOOKUP artist:$ARTIST"

curl -sG 'https://api.getsong.co/search/' \
    --data-urlencode "api_key=$KEY" \
    --data-urlencode "type=song" \
    --data-urlencode "lookup=$LOOKUP" \
    -H 'User-Agent: Setlist/1.0 (personal use)' \
  | python3 -m json.tool 2>/dev/null || echo "(response was not JSON -- shown raw above)"
