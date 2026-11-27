"""
☕ "Chai Stall": the small service used in every lab in this track.

Standard library only (no pip install), so it builds in seconds and runs anywhere.
It is deliberately a *good citizen* of a production platform:

  * GET  /                 a tiny HTML page (order a chai from your browser)
  * GET|POST /order?item=chai   place an order (counts toward the business metrics)
  * GET  /api/info         version, hostname, uptime, current chaos settings
  * GET  /healthz          liveness: the process is alive
  * GET  /readyz           readiness: ready for traffic
  * GET  /metrics          Prometheus metrics (requests, latency histogram, orders, in-flight)
  * POST /chaos?error_rate=0.3&latency_ms=400   inject failures on purpose (incident practice!)
  * POST /chaos/reset      back to healthy

Observability built in
  METRICS  Prometheus text format on /metrics (hand-written, no client library needed)
  LOGS     one JSON object per line on stdout (easy for Loki / any log shipper)
  TRACES   if OTEL_EXPORTER_OTLP_ENDPOINT is set, each request sends one span (OTLP/HTTP JSON)

Configuration (environment variables)
  PORT           default 8080
  APP_VERSION    default 1.0.0
  OTEL_EXPORTER_OTLP_ENDPOINT   e.g. http://jaeger:4318   (empty = tracing off)
  SERVICE_NAME   default chai-stall
  CHAOS_ERROR_RATE / CHAOS_LATENCY_MS   start already "broken" (simulates a bad release)
"""

import json
import os
import random
import secrets
import signal
import socket
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("PORT", "8080"))
APP_VERSION = os.environ.get("APP_VERSION", "1.0.0")
SERVICE_NAME = os.environ.get("SERVICE_NAME", "chai-stall")
OTLP = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT", "").rstrip("/")
HOSTNAME = socket.gethostname()
STARTED_AT = time.time()

MENU = {"chai": 10, "coffee": 15, "samosa": 12, "biscuit": 5}
BUCKETS = (0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0)

# ----------------------------------------------------------------- state
LOCK = threading.Lock()
REQUESTS = {}        # (method, path, status) -> count
LATENCY = {}         # path -> {"buckets": [..], "sum": float, "count": int}
ORDERS = {}          # item -> count
IN_FLIGHT = 0
CHAOS = {"error_rate": float(os.environ.get("CHAOS_ERROR_RATE", "0")), "latency_ms": int(os.environ.get("CHAOS_LATENCY_MS", "0"))}


def log(level, msg, **fields):
    """One JSON object per line: the format log shippers love."""
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + "Z", "level": level,
           "service": SERVICE_NAME, "version": APP_VERSION, "msg": msg}
    rec.update(fields)
    print(json.dumps(rec), flush=True)


def route_label(path):
    """Keep metric label values few: only known routes, never raw user input."""
    known = ("/", "/order", "/api/info", "/healthz", "/readyz", "/metrics", "/chaos", "/chaos/reset")
    return path if path in known else "other"


def record(method, path, status, seconds):
    with LOCK:
        REQUESTS[(method, path, status)] = REQUESTS.get((method, path, status), 0) + 1
        h = LATENCY.setdefault(path, {"buckets": [0] * len(BUCKETS), "sum": 0.0, "count": 0})
        for i, upper in enumerate(BUCKETS):
            if seconds <= upper:
                h["buckets"][i] += 1
        h["sum"] += seconds
        h["count"] += 1


