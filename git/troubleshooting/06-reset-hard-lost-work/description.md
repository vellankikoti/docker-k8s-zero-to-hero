# G-06: I ran reset --hard and lost three commits

## 📖 The story
An afternoon of Showdown work: a new title, a tea option and version 1.1.0, three commits. Trying to "clean up", you ran `git reset --hard HEAD~3`. All three are gone from `git log`.

## 🔥 Symptoms
- `git log` ends at "Add a Dockerfile for the API".
- `git status` says `Your branch is up to date with 'origin/main'`.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/06-reset-hard-lost-work/you
git log --oneline --decorate
git reflog -5
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

Commits are not deleted at once. The **reflog** remembers where HEAD pointed before the reset.
</details>
<details><summary>💡 Hint 2</summary>

Which `HEAD@{n}` entry is the moment before the reset?
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git reflog -5                   # HEAD@{0}: reset: moving to HEAD~3 · HEAD@{1}: commit: Bump the version to 1.1.0
git reset --hard 'HEAD@{1}'     # main back to where it was before the reset
git log --oneline --decorate -4 # all three commits are back 🛟
bash ../check.sh
```
`git checkout 'HEAD@{1}'` shows the files again but leaves `main` where it was (detached HEAD).
</details>

## 🏭 Production lesson
`reset --hard` really destroys **uncommitted** changes. Committed work survives in the reflog: entries expire after 90 days by default, or 30 days for commits no branch holds (`gc.reflogExpire`, `gc.reflogExpireUnreachable`). Commit often: it is your safety net.
