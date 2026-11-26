#!/usr/bin/env bash
# selftest.sh: a maintainer's check that everything in Unit 4 is still consistent. No stack needs to be running.
#   ./cicd-observability/scripts/selftest.sh
# Checks: app tests, shell syntax, YAML/JSON syntax, compose files, Prometheus rules (check + unit tests),
# the GitHub Actions workflow (actionlint), and every Markdown link in the repository.
cd "$(dirname "$0")/../.." || exit 1
fails=0
ok()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }
bad() { printf '  \033[1;31m✖\033[0m %s\n' "$*"; fails=$((fails+1)); }
run() { local label=$1; shift; if "$@" >/tmp/selftest.out 2>&1; then ok "$label"; else bad "$label"; sed 's/^/      /' /tmp/selftest.out | tail -15; fi; }

U=cicd-observability
echo "App"
run "unit tests" bash -c "cd $U/app && python3 -m unittest discover -s tests"
run "app compiles" python3 -m py_compile $U/app/app.py $U/compose-edition/project-2-see-everything/loadgen/loadgen.py $U/compose-edition/project-2-see-everything/scripts/add-panel.py
echo "Shell scripts"
for f in $U/scripts/*.sh $U/compose-edition/*/scripts/*.sh $U/compose-edition/project-1-ship-it/deploy/deploy.sh $U/projects/*/scripts/*.sh $U/projects/project-1-ship-it/app-repo/deploy/*.sh $U/projects/project-1-ship-it/app-repo/ci/*.sh; do [ -e "$f" ] && run "bash -n $f" bash -n "$f"; done
echo "YAML / JSON"
run "yaml files parse" python3 - <<'PY'
import glob, yaml
files = [f for f in glob.glob("cicd-observability/**/*.y*ml", recursive=True) if "/templates/" not in f] + glob.glob(".github/workflows/*.yml")
for f in files:
    list(yaml.safe_load_all(open(f)))
print(len(files), "files")
PY
run "dashboard + pipeline-config json parse" python3 -c "import json;[json.load(open(f)) for f in ('$U/compose-edition/project-2-see-everything/grafana/dashboards/chai-stall.json','$U/compose-edition/project-1-ship-it/pipeline-config.json','$U/projects/project-1-ship-it/app-repo/pipeline-config.json')]"
echo "Kubernetes edition"
if command -v helm >/dev/null; then
  run "helm lint the chai-stall chart" helm lint $U/k8s/chart/chai-stall --set image.tag=selftest
  run "helm template renders every optional resource" bash -c "helm template t $U/k8s/chart/chai-stall --set image.tag=selftest -f $U/k8s/chart/chai-stall/values-prod.yaml --set serviceMonitor.enabled=true --set autoscaling.enabled=true | grep -c '^kind:' | grep -qE '^[7-9]|^[1-9][0-9]'"
else echo "  • helm not installed: skipped the chart checks"; fi
run "Job DSL files exist" bash -c "ls $U/projects/project-1-ship-it/app-repo/jenkins/jobs/*.groovy >/dev/null"
if command -v kubectl >/dev/null && kubectl get --raw /readyz >/dev/null 2>&1; then
  run "platform manifests are accepted by your cluster's API server (dry run)" bash -c "for f in $U/k8s/platform/00-namespaces.yaml $U/k8s/platform/rbac.yaml; do kubectl apply --dry-run=server -f \$f >/dev/null || exit 1; done; for f in registry gitea; do kubectl apply --dry-run=server -n cicd -f $U/k8s/platform/\$f.yaml >/dev/null || exit 1; done"
else echo "  • no cluster reachable: skipped the API-server checks (run k8s-selftest.sh on a real cluster for the full test)"; fi
echo "Docker"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  run "compose: project 1" docker compose -f $U/compose-edition/project-1-ship-it/docker-compose.yml config -q
  run "compose: project 2" docker compose -f $U/compose-edition/project-2-see-everything/docker-compose.yml config -q
  P2=$PWD/$U/compose-edition/project-2-see-everything
  PT="docker run --rm -v $P2:/w -w /w --entrypoint promtool prom/prometheus:v3.5.0"
  run "promtool check rules" $PT check rules prometheus/rules/recording.yml prometheus/rules/alerts.yml
  run "promtool test rules" $PT test rules tests/rules_test.yml
  run "actionlint on the workflow" docker run --rm -v "$PWD":/repo -w /repo rhysd/actionlint:1.7.7 -color=false .github/workflows/unit4-ci.yml
else
  echo "  • docker not available: skipped compose, promtool and actionlint"
fi
echo "Docs"
run "markdown links" python3 scripts/link-check.py
echo; [ $fails -eq 0 ] && echo "selftest: all good" || echo "selftest: $fails problem(s)"
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
