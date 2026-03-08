#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHE_LOCAL_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
CHECTL_VERSION=${CHECTL_VERSION:-$(grep '^CHECTL_VERSION=' "${CHE_LOCAL_DIR}/.env" | cut -d'=' -f2)}

curl -fsSL "https://github.com/eclipse-che/chectl/releases/download/${CHECTL_VERSION}/chectl-linux-x64.tar.gz" -o /tmp/chectl.tar.gz
sudo tar -xzf /tmp/chectl.tar.gz -C /usr/local/bin chectl
rm -f /tmp/chectl.tar.gz
chectl version
