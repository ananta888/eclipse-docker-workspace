#!/usr/bin/env bash
set -euo pipefail

NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_PORT=${VNC_PORT:-5900}
DISPLAY_NUM=${DISPLAY_NUM:-:1}
USE_HOST_X11=${USE_HOST_X11:-0}
HOST_DISPLAY=${HOST_DISPLAY:-host.docker.internal:0.0}
ECLIPSE_WORKSPACE=${ECLIPSE_WORKSPACE:-/home/developer/workspace}
ECLIPSE_SHARED=${ECLIPSE_SHARED:-/shared}
ECLIPSE_BACKUP=${ECLIPSE_BACKUP:-/backup}
ECLIPSE_VM_OPENS=${ECLIPSE_VM_OPENS:---add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.text=ALL-UNNAMED --add-opens=java.desktop/java.awt.font=ALL-UNNAMED}
DISABLE_SAROS=${DISABLE_SAROS:-1}
ECLIPSE_IMPORT_LIST_FILE=${ECLIPSE_IMPORT_LIST_FILE:-${ECLIPSE_WORKSPACE}/.eclipse-import-paths.txt}

DEVELOPER_USER=${DEVELOPER_USER:-developer}
DEVELOPER_HOME=${DEVELOPER_HOME:-/home/${DEVELOPER_USER}}

if [ "${USE_HOST_X11}" = "1" ]; then
  export DISPLAY="${HOST_DISPLAY}"
else
  export DISPLAY="${DISPLAY_NUM}"
fi
export HOME="${DEVELOPER_HOME}"

ensure_dir() {
  local path="$1"
  mkdir -p "${path}"
}

ensure_owned_dir() {
  local path="$1"
  ensure_dir "${path}"
  chown "${DEVELOPER_USER}:${DEVELOPER_USER}" "${path}"
}

RUN_AS_ROOT=0
if [ "$(id -u)" -eq 0 ]; then
  RUN_AS_ROOT=1
  ensure_owned_dir "${DEVELOPER_HOME}"
  ensure_owned_dir "${DEVELOPER_HOME}/.vnc"
  ensure_owned_dir "${DEVELOPER_HOME}/Desktop"
  ensure_owned_dir "${DEVELOPER_HOME}/workspace"
  ensure_owned_dir "${ECLIPSE_WORKSPACE}"
  ensure_owned_dir "${ECLIPSE_BACKUP}"
else
  ensure_dir "${DEVELOPER_HOME}"
  ensure_dir "${DEVELOPER_HOME}/.vnc"
  ensure_dir "${DEVELOPER_HOME}/Desktop"
  ensure_dir "${DEVELOPER_HOME}/workspace"
  ensure_dir "${ECLIPSE_WORKSPACE}"
  ensure_dir "${ECLIPSE_BACKUP}"
fi

if [ -d "${ECLIPSE_SHARED}/launch" ]; then
  ensure_dir "${ECLIPSE_WORKSPACE}/.launches"
  cp -a "${ECLIPSE_SHARED}/launch/." "${ECLIPSE_WORKSPACE}/.launches/"
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "${DEVELOPER_USER}:${DEVELOPER_USER}" "${ECLIPSE_WORKSPACE}/.launches"
  fi
fi

run_as_developer() {
  if [ "${RUN_AS_ROOT}" -eq 1 ]; then
    gosu "${DEVELOPER_USER}" "$@"
  else
    "$@"
  fi
}

set_saros_enabled() {
  local enabled="$1"
  local plugins_dir="/opt/eclipse/plugins"
  if [ ! -d "${plugins_dir}" ]; then
    return
  fi

  if [ "${enabled}" = "1" ]; then
    shopt -s nullglob
    for f in "${plugins_dir}"/saros*.jar.disabled; do
      mv "${f}" "${f%.disabled}"
    done
    shopt -u nullglob
    return
  fi

  shopt -s nullglob
  for f in "${plugins_dir}"/saros*.jar; do
    mv "${f}" "${f}.disabled"
  done
  shopt -u nullglob
}

if [ "${USE_HOST_X11}" != "1" ]; then
  run_as_developer Xvfb "${DISPLAY_NUM}" -screen 0 1920x1080x24 &
  run_as_developer xfce4-session &
  run_as_developer x11vnc -display "${DISPLAY_NUM}" -rfbport "${VNC_PORT}" -shared -forever -nopw &
  run_as_developer websockify --web=/usr/share/novnc/ "${NOVNC_PORT}" "localhost:${VNC_PORT}" &
fi

if [ "${DISABLE_SAROS}" = "1" ]; then
  set_saros_enabled "0"
  echo "Saros bundles disabled for this container runtime."
else
  set_saros_enabled "1"
  echo "Saros bundles enabled for this container runtime."
fi

ECLIPSE_IMPORT_ARGS=()
if [ -f "${ECLIPSE_IMPORT_LIST_FILE}" ]; then
  while IFS= read -r import_path; do
    [ -z "${import_path}" ] && continue
    if [[ "${import_path}" =~ ^ALL[[:space:]]+(.+)$ ]]; then
      all_path="${BASH_REMATCH[1]}"
      if [ -d "${all_path}" ]; then
        ECLIPSE_IMPORT_ARGS+=("-importAll" "${all_path}")
      fi
      continue
    fi
    if [ -d "${import_path}" ]; then
      ECLIPSE_IMPORT_ARGS+=("-import" "${import_path}")
    fi
  done < "${ECLIPSE_IMPORT_LIST_FILE}"
  echo "Eclipse startup imports: ${#ECLIPSE_IMPORT_ARGS[@]} args from ${ECLIPSE_IMPORT_LIST_FILE}"
fi

if [ "${RUN_AS_ROOT}" -eq 1 ]; then
  exec gosu "${DEVELOPER_USER}" /opt/eclipse/eclipse "${ECLIPSE_IMPORT_ARGS[@]}" -data "${ECLIPSE_WORKSPACE}" -vmargs ${ECLIPSE_VM_OPENS}
else
  exec /opt/eclipse/eclipse "${ECLIPSE_IMPORT_ARGS[@]}" -data "${ECLIPSE_WORKSPACE}" -vmargs ${ECLIPSE_VM_OPENS}
fi
