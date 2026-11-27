#!/usr/bin/env bash
# k8s-deploy.sh: release the Chai Stall to production (namespace stall-prod) with one of four strategies.
# Plain Kubernetes + Helm: nothing here you did not meet in Unit 3.
#
#   k8s-deploy.sh rolling   TAG          update the live release in place, Pod by Pod       (K06: RollingUpdate)
#   k8s-deploy.sh recreate  TAG          stop all old Pods, then start new ones: an outage  (K06: Recreate)
#   k8s-deploy.sh bluegreen TAG          deploy to the idle colour, test it, flip ALL traffic (K05 + K12)
#   k8s-deploy.sh canary    TAG [PCT]    deploy to the idle colour, send PCT% of traffic    (K12 weights)
#   k8s-deploy.sh analyse   [canary]     judge the canary on its OWN traffic (exit 1 = bad)
#   k8s-deploy.sh promote                canary looks good: 100% to the new version
#   k8s-deploy.sh rollback               canary looks bad / flip was a mistake: go back
#   k8s-deploy.sh retire                 scale the idle colour to 0 (it was kept for instant rollback)
#   k8s-deploy.sh status | state
#
# Two Helm releases, "chai-blue" and "chai-green", each with its own Deployment and Service. ONE HTTPRoute
# ("chai") sends traffic to them by WEIGHT. A strategy is only "which weights, and when".
set -euo pipefail

NS=${NS:-stall-prod}
CHART=${CHART:-chart/chai-stall}
IMAGE_REPO=${IMAGE_REPO:-localhost:30500/chai-stall}
ROUTE=${ROUTE:-chai}
HELM_WAIT=${HELM_WAIT---wait --timeout 3m}     # tests may set HELM_WAIT="" to skip waiting
HELM_TEST=${HELM_TEST:-1}
CHAOS_ERROR_RATE=${CHAOS_ERROR_RATE:-0}
CHAOS_LATENCY_MS=${CHAOS_LATENCY_MS:-0}
CHECK_REQUESTS=${CHECK_REQUESTS:-100}
MAX_ERROR_PERCENT=${MAX_ERROR_PERCENT:-5}

say() { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

command -v kubectl >/dev/null || die "kubectl not found"
command -v helm >/dev/null || die "helm not found"
kubectl get httproute "$ROUTE" -n "$NS" >/dev/null 2>&1 || die "HTTPRoute '$ROUTE' not found in namespace $NS. Install the platform first: cicd-observability/scripts/k8s-up.sh"

# ---- state ---------------------------------------------------------------------------------------
weights() {  # sets WB (blue) and WG (green) from the HTTPRoute
  local w; w=$(kubectl -n "$NS" get httproute "$ROUTE" -o jsonpath='{.spec.rules[0].backendRefs[*].weight}')
  WB=${w%% *}; WG=${w##* }
}
set_weights() {  # set_weights BLUE GREEN
  kubectl -n "$NS" patch httproute "$ROUTE" --type=json -p \
    "[{\"op\":\"replace\",\"path\":\"/spec/rules/0/backendRefs/0/weight\",\"value\":$1},{\"op\":\"replace\",\"path\":\"/spec/rules/0/backendRefs/1/weight\",\"value\":$2}]" >/dev/null
}
remember_previous() {  # remember_previous SLOT: the colour that was serving traffic before a flip (used by rollback)
  kubectl -n "$NS" annotate httproute "$ROUTE" "z2h/previous-slot=$1" --overwrite >/dev/null
}
previous_slot() { kubectl -n "$NS" get httproute "$ROUTE" -o jsonpath='{.metadata.annotations.z2h/previous-slot}' 2>/dev/null || true; }
released() { helm status "chai-$1" -n "$NS" >/dev/null 2>&1; }
other() { [ "$1" = blue ] && echo green || echo blue; }
active_slot() { weights; if [ "$WG" -gt "$WB" ]; then echo green; else echo blue; fi; }

# ---- helpers -------------------------------------------------------------------------------------
deploy_slot() {  # deploy_slot SLOT TAG [extra helm args...]
  local slot=$1 tag=$2 rel rc=0 revs; shift 2; rel="chai-$slot"
  # The slot's contents are about to change, so it can no longer serve as "the version to roll back to".
  if [ "$(previous_slot)" = "$slot" ]; then kubectl -n "$NS" annotate httproute "$ROUTE" z2h/previous-slot- >/dev/null; fi
  say "helm upgrade $rel → image tag $tag"
  # shellcheck disable=SC2086
  helm upgrade --install "$rel" "$CHART" -n "$NS" -f "$CHART/values-prod.yaml" \
    --set "slot=$slot" --set "image.repository=$IMAGE_REPO" --set "image.tag=$tag" \
    --set-string "chaos.errorRate=$CHAOS_ERROR_RATE" --set-string "chaos.latencyMs=$CHAOS_LATENCY_MS" \
    "$@" $HELM_WAIT || rc=$?
  if [ $rc -eq 0 ] && [ "$HELM_TEST" = 1 ]; then
    # The exit code is the smoke test's verdict; its output is shown best effort (never "helm test --logs": a log fetch
    # failure must not turn a passing test into a failed release).
    helm test "$rel" -n "$NS" >/dev/null || rc=$?
    kubectl -n "$NS" logs "$rel-smoke" 2>&1 | tail -3 || true
  fi
  if [ $rc -ne 0 ]; then
    # Evidence first: a rollback deletes the failed Pods and their events.
    printf '\033[1;31m✖ %s is not healthy. Evidence, collected BEFORE rolling back:\033[0m\n' "$rel" >&2
    "$(dirname "$0")/diagnose.sh" "$NS" "$rel" >&2 || true
    revs=$(helm history "$rel" -n "$NS" -o json 2>/dev/null | grep -o '"revision"' | wc -l)
    if [ "$revs" -gt 1 ]; then say "rolling $rel back to its previous revision"; helm rollback "$rel" -n "$NS" --wait --timeout 2m >/dev/null || true
    else say "first release of $rel: uninstalling it"; helm uninstall "$rel" -n "$NS" >/dev/null || true; fi
    return 1
  fi
  ok "$rel is healthy (helm --wait and helm test passed)"
}
service_url() { echo "http://chai-$1.$NS.svc.cluster.local"; }
check_slot() {  # check_slot SLOT  → exit 1 if its own error rate is too high
  if [ -n "${CHECK_CMD:-}" ]; then $CHECK_CMD "$1"; return; fi     # (a seam for tests; unset in real use)
  "$(dirname "$0")/canary-check.sh" "$(service_url "$1")" "$CHECK_REQUESTS" "$MAX_ERROR_PERCENT"
}
need_first_release() { [ -n "$(helm list -n "$NS" -q)" ] || die "nothing is released yet. Do a first release with: k8s-deploy.sh bluegreen TAG"; }

cmd=${1:-}; shift || true
case "$cmd" in
  rolling|recreate)
    tag=${1:?usage: k8s-deploy.sh $cmd TAG}
    slot=$(active_slot)
    if ! released "$slot"; then say "first release: creating chai-$slot"; set_weights 100 0; slot=blue; fi
    extra=(); [ "$cmd" = recreate ] && extra=(--set strategy.type=Recreate)
    say "$cmd: updating the live release chai-$slot in place"
    if ! deploy_slot "$slot" "$tag" "${extra[@]}"; then die "release failed (the evidence is printed above and the release was rolled back)"; fi
    if ! check_slot "$slot"; then
      say "the new version fails its own health check: rolling back"
      helm rollback "chai-$slot" -n "$NS" --wait >/dev/null || true
      die "rolled back chai-$slot"
    fi
    ok "production serves $tag from chai-$slot"
    ;;

  bluegreen)
    tag=${1:?usage: k8s-deploy.sh bluegreen TAG}
    if [ -z "$(helm list -n "$NS" -q)" ]; then
      say "first release: deploying to blue, all traffic to blue"
      deploy_slot blue "$tag"; set_weights 100 0
      ok "production serves $tag from chai-blue"; exit 0
    fi
    active=$(active_slot); idle=$(other "$active")
    say "blue/green: deploying $tag to the IDLE colour chai-$idle (live traffic untouched)"
    deploy_slot "$idle" "$tag"
    if ! check_slot "$idle"; then die "chai-$idle fails its health check: NOT flipping traffic (production is unchanged)"; fi
    say "flipping 100% of traffic to chai-$idle (chai-$active stays up for instant rollback)"
    remember_previous "$active"
    if [ "$idle" = blue ]; then set_weights 100 0; else set_weights 0 100; fi
    ok "production serves $tag from chai-$idle"
    ;;

  canary)
    tag=${1:?usage: k8s-deploy.sh canary TAG [PERCENT]}; pct=${2:-10}
    need_first_release
    active=$(active_slot); idle=$(other "$active")
    say "canary: deploying $tag to chai-$idle and sending $pct% of traffic to it"
    deploy_slot "$idle" "$tag"
    if [ "$idle" = blue ]; then set_weights "$pct" "$((100-pct))"; else set_weights "$((100-pct))" "$pct"; fi
    ok "$pct% of production traffic now goes to chai-$idle. Next: analyse, then promote or rollback"
    ;;

  analyse|analyze)
    weights
    if [ "$WB" -gt 0 ] && [ "$WG" -gt 0 ]; then
      if [ "$WB" -lt "$WG" ]; then canary=blue; else canary=green; fi
      say "judging the canary chai-$canary on its own traffic"
      check_slot "$canary"
    else
      echo "no canary is running"
    fi
    ;;

  promote)
    weights
    if [ "$WB" -gt 0 ] && [ "$WG" -gt 0 ]; then
      if [ "$WB" -lt "$WG" ]; then remember_previous green; set_weights 100 0; to=blue
      else remember_previous blue; set_weights 0 100; to=green; fi
      ok "promoted: 100% of traffic to chai-$to"
    else die "no canary to promote (weights are $WB/$WG)"; fi
    ;;

  rollback)
    weights
    if [ "$WB" -gt 0 ] && [ "$WG" -gt 0 ]; then
      if [ "$WB" -gt "$WG" ]; then set_weights 100 0; back=blue; else set_weights 0 100; back=green; fi
      ok "canary removed: 100% of traffic back to chai-$back"
    else
      active=$(active_slot); back=$(previous_slot)
      [ -n "$back" ] && [ "$back" != "$active" ] || die "there is no earlier version that served traffic: nothing to roll back to"
      released "$back" || die "chai-$back is no longer released: nothing to roll back to"
      remember_previous "$active"
      if [ "$back" = blue ]; then set_weights 100 0; else set_weights 0 100; fi
      ok "flipped back: 100% of traffic to chai-$back"
    fi
    ;;

  retire)
    active=$(active_slot); idle=$(other "$active")
    released "$idle" || die "chai-$idle is not released"
    kubectl -n "$NS" scale deploy "chai-$idle" --replicas=0 >/dev/null
    ok "chai-$idle scaled to 0 (the router still knows it; weight is 0)"
    ;;

  state) weights; echo "BLUE=$WB GREEN=$WG"; ;;

  status)
    weights; echo "traffic weights: blue=$WB green=$WG"
    helm list -n "$NS"
    kubectl -n "$NS" get deploy,pods -o wide 2>/dev/null | cut -c1-170
    ;;

  *) sed -n '2,19p' "$0"; exit 1 ;;
esac
