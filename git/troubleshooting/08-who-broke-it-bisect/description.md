# G-08: Who broke the health check? (bisect)

## 📖 The story
Release smoke test: the Showdown API container never turns healthy. The Dockerfile's health check asks for `/healthz`. The last good release is tag `v1.0`, and there are 10 commits since, by Lakshmi, Ravi and you. Find the commit that broke it, then undo it the team-safe way.

## 🔥 Symptoms
- `grep -n 'path == "/health' api/app.py` shows `elif path == "/health":`
- `git log --oneline v1.0..main` lists 10 commits.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/08-who-broke-it-bisect/you
git log --oneline v1.0..main
git show v1.0:api/app.py | grep -n 'path == "/health'
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

`git bisect run <command>`: the command must exit 0 for *good* and 1–127 (not 125) for *bad*.
</details>
<details><summary>💡 Hint 2</summary>

`grep -q 'path == "/healthz"' api/app.py` exits 0 when the route is there and 1 when it is not.
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git bisect start main v1.0
git bisect run grep -q 'path == "/healthz"' api/app.py   # f587695 is the first bad commit
git bisect reset
git revert --no-edit f587695       # main is shared: undo with a new commit
git push
bash ../check.sh
```
Reverting the newest commit (`git revert HEAD`) because "it is usually the culprit" changes the wrong thing.
</details>

## 🏭 Production lesson
Bisect halves the suspects at each test: 10 commits took 3 tests here. Pair it with an automated check so the bug cannot come back.
