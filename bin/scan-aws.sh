#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
require_cmd aws
ensure_dirs

JSON_DIR="${ROOT_DIR}/${INVENTORY_DIR}/json"
CSV_DIR="${ROOT_DIR}/${INVENTORY_DIR}/csv"
SUMMARY_DIR="${ROOT_DIR}/${INVENTORY_DIR}/summary"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"

log() {
  printf '[%s] %s\n' "$(timestamp_utc)" "$*" >&2
}

regions() {
  if [[ -n "${DISCOVERY_REGIONS:-}" ]]; then
    printf '%s' "$DISCOVERY_REGIONS" | tr ',' '\n'
    return
  fi

  if [[ "$DISCOVERY_REGION_MODE" == "all" ]]; then
    aws_cli ec2 describe-regions \
      --all-regions \
      --query 'Regions[?OptInStatus==`opt-in-not-required` || OptInStatus==`opted-in`].RegionName' \
      --output text | tr '\t' '\n'
  else
    local profile_region
    profile_region="$(aws_cli configure get region 2>/dev/null || true)"
    printf '%s\n' "${AWS_REGION:-${AWS_DEFAULT_REGION:-${profile_region:-us-east-1}}}"
  fi
}

write_metadata() {
  local region_json
  mapfile -t region_json < <(regions)
  {
    printf '{\n'
    printf '  "written_at": "%s",\n' "$(timestamp_utc)"
    printf '  "run_id": "%s",\n' "$RUN_ID"
    printf '  "region_mode": "%s",\n' "$DISCOVERY_REGION_MODE"
    printf '  "regions": '
    json_array_join "${region_json[@]}"
    printf ',\n'
    printf '  "safety": "read-only discovery; no mutating AWS APIs are used"\n'
    printf '}\n'
  } > "${JSON_DIR}/metadata.json"
}

discover_route53() {
  log "Discovering Route53 hosted zones and records"
  aws_cli route53 list-hosted-zones --output json > "${JSON_DIR}/route53-hosted-zones.json"

  local zones_tsv records_tsv zone_id zone_name record_file
  zones_tsv="${SUMMARY_DIR}/route53-hosted-zones.tsv"
  records_tsv="${SUMMARY_DIR}/route53-records.tsv"
  printf 'zone_id\tzone_name\tprivate_zone\trecord_count\tcomment\n' > "$zones_tsv"
  printf 'zone_id\tzone_name\trecord_name\trecord_type\tttl\ttargets\n' > "$records_tsv"

  aws_cli route53 list-hosted-zones \
    --query 'HostedZones[].[Id,Name,Config.PrivateZone,ResourceRecordSetCount,Config.Comment]' \
    --output text |
    while IFS=$'\t' read -r zone_id zone_name private_zone count comment; do
      [[ -n "${zone_id:-}" ]] || continue
      zone_id="${zone_id#/hostedzone/}"
      printf '%s\t%s\t%s\t%s\t%s\n' "$zone_id" "$zone_name" "$private_zone" "$count" "${comment:-}" >> "$zones_tsv"
      record_file="${JSON_DIR}/route53-records-${zone_id}.json"
      aws_cli route53 list-resource-record-sets --hosted-zone-id "$zone_id" --output json > "$record_file"
      aws_cli route53 list-resource-record-sets \
        --hosted-zone-id "$zone_id" \
        --query 'ResourceRecordSets[].[Name,Type,TTL,join(`;`,not_null(ResourceRecords[].Value, [``])),AliasTarget.DNSName]' \
        --output text |
        while IFS=$'\t' read -r record_name record_type ttl records alias; do
          [[ -n "${record_name:-}" ]] || continue
          local targets="${records:-}"
          if [[ -n "${alias:-}" && "$alias" != "None" ]]; then
            targets="ALIAS:${alias}"
          fi
          printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$zone_id" "$zone_name" "$record_name" "$record_type" "${ttl:-}" "$targets" >> "$records_tsv"
        done
    done

  write_csv_from_tsv "$zones_tsv" "${CSV_DIR}/route53-hosted-zones.csv"
  write_csv_from_tsv "$records_tsv" "${CSV_DIR}/route53-records.csv"
}

