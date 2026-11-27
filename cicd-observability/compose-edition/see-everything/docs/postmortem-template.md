# Postmortem: <short title>

> **Blameless.** We describe what the system and the process allowed, not who made a mistake. People acted sensibly on the information they had.
> Copy this file, fill it in within two working days, and review it with the team.

| | |
|---|---|
| **Date** | YYYY-MM-DD |
| **Duration** | start → end (minutes) |
| **Severity** | SEV1 / SEV2 / SEV3 |
| **Authors / incident commander** | |
| **Status** | draft / reviewed / actions complete |

## 1. Summary
Two or three sentences a stranger can understand. *What broke, who was affected, how long, how it was fixed.*

## 2. Impact
- Customers affected: *(for example "about 40% of orders failed")*
- Duration of user-visible impact:
- **Error budget burned:** *(for example 80% of the monthly budget; use the dashboard's budget panel)*
- Revenue / reputational impact:

## 3. Timeline (use the real timestamps from the alert emails, Grafana and Jenkins)
| Time | Event |
|---|---|
| hh:mm | the change that started it (release? config?) |
| hh:mm | first symptom in the metrics |
| hh:mm | **alert fired** (how long after the symptom?) |
| hh:mm | human acknowledged |
| hh:mm | cause identified |
| hh:mm | **mitigation applied** (rollback / reset / scale) |
| hh:mm | **alert resolved**, service confirmed healthy |

**Time to detect:** ___ min · **Time to mitigate:** ___ min · **Time to resolve:** ___ min

## 4. Root cause(s) and contributing factors
Use "five whys". The first answer is rarely the root.
1. Why did orders fail? →
2. Why did that happen? →
3. Why was it not caught before production? →
4. Why did it reach all users? →
5. Why did detection take as long as it did? →

## 5. What went well
- *(for example "the alert fired within 40 s and linked to the right runbook section")*

## 6. What went badly / where we got lucky
-

## 7. Action items
Every item has **one owner** and a **date**. Prefer fixes that make the mistake *impossible or caught automatically* over "be more careful".

| # | Action | Type (prevent / detect / mitigate) | Owner | Due |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |

## 8. Lessons and what we will change in the pipeline, dashboards or runbook
-
