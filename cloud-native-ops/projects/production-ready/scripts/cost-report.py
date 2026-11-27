#!/usr/bin/env python3
"""cost-report.py: what does each team's corner of the cluster cost, and where is money wasted?

Reads what your Pods ASKED for (requests: the cluster reserves it, so it is what you pay for) and, if metrics-server is
installed, what they actually USE. Rupee prices are an illustrative rate card, not a bill: change them with
--cpu-rate and --mem-rate (rupees per vCPU-hour and per GiB-hour) to match your cloud.

    ./scripts/cost-report.py                      read the live cluster through kubectl
    ./scripts/cost-report.py --pods p.json --namespaces n.json --top top.txt     (used by the tests)
"""
import argparse
import json
import subprocess
import sys
from collections import defaultdict

HOURS_PER_MONTH = 730
NIGHT_HOURS_OFF = 9          # the night-shift CronJobs close dev and staging from 22:00 to 07:00


def qty(value, kind):
    """'250m' -> 0.25 (cpu cores);  '128Mi' -> 0.125 (memory GiB)."""
    v = str(value)
    if kind == "cpu":
        return float(v[:-1]) / 1000 if v.endswith("m") else float(v)
    units = {"Ki": 2 ** -20, "Mi": 2 ** -10, "Gi": 1, "Ti": 2 ** 10, "K": 1e3 / 2 ** 30, "M": 1e6 / 2 ** 30, "G": 1e9 / 2 ** 30}
    for suffix, factor in units.items():
        if v.endswith(suffix):
            return float(v[: -len(suffix)]) * factor
    return float(v) / 2 ** 30


def kubectl(*args):
    try:
        return subprocess.run(["kubectl", *args], check=True, capture_output=True, text=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit(f"cost-report: kubectl failed: {getattr(e, 'stderr', e)}")


def requested(pods):
    """{namespace: [cpu cores, memory GiB, pod count]} for Pods that hold a reservation."""
    out = defaultdict(lambda: [0.0, 0.0, 0])
    for p in pods["items"]:
        if p["status"].get("phase") not in ("Pending", "Running"):
            continue
        ns = p["metadata"]["namespace"]
        out[ns][2] += 1
        for c in p["spec"].get("containers", []):
            r = c.get("resources", {}).get("requests", {})
            out[ns][0] += qty(r.get("cpu", "0"), "cpu")
            out[ns][1] += qty(r.get("memory", "0"), "mem")
    return out


def used(top_text):
    """{namespace: [cpu cores, memory GiB]} from `kubectl top pods -A --no-headers` (namespace pod cpu memory)."""
    out = defaultdict(lambda: [0.0, 0.0])
    for line in top_text.strip().splitlines():
        f = line.split()
        if len(f) >= 4:
            out[f[0]][0] += qty(f[2], "cpu")
            out[f[0]][1] += qty(f[3], "mem")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pods"), ap.add_argument("--namespaces"), ap.add_argument("--top")
    ap.add_argument("--cpu-rate", type=float, default=2.4, help="rupees per vCPU-hour (default 2.4)")
    ap.add_argument("--mem-rate", type=float, default=0.35, help="rupees per GiB-hour (default 0.35)")
    a = ap.parse_args()

    pods = json.load(open(a.pods)) if a.pods else json.loads(kubectl("get", "pods", "-A", "-o", "json"))
    nss = json.load(open(a.namespaces)) if a.namespaces else json.loads(kubectl("get", "ns", "-o", "json"))
    if a.top:
        top = open(a.top).read()
    else:
        try:
            top = subprocess.run(["kubectl", "top", "pods", "-A", "--no-headers"], capture_output=True, text=True, timeout=30).stdout
        except Exception:
            top = ""
    req, use = requested(pods), used(top)

    rows, untagged = [], []
    for n in nss["items"]:
        labels, name = n["metadata"].get("labels", {}), n["metadata"]["name"]
        if "z2h/cost-center" not in labels:
            if name in req and not name.startswith(("kube-", "default")):
                untagged.append(name)
            continue
        cpu, mem, count = req.get(name, (0, 0, 0))
        month = (cpu * a.cpu_rate + mem * a.mem_rate) * HOURS_PER_MONTH
        rows.append((labels["z2h/cost-center"], name, labels.get("z2h/env", "?"), count, cpu, mem, month, use.get(name)))

    print(f"{'COST CENTRE':<16}{'NAMESPACE':<14}{'ENV':<9}{'PODS':>5}{'vCPU asked':>12}{'GiB asked':>11}{'₹/month 24x7':>14}   used vs asked")
    total = 0.0
    for cc, name, env, count, cpu, mem, month, u in sorted(rows):
        total += month
        if u and cpu > 0:
            note = f"CPU {u[0] / cpu:>4.0%}  memory {u[1] / mem:>4.0%}" if mem > 0 else ""
        else:
            note = "(install metrics-server to see this)" if not top.strip() else "idle"
        print(f"{cc:<16}{name:<14}{env:<9}{count:>5}{cpu:>12.2f}{mem:>11.2f}{month:>14,.0f}   {note}")
    print(f"{'':<16}{'TOTAL':<14}{'':<9}{'':>5}{'':>12}{'':>11}{total:>14,.0f}")

    print("\nWhere the money can be saved (automation, not nagging):")
    nonprod = sum(r[6] for r in rows if r[2] in ("dev", "staging"))
    saving = nonprod * NIGHT_HOURS_OFF / 24
    print(f"  • night shift: dev and staging need nobody from 22:00 to 07:00. Closing them saves about ₹{saving:,.0f} a month "
          f"({NIGHT_HOURS_OFF}h of 24).  ./scripts/night-shift.sh enable")
    for cc, name, env, count, cpu, mem, month, u in sorted(rows):
        if u and cpu > 0 and u[0] / cpu < 0.3 and month > 0:
            print(f"  • right-size {name}: it uses {u[0] / cpu:.0%} of the CPU it reserved. Lower its requests, or let the autoscaler decide.")
    if untagged:
        print(f"  • these namespaces run Pods but have no z2h/cost-center label, so nobody is billed: {', '.join(untagged)}")
    print("\n(Prices are an illustrative rate card: ₹%.2f per vCPU-hour, ₹%.2f per GiB-hour. Your cloud's real numbers will differ.)" % (a.cpu_rate, a.mem_rate))


if __name__ == "__main__":
    main()
