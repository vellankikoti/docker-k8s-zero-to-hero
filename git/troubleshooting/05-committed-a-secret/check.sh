#!/usr/bin/env bash
# G-05: Am I done? Run it from your clone: bash ../check.sh
# It only looks; it never changes anything. Exit 0 = fixed, 1 = not yet.
set -u
# Find the sandbox: this file's folder when break.sh copied it there, else $T/<scenario>.
S="$(cd "$(dirname "$0")" && pwd)"
[ -d "$S/you" ] || S="${Z2H_GIT_TS:-/tmp/z2h-git-ts}/$(basename "$S")"
# Read-only and isolated: no inherited GIT_* variables, no system or global config, no optional locks.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_OPTIONAL_LOCKS=0 LC_ALL=C
_p() { local f="$1"; shift; [ -z "${NO_COLOR:-}" ] || f="$(printf '%s' "$f" | sed 's/\\033\[[0-9;]*m//g')"; printf "$f" "$@"; }
ok()   { _p '\033[1;32m✔ %s\033[0m\n' "$*"; exit 0; }
no()   { _p '\033[1;33m⚠ Not yet. %s Look again, make one change, then run bash ../check.sh once more.\033[0m\n' "$*"; exit 1; }
[ -d "$S/you/.git" ] || no "There is no sandbox in $S. Break the scenario first."
you() { git -C "$S/you" "$@"; }
origin() { git -C "$S/origin.git" "$@"; }
# has REV SUBJECT: does the history of REV contain a commit with exactly this subject?
has() { you log --format=%s "$1" 2>/dev/null | grep -qxF "$2"; }

k="z2h-demo-key-NOT-REAL-123"
# break.sh's commit has a fixed id. If it ever reached origin, a force push does not take it back.
leak=0a75a164ed8ba5a4b8bc31ba4aec963c7361f6b3
for r in origin.git lakshmi ravi; do
  git -C "$S/$r" cat-file -e "$leak^{commit}" 2>/dev/null && no "The commit with the password reached $r: it was pushed. Rewriting history does not take it back. Treat the password as leaked: rotate it."
done
git -C "$S/origin.git" log --all -p | grep -qF "$k" && no "The password is on origin: it was pushed. Treat it as leaked: rotate it."
n=$(you log --all -p | grep -cF "$k")
[ "$n" = 0 ] || no "The password is still in your history ($n line(s) in git log --all -p)."
has main "Store votes in Redis by default" || no "Your commit \"Store votes in Redis by default\" is gone. Keep the code change; remove only the file."
you show main:api/app.py | grep -qF 'os.environ.get("REDIS_HOST", "redis")' || no "The code change of your commit is missing."
[ -f "$S/you/api/.env" ] || no "api/.env is gone from your disk. Your local setup needs it; only Git should forget it."
you check-ignore -q api/.env || no "Git does not ignore api/.env, so the next git add . commits it again."
ok "The password is in no commit, api/.env stays on your disk, and Git ignores it."
