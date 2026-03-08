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

mkdir -p "$(dirname "${PREFS_FILE}")"

"${ECLIPSE_HOME}/eclipse" \
  -nosplash \
  -application org.eclipse.ui.ide.workbench \
  -data "${WORKSPACE_DIR}" \
  -vmargs -Dexport.preferences="${PREFS_FILE}"
