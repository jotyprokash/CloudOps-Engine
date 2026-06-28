#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/scan-aws.sh"
"${SCRIPT_DIR}/map-domains.sh"
"${SCRIPT_DIR}/write-nginx.sh"

cat <<'EOF'
Read-only scan and mapping pass complete.

Next review:
- inventory/json/
- inventory/csv/
- artifacts/plans/
- artifacts/nginx/

Validation helpers:
- bin/check-dns.sh
- bin/check-certs.sh
- bin/check-acm.sh
EOF
