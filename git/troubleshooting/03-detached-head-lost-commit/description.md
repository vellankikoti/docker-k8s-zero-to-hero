# G-03: Where did my commit go? (detached HEAD)

## 📖 The story
You went back to the first commit of the Showdown to look at the voting API, liked an idea, and committed "Add tea as a third vote option" right there. Then you switched back to `main`. Your commit is not in `git log`.

## 🔥 Symptoms
- `git log` on `main` does not show "Add tea as a third vote option".
- When you switched, Git printed `Warning: you are leaving 1 commit behind`.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/03-detached-head-lost-commit/you
git log --oneline --graph --decorate --all
git reflog -5
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

A commit made in detached HEAD belongs to **no branch**, so `--all` does not show it. Git still remembers everywhere HEAD has been.
</details>
<details><summary>💡 Hint 2</summary>

Find the commit's id in `git reflog`, then put a branch on it.
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git reflog -5                        # 1954f61 HEAD@{1}: commit: Add tea as a third vote option
git branch tea-option 1954f61        # rescue it with a branch
git merge --no-edit tea-option       # bring it into main, if you want it there
bash ../check.sh
```
`git checkout 1954f61` shows the commit again, but leaves you in detached HEAD: it is still on no branch.
</details>

## 🏭 Production lesson
Detached HEAD is for **looking** at the past. Before you commit there, run `git switch -c <name>`. A commit that no branch holds stays in the reflog, but Git expires such entries after 30 days by default (`gc.reflogExpireUnreachable`) and garbage collection can then delete the commit.
