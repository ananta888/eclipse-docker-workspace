#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHE_LOCAL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
set -a
. "${CHE_LOCAL_DIR}/.env"
set +a

minikube start \
  --profile="${MINIKUBE_PROFILE}" \
  --driver="${MINIKUBE_DRIVER}" \
  --cpus="${MINIKUBE_CPUS}" \
  --memory="${MINIKUBE_MEMORY}" \
  --kubernetes-version=stable
