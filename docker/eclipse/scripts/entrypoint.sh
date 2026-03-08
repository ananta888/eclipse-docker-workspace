#!/usr/bin/env bash
set -euo pipefail

NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_PORT=${VNC_PORT:-5900}
DISPLAY_NUM=${DISPLAY_NUM:-:1}
ECLIPSE_WORKSPACE=${ECLIPSE_WORKSPACE:-/home/developer/workspace}
ECLIPSE_SHARED=${ECLIPSE_SHARED:-/shared}
ECLIPSE_BACKUP=${ECLIPSE_BACKUP:-/backup}

DEVELOPER_USER=${DEVELOPER_USER:-developer}
DEVELOPER_HOME=${DEVELOPER_HOME:-/home/${DEVELOPER_USER}}

export DISPLAY="${DISPLAY_NUM}"
export HOME="${DEVELOPER_HOME}"

mkdir -p \
  "${DEVELOPER_HOME}" \
  "${DEVELOPER_HOME}/.vnc" \
  "${DEVELOPER_HOME}/Desktop" \
  "${DEVELOPER_HOME}/workspace" \
  "${ECLIPSE_WORKSPACE}" \
  "${ECLIPSE_BACKUP}"

chown -R "${DEVELOPER_USER}:${DEVELOPER_USER}" \
  "${DEVELOPER_HOME}" \
  "${ECLIPSE_WORKSPACE}" \
  "${ECLIPSE_BACKUP}"

if [ -d "${ECLIPSE_SHARED}/launch" ]; then
  mkdir -p "${ECLIPSE_WORKSPACE}/.launches"
  cp -a "${ECLIPSE_SHARED}/launch/." "${ECLIPSE_WORKSPACE}/.launches/"
  chown -R "${DEVELOPER_USER}:${DEVELOPER_USER}" "${ECLIPSE_WORKSPACE}"
fi

gosu "${DEVELOPER_USER}" Xvfb "${DISPLAY_NUM}" -screen 0 1920x1080x24 &
gosu "${DEVELOPER_USER}" xfce4-session &
gosu "${DEVELOPER_USER}" x11vnc -display "${DISPLAY_NUM}" -rfbport "${VNC_PORT}" -shared -forever -nopw &
gosu "${DEVELOPER_USER}" websockify --web=/usr/share/novnc/ "${NOVNC_PORT}" "localhost:${VNC_PORT}" &

exec gosu "${DEVELOPER_USER}" /opt/eclipse/eclipse -data "${ECLIPSE_WORKSPACE}"
