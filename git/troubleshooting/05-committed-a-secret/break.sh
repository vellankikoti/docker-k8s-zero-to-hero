#!/usr/bin/env bash
# G-05 break: a password file is committed along with a code change. Nothing is pushed.
# The password is a fake demo value, z2h-demo-key-NOT-REAL-123. It opens nothing. Never try this with a real one.
source "$(dirname "$0")/../_lib.sh"
world 05-committed-a-secret
printf 'REDIS_PASSWORD=z2h-demo-key-NOT-REAL-123\n' > api/.env
edit api/app.py 's/os.environ.get("REDIS_HOST", "")/os.environ.get("REDIS_HOST", "redis")/'
git add .
as "${YOU[@]}" "Thu, 05 Nov 2026 14:00:00 +0530" git commit -q -m "Store votes in Redis by default"
say "Your last commit:"
git show --stat --oneline HEAD
echo "Your clone: $S/you"
