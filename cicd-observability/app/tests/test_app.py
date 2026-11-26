"""Unit + HTTP tests for the Chai Stall. Run:  python3 -m unittest discover -s tests -v  (from the app folder)"""
import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import app  # noqa: E402

app.log = lambda *args, **kwargs: None  # keep test output readable


def call(base, path, method="GET"):
    req = urllib.request.Request(base + path, method=method, data=b"" if method == "POST" else None)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


class ChaiStallTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), app.Handler)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        app.CHAOS.update(error_rate=0.0, latency_ms=0)

    def test_health_endpoints(self):
        for p in ("/healthz", "/readyz"):
            self.assertEqual(call(self.base, p)[0], 200)

    def test_order_ok_and_counted(self):
        status, body = call(self.base, "/order?item=samosa", "POST")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["price_inr"], 12)
        self.assertIn('orders_total{item="samosa"}', call(self.base, "/metrics")[1])

    def test_unknown_item_is_400(self):
        self.assertEqual(call(self.base, "/order?item=pizza", "POST")[0], 400)

    def test_unknown_path_uses_other_label(self):
        self.assertEqual(call(self.base, "/nope/123")[0], 404)
        self.assertIn('path="other"', call(self.base, "/metrics")[1])

    def test_metrics_format(self):
        call(self.base, "/api/info")
        text = call(self.base, "/metrics")[1]
        for needle in ("# TYPE http_requests_total counter", "http_request_duration_seconds_bucket", "app_info{version="):
            self.assertIn(needle, text)

    def test_chaos_makes_orders_fail_then_reset_heals(self):
        self.assertEqual(call(self.base, "/chaos?error_rate=1", "POST")[0], 200)
        self.assertEqual(call(self.base, "/order", "POST")[0], 500)
        self.assertEqual(call(self.base, "/chaos/reset", "POST")[0], 200)
        self.assertEqual(call(self.base, "/order", "POST")[0], 200)

    def test_chaos_rejects_garbage(self):
        self.assertEqual(call(self.base, "/chaos?error_rate=abc", "POST")[0], 400)

    def test_health_is_never_broken_by_chaos(self):
        call(self.base, "/chaos?error_rate=1", "POST")
        self.assertEqual(call(self.base, "/healthz")[0], 200)


if __name__ == "__main__":
    unittest.main()