def render_metrics():
    out = []
    add = out.append
    add("# HELP app_info Static information about this build (value is always 1).")
    add("# TYPE app_info gauge")
    add(f'app_info{{version="{APP_VERSION}",service="{SERVICE_NAME}"}} 1')
    add("# HELP app_start_time_seconds Unix time the process started.")
    add("# TYPE app_start_time_seconds gauge")
    add(f"app_start_time_seconds {STARTED_AT:.0f}")
    with LOCK:
        add("# HELP http_requests_total Requests handled, by method, route and status code.")
        add("# TYPE http_requests_total counter")
        for (m, p, s), n in sorted(REQUESTS.items()):
            add(f'http_requests_total{{method="{m}",path="{p}",status="{s}"}} {n}')
        add("# HELP http_request_duration_seconds Request latency in seconds.")
        add("# TYPE http_request_duration_seconds histogram")
        for p, h in sorted(LATENCY.items()):
            for upper, n in zip(BUCKETS, h["buckets"]):
                add(f'http_request_duration_seconds_bucket{{path="{p}",le="{upper}"}} {n}')
            add(f'http_request_duration_seconds_bucket{{path="{p}",le="+Inf"}} {h["count"]}')
            add(f'http_request_duration_seconds_sum{{path="{p}"}} {h["sum"]:.6f}')
            add(f'http_request_duration_seconds_count{{path="{p}"}} {h["count"]}')
        add("# HELP orders_total Orders placed, by menu item (a business metric).")
        add("# TYPE orders_total counter")
        for item, n in sorted(ORDERS.items()):
            add(f'orders_total{{item="{item}"}} {n}')
        add("# HELP http_requests_in_flight Requests being handled right now.")
        add("# TYPE http_requests_in_flight gauge")
        add(f"http_requests_in_flight {IN_FLIGHT}")
        add("# HELP chaos_error_rate Injected failure rate (0 to 1).")
        add("# TYPE chaos_error_rate gauge")
        add(f"chaos_error_rate {CHAOS['error_rate']}")
        add("# HELP chaos_latency_ms Injected extra latency in milliseconds.")
        add("# TYPE chaos_latency_ms gauge")
        add(f"chaos_latency_ms {CHAOS['latency_ms']}")
    return "\n".join(out) + "\n"


def send_span(name, trace_id, span_id, start, end, status, attrs):
    """Fire-and-forget OTLP/HTTP JSON span. Tracing must never break the app."""
    if not OTLP:
        return
    def attr(k, v):
        return {"key": k, "value": {"stringValue": str(v)}}
    body = {"resourceSpans": [{
        "resource": {"attributes": [attr("service.name", SERVICE_NAME), attr("service.version", APP_VERSION),
                                    attr("host.name", HOSTNAME)]},
        "scopeSpans": [{"scope": {"name": "chai-stall"}, "spans": [{
            "traceId": trace_id, "spanId": span_id, "name": name, "kind": 2,
            "startTimeUnixNano": str(int(start * 1e9)), "endTimeUnixNano": str(int(end * 1e9)),
            "attributes": [attr(k, v) for k, v in attrs.items()],
            "status": {"code": 2 if status >= 500 else 1}}]}]}]}
    def post():
        try:
            req = urllib.request.Request(OTLP + "/v1/traces", json.dumps(body).encode(),
                                         {"Content-Type": "application/json"})
            urllib.request.urlopen(req, timeout=2).read()
        except Exception:
            pass
    threading.Thread(target=post, daemon=True).start()


