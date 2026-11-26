#!/usr/bin/env bash
# G-10 reference fix: fetch, then rebase onto the rewritten branch, naming it. With an explicit upstream,
# git rebase skips the commits that Lakshmi's rebase already holds and replays only yours. Then push.
# (git pull --rebase is NOT the fix here: it uses the fork point, which is your own pushed commit, and drops it.)
source "$(dirname "$0")/../_lib.sh"
sandbox 10-force-push-erased-a-commit
as "${YOU[@]}" "Thu, 05 Nov 2026 11:30:00 +0530" git switch -q feature/frontend
as "${YOU[@]}" "Thu, 05 Nov 2026 11:30:00 +0530" git fetch -q origin
as "${YOU[@]}" "Thu, 05 Nov 2026 11:31:00 +0530" git rebase -q origin/feature/frontend
as "${YOU[@]}" "Thu, 05 Nov 2026 11:32:00 +0530" git push -q origin feature/frontend
ok "Your commit is back on feature/frontend, on top of Lakshmi's rebase."
git log --oneline --graph --decorate --all
