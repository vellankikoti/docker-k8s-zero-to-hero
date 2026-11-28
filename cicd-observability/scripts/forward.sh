#!/usr/bin/env bash
# forward.sh start [SET] [--lab|--local] | stop | status: open (or close) the doors into the cluster with background port-forwards.
#   SET = ship-it (default) | observability | all
#
# Where the doors listen:
#   on your laptop       127.0.0.1  (only you can reach them)
#   in a browser lab     0.0.0.0    (Killercoda, iximuz and similar). Their "open a port / Traffic" feature reaches the VM
#                                    from OUTSIDE it and cannot see a loopback-only listener. Detected automatically
#                                    (user "laborant", OR a machine named "controlplane" as in Killercoda's Kubernetes
#                                    playgrounds, where you are root); force it with --lab, or local-only with --local.
#                                    Or set FORWARD_ADDRESS=<ip> yourself.
#
#   Jenkins    http://localhost:8081   admin / z2h-jenkins
#   Git server http://localhost:3001   z2h / z2h-gitea-pass
#   Inbox      http://localhost:8025   (every email the platform sends lands here)
#   Staging    http://localhost:8082   the staging release of the Chai Stall
#   Production http://localhost:8090   through the Gateway (needs Envoy Gateway)
#   observability set:
#   Grafana    http://localhost:3000   admin / z2h-grafana        Prometheus   http://localhost:9090
#   Alertmanager http://localhost:9093                            Jaeger       http://localhost:16686
#   Inbox      http://localhost:8025                              The app      http://localhost:8083
set -uo pipefail
. "$(dirname "$0")/k8s-lib.sh"
PIDFILE=${TMPDIR:-/tmp}/z2h-forward.pids

# --- where to listen -------------------------------------------------------------------------------------------------
SET=ship-it; MODE=auto
for a in "${@:2}"; do
  case "$a" in
    --lab) MODE=lab ;;
    --local) MODE=local ;;
    ship-it|observability|all) SET=$a ;;
    *) die "unknown option: $a   (SET: ship-it | observability | all;  mode: --lab | --local)" ;;
  esac
done
LAB=0
case "$MODE" in
  lab) LAB=1 ;;
  local) LAB=0 ;;
  *) # Killercoda / iximuz run you as "laborant", and Killercoda's Kubernetes playgrounds put you on a host called "controlplane" (as root).
     # A laptop is neither, so its doors stay on 127.0.0.1: only you can reach them.
     # Other browser-lab signals are checked too (env markers such as KILLERCODA*, hostnames that say "killercoda"/"iximuz").
     # Unsure? We stay on 127.0.0.1 (safe for a laptop or a cloud VM) and print the one-line --lab fix below.
     HN=$(hostname 2>/dev/null || true)
     case "${USER:-$(id -un 2>/dev/null)}|$HN|$(env 2>/dev/null | grep -ic '^KILLERCODA\|^IXIMUZ' || true)" in
       laborant\|*|*\|controlplane\|*|*\|*killercoda*\|*|*\|*iximuz*\|*) LAB=1 ;;
       *\|[1-9]*) LAB=1 ;;
     esac ;;
esac
if [ -n "${FORWARD_ADDRESS:-}" ]; then ADDR=$FORWARD_ADDRESS
elif [ "$LAB" = 1 ]; then ADDR=0.0.0.0
else ADDR=127.0.0.1; fi

LOGDIR=${TMPDIR:-/tmp}
logfile() { echo "$LOGDIR/z2h-forward-$1.log"; }

# Why a forward might have died, in plain words (the raw kubectl message is shown too).
hint() {
  case "$1" in
    jenkins)    echo "is the Jenkins Pod Ready?  kubectl -n cicd get pods   (jenkins-0 must be 2/2 Running). Is local port 8081 used by something else?" ;;
    gitea)      echo "is the Git server Ready?  kubectl -n cicd get pods -l app=gitea. Is local port 3001 used by something else?" ;;
    mailpit)    echo "kubectl -n mail get pods. Is local port 8025 used by something else?" ;;
    staging)    echo "kubectl -n stall-staging get pods. Is local port 8082 used by something else?" ;;
    production) echo "is the Gateway's Envoy proxy Ready?  kubectl -n envoy-gateway-system get pods. Is local port 8090 used by something else?" ;;
    grafana)    echo "kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana. Is local port 3000 used by something else?" ;;
    prometheus) echo "kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus. Is local port 9090 used by something else?" ;;
    alertmanager) echo "kubectl -n monitoring get pods -l app.kubernetes.io/name=alertmanager. Is local port 9093 used by something else?" ;;
    jaeger)     echo "kubectl -n observability get pods -l app=jaeger. Is local port 16686 used by something else?" ;;
    app)        echo "kubectl -n stall-demo get pods. Is local port 8083 used by something else?" ;;
  esac
}

