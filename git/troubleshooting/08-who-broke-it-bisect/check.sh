#!/usr/bin/env bash
# G-08: Am I done? Run it from your clone: bash ../check.sh
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

[ -e "$S/you/.git/BISECT_LOG" ] && no "A bisect is still running. End it with git bisect reset."
[ "$(you symbolic-ref -q --short HEAD)" = main ] || no "HEAD is not on main."
o() { git -C "$S/origin.git" "$@"; }
o show main:api/app.py | grep -qF 'elif path == "/healthz":' || no "The /healthz route is not back on origin's main yet."
o log --format=%s main | grep -qxF "Tidy up the request routing" || no "The commit \"Tidy up the request routing\" is gone from origin's history. main is shared: undo it with a new commit, never rewrite."
o show main:api/app.py | grep -qF 'os.environ.get("APP_VERSION", "1.1.0")' || no "Later work (version 1.1.0) is missing from origin's main."
o show main:api/Dockerfile | grep -qF -- '--retries=5' || no "Later work (5 health check retries) is missing from origin's main."
o show main:api/app.py | grep -qF 'elif path == "/health":' && no "origin's main still has the /health route that replaced /healthz."
ok "The /healthz route is back on origin's main, undone with a new commit, and the ten commits after v1.0 are kept."
