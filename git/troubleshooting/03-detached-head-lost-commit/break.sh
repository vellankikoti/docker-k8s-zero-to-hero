#!/usr/bin/env bash
# G-03 break: you look at the first commit, commit an idea there (detached HEAD), then switch back to main.
source "$(dirname "$0")/../_lib.sh"
world 03-detached-head-lost-commit
as "${YOU[@]}" "Thu, 05 Nov 2026 11:00:00 +0530" git switch -q --detach HEAD~1
edit api/app.py 's/"cats:🐱:Cats,dogs:🐶:Dogs"))/"cats:🐱:Cats,dogs:🐶:Dogs,tea:🍵:Tea"))/'
as "${YOU[@]}" "Thu, 05 Nov 2026 11:10:00 +0530" git commit -q -am "Add tea as a third vote option"
say "You committed while looking at an old commit. Now back to main…"
as "${YOU[@]}" "Thu, 05 Nov 2026 11:15:00 +0530" git switch main
git log --oneline --decorate
echo "Your clone: $S/you"
