#!/usr/bin/env bash
# registry-digest.sh TAG [REGISTRY=localhost:5001] [REPO=chai-stall]: print the content digest the registry holds for a tag.
# A tag is a movable label; the digest is the fingerprint of the content. Compare them to see if a tag moved.
tag=${1:?usage: registry-digest.sh TAG}; reg=${2:-localhost:5001}; repo=${3:-chai-stall}
curl -sI \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  "http://$reg/v2/$repo/manifests/$tag" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2; found=1} END{exit !found}' \
  || { echo "tag '$tag' not found in $reg/$repo" >&2; exit 1; }
