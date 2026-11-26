#!/usr/bin/env bash
# G-04 reference fix: keep the colour the team agreed on, remove the markers, mark the file resolved, commit.
source "$(dirname "$0")/../_lib.sh"
sandbox 04-merge-conflict
sed -i.bak '/^<<<<<<< /,/^>>>>>>> /c\
THEME_COLOR = os.environ.get("THEME_COLOR", "#7c3aed")
' api/app.py && rm -f api/app.py.bak
git add api/app.py
as "${YOU[@]}" "Thu, 05 Nov 2026 12:30:00 +0530" git commit -q --no-edit
ok "Conflict resolved with the agreed colour."
grep -n 'THEME_COLOR = ' api/app.py
git log --oneline --graph --decorate -4
