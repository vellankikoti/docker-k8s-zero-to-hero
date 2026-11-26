"""A tiny customer simulator: orders chai and friends at a steady rate. Standard library only."""
import os
import random
import threading
import time
import urllib.request

TARGETS = [t for t in os.environ.get("TARGETS", "http://localhost:8080").split(",") if t]
RATE = float(os.environ.get("RATE_PER_SECOND", "5"))
ITEMS = ["chai"] * 6 + ["coffee"] * 2 + ["samosa"] * 2 + ["biscuit"]


def one():
    url = f"{random.choice(TARGETS)}/order?item={random.choice(ITEMS)}"
    try:
        urllib.request.urlopen(urllib.request.Request(url, method="POST", data=b""), timeout=5).read()
    except Exception:
        pass  # 500s are expected during incidents; the app's own metrics record them


print(f"loadgen: {RATE}/s against {TARGETS}", flush=True)
while True:
    threading.Thread(target=one, daemon=True).start()
    time.sleep(random.expovariate(RATE))
