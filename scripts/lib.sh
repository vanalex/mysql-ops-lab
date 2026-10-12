#!/usr/bin/env bash
# Shared helpers for the lab scripts.
set -euo pipefail
NS="${NS:-mysql-lab}"

# Read a key from the lab secret.
secret() {
  kubectl -n "$NS" get secret mysql-lab-secrets -o "jsonpath={.data.$1}" | base64 -d
}

# Run SQL as root inside a pod. Usage: mysql_exec mysql-0 [extra mysql args] < file.sql
mysql_exec() {
  local pod="$1"; shift
  kubectl -n "$NS" exec -i "$pod" -c mysql -- \
    sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql -uroot "$@"' sh "$@"
}
