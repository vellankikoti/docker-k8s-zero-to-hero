#!/usr/bin/env bash
# forward.sh start|stop|status: open (or close) every door into the cluster with background port-forwards.
#
#   Jenkins    http://localhost:8081   admin / z2h-jenkins
#   Git server http://localhost:3001   z2h / z2h-gitea-pass
#   Inbox      http://localhost:8025   (every email the platform sends lands here)
#   Staging    http://localhost:8082   the staging release of the Chai Stall
#   Production http://localhost:8090   through the Gateway (needs Envoy Gateway)
set -uo pipefail
. "$(dirname "$0")/k8s-lib.sh"
PIDFILE=${TMPDIR:-/tmp}/z2h-unit4-forward.pids

LOGDIR=${TMPDIR:-/tmp}
logfile() { echo "$LOGDIR/z2h-unit4-forward-$1.log"; }

# Why a forward might have died, in plain words (the raw kubectl message is shown too).
hint() {
  case "$1" in
    jenkins)    echo "is the Jenkins Pod Ready?  kubectl -n cicd get pods   (jenkins-0 must be 2/2 Running). Is local port 8081 used by something else?" ;;
    gitea)      echo "is the Git server Ready?  kubectl -n cicd get pods -l app=gitea. Is local port 3001 used by something else?" ;;
    mailpit)    echo "kubectl -n mail get pods. Is local port 8025 used by something else?" ;;
    staging)    echo "kubectl -n stall-staging get pods. Is local port 8082 used by something else?" ;;
    production) echo "is the Gateway's Envoy proxy Ready?  kubectl -n envoy-gateway-system get pods. Is local port 8090 used by something else?" ;;
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
  nohup kubectl -n "$ns" port-forward "$target" "$ports" --address 127.0.0.1 >"$(logfile "$name")" 2>&1 &
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
    start_one jenkins    cicd          svc/jenkins        8081:8080
    start_one gitea      cicd          svc/gitea          3001:3000
    start_one mailpit    mail          svc/mailpit        8025:8025
    start_one staging    stall-staging svc/chai-stall     8082:80
    envoy=$(kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=chai -o name 2>/dev/null | head -1)
    if [ -n "$envoy" ]; then start_one production envoy-gateway-system "$envoy" 8090:80; else warn "production: the Gateway has no proxy Service yet (install Envoy Gateway, then run this again)"; fi
    sleep 4; "$0" status ;;
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
