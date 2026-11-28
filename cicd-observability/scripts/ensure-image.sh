#!/usr/bin/env bash
# ensure-image.sh [TAG]: make sure the Chai Stall image TAG (default $CHAI_IMAGE_TAG, see k8s-lib.sh) is in the cluster's registry. Safe to run again.
#
# Why it exists: every project that deploys the Chai Stall needs the image somewhere the nodes can pull it from. This builds it
# INSIDE the cluster with Kaniko (no Docker, no registry login, no internet except the Python base image) and pushes it to the
# in-cluster registry that `k8s-up.sh` (or `k8s-up.sh --lite`) installed. If the image is already there, it does nothing.
#
#   ./cicd-observability/scripts/ensure-image.sh          builds chai-stall:1.5.0
#   ./cicd-observability/scripts/ensure-image.sh 1.0.1    builds that tag
set -euo pipefail
. "$(dirname "$0")/k8s-lib.sh"
TAG=${1:-$CHAI_IMAGE_TAG}
need_cluster
kubectl -n cicd get deploy registry >/dev/null 2>&1 || die "there is no image registry in this cluster yet. Run first:  ./cicd-observability/scripts/k8s-up.sh --lite"

tags() { kubectl -n cicd exec deploy/registry -- wget -qO- http://localhost:5000/v2/chai-stall/tags/list 2>/dev/null || true; }
have() { tags | grep -q "\"$TAG\""; }

if have; then ok "image chai-stall:$TAG is already in the registry. Nothing to do."; exit 0; fi

say "Building chai-stall:$TAG inside the cluster (Kaniko, one Job; about 1 minute)"
kubectl -n cicd delete job build-chai-image --ignore-not-found >/dev/null
kubectl -n cicd create configmap chai-src --from-file="$COURSE_ROOT/cicd-observability/app/app.py" \
  --from-file="$COURSE_ROOT/cicd-observability/app/Dockerfile" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# (Kaniko builds as root, which the "cicd" namespace allows; kubectl's Pod Security warning about that is expected, so show errors only.)
out=$(kubectl apply -f - 2>&1 <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: build-chai-image
  namespace: cicd
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 600
  template:
    spec:
      restartPolicy: Never
      # A ConfigMap volume shows each file as a SYMLINK into a hidden folder. Kaniko's COPY would copy the symlink, not the file,
      # and the image would hold a dangling "app.py" (the container then dies with "can't open file '/srv/app.py'"). So first
      # copy the files for real (cp -L follows the links) into a plain folder, and build from that.
      initContainers:
        - name: materialize
          image: busybox:1.36
          command: ["sh", "-c", "cp -L /cm/* /src/ && ls -l /src"]
          volumeMounts:
            - { name: cm, mountPath: /cm, readOnly: true }
            - { name: src, mountPath: /src }
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:v1.23.2
          args:
            - --context=dir:///src
            - --dockerfile=/src/Dockerfile
            - --destination=registry.cicd.svc.cluster.local:5000/chai-stall:$TAG
            - --build-arg=APP_VERSION=$TAG
            - --insecure
            - --cache=false
          volumeMounts: [{ name: src, mountPath: /src, readOnly: true }]
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { memory: 1Gi }
      volumes:
        - { name: cm, configMap: { name: chai-src } }
        - { name: src, emptyDir: {} }
YAML
) || die "could not create the build Job: $out"

waited=0
for _ in $(seq 1 120); do
  st=$(kubectl -n cicd get job build-chai-image -o jsonpath='{.status.succeeded}/{.status.failed}' 2>/dev/null || echo "/")
  case "$st" in
    1/*) break ;;
    */1) echo "--- the build log:" >&2; kubectl -n cicd logs job/build-chai-image --tail=25 >&2 || true
         die "the image build failed (the log is above). A pull error for the Python base image means this cluster has no route to Docker Hub." ;;
  esac
  sleep 5
  [ $(( ++waited % 6 )) -eq 0 ] && printf '   ⏳ building chai-stall:%s: %s so far (Kaniko pulls the Python base image first)\n' "$TAG" "$((waited * 5))s"
done
have || die "the build finished but chai-stall:$TAG is not in the registry. Look: kubectl -n cicd logs job/build-chai-image"
ok "image chai-stall:$TAG is in the registry (nodes pull it as localhost:30500/chai-stall:$TAG)."
