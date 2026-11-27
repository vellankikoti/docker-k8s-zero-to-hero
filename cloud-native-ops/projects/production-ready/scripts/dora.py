#!/usr/bin/env python3
"""dora.py: the four DORA metrics, read from what already exists: Helm's release history (and, for lead time, git).

    Deployment frequency   how often do we ship to production?
    Lead time for changes  how long from a commit to running in production?
    Change failure rate    what share of our deployments failed or had to be rolled back?
    Time to restore        when a deployment fails, how long until a good one is running?

    ./scripts/dora.py --ns iac-prod [--release chai-stall] [--days 30] [--git ~/infra]
    ./scripts/dora.py --history history.json           (used by the tests)

Every deployment is one Helm revision. Nothing here needs a new tool or a new database: the evidence is already in the cluster.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta, timezone


def when(s):
    """Parse the timestamps Helm prints: '2026-11-27T18:27:46.850327981Z' (JSON) or '2026-11-27 18:27:46.85 +0000 UTC'."""
    m = re.match(r"(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}:\d{2})(?:\.(\d+))?\s*(Z|[+-]\d{2}:?\d{2})?", s.strip())
    if not m:
        raise ValueError(f"cannot read the time {s!r}")
    day, clock, frac, tz = m.groups()
    tz = "+00:00" if tz in (None, "Z") else (tz if ":" in tz else tz[:3] + ":" + tz[3:])
    return datetime.fromisoformat(f"{day}T{clock}.{(frac or '0')[:6].ljust(6, '0')}{tz}")


def failed(rev):
    return rev.get("status") == "failed" or str(rev.get("description", "")).lower().startswith("rollback")


def analyse(history, days, now=None, commits=None):
    now = now or datetime.now(timezone.utc)
    since = now - timedelta(days=days)
    revs = sorted((r for r in history if when(r["updated"]) >= since), key=lambda r: r["revision"])
    out = {"deployments": len(revs), "days": days}
    out["per_day"] = len(revs) / days if days else 0
    bad = [r for r in revs if failed(r)]
    out["failure_rate"] = (len(bad) / len(revs)) if revs else None
    restores = []
    for r in revs:
        if r.get("status") == "failed":
            nxt = next((x for x in revs if x["revision"] > r["revision"] and x.get("status") != "failed"), None)   # the next good (or rolled-back) release
            if nxt:
                restores.append((when(nxt["updated"]) - when(r["updated"])).total_seconds())
    out["restore_seconds"] = (sum(restores) / len(restores)) if restores else None
    lead = []
    for c in commits or []:
        good = [when(r["updated"]) for r in revs if not failed(r) and when(r["updated"]) >= c]
        if good:
            lead.append((min(good) - c).total_seconds())
    out["lead_seconds"] = (sum(lead) / len(lead)) if lead else None
    return out


def nice(seconds):
    if seconds is None:
        return "not enough data yet"
    for unit, size in (("day", 86400), ("hour", 3600), ("minute", 60)):
        if seconds >= size:
            return f"{seconds / size:.1f} {unit}s"
    return f"{seconds:.0f} seconds"


def band(metric, v):
    if v is None:
        return ""
    if metric == "freq":
        return "elite" if v >= 1 else "high" if v >= 1 / 7 else "medium" if v >= 1 / 30 else "low"
    if metric == "lead":
        return "elite" if v < 86400 else "high" if v < 7 * 86400 else "medium" if v < 30 * 86400 else "low"
    if metric == "cfr":
        return "elite" if v <= 0.05 else "high" if v <= 0.10 else "medium" if v <= 0.15 else "low"
    return "elite" if v < 3600 else "high" if v < 86400 else "medium" if v < 7 * 86400 else "low"      # restore


def git_commits(path, days):
    try:
        out = subprocess.run(["git", "-C", path, "log", f"--since={days}.days", "--format=%cI"], capture_output=True, text=True, check=True).stdout
    except Exception as e:
        sys.exit(f"dora: cannot read git history of {path}: {e}")
    return [when(l) for l in out.split()]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ns", default="iac-prod"), ap.add_argument("--release", default="chai-stall")
    ap.add_argument("--days", type=int, default=30), ap.add_argument("--git"), ap.add_argument("--history")
    a = ap.parse_args()
    if a.history:
        history = json.load(open(a.history))
    else:
        env = dict(os.environ, HELM_DRIVER=os.environ.get("HELM_DRIVER", "configmap"))
        try:
            history = json.loads(subprocess.run(["helm", "history", a.release, "-n", a.ns, "-o", "json", "--max", "200"],
                                                capture_output=True, text=True, check=True, env=env).stdout)
        except Exception as e:
            sys.exit(f"dora: cannot read the history of {a.release} in {a.ns}: {getattr(e, 'stderr', e)}")
    r = analyse(history, a.days, commits=git_commits(a.git, a.days) if a.git else None)
    print(f"DORA metrics for {a.release} in {a.ns}, last {a.days} days   ({r['deployments']} deployments)\n")
    cfr = "no deployments yet" if r["failure_rate"] is None else f"{r['failure_rate']:.0%}"
    print(f"  Deployment frequency   {r['per_day']:.2f} per day            {band('freq', r['per_day'])}")
    print(f"  Lead time for changes  {nice(r['lead_seconds']) if a.git else 'give --git <repo> to measure it'}   {band('lead', r['lead_seconds'])}")
    print(f"  Change failure rate    {cfr}                  {band('cfr', r['failure_rate'])}")
    print(f"  Time to restore        {nice(r['restore_seconds'])}   {band('restore', r['restore_seconds'])}")
    print("\nThe bands (elite / high / medium / low) are a rough guide, not a grade. The point is the TREND: are we getting faster AND safer?")
    print("A failed deployment is a Helm revision with status 'failed' or a rollback. Change what you ship, then run this again.")


if __name__ == "__main__":
    main()
