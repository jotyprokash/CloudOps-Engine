#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
load_settings
ensure_dirs

PLAN_DIR="${ROOT_DIR}/${WORK_DIR}/plans"
REPORT_DIR="${ROOT_DIR}/${WORK_DIR}/report"
REPORT_FILE="${REPORT_DIR}/index.html"
REPORT_TIME="$(timestamp_utc)"

[[ -d "$PLAN_DIR" ]] || {
  printf 'Missing %s. Run bin/map-domains.sh first.\n' "$PLAN_DIR" >&2
  exit 1
}

html_escape() {
  local value="${1:-}"
  value="${value//&/\&amp;}"
  value="${value//</\&lt;}"
  value="${value//>/\&gt;}"
  printf '%s' "$value"
}

report_text() {
  local value="${1:-}"
  value="${value//\`artifacts\/plans\/labeled-resources.md\`/the labeled resources section}"
  value="${value//\`artifacts\/plans\/domain-mapping.md\`/the domain map section}"
  printf '%s' "$value"
}

render_markdown_table() {
  local line
  local header_rendered=false

  printf '<table>\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    [[ "$line" == \|\-\-\-* ]] && continue

    line="${line#|}"
    line="${line%|}"
    IFS='|' read -r -a cells <<< "$line"

    if [[ "$header_rendered" == false ]]; then
      printf '<thead><tr>'
      for cell in "${cells[@]}"; do
        printf '<th>%s</th>' "$(html_escape "$(report_text "$(printf '%s' "$cell" | sed 's/^ *//; s/ *$//')")")"
      done
      printf '</tr></thead>\n<tbody>\n'
      header_rendered=true
    else
      printf '<tr>'
      for cell in "${cells[@]}"; do
        printf '<td>%s</td>' "$(html_escape "$(report_text "$(printf '%s' "$cell" | sed 's/^ *//; s/ *$//')")")"
      done
      printf '</tr>\n'
    fi
  done
  printf '</tbody>\n</table>\n'
  return 0
}

render_markdown_section() {
  local file="$1"
  local line
  local in_list=false
  local in_table=false
  local table_buffer=""
  local first_heading_skipped=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == \|* ]]; then
      table_buffer+="${line}"$'\n'
      in_table=true
      continue
    fi

    if [[ "$in_table" == true ]]; then
      render_markdown_table <<< "$table_buffer"
      table_buffer=""
      in_table=false
    fi

    if [[ -z "$line" ]]; then
      if [[ "$in_list" == true ]]; then
        printf '</ul>\n'
        in_list=false
      fi
      continue
    fi

    case "$line" in
      '## '*)
        [[ "$in_list" == true ]] && { printf '</ul>\n'; in_list=false; }
        printf '<h3>%s</h3>\n' "$(html_escape "$(report_text "${line#\#\# }")")"
        ;;
      '# '*)
        [[ "$in_list" == true ]] && { printf '</ul>\n'; in_list=false; }
        if [[ "$first_heading_skipped" == false ]]; then
          first_heading_skipped=true
          continue
        fi
        printf '<h2>%s</h2>\n' "$(html_escape "$(report_text "${line#\# }")")"
        ;;
      '- '*)
        if [[ "$in_list" == false ]]; then
          printf '<ul>\n'
          in_list=true
        fi
        printf '<li>%s</li>\n' "$(html_escape "$(report_text "${line#- }")")"
        ;;
      [0-9]'. '*)
        if [[ "$in_list" == false ]]; then
          printf '<ul>\n'
          in_list=true
        fi
        printf '<li>%s</li>\n' "$(html_escape "$(report_text "${line#*. }")")"
        ;;
      *)
        [[ "$in_list" == true ]] && { printf '</ul>\n'; in_list=false; }
        printf '<p>%s</p>\n' "$(html_escape "$(report_text "$line")")"
        ;;
    esac
  done < "$file"

  if [[ "$in_table" == true ]]; then
    render_markdown_table <<< "$table_buffer"
  fi

  [[ "$in_list" == true ]] && printf '</ul>\n'
  return 0
}

