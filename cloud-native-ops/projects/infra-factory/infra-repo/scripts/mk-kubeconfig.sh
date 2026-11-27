#!/bin/sh
# mk-kubeconfig.sh [OUT]: inside a Pod, write a kubeconfig that uses the Pod's own ServiceAccount token.
# Why: Terraform's providers want a kubeconfig file. A build Pod has no kubectl login; it has a ServiceAccount (Lab K14).
# So the pipeline turns "who this Pod is" into a kubeconfig, and Terraform then has exactly that Pod's permissions, nothing more.
#
#   scripts/mk-kubeconfig.sh /tmp/kubeconfig && export KUBECONFIG_PATH=/tmp/kubeconfig
# (SA_DIR and API_SERVER can be overridden; that is how the test runs it outside a Pod.)
set -eu
OUT=${1:-/tmp/kubeconfig}
SA_DIR=${SA_DIR:-/var/run/secrets/kubernetes.io/serviceaccount}
SERVER=${API_SERVER:-https://${KUBERNETES_SERVICE_HOST:-kubernetes.default.svc}:${KUBERNETES_SERVICE_PORT:-443}}
[ -r "$SA_DIR/token" ] || { echo "mk-kubeconfig.sh: no ServiceAccount token at $SA_DIR/token (are you inside a Pod?)" >&2; exit 1; }
cat > "$OUT" <<YAML
apiVersion: v1
kind: Config
clusters:
  - name: in-cluster
    cluster:
      server: $SERVER
      certificate-authority: $SA_DIR/ca.crt
users:
  - name: pod-serviceaccount
    user:
      tokenFile: $SA_DIR/token
contexts:
  - name: in-cluster
    context: { cluster: in-cluster, user: pod-serviceaccount }
current-context: in-cluster
YAML
chmod 600 "$OUT"
echo "wrote $OUT (server $SERVER)"
