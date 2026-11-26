#!/usr/bin/env bash
# Shared helpers for the Git break-and-fix scenarios. Sourced by break.sh and fix.sh (never run).
#
# Every scenario starts from the same world: the Explorer repo, the Showdown app's repository
# (devopsengineers.in PRD §7). explorer/validation/git/world.sh builds it in the scenario's sandbox:
#   $T/<scenario>/origin.git   the team's shared remote (a bare repository, like GitHub)
#   $T/<scenario>/lakshmi      Lakshmi's clone
#   $T/<scenario>/ravi         Ravi's clone
#   $T/<scenario>/you          your clone: you work here
#   $T/<scenario>/check.sh     "Am I done?": run it from your clone with  bash ../check.sh
# T is /tmp/z2h-git-ts unless you set Z2H_GIT_TS. Your own repositories are never touched.
#
# Deterministic: world.sh and every break.sh and fix.sh commit with fixed names, emails and dates
# (the `as` helper), so the commit ids are the same on every machine. Commits you make yourself carry
# your own clock time, so their ids differ.
# Isolated: these scripts read no system or global Git config (explorer/validation/git/isolate.sh), so
# your personal settings (signing, pull.rebase, hooks, aliases) never change the sandbox. The git commands
# you type yourself still use your own config.
set -uo pipefail

TS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Two layouts run these scripts: the devops-engineers repo (zero-to-hero/git/troubleshooting) and
# the public practice repo docker-k8s-zero-to-hero (git/troubleshooting). Both keep the world
# builder at explorer/validation/git/ under their root.
REPO_ROOT="$(cd "$TS_DIR/../../.." && pwd)"
[ -f "$REPO_ROOT/explorer/validation/git/world.sh" ] || REPO_ROOT="$(cd "$TS_DIR/../.." && pwd)"
WORLD_SH="$REPO_ROOT/explorer/validation/git/world.sh"
T="${Z2H_GIT_TS:-/tmp/z2h-git-ts}"
# isolate.sh removes every inherited GIT_* variable, so keep the sandbox root first.
# shellcheck source=/dev/null
source "$REPO_ROOT/explorer/validation/git/isolate.sh"

# say/ok/warn print in colour. With NO_COLOR set (https://no-color.org) they print plain text.
_p() {
  local f="$1"
  shift
  [ -z "${NO_COLOR:-}" ] || f="$(printf '%s' "$f" | sed 's/\\033\[[0-9;]*m//g')"
  # shellcheck disable=SC2059
  printf "$f" "$@"
}
say()  { _p '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { _p '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { _p '\033[1;33m⚠ %s\033[0m\n' "$*"; }
die()  { _p '\033[1;31m✖ %s\033[0m\n' "$*"; exit 1; }

# The teammates of the Explorer repo (explorer/content/git/world.yaml).
LAKSHMI=("Lakshmi" "lakshmi@showdown.example")
RAVI=("Ravi" "ravi@showdown.example")
YOU=("You" "you@showdown.example")

# as NAME EMAIL DATE COMMAND...: run COMMAND as one person at one moment. The date goes into commits,
# tags and reflog entries (https://git-scm.com/docs/git-commit#_date_formats, RFC 2822 form).
as() {
  local n=$1 e=$2 d=$3
  shift 3
  GIT_AUTHOR_NAME="$n" GIT_AUTHOR_EMAIL="$e" GIT_AUTHOR_DATE="$d" \
    GIT_COMMITTER_NAME="$n" GIT_COMMITTER_EMAIL="$e" GIT_COMMITTER_DATE="$d" "$@"
}

# world NAME: build a fresh Explorer repo in $T/NAME, copy the scenario's check.sh next to the clones,
# and cd into your clone. S is the sandbox folder.
world() {
  S="$T/$1"
  [ -f "$WORLD_SH" ] || die "explorer/validation/git/world.sh is missing. Run the scenarios from a full clone of the repository."
  rm -rf "$S"
  mkdir -p "$T"
  bash "$WORLD_SH" "$S" >/dev/null || die "Could not build the Explorer repo in $S."
  export HOME="$S/.home"
  cp "$TS_DIR/$1/check.sh" "$S/check.sh"
  cd "$S/you" || exit 1
}

# sandbox NAME: cd into the clone of an existing sandbox (fix.sh). Fails if break.sh has not run.
sandbox() {
  S="$T/$1"
  [ -d "$S/you/.git" ] || die "No sandbox in $S. Break the scenario first: ./labs.sh git ${1%%-*}"
  export HOME="$S/.home"
  cd "$S/you" || exit 1
}

# edit FILE SED-SCRIPT: change a file in place (works with GNU and BSD sed), and fail if nothing changed.
edit() {
  local f=$1 before
  before="$(cat "$f")"
  sed -i.bak "$2" "$f" && rm -f "$f.bak"
  [ "$(cat "$f")" != "$before" ] || die "edit: $2 changed nothing in $f"
}
