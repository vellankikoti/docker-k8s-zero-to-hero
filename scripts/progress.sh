# progress.sh: so a long wait never looks like a hang. Source it:  . "$(dirname "$0")/progress.sh"
#
#   helm upgrade --install ... --wait >/dev/null 2>"$LOG" &
#   progress_while $! monitoring "Prometheus stack"       # prints how many Pods are ready, every 20 s, until the command ends
#   wait $!  ||  { ...show the error... }
progress_while() {  # progress_while PID NAMESPACE LABEL
  local pid=$1 ns=$2 label=$3 t=0 every=${PROGRESS_EVERY:-20} ready total
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$every"; t=$((t + every))
    kill -0 "$pid" 2>/dev/null || break
    total=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    ready=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '$3 == "Running" { split($2, a, "/"); if (a[1] == a[2]) r++ } END { print r + 0 }')
    printf '   ⏳ %s: %s of %s Pods ready in %s (%ss so far; the first install takes a few minutes)\n' "$label" "$ready" "$total" "$ns" "$t"
  done
}
