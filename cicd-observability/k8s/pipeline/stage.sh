#!/bin/sh
# stage.sh STAGE: the logic of every pipeline stage, in ONE place that belongs to the PLATFORM, not to your repo.
#
# Why it lives here: your repository's Jenkinsfile says WHICH stages exist and in which container they run (the shape of
# your pipeline). HOW a stage works is platform logic: it is delivered to every build Pod at /opt/z2h from the ConfigMap
# "z2h-pipeline" (created by k8s-up.sh). A fix to a stage therefore reaches everyone with:   git pull && ./cicd-observability/scripts/k8s-up.sh
# and nobody has to copy files into their repo.
#
# POSIX sh on purpose: it runs in the python, tools, kaniko and trivy containers, which all have /bin/sh but not all have bash.
#
# Environment (set by the Jenkinsfile): WORKSPACE TAG PUSH_REGISTRY PULL_REPO SCAN_MODE   (optional: HELM_TIMEOUT)
set -eu
PIPE=$(cd "$(dirname "$0")" && pwd)
WS=${WORKSPACE:-$(pwd)}
cd "$WS"
STAGING_NS=${STAGING_NS:-stall-staging}
STAGING_REL=${STAGING_REL:-chai-stall}
HELM_TIMEOUT=${HELM_TIMEOUT:-3m}

need() { for v in "$@"; do eval "[ -n \"\${$v:-}\" ]" || { echo "stage.sh: \$$v is not set (the Jenkinsfile must provide it)" >&2; exit 2; }; done; }

# ------------------------------------------------------------------------------------------------------------------
test_stage() {  # container: python
  cd app
  # Keep the exit code of the tests: a pipe into tee would swallow a failure (sh has no pipefail).
  rc=0; python -m unittest discover -s tests -v > "$WS/test-output.txt" 2>&1 || rc=$?
  cat "$WS/test-output.txt"
  return $rc
}

secret_scan() {  # container: tools (needs bash)
  bash "$PIPE/secret-scan.sh" app chart ci
}

chart_check() {  # container: tools
  need TAG PULL_REPO
  # 1) helm lint.
  helm lint chart/chai-stall --set image.tag="$TAG"
  # 2) render what will be DEPLOYED (--no-hooks: the helm-test Pod is a hook; one left behind by an earlier failed test
  #    would otherwise make the next dry-run try to UPDATE a Pod, which Kubernetes forbids) ...
  helm template chai-stall chart/chai-stall -f chart/chai-stall/values-staging.yaml --no-hooks \
    --set image.tag="$TAG" --set image.repository="$PULL_REPO" -n "$STAGING_NS" > rendered.yaml
  #    ... and let the REAL API server validate the whole release without creating anything: schema, CRDs, quotas, RBAC.
  kubectl apply --dry-run=server -n "$STAGING_NS" -f rendered.yaml
  # 3) The decisive question: will the cluster let the Pods this chart creates RUN? A Deployment is admitted even when
  #    its Pods would be refused (Pod Security only WARNS for workloads), and the refusal would appear minutes later as a
  #    ReplicaSet that never creates Pods. So ask the real question now: submit each Deployment's Pod template as a Pod,
  #    server-side dry run, against the namespace's ENFORCED policy. A hard yes or no, no warning text to parse.
  kubectl create --dry-run=client -o json -f rendered.yaml \
    | jq -c '(if .kind == "List" then .items[] else . end) | select(.kind == "Deployment")
             | {apiVersion: "v1", kind: "Pod", metadata: {generateName: "podcheck-", labels: .spec.template.metadata.labels}, spec: .spec.template.spec}' \
    > podspecs.jsonl
  [ -s podspecs.jsonl ] || { echo "✖ chart-check found no Deployment in the rendered chart"; return 1; }
  while IFS= read -r pod; do
    if ! echo "$pod" | kubectl create --dry-run=server -n "$STAGING_NS" -f - ; then
      echo "✖ the cluster would refuse to run this chart's Pods (see the message above: usually Pod Security). Fix the chart's securityContext."
      return 1
    fi
  done < podspecs.jsonl
  echo "✔ the chart renders, the API server accepts it, and the cluster will admit its Pods"
}

