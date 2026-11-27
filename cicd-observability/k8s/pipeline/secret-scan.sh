#!/usr/bin/env bash
# secret-scan.sh [PATH...]: a tiny "did somebody commit a secret?" check. Fails (exit 1) when it finds one.
# Real teams use gitleaks / trufflehog / GitHub secret scanning. This one shows the idea in 20 lines.
paths=("$@"); [ ${#paths[@]} -gt 0 ] || paths=(app)
patterns=(
  'AKIA[0-9A-Z]{16}'                                            # an AWS access key id
  '-----BEGIN ([A-Z]+ )?PRIVATE KEY-----'                       # a private key
  '(password|passwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]$]{8,}["'"'"']'   # password = "something"
)
found=0
for p in "${patterns[@]}"; do
  if grep -rEni --exclude-dir=__pycache__ --exclude-dir=.git -e "$p" "${paths[@]}" 2>/dev/null; then found=1; fi
done
if [ $found -eq 1 ]; then echo "✖ possible secret(s) found above. Remove them, rotate them, and use a Kubernetes Secret / the credential store."; exit 1; fi
echo "✔ no secrets found in: ${paths[*]}"
