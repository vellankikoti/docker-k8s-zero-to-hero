#!/usr/bin/env bash
# G-08 break: v1.0 is tagged; ten small commits later the API's health check route is gone. Which commit?
source "$(dirname "$0")/../_lib.sh"
world 08-who-broke-it-bisect
cd ../lakshmi || exit 1
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 09:00:00 +0530" git tag -a v1.0 -m "Showdown 1.0"
n=0
# commit WHO FILE SED-SCRIPT MESSAGE: one small change, one commit, ten minutes after the last one.
commit() {
  local who=$1 f=$2 s=$3 m=$4 p
  n=$((n + 1))
  case $who in L) p=("${LAKSHMI[@]}") ;; R) p=("${RAVI[@]}") ;; Y) p=("${YOU[@]}") ;; esac
  edit "$f" "$s"
  as "${p[@]}" "Thu, 05 Nov 2026 $(printf '%02d' $((9 + n / 6))):$(printf '%02d' $((n % 6 * 10))):00 +0530" git commit -q -am "$m"
}
commit L api/app.py 's/"cats:🐱:Cats,dogs:🐶:Dogs"))/"cats:🐱:Cats,dogs:🐶:Dogs,tea:🍵:Tea"))/' "Add tea as a third vote option"
commit R api/app.py 's/os.environ.get("TITLE", "Cats vs Dogs")/os.environ.get("TITLE", "The Showdown")/' "Rename the app to The Showdown"
commit Y api/Dockerfile 's/--interval=10s/--interval=15s/' "Check health every 15 seconds"
commit L api/app.py 's/os.environ.get("THEME_COLOR", "#ff5a5f")/os.environ.get("THEME_COLOR", "#e53e3e")/' "Use a darker red for the theme"
commit R api/app.py 's/elif path == "\/healthz":/elif path == "\/health":/' "Tidy up the request routing"
commit Y api/app.py 's/os.environ.get("APP_VERSION", "1.0.0")/os.environ.get("APP_VERSION", "1.0.1")/' "Bump the version to 1.0.1"
commit L api/Dockerfile 's/--retries=3/--retries=5/' "Give the health check 5 retries"
commit R api/app.py 's/,tea:🍵:Tea"))/,tea:🍵:Tea,coffee:☕:Coffee"))/' "Add coffee to the vote options"
commit Y api/app.py 's/or \["5"\])\[0\]), 60)/or ["5"])[0]), 30)/' "Cap the CPU burn at 30 seconds"
commit L api/app.py 's/os.environ.get("APP_VERSION", "1.0.1")/os.environ.get("APP_VERSION", "1.1.0")/' "Bump the version to 1.1.0"
as "${LAKSHMI[@]}" "Thu, 05 Nov 2026 11:00:00 +0530" git push -q --follow-tags origin main
cd ../you || exit 1
as "${YOU[@]}" "Thu, 05 Nov 2026 11:30:00 +0530" git pull -q
say "The release smoke test says the API never turns healthy. The Dockerfile asks for /healthz:"
grep -n 'healthz' api/Dockerfile; grep -n 'path == "/health' api/app.py
git log --oneline v1.0..main
echo "Your clone: $S/you"
