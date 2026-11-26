#!/usr/bin/env bash
# G-10 break: you push a commit to feature/frontend; Lakshmi, from a stale clone, rebases the branch onto
# main and force-pushes it. Your commit is no longer on origin.
source "$(dirname "$0")/../_lib.sh"
world 10-force-push-erased-a-commit
as "${YOU[@]}" "Thu, 05 Nov 2026 09:50:00 +0530" git switch -q feature/frontend
edit frontend/nginx.conf 's/proxy_read_timeout 70s;/proxy_read_timeout 90s;/'
as "${YOU[@]}" "Thu, 05 Nov 2026 10:00:00 +0530" git commit -q -am "Wait 90 seconds for slow API answers"
as "${YOU[@]}" "Thu, 05 Nov 2026 10:01:00 +0530" git push -q origin feature/frontend
say "You pushed your commit to feature/frontend. Lakshmi has not fetched since yesterday. She tidies the branch…"
cd ../lakshmi || exit 1
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 11:00:00 +0530" git switch -q feature/frontend
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 11:01:00 +0530" git rebase -q main
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 11:02:00 +0530" git push --force origin feature/frontend
cd ../you || exit 1
echo "Your clone: $S/you"
