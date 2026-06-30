#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
ensure_dirs

require_cmd aws

INPUT="${1:-${ROOT_DIR}/${INVENTORY_DIR}/summary/acm-certificates.tsv}"
OUT="${ROOT_DIR}/${WORK_DIR}/validation/ssl-results.txt"

if [[ ! -f "$INPUT" ]]; then
  printf 'Input file not found: %s\nRun bin/scan-aws.sh first or pass an ACM certificate TSV.\n' "$INPUT" >&2
  exit 1
fi

: > "$OUT"
tail -n +2 "$INPUT" | while IFS=$'\t' read -r region domain status type in_use arn; do
  [[ -n "${arn:-}" ]] || continue
  {
    printf '## %s (%s)\n' "$domain" "$region"
    aws_cli acm describe-certificate \
      --region "$region" \
      --certificate-arn "$arn" \
      --query 'Certificate.{DomainName:DomainName,Status:Status,NotBefore:NotBefore,NotAfter:NotAfter,InUseBy:InUseBy,SubjectAlternativeNames:SubjectAlternativeNames,RenewalEligibility:RenewalEligibility,DomainValidationOptions:DomainValidationOptions[].{DomainName:DomainName,ValidationStatus:ValidationStatus,ResourceRecord:ResourceRecord}}' \
      --output json
    printf '\n'
  } >> "$OUT"
done

printf 'SSL validation results written to %s\n' "$OUT"
