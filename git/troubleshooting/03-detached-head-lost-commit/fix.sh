#!/usr/bin/env bash
# G-03 reference fix: find the commit in the reflog, put a branch on it, merge it into main.
source "$(dirname "$0")/../_lib.sh"
sandbox 03-detached-head-lost-commit
h=$(git reflog --format='%h %gs' | grep 'commit: Add tea as a third vote option' | head -1 | cut -d' ' -f1)
[ -n "$h" ] || die "The commit is not in the reflog."
git branch tea-option "$h"
as "${YOU[@]}" "Thu, 05 Nov 2026 11:30:00 +0530" git merge -q --no-edit tea-option
ok "Rescued $h onto the branch tea-option and merged it into main."
git log --oneline --graph --decorate
