# G-07: git pull refuses: "local changes would be overwritten"

## 📖 The story
You are halfway through an edit in `api/app.py` (a 30-second cap for `/api/burn`), not ready to commit. Lakshmi asks you to pull her urgent change for the fest final. `git pull` refuses.

## 🔥 Symptoms
- `git pull` prints `error: Your local changes to the following files would be overwritten by merge:` and `api/app.py`.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/07-pull-blocked-local-changes/you
git status
git diff
git pull
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

Git will not mix incoming changes with your **uncommitted** ones in the same file. Can you put your work aside for a moment?
</details>
<details><summary>💡 Hint 2</summary>

There is a command that works like a drawer: put things in, take them out later.
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git stash          # put your unfinished edit in a drawer
git pull           # Lakshmi's change comes in
git stash pop      # take your edit back out, on top of her change
git diff           # your work is still here ✅
bash ../check.sh
```
(Alternative: commit your work first, then `git pull --rebase`.) Throwing the edit away (`git restore api/app.py`) also makes the pull work, and loses your work.
</details>

## 🏭 Production lesson
`git stash` is the fastest way to switch context. Do not leave things there for weeks; `git stash list` shows what is there. If your Git config has `pull.rebase=true`, the message reads differently (`cannot pull with rebase: You have unstaged changes.`); the fix is the same.
