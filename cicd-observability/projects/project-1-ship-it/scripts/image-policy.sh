#!/usr/bin/env bash
# image-policy.sh IMAGE: "policy as code" for container images. Fails when the image breaks a house rule.
img=${1:?usage: image-policy.sh IMAGE}
fail=0
user=$(docker inspect -f '{{.Config.User}}' "$img")
case "$user" in ""|root|0|0:0) echo "✖ runs as root (user='${user:-<none>}'): add a USER line"; fail=1 ;; *) echo "✔ runs as non-root user: $user" ;; esac
hc=$(docker inspect -f '{{if .Config.Healthcheck}}yes{{end}}' "$img")
[ "$hc" = yes ] && echo "✔ has a HEALTHCHECK" || { echo "✖ no HEALTHCHECK: orchestrators cannot tell if it is healthy"; fail=1; }
ver=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$img" | grep -c '^APP_VERSION=')
[ "$ver" -ge 1 ] && echo "✔ carries APP_VERSION" || { echo "✖ no APP_VERSION baked in"; fail=1; }
exit $fail
