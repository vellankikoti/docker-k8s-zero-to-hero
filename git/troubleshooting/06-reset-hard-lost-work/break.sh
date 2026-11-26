#!/usr/bin/env bash
# G-06 break: three commits of work, then git reset --hard HEAD~3 "to clean up".
source "$(dirname "$0")/../_lib.sh"
world 06-reset-hard-lost-work
edit api/app.py 's/os.environ.get("TITLE", "Cats vs Dogs")/os.environ.get("TITLE", "The Showdown")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 15:00:00 +0530" git commit -q -am "Rename the app to The Showdown"
edit api/app.py 's/"cats:🐱:Cats,dogs:🐶:Dogs"))/"cats:🐱:Cats,dogs:🐶:Dogs,tea:🍵:Tea"))/'
as "${YOU[@]}" "Thu, 05 Nov 2026 15:40:00 +0530" git commit -q -am "Add tea as a third vote option"
edit api/app.py 's/os.environ.get("APP_VERSION", "1.0.0")/os.environ.get("APP_VERSION", "1.1.0")/'
as "${YOU[@]}" "Thu, 05 Nov 2026 16:20:00 +0530" git commit -q -am "Bump the version to 1.1.0"
git log --oneline --decorate -4
say "Running: git reset --hard HEAD~3 …"
as "${YOU[@]}" "Thu, 05 Nov 2026 16:30:00 +0530" git reset --hard HEAD~3
git log --oneline --decorate
echo "Your clone: $S/you"
