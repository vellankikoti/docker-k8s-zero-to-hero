#!/usr/bin/env bash
# A predictable Git environment for the Explorer repo (PRD §7, §13, WU-GIT-01). Sourced, never run.
#
# Sourced by world.sh and capture/_lib.sh. After it, git reads no system or global config, never
# prompts, never pages, prints English and no colour, and cannot be pointed at another repository by
# an inherited GIT_DIR. Your own ~/.gitconfig and this repository's .git are never read or written.
#
# Sources (git-scm.com, checked 2026-11-21):
#   https://git-scm.com/docs/git#Documentation/git.txt-GITCONFIGGLOBAL
#     "if GIT_CONFIG_GLOBAL is set, neither $HOME/.gitconfig nor $XDG_CONFIG_HOME/git/config will be
#      read. Can be set to /dev/null to skip reading configuration files of the respective level."
#     (added in Git 2.32.0, Documentation/RelNotes/2.32.0)
#   https://git-scm.com/docs/git#Documentation/git.txt-GITCONFIGNOSYSTEM  (skip $(prefix)/etc/gitconfig)
#   https://git-scm.com/docs/git#Documentation/git.txt-GITPAGER           ("cat": no pager)
#   https://git-scm.com/docs/git#Documentation/git.txt-GITTERMINALPROMPT  (false: never prompt)

# Every inherited GIT_* variable goes: an inherited GIT_DIR, GIT_CONFIG_COUNT/KEY/VALUE, GIT_DEFAULT_HASH or
# author identity would send git to another repository, add config or change a commit id.
for v in $(env | sed -n 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p'); do unset "$v"; done
unset v EMAIL XDG_CONFIG_HOME LANGUAGE

# No system config, no global config. HOME is set by the caller to an empty folder inside the world,
# so even a Git older than 2.32 (no GIT_CONFIG_GLOBAL) finds no ~/.gitconfig.
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_TERMINAL_PROMPT=0
export GIT_PAGER=cat
export PAGER=cat
# English messages, and no local time zone in anything git prints with --date=local.
export LC_ALL=C
export TZ=UTC
