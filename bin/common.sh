#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_settings() {
  if [[ -f "${ROOT_DIR}/settings/settings.env" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/settings/settings.env"
  fi
  if [[ -f "${ROOT_DIR}/settings/labels.conf" ]]; then
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/settings/labels.conf"
  fi

  INVENTORY_DIR="${INVENTORY_DIR:-inventory}"
  WORK_DIR="${WORK_DIR:-artifacts}"
  DISCOVERY_REGION_MODE="${DISCOVERY_REGION_MODE:-current}"
  DETECT_CONTAINERS="${DETECT_CONTAINERS:-true}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

aws_cli() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" "$@"
  else
    aws "$@"
  fi
}

ensure_dirs() {
  mkdir -p \
    "${ROOT_DIR}/${INVENTORY_DIR}/json" \
    "${ROOT_DIR}/${INVENTORY_DIR}/csv" \
    "${ROOT_DIR}/${INVENTORY_DIR}/summary" \
    "${ROOT_DIR}/${WORK_DIR}/plans" \
    "${ROOT_DIR}/${WORK_DIR}/nginx" \
    "${ROOT_DIR}/${WORK_DIR}/validation"
}

timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

csv_escape() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}

csv_row() {
  local first=true value
  for value in "$@"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    csv_escape "$value"
  done
  printf '\n'
}

write_csv_from_tsv() {
  local input="$1"
  local output="$2"
  local line
  : > "$output"
  while IFS= read -r line || [[ -n "$line" ]]; do
    IFS=$'\t' read -r -a cols <<< "$line"
    csv_row "${cols[@]}" >> "$output"
  done < "$input"
}

normalize() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

contains_token() {
  local haystack pattern
  haystack="$(normalize "$1")"
  shift || true
  for pattern in "$@"; do
    pattern="$(normalize "$pattern")"
    [[ -n "$pattern" ]] || continue
    if [[ "$haystack" == *"$pattern"* ]]; then
      return 0
    fi
  done
  return 1
}

split_words() {
  local value="${1:-}"
  # shellcheck disable=SC2206
  SPLIT_WORDS_RESULT=($value)
}

label_text() {
  local text="${1:-}"
  local live_words stage_words dev_words
  split_words "${LIVE_PATTERNS:-}"
  live_words=("${SPLIT_WORDS_RESULT[@]:-}")
  split_words "${STAGING_PATTERNS:-}"
  stage_words=("${SPLIT_WORDS_RESULT[@]:-}")
  split_words "${DEVELOPMENT_PATTERNS:-}"
  dev_words=("${SPLIT_WORDS_RESULT[@]:-}")

  if contains_token "$text" "${live_words[@]:-}"; then
    printf 'live'
  elif contains_token "$text" "${stage_words[@]:-}"; then
    printf 'staging'
  elif contains_token "$text" "${dev_words[@]:-}"; then
    printf 'development'
  else
    printf 'unknown'
  fi
}

confidence_for_label() {
  case "${1:-unknown}" in
    live|staging|development) printf 'medium' ;;
    *) printf 'none' ;;
  esac
}

json_array_join() {
  local first=true value
  printf '['
  for value in "$@"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    printf '"%s"' "${value//\"/\\\"}"
  done
  printf ']'
}
