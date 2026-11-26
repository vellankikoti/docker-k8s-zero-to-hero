# G-04: A merge stopped halfway (conflict)

## 📖 The story
You tried a blue theme on the branch `blue-theme`. Meanwhile `main` got a green theme. You merge `blue-theme` into `main` and Git stops with CONFLICT. The team has since agreed on violet: **#7c3aed**.

## 🔥 Symptoms
- `git status` shows `You have unmerged paths` and `both modified:   api/app.py`

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/04-merge-conflict/you
git status
grep -n -A4 '<<<<<<<' api/app.py
git diff
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

The file holds both versions between `<<<<<<<`, `=======` and `>>>>>>>`.
</details>
<details><summary>💡 Hint 2</summary>

Write the agreed line, delete all the markers, then mark the file as resolved.
</details>
<details><summary>✅ Root cause & fix</summary>

Edit `api/app.py` so the five lines become one: `THEME_COLOR = os.environ.get("THEME_COLOR", "#7c3aed")`. Then:
```bash
grep -c '<<<<<<<' api/app.py      # 0
git add api/app.py
git commit --no-edit
bash ../check.sh
```
Want to give up instead? `git merge --abort` puts everything back.
</details>

## 🏭 Production lesson
`git add` marks a file resolved whatever it holds. Committing it unedited puts the markers in history, and the API no longer starts (`python3 -m py_compile api/app.py` fails). Check for markers before you commit.
