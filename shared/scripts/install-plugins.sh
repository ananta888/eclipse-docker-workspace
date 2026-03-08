#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
PLUGINS_FILE=${PLUGINS_FILE:-${REPO_ROOT}/shared/p2/plugins.txt}
ECLIPSE_HOME=${ECLIPSE_HOME:-${REPO_ROOT}/portable/eclipse}
P2_PROFILE=${P2_PROFILE:-SDKProfile}

if [ ! -x "${ECLIPSE_HOME}/eclipse" ]; then
  echo "Eclipse binary not found: ${ECLIPSE_HOME}/eclipse" >&2
  exit 1
fi

if [ ! -f "${PLUGINS_FILE}" ]; then
  echo "plugins.txt not found: ${PLUGINS_FILE}" >&2
  exit 1
fi

while IFS= read -r raw_line; do
  line="${raw_line#"${raw_line%%[![:space:]]*}"}"
  [ -z "${line}" ] && continue
  case "${line}" in
    \#*) continue ;;
  esac

  IFS='|' read -r repo iu <<< "${line}"
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  iu="${iu#"${iu%%[![:space:]]*}"}"
  iu="${iu%"${iu##*[![:space:]]}"}"
  [ -z "${repo}" ] && continue
  [ -z "${iu}" ] && continue

  if [ -n "${ECLIPSE_VERSION:-}" ]; then
    repo="${repo//'${ECLIPSE_VERSION}'/${ECLIPSE_VERSION}}"
    repo="${repo//'$ECLIPSE_VERSION'/${ECLIPSE_VERSION}}"
  fi

  echo "Installing ${iu} from ${repo}"
  "${ECLIPSE_HOME}/eclipse" \
    -application org.eclipse.equinox.p2.director \
    -nosplash \
    -repository "${repo}" \
    -installIU "${iu}" \
    -profile "${P2_PROFILE}" \
    -destination "${ECLIPSE_HOME}" \
    -bundlepool "${ECLIPSE_HOME}" \
    -roaming

done < "${PLUGINS_FILE}"
