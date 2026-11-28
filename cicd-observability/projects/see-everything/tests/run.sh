#!/usr/bin/env bash
# run.sh: check and unit-test the alert rules. Needs Docker (for promtool) and python3 with PyYAML. No cluster.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# Work in a private scratch folder that any user can read: the promtool container may run as a different user than you
# (a locked-down umask or a root-owned folder gave "stat rules.generated.yml: permission denied").
T=$(mktemp -d); chmod 755 "$T"
trap 'rm -rf "$T"' EXIT
cp "$HERE/tests/rules_test.yml" "$T/"
# The cluster gets manifests/20-rules.yaml; promtool wants plain rule groups. Cut the groups out of the SAME file.
python3 - "$HERE/manifests/20-rules.yaml" "$T/rules.generated.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"groups": doc["spec"]["groups"]}, open(sys.argv[2], "w"), sort_keys=False)
PY
chmod 644 "$T"/*.yml
cd "$T"
if command -v promtool >/dev/null 2>&1; then P=(promtool)          # already installed: no Docker needed
else
  command -v docker >/dev/null 2>&1 || { echo "✖ need promtool or Docker. Install Docker, or: https://prometheus.io/download/" >&2; exit 1; }
  P=(docker run --rm --user "$(id -u):$(id -g)" -v "$T":/w:ro -w /w --entrypoint promtool prom/prometheus:v3.5.0)
fi
"${P[@]}" check rules rules.generated.yml
"${P[@]}" test rules rules_test.yml
