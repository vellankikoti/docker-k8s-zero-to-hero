#!/usr/bin/env bash
# G-09: Am I done? Run it from your clone: bash ../check.sh
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

o() { git -C "$S/origin.git" "$@"; }
old=$(o rev-parse -q --verify 'v1.0^{commit}') || no "v1.0 is gone from origin. A published release tag stays."
first=$(o rev-list -1 --grep='^Add a Dockerfile for the API$' main)
[ "$old" = "$first" ] || no "v1.0 was moved on origin. Anyone who fetched it before still has the old v1.0: two different releases now share one name."
r=$(git -C "$S/ravi" rev-parse -q --verify 'v1.0^{commit}')
[ "$r" = "$old" ] || no "Ravi's v1.0 differs from origin's."
new=$(o rev-parse -q --verify 'v1.0.1^{commit}') || no "There is no v1.0.1 on origin yet."
[ "$(o cat-file -t v1.0.1)" = tag ] || no "v1.0.1 is a lightweight tag. Release tags carry a message: git tag -a."
o merge-base --is-ancestor "$new" main || no "v1.0.1 is not on origin's main."
o cat-file -e "$new:frontend/Dockerfile" 2>/dev/null || no "v1.0.1 has no frontend either."
ok "v1.0 is unchanged everywhere, and v1.0.1 releases the commit with the frontend."
