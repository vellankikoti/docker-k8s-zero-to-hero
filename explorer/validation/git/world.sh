#!/usr/bin/env bash
# Build the Explorer repo (PRD §7, §8.4, WU-GIT-01): the Showdown app's repository, shared by two
# fictional teammates through a bare remote `origin`. Described in explorer/content/git/world.yaml.
#
#   bash explorer/validation/git/world.sh [DIR]      build the world in DIR (default: a new temp folder)
#   bash explorer/validation/git/world.sh refs DIR   print every ref of every repository in DIR
#
# DIR must be an absolute path outside this repository that does not exist yet, or is empty. It ends up as:
#   DIR/origin.git   the shared remote: a bare repository, like the team's GitHub repository
#   DIR/lakshmi      Lakshmi's clone (she starts the project)
#   DIR/ravi         Ravi's clone (he builds the frontend on feature/frontend)
#   DIR/you          your clone, made last: main plus origin/main and origin/feature/frontend
#   DIR/.home        an empty HOME for git, so no personal config is read
#
# Deterministic: every commit has a fixed author, committer and date, and its files are byte-for-byte
# copies of zero-to-hero/apps (checked against their blob ids below). The same Git object format
# (sha1, set explicitly) gives the same commit ids on every machine and every run.
# Isolated: isolate.sh turns off system and global config; nothing outside DIR is written.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# In devops-engineers the apps are in zero-to-hero/apps; in the public practice repo, in apps/
APPS="$ROOT/zero-to-hero/apps"
[ -d "$APPS" ] || APPS="$ROOT/apps"
# shellcheck source=/dev/null
source "$HERE/isolate.sh"

# The teammates (fictional, PRD §14). Emails use .example, reserved for documentation (RFC 2606 §2).
LAKSHMI=("Lakshmi" "lakshmi@showdown.example")
RAVI=("Ravi" "ravi@showdown.example")
YOU=("You" "you@showdown.example")
BRANCH=feature/frontend

# Inputs: path in the repository, blob id (`git hash-object --no-filters`). A changed file changes every
# commit id after it, so the build refuses instead of building a different world.
INPUTS="api/app.py 22ed3c42984016ca9f8a2faaefe62e3c013e6653
api/static/index.html 378791e00771dba696e57645c93819c996ec3e37
api/Dockerfile ab5470cdabfb78069ed2c227307c759acad75809
frontend/nginx.conf f9795551648459436cbf58609563cfe79ad2e046
frontend/Dockerfile edd894e7210f4cc2528d9fd7274d8f6bc85255b0"

die() { echo "world.sh: $*" >&2; exit 1; }

# as NAME EMAIL DATE git ARGS...: run git as one person at one moment. The date goes into commits and
# into reflog entries (https://git-scm.com/docs/git-commit#_date_formats, RFC 2822 form).
as() {
  local n=$1 e=$2 d=$3
  shift 3
  GIT_AUTHOR_NAME="$n" GIT_AUTHOR_EMAIL="$e" GIT_AUTHOR_DATE="$d" \
    GIT_COMMITTER_NAME="$n" GIT_COMMITTER_EMAIL="$e" GIT_COMMITTER_DATE="$d" "$@"
}

# put REPO FILE...: copy files from zero-to-hero/apps into REPO with mode 0644, after checking their blob ids.
put() {
  local repo=$1 f want got
  shift
  for f in "$@"; do
    want="$(printf '%s\n' "$INPUTS" | awk -v f="$f" '$1 == f { print $2 }')"
    got="$(cd "$W" && git hash-object --no-filters "$APPS/$f")"
    [ "$got" = "$want" ] || die "zero-to-hero/apps/$f changed (blob $got, expected $want). Every commit id would change: update INPUTS, rebuild, re-capture and update explorer/content/git/world.yaml."
    mkdir -p "$repo/$(dirname "$f")"
    cp "$APPS/$f" "$repo/$f"
    chmod 0644 "$repo/$f"
  done
}

refs() {
  local d=$1 r
  for r in origin.git lakshmi ravi you; do
    [ -d "$d/$r" ] || continue
    git -C "$d/$r" for-each-ref --format="$r %(objectname) %(refname)"
    [ "$r" = origin.git ] || printf '%s %s HEAD^{tree}\n' "$r" "$(git -C "$d/$r" rev-parse 'HEAD^{tree}')"
  done
}

