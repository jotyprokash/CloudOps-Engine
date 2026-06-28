#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
require_cmd aws
ensure_dirs

SUMMARY="${ROOT_DIR}/${INVENTORY_DIR}/summary/acm-certificates.tsv"
OUT="${ROOT_DIR}/${WORK_DIR}/validation/acm-results.txt"

[[ -f "$SUMMARY" ]] || {
  printf 'Missing %s. Run bin/scan-aws.sh first.\n' "$SUMMARY" >&2
  exit 1
}

: > "$OUT"
tail -n +2 "$SUMMARY" | while IFS=$'\t' read -r region domain status type in_use arn; do
  [[ -n "${arn:-}" ]] || continue
  {
    printf '## %s (%s)\n' "$domain" "$region"
    aws_cli acm describe-certificate \
      --region "$region" \
      --certificate-arn "$arn" \
      --query 'Certificate.{DomainName:DomainName,Status:Status,NotBefore:NotBefore,NotAfter:NotAfter,InUseBy:InUseBy,SubjectAlternativeNames:SubjectAlternativeNames,DomainValidationOptions:DomainValidationOptions[].{DomainName:DomainName,ValidationStatus:ValidationStatus,ResourceRecord:ResourceRecord}}' \
      --output json
    printf '\n'
  } >> "$OUT"
done

printf 'ACM validation results written to %s\n' "$OUT"
