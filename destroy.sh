#!/usr/bin/env bash
set -euo pipefail
echo "WARNING: This destroys everything!"
read -p "Type 'yes' to confirm: " CONFIRM
[[ "${CONFIRM}" != "yes" ]] && echo "Aborted." && exit 0

kubectl delete namespace myapp --ignore-not-found 2>/dev/null || true
kubectl delete namespace jenkins --ignore-not-found 2>/dev/null || true
cd terraform && terraform destroy -auto-approve
echo "All resources destroyed."
