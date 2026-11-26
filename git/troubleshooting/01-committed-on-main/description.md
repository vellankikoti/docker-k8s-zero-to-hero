# G-01: Oops, I committed on main

## 📖 The story
The Showdown team has one rule: every change goes through a pull request. You made two commits for the new title, "Rename the app to The Showdown" and "Bump the version to 1.1.0". Then you notice your prompt says **main**. Nothing is pushed yet.

## 🔥 Symptoms
- `git status` says `Your branch is ahead of 'origin/main' by 2 commits.`
- A push from here would put your commits on the team's `main` without a review.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/01-committed-on-main/you
git status
git log --oneline --graph --decorate --all
git branch -vv
bash ../check.sh        # am I done? (exit 0 = yes)
```

<details><summary>💡 Hint 1</summary>

A branch is a name that points at a commit. You can create a new one right where you are, so your two commits get a home.
</details>
<details><summary>💡 Hint 2</summary>

A new branch alone is not enough: `main` still points at your commits. Where should `main` point? At `origin/main`.
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git branch feature/showdown-title             # a branch for your two commits
git reset --hard origin/main                  # main back to the team's state (safe: not pushed)
git switch feature/showdown-title
git push -u origin feature/showdown-title     # now open a pull request
bash ../check.sh
```
The tempting `git switch -c feature/showdown-title` alone leaves `main` 2 commits ahead (`git branch -vv` shows it).
</details>

## 🏭 Production lesson
Committing on the wrong branch happens to everyone. If it is **not pushed**, it is a 10-second fix. A shell prompt that shows the branch helps you notice.
