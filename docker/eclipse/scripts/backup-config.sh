#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR=${1:-${HOME}}
BACKUP_DIR=${2:-/backup}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE="${BACKUP_DIR}/eclipse-home-${TIMESTAMP}.tar.gz"

mkdir -p "${BACKUP_DIR}"
tar -czf "${ARCHIVE}" -C "${SOURCE_DIR}" .
echo "Backup created: ${ARCHIVE}"