build() {
  W=$1
  case "$W" in /*) ;; *) die "DIR must be an absolute path: $W" ;; esac
  case "$W/" in "$ROOT"/*) die "DIR is inside this repository ($ROOT); use a folder outside it" ;; esac
  if [ -e "$W" ] && [ -n "$(ls -A "$W")" ]; then die "DIR is not empty: $W"; fi
  mkdir -p "$W/.home"
  export HOME="$W/.home"
  # Git never looks above the world for a repository.
  export GIT_CEILING_DIRECTORIES="$(dirname "$W")"
  cd "$W"
  local init=(git -c init.defaultBranch=main init -q --object-format=sha1 --initial-branch=main)

  # Monday: Lakshmi creates the shared repository and pushes the voting API to main.
  "${init[@]}" --bare origin.git
  "${init[@]}" lakshmi
  git -C lakshmi config user.name "${LAKSHMI[0]}"
  git -C lakshmi config user.email "${LAKSHMI[1]}"
  git -C lakshmi remote add origin "$W/origin.git"
  put lakshmi api/app.py api/static/index.html
  git -C lakshmi add api
  as "${LAKSHMI[@]}" "Mon, 02 Nov 2026 10:00:00 +0530" git -C lakshmi commit -q -m "Add the voting API"
  as "${LAKSHMI[@]}" "Mon, 02 Nov 2026 10:05:00 +0530" git -C lakshmi push -q -u origin main

  # Ravi clones it and starts the frontend on a feature branch.
  as "${RAVI[@]}" "Mon, 02 Nov 2026 14:00:00 +0530" git clone -q "$W/origin.git" ravi
  git -C ravi config user.name "${RAVI[0]}"
  git -C ravi config user.email "${RAVI[1]}"
  as "${RAVI[@]}" "Tue, 03 Nov 2026 11:00:00 +0530" git -C ravi switch -q -c "$BRANCH"
  put ravi frontend/nginx.conf
  git -C ravi add frontend
  as "${RAVI[@]}" "Tue, 03 Nov 2026 11:15:00 +0530" git -C ravi commit -q -m "Add the nginx reverse proxy config"
  as "${RAVI[@]}" "Tue, 03 Nov 2026 11:20:00 +0530" git -C ravi push -q -u origin "$BRANCH"

  # Tuesday afternoon: main moves on without the frontend.
  put lakshmi api/Dockerfile
  git -C lakshmi add api
  as "${LAKSHMI[@]}" "Tue, 03 Nov 2026 15:40:00 +0530" git -C lakshmi commit -q -m "Add a Dockerfile for the API"
  as "${LAKSHMI[@]}" "Tue, 03 Nov 2026 15:45:00 +0530" git -C lakshmi push -q origin main

  # Wednesday: Ravi finishes the frontend. His branch is not merged.
  put ravi frontend/Dockerfile
  git -C ravi add frontend
  as "${RAVI[@]}" "Wed, 04 Nov 2026 09:20:00 +0530" git -C ravi commit -q -m "Add a Dockerfile for the frontend"
  as "${RAVI[@]}" "Wed, 04 Nov 2026 09:25:00 +0530" git -C ravi push -q origin "$BRANCH"

  # Both teammates fetch, so every clone knows every branch on origin.
  as "${LAKSHMI[@]}" "Wed, 04 Nov 2026 09:30:00 +0530" git -C lakshmi fetch -q origin
  as "${RAVI[@]}" "Wed, 04 Nov 2026 09:30:00 +0530" git -C ravi fetch -q origin

  # You join the team: a fresh clone.
  as "${YOU[@]}" "Wed, 04 Nov 2026 10:00:00 +0530" git clone -q "$W/origin.git" you
  git -C you config user.name "${YOU[0]}"
  git -C you config user.email "${YOU[1]}"

  echo "The Explorer repo is ready in $W"
  refs "$W"
}

case "${1:-}" in
  refs) [ -n "${2:-}" ] || die "usage: world.sh refs DIR"; refs "$2" ;;
  -h|--help) sed -n '2,19p' "$0" ;;
  "") build "$(mktemp -d)/explorer-repo" ;;
  *) build "$1" ;;
esac
