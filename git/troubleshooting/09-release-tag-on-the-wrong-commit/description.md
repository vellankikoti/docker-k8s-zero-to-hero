# G-09: The release tag on the wrong commit (exercise)

## 📖 The story
Release time for the Showdown. Lakshmi merged Ravi's frontend into `main` and pushed it at 10:00. At 10:30 you tag `v1.0` on your `main` and push the tag. You had not fetched since yesterday. Ravi has already fetched your tag. The release pipeline builds `v1.0`: it has no frontend.

## 🔥 Symptoms
- `git ls-tree -r --name-only v1.0` lists only `api/` files.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/09-release-tag-on-the-wrong-commit/you
git show --no-patch v1.0
git status
git fetch
git log --oneline --graph --decorate --all
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

`git status` compares your branch with your **last fetched** copy of `origin/main`, not with `origin` itself.
</details>
<details><summary>💡 Hint 2</summary>

Others already have `v1.0`. Read "On Re-tagging" in `git help tag`.
</details>
<details><summary>✅ Root cause & fix</summary>

Leave `v1.0` alone and release a new version on the right commit:
```bash
git pull
git tag -a v1.0.1 -m 'Showdown 1.0.1: includes the frontend'
git push origin v1.0.1
bash ../check.sh
```
Moving the tag (`git tag -f`, then `git push --force origin v1.0`) changes it on `origin`, but Ravi keeps the old one: a plain `git fetch` leaves it, and `git fetch --tags` refuses with `would clobber existing tag`. Two releases now share one name.
</details>

## 🏭 Production lesson
A pushed release tag is a promise. Never move it; publish a new version. Fetch before you tag.
