#!/usr/bin/env bash
# G-02 break: Lakshmi pushes to main first; your push of a commit made on the old main is rejected.
source "$(dirname "$0")/../_lib.sh"
world 02-push-rejected
cd ../lakshmi || exit 1
edit api/Dockerfile 's/--retries=3/--retries=5/'
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 09:00:00 +0530" git commit -q -am "Give the health check 5 retries"
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 09:05:00 +0530" git push -q origin main
cd ../you || exit 1
edit api/app.py 's/os.environ.get("THEME_COLOR", "#ff5a5f")/os.environ.get("THEME_COLOR", "#2563eb")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 09:30:00 +0530" git commit -q -am "Make the theme blue"
say "Pushing your commit…"
as "${YOU[@]}" "Thu, 05 Nov 2026 09:31:00 +0530" git push
echo "Your clone: $S/you"
