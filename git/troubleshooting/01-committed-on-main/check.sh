#!/usr/bin/env bash
# G-01: Am I done? Run it from your clone: bash ../check.sh
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

a="Rename the app to The Showdown"; b="Bump the version to 1.1.0"
[ "$(you rev-parse main)" = "$(you rev-parse origin/main)" ] || no "main is not where origin/main is: $(you rev-list --count origin/main..main) commit(s) of yours are still on main."
has main "$a" && no "main still holds \"$a\"."
br=""
for r in $(origin for-each-ref --format='%(refname:short)' refs/heads/); do
  [ "$r" = main ] && continue
  git -C "$S/origin.git" log --format=%s "$r" | grep -qxF "$a" && git -C "$S/origin.git" log --format=%s "$r" | grep -qxF "$b" && br=$r
done
[ -n "$br" ] || no "No branch on origin holds both commits yet. Give them a branch and push it."
git -C "$S/origin.git" log --format=%s main | grep -qxF "$a" && no "origin's main holds your commits: they were pushed to main."
ok "main matches origin/main, and both commits are on $br on origin, ready for a pull request."
