#!/usr/bin/env bash
# G-07 break: you have unfinished edits in api/app.py; Lakshmi pushed an urgent change to the same file.
source "$(dirname "$0")/../_lib.sh"
world 07-pull-blocked-local-changes
cd ../lakshmi || exit 1
edit api/app.py 's/os.environ.get("TITLE", "Cats vs Dogs")/os.environ.get("TITLE", "Fest final: Cats vs Dogs")/'
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 17:00:00 +0530" git commit -q -am "Urgent: name the poll for the fest final"
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 17:01:00 +0530" git push -q origin main
cd ../you || exit 1
edit api/app.py 's/or \["5"\])\[0\]), 60)/or ["5"])[0]), 30)/'
say "You have unfinished edits in api/app.py. Now pulling Lakshmi's urgent change…"
as "${YOU[@]}" "Thu, 05 Nov 2026 17:05:00 +0530" git pull
echo "Your clone: $S/you"
