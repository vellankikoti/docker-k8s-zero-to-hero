#!/usr/bin/env python3
"""add-panel.py TITLE PROMQL [UNIT]: append a time-series panel to the dashboard file (dashboards as code).

  ./scripts/add-panel.py "Orders per minute" 'sum(increase(orders_total[1m]))'
  ./scripts/add-panel.py "Slow-order share" '1 - sli:order_latency_good:ratio_rate5m' percentunit

Grafana notices the file change by itself (about 20 seconds). Standard library only.
To undo, restore the file from Git (git diff shows exactly what this script added).
"""
import json
import sys
from pathlib import Path

if len(sys.argv) < 3:
    sys.exit(__doc__)
title, expr = sys.argv[1], sys.argv[2]
unit = sys.argv[3] if len(sys.argv) > 3 else "short"
path = Path(__file__).resolve().parent.parent / "grafana" / "dashboards" / "chai-stall.json"
dash = json.loads(path.read_text())
panels = dash["panels"]
ds = {"type": "prometheus", "uid": "prometheus"}
bottom = max(p["gridPos"]["y"] + p["gridPos"]["h"] for p in panels)
panels.append({
    "id": max(p["id"] for p in panels) + 1, "type": "timeseries", "title": title, "datasource": ds,
    "gridPos": {"x": 0, "y": bottom, "w": 24, "h": 8},
    "targets": [{"expr": expr, "legendFormat": "", "refId": "A", "datasource": ds}],
    "fieldConfig": {"defaults": {"unit": unit, "custom": {"lineWidth": 2, "fillOpacity": 10}}, "overrides": []},
    "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
})
path.write_text(json.dumps(dash, indent=1) + "\n")
print(f"added panel {title!r} at the bottom of {path.name}; Grafana reloads it in about 20 seconds")