write_section() {
  local title="$1"
  local file="$2"

  [[ -f "$file" ]] || return 0

  printf '<section class="panel">\n'
  printf '<div class="panel-head">\n'
  printf '<h2>%s</h2>\n' "$(html_escape "$title")"
  printf '</div>\n'
  render_markdown_section "$file"
  printf '</section>\n'
}

main() {
  mkdir -p "$REPORT_DIR"

  {
    cat <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>CloudOps Engine Report</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f7fb;
      --panel: #ffffff;
      --ink: #172033;
      --muted: #5b6477;
      --line: #d8dfeb;
      --accent: #0f6cbd;
      --accent-soft: #eaf3ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font: 15px/1.55 "Segoe UI", "Helvetica Neue", Arial, sans-serif;
      color: var(--ink);
      background:
        radial-gradient(circle at top right, #dcecff 0, transparent 28%),
        linear-gradient(180deg, #f9fbff 0%, var(--bg) 100%);
    }
    main {
      max-width: 1200px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }
    header {
      margin-bottom: 24px;
      padding: 28px 30px;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: linear-gradient(180deg, #ffffff 0%, #f8fbff 100%);
      box-shadow: 0 10px 30px rgba(20, 33, 61, 0.06);
    }
    h1, h2, h3 { margin: 0 0 12px; line-height: 1.2; }
    h1 { font-size: 30px; }
    h2 { font-size: 22px; }
    h3 { font-size: 18px; margin-top: 18px; }
    p { margin: 0 0 12px; }
    .meta {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 16px;
    }
    .meta span {
      padding: 8px 12px;
      border-radius: 999px;
      background: var(--accent-soft);
      color: var(--accent);
      font-size: 13px;
      font-weight: 600;
    }
    .grid {
      display: grid;
      gap: 18px;
    }
	    .panel {
	      padding: 22px;
	      border: 1px solid var(--line);
	      border-radius: 14px;
	      background: var(--panel);
	      box-shadow: 0 8px 24px rgba(20, 33, 61, 0.05);
	      overflow-x: auto;
	    }
	    .panel-head {
	      margin-bottom: 14px;
	      padding-bottom: 10px;
	      border-bottom: 1px solid var(--line);
	    }
    ul {
      margin: 0 0 12px 18px;
      padding: 0;
    }
    li { margin-bottom: 6px; }
	    table {
	      width: 100%;
	      table-layout: fixed;
	      border-collapse: collapse;
	      font-size: 12px;
	      margin: 10px 0 16px;
	    }
	    th, td {
	      padding: 8px 10px;
	      border: 1px solid var(--line);
	      text-align: left;
	      vertical-align: top;
	      overflow-wrap: anywhere;
	      word-break: break-word;
	    }
    th {
      position: sticky;
      top: 0;
      background: #eef4fb;
    }
    tbody tr:nth-child(even) {
      background: #fafcff;
    }
    .note {
      color: var(--muted);
      font-size: 13px;
    }
    @media print {
      body { background: #fff; }
      main { max-width: none; padding: 0; }
      header, .panel { box-shadow: none; }
      .panel { break-inside: avoid; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <h1>CloudOps Engine Report</h1>
      <p>Read-only discovery and domain planning output for review, sharing, and PDF export.</p>
      <div class="meta">
        <span>Written ${REPORT_TIME}</span>
        <span>Printable to PDF</span>
      </div>
      <p class="note">Open this file in a browser and use Print to save a PDF when you need a static handoff.</p>
    </header>
    <div class="grid">
EOF

    write_section "Labeled Resources" "${PLAN_DIR}/labeled-resources.md"
    write_section "Domain Map" "${PLAN_DIR}/domain-mapping.md"
    write_section "Migration Plan" "${PLAN_DIR}/migration-plan.md"
    write_section "Validation Checklist" "${PLAN_DIR}/validation-checklist.md"
    write_section "Rollback Plan" "${PLAN_DIR}/rollback-plan.md"

    cat <<'EOF'
    </div>
  </main>
</body>
</html>
EOF
  } > "$REPORT_FILE"

  printf 'Wrote HTML report to %s\n' "$REPORT_FILE"
}

main "$@"
