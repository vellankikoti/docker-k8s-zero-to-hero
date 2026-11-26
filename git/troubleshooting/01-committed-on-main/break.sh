#!/usr/bin/env bash
# G-01 break: two commits for a new feature, made on main by mistake. Nothing is pushed.
source "$(dirname "$0")/../_lib.sh"
world 01-committed-on-main
edit api/app.py 's/os.environ.get("TITLE", "Cats vs Dogs")/os.environ.get("TITLE", "The Showdown")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 10:10:00 +0530" git commit -q -am "Rename the app to The Showdown"
edit api/app.py 's/os.environ.get("APP_VERSION", "1.0.0")/os.environ.get("APP_VERSION", "1.1.0")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 10:20:00 +0530" git commit -q -am "Bump the version to 1.1.0"
say "You made two commits for the new title… on main."
git status -sb | head -1
git log --oneline --graph --decorate --all
echo "Your clone: $S/you"
