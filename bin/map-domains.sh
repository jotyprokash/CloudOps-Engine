#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
ensure_dirs

SUMMARY_DIR="${ROOT_DIR}/${INVENTORY_DIR}/summary"
PLAN_DIR="${ROOT_DIR}/${WORK_DIR}/plans"
VALIDATION_DIR="${ROOT_DIR}/${WORK_DIR}/validation"
RUN_AT="$(timestamp_utc)"

label_domain_with_suffixes() {
  local domain="$1" suffix
  split_words "${LIVE_DOMAIN_SUFFIXES:-}"
  for suffix in "${SPLIT_WORDS_RESULT[@]:-}"; do
    [[ -n "$suffix" && "$domain" == *"$suffix" ]] && { printf 'live'; return; }
  done
  split_words "${STAGING_DOMAIN_SUFFIXES:-}"
  for suffix in "${SPLIT_WORDS_RESULT[@]:-}"; do
    [[ -n "$suffix" && "$domain" == *"$suffix" ]] && { printf 'staging'; return; }
  done
  split_words "${DEVELOPMENT_DOMAIN_SUFFIXES:-}"
  for suffix in "${SPLIT_WORDS_RESULT[@]:-}"; do
    [[ -n "$suffix" && "$domain" == *"$suffix" ]] && { printf 'development'; return; }
  done
  label_text "$domain"
}

write_labeled_resources() {
  local output="${PLAN_DIR}/labeled-resources.md"
  {
    printf '# Labeled Resources\n\n'
    printf 'Written: %s\n\n' "$RUN_AT"
    printf 'Labels are a first pass. Confirm each one with service owners before moving traffic.\n\n'
    printf '| Resource Type | Region/Zone | Identifier | Evidence | Label | Confidence |\n'
    printf '|---|---|---|---|---|---|\n'
  } > "$output"

  if [[ -f "${SUMMARY_DIR}/route53-records.tsv" ]]; then
    tail -n +2 "${SUMMARY_DIR}/route53-records.tsv" | while IFS=$'\t' read -r zone_id zone_name record_name record_type ttl targets; do
      local class confidence evidence
      evidence="${record_name} ${targets} ${zone_name}"
      class="$(label_domain_with_suffixes "$evidence")"
      confidence="$(confidence_for_label "$class")"
      printf '| route53-record | %s | %s %s | %s | %s | %s |\n' "$zone_name" "$record_type" "$record_name" "$targets" "$class" "$confidence" >> "$output"
    done
  fi

  if [[ -f "${SUMMARY_DIR}/acm-certificates.tsv" ]]; then
    tail -n +2 "${SUMMARY_DIR}/acm-certificates.tsv" | while IFS=$'\t' read -r region domain status type in_use arn; do
      local class confidence
      class="$(label_domain_with_suffixes "$domain")"
      confidence="$(confidence_for_label "$class")"
      printf '| acm-certificate | %s | %s | status=%s in_use=%s | %s | %s |\n' "$region" "$domain" "$status" "$in_use" "$class" "$confidence" >> "$output"
    done
  fi

  if [[ -f "${SUMMARY_DIR}/load-balancers.tsv" ]]; then
    tail -n +2 "${SUMMARY_DIR}/load-balancers.tsv" | while IFS=$'\t' read -r region name dns type scheme state arn; do
      local class confidence
      class="$(label_text "${name} ${dns} ${scheme}")"
      confidence="$(confidence_for_label "$class")"
      printf '| load-balancer | %s | %s | dns=%s scheme=%s state=%s | %s | %s |\n' "$region" "$name" "$dns" "$scheme" "$state" "$class" "$confidence" >> "$output"
    done
  fi

  if [[ -f "${SUMMARY_DIR}/ec2-instances.tsv" ]]; then
    tail -n +2 "${SUMMARY_DIR}/ec2-instances.tsv" | while IFS=$'\t' read -r region instance_id name state private_ip public_ip tags; do
      local class confidence
      class="$(label_text "${name} ${tags}")"
      confidence="$(confidence_for_label "$class")"
      printf '| ec2-instance | %s | %s | name=%s state=%s tags=%s | %s | %s |\n' "$region" "$instance_id" "$name" "$state" "$tags" "$class" "$confidence" >> "$output"
    done
  fi
}

write_domain_mapping() {
  local output="${PLAN_DIR}/domain-mapping.md"
  local machine="${PLAN_DIR}/domain-mapping.tsv"
  {
    printf '# Domain Map\n\n'
    printf 'Written: %s\n\n' "$RUN_AT"
    printf 'Create new records first, validate them, then plan cutover. Do not delete old DNS during scan or mapping artifacts.\n\n'
    printf '| Current Record | Type | Current Target | Environment | New Record | Confidence | Notes |\n'
    printf '|---|---|---|---|---|---|---|\n'
  } > "$output"
  printf 'current_record\trecord_type\tcurrent_target\tsuggested_environment\tsuggested_new_record\tconfidence\tnotes\n' > "$machine"

  [[ -f "${SUMMARY_DIR}/route53-records.tsv" ]] || return 0
  tail -n +2 "${SUMMARY_DIR}/route53-records.tsv" | while IFS=$'\t' read -r zone_id zone_name record_name record_type ttl targets; do
    case "$record_type" in
      A|AAAA|CNAME) ;;
      *) continue ;;
    esac
    local class confidence suggested notes clean_record
    clean_record="${record_name%.}"
    class="$(label_domain_with_suffixes "${record_name} ${targets} ${zone_name}")"
    confidence="$(confidence_for_label "$class")"
    suggested="<needs-owner-review>"
    notes="Create parallel DNS first; validate TLS and routing; cut over only after owner approval."
    case "$class" in
      live) suggested="$clean_record" ;;
      staging) suggested="staging.${clean_record#staging.}" ;;
      development) suggested="dev.${clean_record#dev.}" ;;
      unknown) notes="Unknown environment: do not move traffic until ownership and environment are confirmed." ;;
    esac
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$clean_record" "$record_type" "$targets" "$class" "$suggested" "$confidence" "$notes" >> "$output"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$clean_record" "$record_type" "$targets" "$class" "$suggested" "$confidence" "$notes" >> "$machine"
  done
}