start_one() {  # start_one NAME NAMESPACE TARGET LOCAL:REMOTE
  local name=$1 ns=$2 target=$3 ports=$4
  if ! kubectl -n "$ns" get "$target" >/dev/null 2>&1; then
    if [ "$name" = staging ]; then warn "staging: nothing deployed there yet. It appears after the first pipeline run; run 'forward.sh start' again then."
    else warn "$name: $target not found in $ns (skipped). Has k8s-up.sh finished?"; fi
    return
  fi
  : > "$(logfile "$name")"
  nohup kubectl -n "$ns" port-forward "$target" "$ports" --address "$ADDR" >"$(logfile "$name")" 2>&1 &
  echo "$! $name ${ports%%:*}" >> "$PIDFILE"
}

stop_all() {
  [ -f "$PIDFILE" ] || return 0
  while read -r pid name _; do kill "$pid" 2>/dev/null || true; done < "$PIDFILE"
  rm -f "$PIDFILE"
}

case "${1:-status}" in
  start)
    need_cluster; stop_all
    if [ "$SET" = ship-it ] || [ "$SET" = all ]; then
      start_one jenkins    cicd          svc/jenkins        8081:8080
      start_one gitea      cicd          svc/gitea          3001:3000
      start_one mailpit    mail          svc/mailpit        8025:8025
      start_one staging    stall-staging svc/chai-stall     8082:80
      envoy=$(kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=chai -o name 2>/dev/null | head -1)
      if [ -n "$envoy" ]; then start_one production envoy-gateway-system "$envoy" 8090:80; else warn "production: the Gateway has no proxy Service yet (install Envoy Gateway, then run this again)"; fi
    fi
    if [ "$SET" = observability ] || [ "$SET" = all ]; then
      [ "$SET" = all ] || start_one mailpit mail svc/mailpit 8025:8025
      start_one grafana      monitoring    svc/kube-prometheus-stack-grafana        3000:80
      start_one prometheus   monitoring    svc/kube-prometheus-stack-prometheus     9090:9090
      start_one alertmanager monitoring    svc/kube-prometheus-stack-alertmanager   9093:9093
      start_one jaeger       observability svc/jaeger                               16686:16686
      start_one app          stall-demo    svc/chai-stall                           8083:80
    fi
    sleep 4; "$0" status
    if [ "$ADDR" = 127.0.0.1 ]; then
      echo
      echo "  Doors are open on this machine only (127.0.0.1). In a browser lab (Killercoda, iximuz) the lab's port link shows"
      echo "  '502 Bad Gateway' for them: run   $0 stop   then   $0 start $SET --lab"
    fi
    if [ "$ADDR" = 0.0.0.0 ]; then
      echo
      echo "  Browser lab detected: the doors listen on every interface so your lab can expose them."
      echo "  To open one in your browser, use your lab's port feature and give it the port number:"
      echo "    Killercoda: the menu's  Traffic / Ports  →  enter the port number: 8081 Jenkins, 3001 Git server, 8025 inbox, 8082 staging, 8090 production,"
      echo "                3000 Grafana, 9090 Prometheus, 9093 Alertmanager, 16686 Jaeger, 8083 the demo app"
      echo "    iximuz Labs: expose the same port from the lab's ports / web-access panel"
      echo "  (Inside the lab terminal, curl and git keep using http://localhost:PORT as usual.)"
    fi ;;
  stop) stop_all; ok "port-forwards stopped" ;;
  status)
    [ -f "$PIDFILE" ] || { echo "no port-forwards running. Start them: $0 start"; exit 0; }
    while read -r pid name port; do
      if kill -0 "$pid" 2>/dev/null; then printf '  \033[1;32m●\033[0m %-11s http://localhost:%s\n' "$name" "$port"
      else
        printf '  \033[1;31m○\033[0m %-11s stopped\n' "$name"
        [ -s "$(logfile "$name")" ] && sed 's/^/      kubectl said: /' "$(logfile "$name")" | tail -3
        printf '      hint: %s\n' "$(hint "$name")"
      fi
    done < "$PIDFILE" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