build() {  # container: kaniko (daemonless image build, no Docker socket)
  need TAG PUSH_REGISTRY
  mkdir -p out
  /kaniko/executor --context="dir://$WS/app" --dockerfile="$WS/app/Dockerfile" \
    --destination="$PUSH_REGISTRY/chai-stall:$TAG" --insecure \
    --build-arg "APP_VERSION=$TAG" --cache=false \
    --digest-file="$WS/out/digest.txt" --tar-path="$WS/out/image.tar"
  chmod -R a+rX "$WS/out"        # Kaniko is root; the scanner and the later stages are not
}

scan() {  # container: trivy
  need SCAN_MODE
  # enforce = a CRITICAL finding fails the build, AND so does a scanner that cannot run (it fails CLOSED: a gate that
  #           silently passes when it cannot check anything is worse than no gate).
  # report  = findings are shown but never block, and neither does a scanner that cannot start (for example no route
  #           to its vulnerability database).
  trivy --version | head -1
  ls -l "$WS/out/image.tar"
  exit_code=1; [ "$SCAN_MODE" = report ] && exit_code=0
  rc=0
  trivy image --input "$WS/out/image.tar" --cache-dir /tmp/trivy-cache --severity CRITICAL --exit-code "$exit_code" --no-progress || rc=$?
  if [ "$SCAN_MODE" = report ] && [ $rc -ne 0 ]; then
    echo "⚠ the scanner itself failed (exit $rc) and SCAN_MODE=report never blocks. Read the message above:"
    echo "  usually it cannot download its vulnerability database (no route to mirror.gcr.io / ghcr.io from this cluster)."
    return 0
  fi
  return $rc
}

record() {  # container: tools
  need TAG PULL_REPO BUILD_NUMBER
  digest=$(cat out/digest.txt)
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  printf '{"version":"%s","image":"%s:%s","digest":"%s","commit":"%s","build":"%s"}\n' \
    "$TAG" "$PULL_REPO" "$TAG" "$digest" "$commit" "$BUILD_NUMBER" | tee build-info.json
}

deploy_staging() {  # container: tools
  need TAG PULL_REPO
  # Not "helm --atomic": an automatic rollback DELETES the failed Pods and events, so nobody could see why it failed.
  # Instead: wait for health, run the smoke test, and on failure print the evidence FIRST, then roll back.
  rc=0
  helm upgrade --install "$STAGING_REL" chart/chai-stall -n "$STAGING_NS" -f chart/chai-stall/values-staging.yaml \
    --set image.repository="$PULL_REPO" --set image.tag="$TAG" --wait --timeout "$HELM_TIMEOUT" || rc=$?
  if [ $rc -eq 0 ]; then
    # The exit code of THIS command is the verdict of the smoke test. (Not "helm test --logs": that also fails when the
    # logs cannot be fetched, and made a passing test look like a failed deploy.) The Pod's output is printed best effort.
    helm test "$STAGING_REL" -n "$STAGING_NS" || rc=$?
    kubectl -n "$STAGING_NS" logs "$STAGING_REL-smoke" 2>&1 || true
  fi
  if [ $rc -ne 0 ]; then
    echo "✖ the staging release is not healthy. Evidence, collected BEFORE rolling back:"
    bash "$PIPE/diagnose.sh" "$STAGING_NS" "$STAGING_REL" || true
    revs=$(helm history "$STAGING_REL" -n "$STAGING_NS" -o json 2>/dev/null | grep -o '"revision"' | wc -l)
    if [ "$revs" -gt 1 ]; then echo "↩ rolling back to the previous revision"; helm rollback "$STAGING_REL" -n "$STAGING_NS" --wait --timeout 2m || true
    else echo "↩ this was the first release: uninstalling it"; helm uninstall "$STAGING_REL" -n "$STAGING_NS" || true
         kubectl -n "$STAGING_NS" delete pod "$STAGING_REL-smoke" --ignore-not-found || true; fi
    return 1
  fi
  echo "✔ staging runs $TAG and passed its smoke test"
}

# ------------------------------------------------------------------------------------------------------------------
case "${1:-}" in
  test)           test_stage ;;
  secret-scan)    secret_scan ;;
  chart-check)    chart_check ;;
  build)          build ;;
  scan)           scan ;;
  record)         record ;;
  deploy-staging) deploy_staging ;;
  *) echo "usage: stage.sh test|secret-scan|chart-check|build|scan|record|deploy-staging" >&2; exit 2 ;;
esac
