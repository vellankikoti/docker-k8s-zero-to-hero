#!/usr/bin/env bash
# G-05 reference fix (the commit is not pushed): stop tracking the file, ignore it, rewrite the last commit.
source "$(dirname "$0")/../_lib.sh"
sandbox 05-committed-a-secret
git rm -q --cached api/.env
echo ".env" >> .gitignore
git add .gitignore
as "${YOU[@]}" "Thu, 05 Nov 2026 14:10:00 +0530" git commit -q --amend --no-edit
ok "The last commit no longer holds api/.env; the file stays on your disk and Git ignores it."
git show --stat --oneline HEAD
