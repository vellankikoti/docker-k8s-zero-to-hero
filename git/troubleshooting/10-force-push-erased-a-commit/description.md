# G-10: The force push that erased my commit (exercise)

## 📖 The story
At 10:00 you pushed "Wait 90 seconds for slow API answers" to `feature/frontend`. At 11:00 Lakshmi, who had not fetched since yesterday, rebased `feature/frontend` onto `main` to tidy it and ran `git push --force`. Your commit is no longer on `origin`.

## 🔥 Symptoms
- `git fetch` prints `(forced update)` for `feature/frontend`.
- `git status` says your branch and `origin/feature/frontend` have diverged, 3 and 3.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/10-force-push-erased-a-commit/you
git fetch
git status
git log --oneline --graph --decorate --all
git reflog origin/feature/frontend
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

Lakshmi's two commits are the same changes as Ravi's two old ones, with new ids. Only your commit is missing.
</details>
<details><summary>💡 Hint 2</summary>

`git pull --rebase` uses the reflog of `origin/feature/frontend` to decide what is "yours". Your own push recorded your commit there.
</details>
<details><summary>✅ Root cause & fix</summary>

Rebase onto the rewritten branch, naming it. With an explicit upstream, `git rebase` skips commits already applied upstream and replays only yours:
```bash
git fetch
git rebase origin/feature/frontend
git push
bash ../check.sh
```
`git pull --rebase` reports success here and **drops your commit**: its fork point is your own pushed commit (`git merge-base --fork-point`). Your commit is still in `git reflog`.
</details>

## 🏭 Production lesson
Rewriting a shared branch forces everyone to repair their history. If you must, use `git push --force-with-lease`: Lakshmi's push would have been refused with `(stale info)`, because `origin` had moved since her last fetch.
