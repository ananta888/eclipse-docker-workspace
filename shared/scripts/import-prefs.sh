#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
ECLIPSE_HOME=${ECLIPSE_HOME:-${REPO_ROOT}/portable/eclipse}
WORKSPACE_DIR=${WORKSPACE_DIR:-${REPO_ROOT}/portable/workspace}
PREFS_FILE=${PREFS_FILE:-${REPO_ROOT}/shared/prefs/eclipse.epf}

if [ ! -x "${ECLIPSE_HOME}/eclipse" ]; then
  echo "Eclipse binary not found: ${ECLIPSE_HOME}/eclipse" >&2
  exit 1
fi

if [ ! -f "${PREFS_FILE}" ]; then
  echo "Preferences file not found: ${PREFS_FILE}" >&2
  exit 1
fi

"${ECLIPSE_HOME}/eclipse" \
  -nosplash \
  -application org.eclipse.equinox.p2.director \
  -data "${WORKSPACE_DIR}" \
  -vmargs -Dimport.preferences="${PREFS_FILE}"
