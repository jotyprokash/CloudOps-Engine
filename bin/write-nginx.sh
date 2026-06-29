#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
ensure_dirs

PLAN_TSV="${ROOT_DIR}/${WORK_DIR}/plans/domain-mapping.tsv"
OUT_DIR="${ROOT_DIR}/${WORK_DIR}/nginx"
SERVER_TEMPLATE="${ROOT_DIR}/nginx/snippets/nginx-server.conf.tpl"
UPSTREAM_TEMPLATE="${ROOT_DIR}/nginx/snippets/nginx-upstream.conf.tpl"

usage() {
  cat <<'EOF'
Usage: bin/write-nginx.sh [--upstream http://__UPSTREAM_HOST__:__UPSTREAM_PORT__] [--cert /path/to/fullchain.pem] [--key /path/to/privkey.pem]

Writes generic Nginx configs from artifacts/plans/domain-mapping.tsv.
Review the files before deployment.
EOF
}

UPSTREAM="${UPSTREAM:-http://__UPSTREAM_HOST__:__UPSTREAM_PORT__}"
SSL_CERTIFICATE_PATH="${SSL_CERTIFICATE_PATH:-/path/to/fullchain.pem}"
SSL_CERTIFICATE_KEY_PATH="${SSL_CERTIFICATE_KEY_PATH:-/path/to/privkey.pem}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upstream) UPSTREAM="$2"; shift 2 ;;
    --cert) SSL_CERTIFICATE_PATH="$2"; shift 2 ;;
    --key) SSL_CERTIFICATE_KEY_PATH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 1 ;;
  esac
done

[[ -f "$PLAN_TSV" ]] || {
  printf 'Missing %s. Run bin/map-domains.sh first.\n' "$PLAN_TSV" >&2
  exit 1
}

safe_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/[.]/_/g'
}

render_template() {
  local template="$1" output="$2" server_name="$3" safe="$4" upstream="$5"
  sed \
    -e "s#__SERVER_NAME__#${server_name}#g" \
    -e "s#__SAFE_NAME__#${safe}#g" \
    -e "s#__UPSTREAM__#${upstream}#g" \
    -e "s#__SSL_CERTIFICATE_PATH__#${SSL_CERTIFICATE_PATH}#g" \
    -e "s#__SSL_CERTIFICATE_KEY_PATH__#${SSL_CERTIFICATE_KEY_PATH}#g" \
    "$template" > "$output"
}

render_upstream() {
  local output="$1"
  sed \
    -e "s#__UPSTREAM_NAME__#domain_env_backend#g" \
    -e "s#__UPSTREAM_TARGET__#${UPSTREAM#http://}#g" \
    "$UPSTREAM_TEMPLATE" > "$output"
}

main() {
  mkdir -p "$OUT_DIR"
  render_upstream "${OUT_DIR}/upstream.conf"

  local count=0
  tail -n +2 "$PLAN_TSV" | while IFS=$'\t' read -r current_record record_type current_target env suggested confidence notes; do
    [[ -n "${suggested:-}" && "$suggested" != "<needs-owner-review>" ]] || continue
    case "${NGINX_RENDER_MIN_CONFIDENCE:-low}:${confidence}" in
      low:medium|low:high|low:low|unknown:*|medium:medium|medium:high|high:high) ;;
      *) continue ;;
    esac
    local safe
    safe="$(safe_name "$suggested")"
    render_template "$SERVER_TEMPLATE" "${OUT_DIR}/${safe}.conf" "$suggested" "$safe" "$UPSTREAM"
    count=$((count + 1))
  done

  cat > "${OUT_DIR}/README.txt" <<EOF
Nginx files written by this kit need operator review.

Before deployment:
- Replace placeholder certificate paths.
- Replace placeholder upstreams.
- Run nginx -t in the target environment.
- Deploy through your normal reviewed configuration pipeline.
- Keep old configs available for rollback.
EOF

  printf 'Wrote Nginx files in %s\n' "$OUT_DIR"
}

main "$@"
