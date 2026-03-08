#!/usr/bin/env bash
set -euo pipefail

ARCHIVE_PATH=${1:-}
TARGET_DIR=${2:-${HOME}}

if [ -z "${ARCHIVE_PATH}" ] || [ ! -f "${ARCHIVE_PATH}" ]; then
  echo "Valid archive path required" >&2
  exit 1
fi

mkdir -p "${TARGET_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "${TARGET_DIR}"
echo "Restore completed from ${ARCHIVE_PATH}"
