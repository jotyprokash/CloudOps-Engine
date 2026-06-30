#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
ensure_dirs

require_cmd aws

INPUT="${1:-${ROOT_DIR}/${WORK_DIR}/validation/route53-dns-tests.tsv}"
OUT="${ROOT_DIR}/${WORK_DIR}/validation/dns-results.txt"

if [[ ! -f "$INPUT" ]]; then
  printf 'Input file not found: %s\nRun bin/map-domains.sh first or pass a Route53 test TSV.\n' "$INPUT" >&2
  exit 1
fi

: > "$OUT"
tail -n +2 "$INPUT" | while IFS=$'\t' read -r zone_id record_name record_type; do
  [[ -n "${zone_id:-}" && -n "${record_name:-}" && -n "${record_type:-}" ]] || continue
  {
    printf '## %s %s\n' "$record_type" "$record_name"
    aws_cli route53 test-dns-answer \
      --hosted-zone-id "$zone_id" \
      --record-name "$record_name" \
      --record-type "$record_type" \
      --output json
    printf '\n'
  } >> "$OUT"
done

printf 'DNS validation results written to %s\n' "$OUT"
