#!/usr/bin/env bash
# G-04 break: the same line changed on two branches; the merge stops with a conflict.
source "$(dirname "$0")/../_lib.sh"
world 04-merge-conflict
as "${YOU[@]}" "Thu, 05 Nov 2026 12:00:00 +0530" git switch -q -c blue-theme
edit api/app.py 's/os.environ.get("THEME_COLOR", "#ff5a5f")/os.environ.get("THEME_COLOR", "#2563eb")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 12:05:00 +0530" git commit -q -am "Make the theme blue"
as "${YOU[@]}" "Thu, 05 Nov 2026 12:10:00 +0530" git switch -q main
edit api/app.py 's/os.environ.get("THEME_COLOR", "#ff5a5f")/os.environ.get("THEME_COLOR", "#16a34a")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 12:15:00 +0530" git commit -q -am "Make the theme green"
say "Merging blue-theme into main…"
as "${YOU[@]}" "Thu, 05 Nov 2026 12:20:00 +0530" git merge blue-theme
echo "Your clone: $S/you"
