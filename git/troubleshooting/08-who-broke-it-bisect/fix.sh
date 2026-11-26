#!/usr/bin/env bash
# G-08 reference fix: let bisect find the first bad commit, then revert it (main is shared) and push.
source "$(dirname "$0")/../_lib.sh"
sandbox 08-who-broke-it-bisect
git bisect start main v1.0 >/dev/null
bad=$(git bisect run grep -q 'path == "/healthz"' api/app.py | sed -n 's/^\([0-9a-f]*\) is the first bad commit$/\1/p')
git bisect reset >/dev/null 2>&1
[ -n "$bad" ] || die "bisect found no first bad commit."
ok "First bad commit: $(git log -1 --format='%h %s' "$bad")"
as "${YOU[@]}" "Thu, 05 Nov 2026 12:00:00 +0530" git revert --no-edit "$bad" >/dev/null
as "${YOU[@]}" "Thu, 05 Nov 2026 12:01:00 +0530" git push -q
grep -n 'path == "/health' api/app.py
git log --oneline --decorate -2
