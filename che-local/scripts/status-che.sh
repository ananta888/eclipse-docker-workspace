#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHE_LOCAL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
set -a
. "${CHE_LOCAL_DIR}/.env"
set +a

kubectl get pods -n "${CHE_NAMESPACE}"
