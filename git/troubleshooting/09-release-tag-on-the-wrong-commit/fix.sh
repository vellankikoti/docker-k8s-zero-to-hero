#!/usr/bin/env bash
# G-09 reference fix: leave the published v1.0 alone and release v1.0.1 on the commit that has the frontend.
source "$(dirname "$0")/../_lib.sh"
sandbox 09-release-tag-on-the-wrong-commit
as "${YOU[@]}" "Thu, 05 Nov 2026 11:00:00 +0530" git pull -q
as "${YOU[@]}" "Thu, 05 Nov 2026 11:01:00 +0530" git tag -a v1.0.1 -m "Showdown 1.0.1: includes the frontend"
as "${YOU[@]}" "Thu, 05 Nov 2026 11:02:00 +0530" git push -q origin v1.0.1
as "${RAVI[@]}" "Thu, 05 Nov 2026 11:10:00 +0530" git -C ../ravi fetch -q origin
ok "v1.0.1 is on the commit with the frontend; v1.0 is unchanged."
git ls-tree -r --name-only v1.0.1
