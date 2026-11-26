#!/usr/bin/env bash
# G-09 break: Lakshmi merges the frontend into main; you tag v1.0 on your stale main and push the tag.
source "$(dirname "$0")/../_lib.sh"
world 09-release-tag-on-the-wrong-commit
cd ../lakshmi || exit 1
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 10:00:00 +0530" git merge -q --no-ff -m "Merge the frontend into main" origin/feature/frontend
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 10:05:00 +0530" git push -q origin main
cd ../you || exit 1
say "Release time. You tag v1.0 on your main and push the tag…"
as "${YOU[@]}" "Thu, 05 Nov 2026 10:30:00 +0530" git tag -a v1.0 -m "Showdown 1.0"
as "${YOU[@]}" "Thu, 05 Nov 2026 10:31:00 +0530" git push origin v1.0
# Ravi fetches: his clone now has v1.0 too.
as "${RAVI[@]}" "Thu, 05 Nov 2026 10:40:00 +0530" git -C ../ravi fetch -q origin
say "The release pipeline built v1.0. The release has no frontend:"
git ls-tree -r --name-only v1.0
echo "Your clone: $S/you"
