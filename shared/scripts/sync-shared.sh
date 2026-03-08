#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
TARGET_SHARED_DIR=${1:-${TARGET_SHARED_DIR:-${REPO_ROOT}/eclipse-data/home/shared}}

mkdir -p "${TARGET_SHARED_DIR}"
rsync -a --delete "${REPO_ROOT}/shared/" "${TARGET_SHARED_DIR}/"
