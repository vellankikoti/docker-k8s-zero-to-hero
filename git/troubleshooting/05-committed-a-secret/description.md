# G-05: I committed a secret 🔐

## 📖 The story
You pointed the Showdown API at the team's demo Redis and kept its password in `api/.env` for local testing. Then you ran `git add .` and committed. **It is not pushed yet.** The team rule: secrets never enter Git history.

The password here is a fake demo value, `z2h-demo-key-NOT-REAL-123`. Never try this with a real one.

## 🔥 Symptoms
- `git show --stat HEAD` lists `api/.env`.
- `git log -p | grep z2h-demo-key` finds the password.

## 🔍 Investigate
```bash
cd /tmp/z2h-git-ts/05-committed-a-secret/you
git show --stat HEAD
git log -p | grep z2h-demo-key
bash ../check.sh
```

<details><summary>💡 Hint 1</summary>

Remove the file **from the commit**, but keep it on your disk.
</details>
<details><summary>💡 Hint 2</summary>

Make Git ignore it from now on, then rewrite the last (unpushed) commit.
</details>
<details><summary>✅ Root cause & fix</summary>

```bash
git rm --cached api/.env              # stop tracking it, keep the file on disk
echo '.env' >> .gitignore
git add .gitignore
git commit --amend --no-edit          # rewrite the last commit without the file
git log -p | grep z2h-demo-key; echo "exit code: $?"    # exit code: 1, nothing found
bash ../check.sh
```
`git rm --cached api/.env` plus a **new** commit is not enough: the old commit still holds the password.
</details>

## 🏭 Production lesson
🚨 **If it had been pushed:** treat it as leaked. **Revoke and rotate the password first.** Rewriting history afterwards (`git commit --amend` and `git push --force`, or `git filter-repo` for older commits) cleans `origin`, but every clone that fetched the old commit keeps it. GitHub's guide says so: "You cannot remove sensitive data from other users' clones of your repository" (docs.github.com, Removing sensitive data from a repository). Prevention: `.gitignore` from day one, and secret scanning in CI.
