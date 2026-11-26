# G-02: My push was rejected

## 📖 The story
You made the Showdown theme blue and pushed. Git said no. Lakshmi says she only pushed one small Dockerfile change this morning.

## 🔥 Symptoms
- `git push` prints `! [rejected]        main -> main (fetch first)`

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/02-push-rejected/you
git push
git fetch
git status
git log --oneline --graph --decorate --all
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

After `git fetch`, does `git status` say *behind*, *ahead*, or *diverged*?
</details>
<details><summary>💡 Hint 2</summary>

Lakshmi's commit must come into your branch before yours can go on top.
</details>
<details><summary>✅ Root cause & fix</summary>

Lakshmi pushed first. Bring her commit in, replay yours on top, then push:
```bash
git pull --rebase
git push
bash ../check.sh
```
(`git pull --no-rebase` also works; it adds a merge commit.)
</details>

## 🏭 Production lesson
A rejected push is Git protecting your teammate's work. `git push --force` "fixes" it by deleting her commit from `origin` (try it, then run `bash ../check.sh`).
