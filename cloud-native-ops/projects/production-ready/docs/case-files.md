# 🕵️ Case files: four real failures, and the lock that would have helped

> Real incidents, told simply. None of them was "someone was stupid": each was **a normal person, a normal day, and a system with no second lock**. For each case you get what happened, the chain of small causes, and the drill in this project that practises the missing lock.
> Numbers are from the companies' own public write-ups, rounded.

---

## 1. Knight Capital, 2012: one server out of eight
**What happened.** A trading firm deployed new software to its servers by hand. **Seven of eight** got it. The eighth still ran old code, and a setting the new software reused made that old code start sending orders by itself. In about **45 minutes** the firm lost roughly **$440 million**, more than it was worth.

**The chain.** a manual deploy · no check that every server had the same version · old code left lying around · no big red "stop" button · no automatic rollback · the alarms were noisy, so people did not trust them.

**The missing locks.** *one automated deploy for every server* · *a check that all copies run the same version* · *a kill switch* · *rollback you have practised*.

**Your drill:** `gameday.sh skew`. It puts one Pod on an old image next to the real ones; `skew.sh` shouts that two versions run side by side. In your own pipeline, Kubernetes already prevents half of this (a Deployment replaces **all** Pods with the **same** template), and Ship It's blue/green and canary give you the rollback.

---

## 2. GitLab, 2017: five backups, none of them worked
**What happened.** While fixing a slow database replica late at night, an engineer deleted the data directory on the **wrong server**: the live one. Then came the second shock: of **five** backup and replication methods, **none** could restore the data in time (some had never run, some wrote empty files, one was an unmonitored error email). GitLab restored from a copy about **six hours old** and lost about six hours of issues, comments and merge requests. They published everything, live, and the internet respected them for it.

**The chain.** tired person · same-looking terminals for live and spare servers · backups that were never *restored* as a test · failures nobody was told about.

**The missing locks.** *restore drills on a schedule* · *a backup job that checks its own output* · *alerts when a backup fails* · *terminals that look different in production*.

**Your drill:** `gameday.sh restore`. The ledger is wiped with one command; you bring it back from the backup and **count the orders**. Look at [`10-ledger.yaml`](../manifests/10-ledger.yaml): the backup Job refuses to call a file a backup unless it exists and starts with the Redis marker, and `ledger.sh restore` skips a damaged file and uses the previous good one. Write down your **RPO** (how much data may be lost: here, up to 5 minutes) and **RTO** (how long to recover: here, about a minute).

---

## 3. Amazon S3, 2017: one typo, four hours
**What happened.** A team member ran a routine command to take a *small number* of servers out of one subsystem. One input was typed wrong, and a **much bigger set** of servers was removed. The storage service in a major region went down for about **four hours**, and a large part of the internet that depended on it stopped working with it. The restart took long because the subsystems had not been fully restarted for years.

**The chain.** a powerful tool with no limit on how much it may remove at once · a typo · a huge shared dependency · a recovery path that had not been practised at that size.

**The missing locks.** *a limit on blast radius* ("never remove more than X% at once, never go below a minimum") · *practised full restarts*. Amazon added exactly these safeguards afterwards.

**Your drill:** `gameday.sh policy`, especially the last line: scaling production to **zero** is refused by the API server itself ([`z2h-prod-never-scaled-to-zero`](../manifests/00-policies.yaml)). A guardrail that works at 2 a.m. beats a person who is careful. Then try `kubectl -n iac-prod scale deploy chai-stall --replicas=1` (allowed): the rule limits the *blast radius*, it does not stop work.

---

## 4. Cloudflare, 2019: a rule that ate every CPU
**What happened.** An engineer shipped a new firewall rule containing a **regular expression** that, for some inputs, takes exponentially long to evaluate. The rule went to **every** server in the world at once. CPUs hit 100% everywhere and a large part of Cloudflare's network returned errors for about **27 minutes**. Once they found the cause, a global kill switch ended it.

**The chain.** a change that looked harmless · no test for worst-case performance · deployed **everywhere at the same moment** · the safety valve (the kill switch) was found, but only after a while.

**The missing locks.** *gradual rollout* (a few servers first, then more) · *performance tests on new rules* · *a kill switch you can find in a hurry* · *automatic rollback when error rate jumps*.

**Your drill:** do the **canary** release in [Ship It](../../../../cicd-observability/projects/ship-it/README.md): the buggy version gets 20% of traffic, the pipeline measures the error rate **on the canary's own requests**, sees the failure and rolls back by itself. Then `gameday.sh kill` and `gameday.sh rush` to see the autoscaler and the Service share the load.

---

## How to write your own case file
For any incident (yours, or one you read about), fill five lines: **what happened · the chain of small causes · what the system allowed · the lock that was missing · the drill that practises it.** If the lock is "be more careful", it is not a lock yet. A lock is something that works **even when people are tired**.
