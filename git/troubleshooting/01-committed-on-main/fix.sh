#!/usr/bin/env bash
# G-01 reference fix: give the two commits a branch, move main back to origin/main, push the branch.
source "$(dirname "$0")/../_lib.sh"
sandbox 01-committed-on-main
git branch feature/showdown-title
as "${YOU[@]}" "Thu, 05 Nov 2026 10:30:00 +0530" git reset -q --hard origin/main
as "${YOU[@]}" "Thu, 05 Nov 2026 10:30:00 +0530" git switch -q feature/showdown-title
as "${YOU[@]}" "Thu, 05 Nov 2026 10:31:00 +0530" git push -q -u origin feature/showdown-title
ok "The two commits are on feature/showdown-title (pushed); main matches origin/main again."
git log --oneline --graph --decorate --all
