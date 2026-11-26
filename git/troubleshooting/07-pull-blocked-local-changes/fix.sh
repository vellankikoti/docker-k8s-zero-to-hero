#!/usr/bin/env bash
# G-07 reference fix: put the unfinished edit aside, pull, take the edit back.
source "$(dirname "$0")/../_lib.sh"
sandbox 07-pull-blocked-local-changes
as "${YOU[@]}" "Thu, 05 Nov 2026 17:10:00 +0530" git stash -q
as "${YOU[@]}" "Thu, 05 Nov 2026 17:10:00 +0530" git pull -q
as "${YOU[@]}" "Thu, 05 Nov 2026 17:10:00 +0530" git stash pop -q
ok "Pulled Lakshmi's change and restored your edit."
grep -nE 'TITLE = |or \["5"\]' api/app.py
