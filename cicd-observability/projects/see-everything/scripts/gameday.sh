#!/usr/bin/env bash
# gameday.sh: break the Chai Stall on purpose, watch your signals catch it, then put it back.
#
#   gameday.sh list                  the incidents and which Kubernetes scenario each one echoes
#   gameday.sh start INCIDENT        cause it (and tell you where to look)
#   gameday.sh watch ALERT           wait until that alert is FIRING and its email is in the inbox (up to 5 minutes)
#   gameday.sh recover               put everything back exactly as values-app.yaml says, and wait until it is healthy
#   gameday.sh drill INCIDENT ALERT  start + watch + recover in one go (what the automated test does)
#
# Every incident is a Helm release change, so "recover" is one honest helm upgrade: nothing is hand-edited and left behind.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

list() {
  cat <<'EOF'
  INCIDENT    what happens                                         first alert         the Kubernetes scenario it echoes
  errors      a bad release: 30% of orders fail                    OrderSLOFastBurn    S5.4  the bad rollout
  slow        a slow release: every order takes 800 ms             ChaiStallHighLatency S5.2 slow start / probes
  crashloop   a typo in config: the app crashes at start           ChaiStallPodRestarting S1.3 the crash loop
  bad-image   a typo in the image tag: ImagePullBackOff            ChaiStallReplicasUnavailable S1.2 the image typo
  outage      replicas set to 0: nobody can order                  ChaiStallDown       S2.x  the Deployment that was scaled away
EOF
}

start() {
  case "${1:-}" in
    errors)    release_app --set-string chaos.errorRate=0.3; why="30% of /order calls now fail with a 500" ;;
    slow)      release_app --set-string chaos.latencyMs=800; why="every order now takes 800 ms" ;;
    crashloop) release_app --set-string chaos.errorRate=thirty-percent; why="the new Pods crash at start (the config value is not a number)" ;;
    bad-image) release_app --set image.tag=1.0.0-typo; why="the new Pod cannot pull its image; the OLD Pods keep serving (maxUnavailable: 0)" ;;
    outage)    release_app --set replicaCount=0; why="there are no Pods at all" ;;
    *) list; die "unknown incident: ${1:-}"; ;;
  esac
  ok "Incident started: $why."
  cat <<MSG
   Where to look (open the doors first:  ./cicd-observability/scripts/forward.sh start observability):
     Grafana     http://localhost:3000  → "Chai Stall: Service Overview" (set refresh to 5s, range to 15 minutes)
     Kubernetes  kubectl -n $DEMO_NS get pods,events --sort-by=.lastTimestamp | tail -15
     Logs        Grafana → Explore → Loki:   {service="chai-stall"} | json | level="error"
     Inbox       http://localhost:8025   (the email arrives after ~1 to 2 minutes)
   Then fix it:   $0 recover
MSG
}

watch_alert() {
  local name=${1:?usage: gameday.sh watch ALERT} i
  say "Waiting for $name to fire (Prometheus evaluates every 30 s; each alert has a short 'for' time)"
  for i in $(seq 1 60); do prom_alert "$name" firing && break; sleep 5; done
  prom_alert "$name" firing || { printf '\033[1;31m✖ %s did not fire within 5 minutes.\033[0m Look: Prometheus → Alerts, and the rule: kubectl -n observability get prometheusrule chai-stall\n' "$name"; return 1; }
  ok "$name is FIRING in Prometheus"
  say "Waiting for its email (Alertmanager groups for ~10 s first)"
  for i in $(seq 1 36); do mail_has "$name" && break; sleep 5; done
  mail_has "$name" || { printf '\033[1;31m✖ no email for %s in the inbox.\033[0m Look: Alertmanager → Status, and: kubectl -n monitoring logs alertmanager-kube-prometheus-stack-alertmanager-0 | tail\n' "$name"; return 1; }
  ok "the email for $name is in the inbox"
}

recover() {
  say "Putting the release back exactly as values-app.yaml says"
  release_app --wait --timeout 5m || die "the release did not become healthy: kubectl -n $DEMO_NS get pods"
  ok "Healthy again. Alerts clear within a minute or two, and a [RESOLVED] email follows."
}

case "${1:-list}" in
  list) list ;;
  start) need_cluster; start "${2:-}" ;;
  watch) need_cluster; watch_alert "${2:-}" ;;
  recover) need_cluster; recover ;;
  drill) need_cluster; start "${2:-}" >/dev/null || exit 1; rc=0; watch_alert "${3:-}" || rc=1; recover; exit $rc ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
