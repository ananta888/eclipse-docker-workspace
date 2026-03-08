#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
PORTABLE_ROOT=${PORTABLE_ROOT:-${REPO_ROOT}/portable}
ECLIPSE_DIR=${ECLIPSE_DIR:-${PORTABLE_ROOT}/eclipse}
WORKSPACE_DIR=${WORKSPACE_DIR:-${PORTABLE_ROOT}/workspace}
CONFIG_DIR=${CONFIG_DIR:-${PORTABLE_ROOT}/config}
ARCHIVE_PATH=${ARCHIVE_PATH:-${REPO_ROOT}/portable-eclipse.tar.gz}

mkdir -p "${ECLIPSE_DIR}" "${WORKSPACE_DIR}" "${CONFIG_DIR}"
cp -a "${REPO_ROOT}/shared" "${CONFIG_DIR}/shared"

tar -czf "${ARCHIVE_PATH}" -C "${PORTABLE_ROOT}" .
echo "Portable package created: ${ARCHIVE_PATH}"
