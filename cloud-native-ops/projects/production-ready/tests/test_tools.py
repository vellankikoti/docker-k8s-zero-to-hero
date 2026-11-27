"""Unit tests for the cost and DORA tools. No cluster needed:  python3 -m unittest discover -s tests -v   (from this folder)"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(HERE, "..", "scripts")


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(SCRIPTS, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


cost, dora = load("cost-report"), load("dora")
NOW = datetime(2026, 11, 27, 12, 0, tzinfo=timezone.utc)


def rev(n, hours_ago, status="superseded", desc="Upgrade complete"):
    t = (NOW - timedelta(hours=hours_ago)).strftime("%Y-%m-%dT%H:%M:%S.123456789Z")      # Helm prints nanoseconds
    return {"revision": n, "updated": t, "status": status, "description": desc}


class Quantities(unittest.TestCase):
    def test_cpu(self):
        self.assertAlmostEqual(cost.qty("250m", "cpu"), 0.25)
        self.assertEqual(cost.qty("2", "cpu"), 2.0)

    def test_memory(self):
        self.assertAlmostEqual(cost.qty("128Mi", "mem"), 0.125)
        self.assertEqual(cost.qty("1Gi", "mem"), 1.0)
        self.assertAlmostEqual(cost.qty("1073741824", "mem"), 1.0)


class CostReport(unittest.TestCase):
    def pod(self, ns, cpu, mem, phase="Running"):
        return {"metadata": {"namespace": ns}, "status": {"phase": phase},
                "spec": {"containers": [{"resources": {"requests": {"cpu": cpu, "memory": mem}}}]}}

    def test_requests_are_summed_per_namespace_and_finished_pods_are_ignored(self):
        pods = {"items": [self.pod("a", "100m", "128Mi"), self.pod("a", "100m", "128Mi"), self.pod("a", "5", "5Gi", "Succeeded")]}
        r = cost.requested(pods)["a"]
        self.assertAlmostEqual(r[0], 0.2)
        self.assertAlmostEqual(r[1], 0.25)
        self.assertEqual(r[2], 2)

    def test_usage_parsing(self):
        u = cost.used("iac-prod  chai-1  10m  40Mi\niac-prod  chai-2  30m  60Mi\n")
        self.assertAlmostEqual(u["iac-prod"][0], 0.04)
        self.assertAlmostEqual(u["iac-prod"][1], 100 / 1024)

    def test_report_names_the_cost_centre_and_the_night_shift_saving(self):
        d = tempfile.mkdtemp()
        pods = {"items": [self.pod("iac-dev", "1", "1Gi"), self.pod("loose", "1", "1Gi")]}
        nss = {"items": [{"metadata": {"name": "iac-dev", "labels": {"z2h/cost-center": "cc-1", "z2h/env": "dev"}}},
                         {"metadata": {"name": "loose", "labels": {}}}]}
        for n, v in (("p.json", pods), ("n.json", nss)):
            json.dump(v, open(os.path.join(d, n), "w"))
        open(os.path.join(d, "t.txt"), "w").write("iac-dev x 100m 100Mi\n")
        out = subprocess.run([sys.executable, os.path.join(SCRIPTS, "cost-report.py"), "--pods", d + "/p.json", "--namespaces", d + "/n.json", "--top", d + "/t.txt"],
                             capture_output=True, text=True, check=True).stdout
        self.assertIn("cc-1", out)
        self.assertIn("night shift", out)
        self.assertIn("loose", out)                    # a namespace with Pods but no cost centre is called out
        self.assertIn("right-size iac-dev", out)       # uses 10% of the CPU it reserved


class Dora(unittest.TestCase):
    def test_counts_failures_and_rollbacks(self):
        h = [rev(1, 48), rev(2, 24, "failed", 'Upgrade "chai-stall" failed'), rev(3, 23, "superseded", "Rollback to 1"), rev(4, 1, "deployed")]
        r = dora.analyse(h, 30, NOW)
        self.assertEqual(r["deployments"], 4)
        self.assertAlmostEqual(r["failure_rate"], 0.5)                 # the failed one and the rollback
        self.assertAlmostEqual(r["restore_seconds"], 3600, delta=1)     # failed at 24h ago, restored 1h later
        self.assertAlmostEqual(r["per_day"], 4 / 30)

    def test_old_revisions_are_outside_the_window(self):
        r = dora.analyse([rev(1, 24 * 40), rev(2, 24)], 30, NOW)
        self.assertEqual(r["deployments"], 1)

    def test_lead_time_is_commit_to_next_good_deploy(self):
        h = [rev(1, 10), rev(2, 2)]
        commits = [NOW - timedelta(hours=12), NOW - timedelta(hours=3)]
        r = dora.analyse(h, 30, NOW, commits)
        # commit 12h ago -> deployed at 10h ago (2h); commit 3h ago -> deployed at 2h ago (1h): mean 1.5h
        self.assertAlmostEqual(r["lead_seconds"], 5400, delta=1)

    def test_no_history_does_not_crash(self):
        r = dora.analyse([], 30, NOW)
        self.assertIsNone(r["failure_rate"])
        self.assertIsNone(r["restore_seconds"])

    def test_bands(self):
        self.assertEqual(dora.band("freq", 3), "elite")
        self.assertEqual(dora.band("cfr", 0.5), "low")
        self.assertEqual(dora.band("restore", 600), "elite")

    def test_helm_nanosecond_timestamps_parse(self):
        self.assertEqual(dora.when("2026-11-27T18:27:46.850327981Z").microsecond, 850327)
        self.assertEqual(dora.when("2026-11-27T18:27:46Z").second, 46)


if __name__ == "__main__":
    unittest.main()