discover_region() {
  local region="$1"
  log "Discovering regional resources in ${region}"

  aws_cli acm list-certificates --region "$region" --certificate-statuses PENDING_VALIDATION ISSUED INACTIVE EXPIRED VALIDATION_TIMED_OUT REVOKED FAILED --output json > "${JSON_DIR}/acm-certificates-${region}.json"
  aws_cli ec2 describe-instances --region "$region" --output json > "${JSON_DIR}/ec2-instances-${region}.json"
  aws_cli ec2 describe-security-groups --region "$region" --output json > "${JSON_DIR}/security-groups-${region}.json"
  aws_cli ec2 describe-addresses --region "$region" --output json > "${JSON_DIR}/elastic-ips-${region}.json"
  aws_cli elbv2 describe-load-balancers --region "$region" --output json > "${JSON_DIR}/load-balancers-${region}.json"
  aws_cli elbv2 describe-target-groups --region "$region" --output json > "${JSON_DIR}/target-groups-${region}.json"

  aws_cli acm list-certificates \
    --region "$region" \
    --certificate-statuses PENDING_VALIDATION ISSUED INACTIVE EXPIRED VALIDATION_TIMED_OUT REVOKED FAILED \
    --query 'CertificateSummaryList[].[DomainName,Status,Type,InUse,CertificateArn]' \
    --output text |
    while IFS=$'\t' read -r domain status type in_use arn; do
      [[ -n "${arn:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$domain" "$status" "$type" "$in_use" "$arn" >> "${SUMMARY_DIR}/acm-certificates.tsv"
    done

  aws_cli ec2 describe-instances \
    --region "$region" \
    --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`]|[0].Value,State.Name,PrivateIpAddress,PublicIpAddress,Tags[?Key==`Environment`]|[0].Value]' \
    --output text |
    while IFS=$'\t' read -r instance_id name state private_ip public_ip environment; do
      [[ -n "${instance_id:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$instance_id" "${name:-}" "$state" "${private_ip:-}" "${public_ip:-}" "Environment=${environment:-}" >> "${SUMMARY_DIR}/ec2-instances.tsv"
    done

  aws_cli elbv2 describe-load-balancers \
    --region "$region" \
    --query 'LoadBalancers[].[LoadBalancerName,DNSName,Type,Scheme,State.Code,LoadBalancerArn]' \
    --output text |
    while IFS=$'\t' read -r name dns type scheme state arn; do
      [[ -n "${name:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$name" "$dns" "$type" "$scheme" "$state" "$arn" >> "${SUMMARY_DIR}/load-balancers.tsv"
    done

  aws_cli elbv2 describe-target-groups \
    --region "$region" \
    --query 'TargetGroups[].[TargetGroupName,Protocol,Port,TargetType,join(`;`,LoadBalancerArns),TargetGroupArn]' \
    --output text |
    while IFS=$'\t' read -r name protocol port target_type lb_arns arn; do
      [[ -n "${name:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$name" "$protocol" "$port" "$target_type" "$lb_arns" "$arn" >> "${SUMMARY_DIR}/target-groups.tsv"
    done

  aws_cli ec2 describe-security-groups \
    --region "$region" \
    --query 'SecurityGroups[].[GroupId,GroupName,VpcId,Description,Tags[?Key==`Environment`]|[0].Value]' \
    --output text |
    while IFS=$'\t' read -r group_id name vpc_id desc environment; do
      [[ -n "${group_id:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$group_id" "$name" "$vpc_id" "${desc:-}" "Environment=${environment:-}" >> "${SUMMARY_DIR}/security-groups.tsv"
    done

  aws_cli ec2 describe-addresses \
    --region "$region" \
    --query 'Addresses[].[PublicIp,AllocationId,AssociationId,InstanceId,NetworkInterfaceId,Tags[?Key==`Environment`]|[0].Value]' \
    --output text |
    while IFS=$'\t' read -r public_ip allocation_id association_id instance_id network_interface_id environment; do
      [[ -n "${public_ip:-}" ]] || continue
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$region" "$public_ip" "${allocation_id:-}" "${association_id:-}" "${instance_id:-}" "${network_interface_id:-}" "Environment=${environment:-}" >> "${SUMMARY_DIR}/elastic-ips.tsv"
    done

  if [[ "$DETECT_CONTAINERS" == "true" ]]; then
    aws_cli ecs list-clusters --region "$region" --output json > "${JSON_DIR}/ecs-clusters-${region}.json" || true
    aws_cli eks list-clusters --region "$region" --output json > "${JSON_DIR}/eks-clusters-${region}.json" || true
    aws_cli ecs list-clusters --region "$region" --query 'clusterArns[]' --output text 2>/dev/null | tr '\t' '\n' |
      while IFS= read -r cluster_arn; do
        [[ -n "$cluster_arn" ]] || continue
        printf '%s\tecs\t%s\n' "$region" "$cluster_arn" >> "${SUMMARY_DIR}/containers.tsv"
      done
    aws_cli eks list-clusters --region "$region" --query 'clusters[]' --output text 2>/dev/null | tr '\t' '\n' |
      while IFS= read -r cluster_name; do
        [[ -n "$cluster_name" ]] || continue
        printf '%s\teks\t%s\n' "$region" "$cluster_name" >> "${SUMMARY_DIR}/containers.tsv"
      done
  fi
}

main() {
  log "Starting read-only discovery run ${RUN_ID}"
  write_metadata

  printf 'region\tdomain\tstatus\ttype\tin_use\tcertificate_arn\n' > "${SUMMARY_DIR}/acm-certificates.tsv"
  printf 'region\tinstance_id\tname\tstate\tprivate_ip\tpublic_ip\ttags\n' > "${SUMMARY_DIR}/ec2-instances.tsv"
  printf 'region\tname\tdns_name\ttype\tscheme\tstate\tload_balancer_arn\n' > "${SUMMARY_DIR}/load-balancers.tsv"
  printf 'region\tname\tprotocol\tport\ttarget_type\tload_balancer_arns\ttarget_group_arn\n' > "${SUMMARY_DIR}/target-groups.tsv"
  printf 'region\tgroup_id\tname\tvpc_id\tdescription\ttags\n' > "${SUMMARY_DIR}/security-groups.tsv"
  printf 'region\tpublic_ip\tallocation_id\tassociation_id\tinstance_id\tnetwork_interface_id\ttags\n' > "${SUMMARY_DIR}/elastic-ips.tsv"
  printf 'region\tplatform\tidentifier\n' > "${SUMMARY_DIR}/containers.tsv"

  discover_route53

  local region
  while IFS= read -r region; do
    [[ -n "$region" ]] || continue
    discover_region "$region"
  done < <(regions)

  for tsv in "${SUMMARY_DIR}"/*.tsv; do
    write_csv_from_tsv "$tsv" "${CSV_DIR}/$(basename "${tsv%.tsv}").csv"
  done

  log "Discovery complete. JSON: ${JSON_DIR}; CSV: ${CSV_DIR}; summaries: ${SUMMARY_DIR}"
}

main "$@"