PAGE = b"""<!doctype html><meta charset=utf-8><title>Chai Stall</title>
<body style="font-family:system-ui;max-width:32rem;margin:3rem auto;padding:0 1rem">
<h1>\xe2\x98\x95 Chai Stall</h1><p id=v></p>
<button onclick="o('chai')">Order chai</button> <button onclick="o('samosa')">Order samosa</button>
<pre id=out>Click a button.</pre>
<script>
fetch('/api/info').then(r=>r.json()).then(i=>v.textContent='version '+i.version+' \xc2\xb7 served by '+i.hostname);
function o(i){fetch('/order?item='+i,{method:'POST'}).then(r=>r.text().then(t=>out.textContent=r.status+' '+t))}
</script>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "chai-stall"

    def log_message(self, *args):  # we log ourselves, as JSON
        pass

    def reply(self, status, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else (json.dumps(body) + "\n" if ctype == "application/json" else body).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return status

    def handle_any(self):
        global IN_FLIGHT
        url = urlparse(self.path)
        path, q = url.path, {k: v[0] for k, v in parse_qs(url.query).items()}
        label = route_label(path)
        trace_id = (self.headers.get("X-Trace-Id") or secrets.token_hex(16))[:32]
        span_id = secrets.token_hex(8)
        start = time.time()
        with LOCK:
            IN_FLIGHT += 1
        try:
            status = self.dispatch(self.command, path, q)
        except Exception as exc:  # never crash the server on one bad request
            log("error", "unhandled error", error=str(exc), path=label, trace_id=trace_id)
            status = self.reply(500, {"error": "internal error"})
        finally:
            with LOCK:
                IN_FLIGHT -= 1
        end = time.time()
        if label != "/metrics":
            record(self.command, label, status, end - start)
            level = "error" if status >= 500 else "info"
            log(level, "request", method=self.command, path=label, status=status,
                duration_ms=round((end - start) * 1000, 1), trace_id=trace_id)
            send_span(f"{self.command} {label}", trace_id, span_id, start, end, status,
                      {"http.method": self.command, "http.route": label, "http.status_code": status})

    def chaos(self):
        """Apply injected latency and failures. Returns an error status or None."""
        if CHAOS["latency_ms"]:
            time.sleep(CHAOS["latency_ms"] / 1000.0)
        if random.random() < CHAOS["error_rate"]:
            return self.reply(500, {"error": "chaos: injected failure"})
        return None

    def dispatch(self, method, path, q):
        if path == "/metrics":
            return self.reply(200, render_metrics(), "text/plain; version=0.0.4")
        if path == "/healthz":
            return self.reply(200, {"status": "alive"})
        if path == "/readyz":
            return self.reply(200, {"status": "ready"})
        if path == "/chaos" and method == "POST":
            try:
                rate = min(max(float(q.get("error_rate", CHAOS["error_rate"])), 0.0), 1.0)
                lat = min(max(int(q.get("latency_ms", CHAOS["latency_ms"])), 0), 5000)
            except ValueError:
                return self.reply(400, {"error": "error_rate must be 0..1 and latency_ms an integer"})
            CHAOS.update(error_rate=rate, latency_ms=lat)
            log("warn", "chaos configured", **CHAOS)
            return self.reply(200, CHAOS)
        if path == "/chaos/reset" and method == "POST":
            CHAOS.update(error_rate=0.0, latency_ms=0)
            log("info", "chaos reset")
            return self.reply(200, CHAOS)
        if path == "/":
            return self.reply(200, PAGE, "text/html; charset=utf-8")
        if path == "/api/info":
            return self.reply(200, {"service": SERVICE_NAME, "version": APP_VERSION, "hostname": HOSTNAME,
                                    "uptime_seconds": int(time.time() - STARTED_AT), "chaos": CHAOS})
        if path == "/order" and method in ("GET", "POST"):
            failed = self.chaos()
            if failed:
                return failed
            item = q.get("item", "chai")
            if item not in MENU:
                return self.reply(400, {"error": f"unknown item, choose one of {sorted(MENU)}"})
            with LOCK:
                ORDERS[item] = ORDERS.get(item, 0) + 1
            return self.reply(200, {"ok": True, "item": item, "price_inr": MENU[item], "served_by": HOSTNAME})
        return self.reply(404, {"error": "not found"})

    do_GET = do_POST = handle_any


class Server(ThreadingHTTPServer):
    daemon_threads = False  # on shutdown, wait for in-flight requests to finish (graceful, for rolling updates)


def main():
    log("info", "starting", port=PORT, tracing=bool(OTLP))
    server = Server(("0.0.0.0", PORT), Handler)
    # PID 1 in a container ignores SIGTERM unless we handle it: without this, `docker stop` waits 10s then kills.
    signal.signal(signal.SIGTERM, lambda *_: threading.Thread(target=server.shutdown).start())
    server.serve_forever()
    server.server_close()
    log("info", "stopped gracefully")


if __name__ == "__main__":
    main()
