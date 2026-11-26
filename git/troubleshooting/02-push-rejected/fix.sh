#!/usr/bin/env bash
# G-02 reference fix: bring Lakshmi's commit in, replay yours on top of it, push.
source "$(dirname "$0")/../_lib.sh"
sandbox 02-push-rejected
as "${YOU[@]}" "Thu, 05 Nov 2026 09:40:00 +0530" git pull -q --rebase
as "${YOU[@]}" "Thu, 05 Nov 2026 09:41:00 +0530" git push -q
ok "Rebased on Lakshmi's commit and pushed."
git log --oneline --graph --decorate --all