write_migration_plan() {
  local output="${PLAN_DIR}/migration-plan.md"
  cat > "$output" <<EOF
# Migration Plan

Written: ${RUN_AT}

## Operating Principles

- Treat the AWS scan as read-only evidence gathering.
- Confirm every live, staging, and development label with service owners.
- Create new DNS records before cutover.
- Validate DNS, TLS, Nginx routing, application health, and rollback paths before changing user traffic.
- Never delete old DNS records as part of migration. Decommission only after an explicit post-migration change.

## Recommended Phases

1. Capture current state with \`bin/scan-aws.sh\`.
2. Review \`artifacts/plans/labeled-resources.md\` and resolve all unknowns.
3. Review \`artifacts/plans/domain-mapping.md\` with application owners.
4. Request or validate ACM certificates for target names.
5. Write Nginx files with \`bin/write-nginx.sh\`.
6. Create new Route53 records in a separate, reviewed change.
7. Run the DNS and SSL checks.
8. Lower TTLs only after approval and with a rollback window.
9. Cut over traffic by changing aliases or CNAMEs in a reviewed change.
10. Monitor application, load balancer, target group, TLS, and error-rate signals.

## Required Approvals

- Service owner approval for each domain.
- Security approval for public/private exposure changes.
- Platform approval for load balancer, certificate, and DNS changes.
- Incident commander or change manager approval for live cutover.

## Unknown Handling

Any resource labeled \`unknown\` is blocked. Add tags, update \`settings/labels.conf\`, or document owner-confirmed ownership before proceeding.
EOF
}

write_validation_checklist() {
  local output="${PLAN_DIR}/validation-checklist.md"
  cat > "$output" <<'EOF'
# Validation Checklist

## Before Cutover

- Survey is current and reviewed.
- Unknown labels are resolved or explicitly excluded.
- New DNS records exist alongside current records.
- ACM certificates are ISSUED and cover every target hostname.
- Nginx config renders and passes `nginx -t` in the target environment.
- Load balancer listeners and target groups are healthy.
- Security groups allow only required ingress and egress.
- Application health checks pass through the new domain.
- Synthetic tests confirm redirects, headers, cookies, and CORS behavior.

## During Cutover

- Confirm current DNS answers before change.
- Apply reviewed DNS change outside this toolkit.
- Watch authoritative DNS, recursive DNS, TLS handshake, HTTP status, and application telemetry.
- Keep old records and old Nginx settings available.

## After Cutover

- Confirm no traffic remains unexpectedly on development domains.
- Confirm live domains do not point at development targets.
- Keep rollback window open until business owner signs off.
- Schedule separate cleanup only after logs prove migration stability.
EOF
}

write_rollback_plan() {
  local output="${PLAN_DIR}/rollback-plan.md"
  cat > "$output" <<'EOF'
# Rollback Plan

## Trigger Conditions

- Elevated 5xx, 4xx, latency, or TLS failures.
- Incorrect DNS answers from authoritative or recursive resolvers.
- Application owner reports broken workflows.
- Security or compliance issue with the new routing path.

## Rollback Steps

1. Stop further migration changes.
2. Restore previous DNS alias or CNAME target using the approved change system.
3. Keep new records in place only if they do not receive user traffic.
4. Restore previous Nginx settings if proxy routing is implicated.
5. Validate old domain path with DNS, TLS, HTTP, and application checks.
6. Announce rollback status and capture evidence for post-incident review.

## Important Guardrails

- Do not delete DNS records during rollback.
- Do not revoke certificates during rollback.
- Do not destroy load balancers, instances, target groups, or security groups.
- Prefer reversible routing changes over infrastructure mutation.
EOF
}

write_validation_inputs() {
  local dns_file="${VALIDATION_DIR}/domains.txt"
  local ssl_file="${VALIDATION_DIR}/ssl-domains.txt"
  local route53_file="${VALIDATION_DIR}/route53-dns-tests.tsv"
  : > "$dns_file"
  : > "$ssl_file"
  printf 'zone_id\trecord_name\trecord_type\n' > "$route53_file"
  [[ -f "${PLAN_DIR}/domain-mapping.tsv" ]] || return 0
  tail -n +2 "${PLAN_DIR}/domain-mapping.tsv" | while IFS=$'\t' read -r current_record record_type current_target env suggested confidence notes; do
    [[ "$suggested" != "<needs-owner-review>" ]] || continue
    printf '%s\n' "$suggested" >> "$dns_file"
    printf '%s\n' "$suggested" >> "$ssl_file"
  done
  if [[ -f "${SUMMARY_DIR}/route53-records.tsv" ]]; then
    tail -n +2 "${SUMMARY_DIR}/route53-records.tsv" | while IFS=$'\t' read -r zone_id zone_name record_name record_type ttl targets; do
      case "$record_type" in
        A|AAAA|CNAME) printf '%s\t%s\t%s\n' "$zone_id" "$record_name" "$record_type" >> "$route53_file" ;;
      esac
    done
  fi
}

main() {
  write_labeled_resources
  write_domain_mapping
  write_migration_plan
  write_validation_checklist
  write_rollback_plan
  write_validation_inputs
  printf 'Mapping pass complete. Check %s\n' "$PLAN_DIR"
}

main "$@"
