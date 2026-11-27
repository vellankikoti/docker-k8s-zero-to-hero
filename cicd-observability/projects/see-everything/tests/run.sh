#!/usr/bin/env bash
# run.sh: check and unit-test the alert rules. Needs Docker (for promtool) and python3 with PyYAML. No cluster.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$HERE/tests"
trap 'rm -f "$T/rules.generated.yml"' EXIT
# The cluster gets manifests/20-rules.yaml; promtool wants plain rule groups. Cut the groups out of the SAME file.
python3 - "$HERE/manifests/20-rules.yaml" "$T/rules.generated.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"groups": doc["spec"]["groups"]}, open(sys.argv[2], "w"), sort_keys=False)
PY
P=(docker run --rm -v "$T":/w -w /w --entrypoint promtool prom/prometheus:v3.5.0)
"${P[@]}" check rules rules.generated.yml
"${P[@]}" test rules rules_test.yml
