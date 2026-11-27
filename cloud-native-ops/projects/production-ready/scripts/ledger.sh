#!/usr/bin/env bash
# ledger.sh ACTION: the stall's order book, its backup, and the way back.
#   ledger.sh seed [N]     write N orders (default 1000) into the ledger
#   ledger.sh count        how many orders does the ledger hold?
#   ledger.sh backup       take a backup NOW (do not wait for the 5-minute schedule) and check it
#   ledger.sh backups      list the backups
#   ledger.sh disaster     "someone ran the wrong command": wipe the ledger (FLUSHALL)
#   ledger.sh restore      bring back the newest backup (stops the ledger, copies the backup in, starts it, checks the count)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need_cluster
NS=chai-ledger
rc() { kubectl -n "$NS" exec deploy/ledger -- redis-cli "$@"; }
count() { rc GET orders:total 2>/dev/null | tr -d '\r' | sed 's/^$/0/;s/(nil)/0/'; }
case "${1:-}" in
  seed)
    n=${2:-1000}; rc SET orders:total "$n" >/dev/null; rc SET orders:note "seeded by ledger.sh" >/dev/null
    rc SAVE >/dev/null; ok "the ledger now holds $(count) orders (saved to disk)" ;;
  count) echo "$(count)" ;;
  backup)
    say "Taking a backup now (a Job made from the CronJob)"
    kubectl -n "$NS" delete job ledger-backup-now --ignore-not-found >/dev/null
    kubectl -n "$NS" create job ledger-backup-now --from=cronjob/ledger-backup >/dev/null
    kubectl -n "$NS" wait --for=condition=complete job/ledger-backup-now --timeout=120s >/dev/null 2>&1 \
      || { kubectl -n "$NS" logs job/ledger-backup-now --tail=20 >&2 || true; die "the backup failed (log above)"; }
    ok "$(kubectl -n "$NS" logs job/ledger-backup-now | tail -1)"
    kubectl -n "$NS" delete job ledger-backup-now --wait=false >/dev/null ;;
  backups)
    kubectl -n "$NS" run lsb --rm -i --restart=Never --quiet --image=redis:7.4-alpine --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"lsb","image":"redis:7.4-alpine","command":["sh","-c","ls -l /backup"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"ledger-backups"}}]}}' ;;
  disaster)
    before=$(count); rc FLUSHALL >/dev/null; rc SAVE >/dev/null
    printf '\033[1;31m💥 the ledger was %s orders, now %s. (This is the 2017 story: the live data is gone, and the only thing that matters now is the last backup.)\033[0m\n' "$before" "$(count)" ;;
  restore)
    say "Restoring the newest backup"
    cat > /tmp/ledger-restore.yaml <<YAML
apiVersion: batch/v1
kind: Job
metadata: { name: ledger-restore, namespace: $NS }
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      securityContext: { runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, fsGroup: 999, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: restore
          image: redis:7.4-alpine
          command:
            - sh
            - -c
            - |
              set -eu
              newest=""
              for f in \$(ls -1t /backup/ledger-*.rdb 2>/dev/null); do
                if [ "\$(head -c 5 "\$f")" = REDIS ]; then newest=\$f; break; fi
                echo "skipping \$f (not a valid Redis dump)"
              done
              [ -n "\$newest" ] || { echo "NO VALID BACKUP FOUND in /backup"; exit 1; }
              cp "\$newest" /data/dump.rdb
              echo "restored from \$newest"
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 64Mi } }
          volumeMounts:
            - { name: data, mountPath: /data }
            - { name: backup, mountPath: /backup, readOnly: true }
      volumes:
        - { name: data, persistentVolumeClaim: { claimName: ledger-data } }
        - { name: backup, persistentVolumeClaim: { claimName: ledger-backups } }
YAML
    kubectl -n "$NS" scale deploy/ledger --replicas=0 >/dev/null
    kubectl -n "$NS" wait --for=delete pod -l app=ledger --timeout=90s >/dev/null 2>&1 || true
    kubectl -n "$NS" delete job ledger-restore --ignore-not-found >/dev/null
    kubectl apply -f /tmp/ledger-restore.yaml >/dev/null
    if ! kubectl -n "$NS" wait --for=condition=complete job/ledger-restore --timeout=120s >/dev/null 2>&1; then
      kubectl -n "$NS" logs job/ledger-restore --tail=20 >&2 || true; kubectl -n "$NS" scale deploy/ledger --replicas=1 >/dev/null
      die "the restore failed (log above). The ledger was started again, EMPTY: nothing more was lost."
    fi
    kubectl -n "$NS" logs job/ledger-restore | tail -1
    kubectl -n "$NS" scale deploy/ledger --replicas=1 >/dev/null
    kubectl -n "$NS" rollout status deploy/ledger --timeout=120s >/dev/null || die "the ledger did not start again: kubectl -n $NS get pods"
    ok "the ledger is back, holding $(count) orders" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
