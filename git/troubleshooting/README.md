# 🌿 Git Break-and-Fix Scenarios

Ten emergencies every developer meets in their first months on a team: eight classics and two exercises. Each one builds the **Explorer repo** in a throwaway sandbox in `/tmp/z2h-git-ts/`, breaks it the realistic way, and leaves you to investigate. Your own repositories are never touched.

The Explorer repo is the Showdown app's repository (the `apps` folder: `api` and `frontend`), shared by two teammates, Lakshmi and Ravi, through a bare remote `origin`. You join with a fresh clone. It is the same world as every Git page on devopsengineers.in, built by `explorer/validation/git/world.sh`, so run the scenarios from a full clone of this repository.

```
/tmp/z2h-git-ts/<scenario>/
  origin.git   the team's shared remote (like GitHub)
  lakshmi/     Lakshmi's clone
  ravi/        Ravi's clone
  you/         your clone: work here
  check.sh     am I done? run it from your clone: bash ../check.sh
```

Every commit the scripts make has a fixed author and date, so the commit ids in the sandbox are the same on every machine (`9e9bca0`, `1954f61`, `f587695`…). Commits you make yourself carry your clock time, so their ids differ. The scripts ignore your global Git config; the commands you type use it.

## How to run
From the folder that holds `labs.sh` (the repository root in docker-k8s-zero-to-hero, `zero-to-hero` in devops-engineers):
```bash
./labs.sh                 # interactive menu (Git, Docker and Kubernetes)
./labs.sh git 03          # break scenario G-03
./labs.sh git 03 check    # am I done? (the same as bash ../check.sh in your clone)
./labs.sh git 03 fix      # apply the reference fix
./labs.sh git clean       # delete all sandboxes
```
Each folder has `description.md` (story, symptoms, hints and the answer, hidden), `break.sh`, `fix.sh` and `check.sh`. `check.sh` only looks: it exits 0 when the scenario is fixed and 1 when it is not.

## The calm-developer loop
```
1. git status                                  where am I? what's going on?
2. git log --oneline --graph --decorate --all  what does history look like?
3. git reflog                                  where have I been? (committed work is rarely lost)
4. read the message                            Git's hints usually name the command
5. fix → verify (git status, git log, bash ../check.sh)
```

## Scenarios
| # | Site | Emergency | You'll use | Level |
|---|---|---|---|---|
| [G-01](01-committed-on-main/description.md) | GS1.1 | Oops, I committed on `main` | `branch`, `reset --hard origin/main` | 🟢 |
| [G-02](02-push-rejected/description.md) | GS1.2 | My push was rejected | `fetch`, `pull --rebase`, `push` | 🟢 |
| [G-03](03-detached-head-lost-commit/description.md) | GS1.3 | Where did my commit go? (detached HEAD) | `reflog`, `branch <id>` | 🟡 |
| [G-04](04-merge-conflict/description.md) | GS1.4 | A merge stopped halfway | resolve, `add`, `commit` / `merge --abort` | 🟢 |
| [G-05](05-committed-a-secret/description.md) | GS1.5 | I committed a secret 🔐 | `rm --cached`, `.gitignore`, `commit --amend` | 🟡 |
| [G-06](06-reset-hard-lost-work/description.md) | GS2.1 | `reset --hard` ate my commits | `reflog`, `reset --hard HEAD@{1}` | 🟡 |
| [G-07](07-pull-blocked-local-changes/description.md) | GS2.2 | `git pull` refuses: local changes | `stash`, `pull`, `stash pop` | 🟢 |
| [G-08](08-who-broke-it-bisect/description.md) | GS2.3 | Who broke the health check? | `bisect run`, `revert` | 🔴 |
| [G-09](09-release-tag-on-the-wrong-commit/description.md) | GS2.4 | Exercise: the release tag on the wrong commit | `tag -a`, `fetch --tags`, `ls-remote` | 🟡 |
| [G-10](10-force-push-erased-a-commit/description.md) | GS2.5 | Exercise: the force push that erased my commit | `rebase <upstream>`, `push --force-with-lease` | 🔴 |

Every output quoted in the descriptions was captured with Git 2.43.0 on a real run of these scripts, the same runs that devopsengineers.in shows.
