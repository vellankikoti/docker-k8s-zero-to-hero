#!/usr/bin/env bash
# G-06 reference fix: move main back to where HEAD was before the reset (the reflog's HEAD@{1}).
source "$(dirname "$0")/../_lib.sh"
sandbox 06-reset-hard-lost-work
as "${YOU[@]}" "Thu, 05 Nov 2026 16:40:00 +0530" git reset -q --hard 'HEAD@{1}'
ok "main is back where it was before the reset."
git log --oneline --decorate -4
