#!/usr/bin/env bash
set -euo pipefail

NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_PORT=${VNC_PORT:-5900}
ECLIPSE_WORKSPACE=${ECLIPSE_WORKSPACE:-/workspace}
ECLIPSE_SHARED=${ECLIPSE_SHARED:-/shared}
ECLIPSE_BACKUP=${ECLIPSE_BACKUP:-/backup}
DISPLAY_NUM=${DISPLAY_NUM:-:1}
DISPLAY=${DISPLAY_NUM}
export DISPLAY

mkdir -p "${ECLIPSE_WORKSPACE}" "${ECLIPSE_BACKUP}" "${HOME}/.vnc" "${HOME}/Desktop"
if [ -d "${ECLIPSE_SHARED}/launch" ]; then
  mkdir -p "${ECLIPSE_WORKSPACE}/.launches"
  cp -a "${ECLIPSE_SHARED}/launch/." "${ECLIPSE_WORKSPACE}/.launches/"
fi

Xvfb "${DISPLAY_NUM}" -screen 0 1920x1080x24 &
xfce4-session &
x11vnc -display "${DISPLAY_NUM}" -rfbport "${VNC_PORT}" -shared -forever -nopw &
websockify --web=/usr/share/novnc/ "${NOVNC_PORT}" localhost:"${VNC_PORT}" &

exec /opt/eclipse/eclipse -data "${ECLIPSE_WORKSPACE}"
