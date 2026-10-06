#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/weblate-common.sh"
source "$SCRIPT_DIR/defaults.sh"

usage() {
  cat <<'EOF'
Usage: WEBLATE_TOKEN=... ./scripts/check-components.sh [--help]

Fetches every component in the axonivy Weblate project and prints a Markdown
audit table. Override WEBLATE_API_URL or WEBLATE_PROJECT to target another
Weblate instance or project. Save the report with:

  WEBLATE_TOKEN=... ./scripts/check-components.sh > components.md
EOF
}

validate_arguments() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ $# -ne 0 ]]; then
    usage >&2
    exit 2
  fi
}

markdown_cell() {
  printf '%s' "$1" | tr '\r\n' '  ' | sed 's/|/\\|/g'
}

markdown_link_label() {
  printf '%s' "$1" \
    | tr '\r\n' '  ' \
    | sed -e 's/\\/\\\\/g' -e 's/\[/\\[/g' -e 's/\]/\\]/g' -e 's/|/\\|/g'
}

equality_status() {
  local actual=$1
  local expected=$2

  if [[ -z "$actual" || "$actual" == "null" ]]; then
    printf 'UNKNOWN'
  elif [[ "$actual" == "$expected" ]]; then
    printf 'PASS'
  else
    printf 'FAIL'
  fi
}

component_status() {
  local status
  local result=PASS

  for status in "$@"; do
    case "$status" in
      FAIL) result=FAIL ;;
      UNKNOWN)
        if [[ "$result" == PASS ]]; then
          result=UNKNOWN
        fi
        ;;
    esac
  done
  printf '%s' "$result"
}

format_status() {
  case "$1" in
    PASS) printf '✅ PASS' ;;
    FAIL) printf '❌ FAIL' ;;
    UNKNOWN) printf '❔ UNKNOWN' ;;
  esac
}

render_report_header() {
  printf '# Weblate component audit\n\n'
  printf -- '- Project: `%s`\n' "$(markdown_cell "$PROJECT")"
  printf -- '- Generated: %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
  printf '<details><summary>defaults.json</summary>\n\n'
  printf '```json\n'
  cat "$WEBLATE_DEFAULTS_FILE"
  printf '```\n'
  printf '</details>\n\n'
  printf '| Component | Slug | Languages | License | Commit age (hours) | Source branch | Push branch | Push on commit | VCS backend | New languages | Git strategy | Language filter | File pattern | Indentation | Result |\n'
  printf '| --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |\n'
}

format_indentation() {
  local file_format=$1 file_format_params=$2
  local json_indent json_indent_style yaml_indent indentation_display indentation_check

  case "$file_format" in
    json|json-nested|webextension|i18next|i18nextv4|arb|go-i18n-json|go-i18n-json-v2|formatjs|gotext)
      json_indent=$(jq -r 'if .json_indent == null then empty else (.json_indent | tostring) end' <<<"$file_format_params")
      json_indent_style=$(jq -r '.json_indent_style // empty' <<<"$file_format_params")
      indentation_display="${json_indent:-unknown} ${json_indent_style:-unknown}"
      indentation_check=$(component_status \
        "$(equality_status "$json_indent" "$(weblate_default json_indent)")" \
        "$(equality_status "$json_indent_style" "$(weblate_default json_indent_style)")")
      ;;
    yaml|ruby-yaml)
      yaml_indent=$(jq -r 'if .yaml_indent == null then empty else (.yaml_indent | tostring) end' <<<"$file_format_params")
      indentation_display="${yaml_indent:-unknown} spaces"
      indentation_check=$(equality_status "$yaml_indent" "$(weblate_default yaml_indent)")
      ;;
    *)
      indentation_display=N/A
      indentation_check=UNKNOWN
      ;;
  esac

  printf '%s\t%s\n' "$indentation_display" "$indentation_check"
}

render_component_markdown() {
  local component=$1
  local name slug component_url license commit_age source_branch push_branch push_on_commit vcs new_lang merge_style language_filter
  local filemask source_language file_format file_format_params
  local filemask_display translated_languages languages_display indentation_display indentation_check
  local license_check age_check source_branch_check branch_check push_check vcs_check new_lang_check strategy_check language_check status
  local license_display commit_age_display source_branch_display branch_display push_display vcs_display new_lang_display merge_display language_display

  name=$(jq -r '.name // .slug // "(unnamed)"' <<<"$component")
  slug=$(jq -r '.slug // "(missing)"' <<<"$component")
  component_url=$(jq -r '.web_url // empty' <<<"$component")
  if [[ -z "$component_url" ]]; then
    component_url="${API_ORIGIN}/projects/${PROJECT}/${slug}/"
  fi
  license=$(jq -r '.license // empty' <<<"$component")
  commit_age=$(jq -r 'if has("commit_pending_age") and .commit_pending_age != null then (.commit_pending_age | tostring) else empty end' <<<"$component")
  source_branch=$(jq -r '.branch // empty' <<<"$component")
  push_branch=$(jq -r '.push_branch // empty' <<<"$component")
  push_on_commit=$(jq -r 'if has("push_on_commit") and .push_on_commit != null then (.push_on_commit | tostring | ascii_downcase) else empty end' <<<"$component")
  vcs=$(jq -r '.vcs // empty' <<<"$component")
  new_lang=$(jq -r '.new_lang // empty' <<<"$component")
  merge_style=$(jq -r '.merge_style // empty | ascii_downcase' <<<"$component")
  language_filter=$(jq -r '.language_regex // empty' <<<"$component")
  filemask=$(jq -r '.filemask // empty' <<<"$component")
  file_format=$(jq -r '.file_format // empty' <<<"$component")
  file_format_params=$(jq -c '.file_format_params // {}' <<<"$component")
  source_language=$(jq -r 'if (.source_language | type) == "object" then (.source_language.code // empty) else (.source_language // empty) end' <<<"$component")
  filemask_display=${filemask:-unknown}
  translated_languages=$(weblate_fetch_component_languages "$component" "$source_language")
  languages_display="${source_language:-unknown} > ${translated_languages:-none}"

  IFS=$'\t' read -r indentation_display indentation_check \
    <<<"$(format_indentation "$file_format" "$file_format_params")"

  license_check=$(equality_status "$license" "$(weblate_default license)")
  age_check=$(equality_status "$commit_age" "$(weblate_default commit_pending_age)")
  source_branch_check=$(equality_status "$source_branch" "$(weblate_default source_branch)")
  branch_check=$(equality_status "$push_branch" "$(weblate_default push_branch)")
  push_check=$(equality_status "$push_on_commit" "$(weblate_default push_on_commit)")
  vcs_check=$(equality_status "$vcs" "$(weblate_default vcs)")
  new_lang_check=$(equality_status "$new_lang" "$(weblate_default new_lang)")
  strategy_check=$(equality_status "$merge_style" "$(weblate_default merge_style)")
  language_check=$(equality_status "$language_filter" "$(weblate_default language_regex)")
  status=$(component_status "$license_check" "$age_check" "$source_branch_check" "$branch_check" "$push_check" "$vcs_check" "$new_lang_check" "$indentation_check" "$strategy_check" "$language_check")

  if [[ "$status" == FAIL ]]; then
    FAILED_COMPONENTS=$((FAILED_COMPONENTS + 1))
  elif [[ "$status" == UNKNOWN ]]; then
    UNKNOWN_COMPONENTS=$((UNKNOWN_COMPONENTS + 1))
  fi

  license_display=${license:-unknown}
  commit_age_display=${commit_age:-unknown}
  source_branch_display=${source_branch:-unknown}
  branch_display=${push_branch:-unknown}
  push_display=${push_on_commit:-unknown}
  vcs_display=${vcs:-unknown}
  new_lang_display=${new_lang:-unknown}
  merge_display=${merge_style:-unknown}
  language_display=${language_filter:-unknown}

  printf '| %s | `%s` | %s | %s (%s) | %s (%s) | %s (%s) | %s (%s) | %s (%s) | %s (%s) | %s (%s) | %s (%s) | `%s` (%s) | `%s` | %s (%s) | **%s** |\n' \
    "[$(markdown_link_label "$name")](<$(markdown_cell "$component_url")>)" \
    "$(markdown_cell "$slug")" \
    "$(markdown_cell "$languages_display")" \
    "$(markdown_cell "$license_display")" "$(format_status "$license_check")" \
    "$(markdown_cell "$commit_age_display")" "$(format_status "$age_check")" \
    "$(markdown_cell "$source_branch_display")" "$(format_status "$source_branch_check")" \
    "$(markdown_cell "$branch_display")" "$(format_status "$branch_check")" \
    "$(markdown_cell "$push_display")" "$(format_status "$push_check")" \
    "$(markdown_cell "$vcs_display")" "$(format_status "$vcs_check")" \
    "$(markdown_cell "$new_lang_display")" "$(format_status "$new_lang_check")" \
    "$(markdown_cell "$merge_display")" "$(format_status "$strategy_check")" \
    "$(markdown_cell "$language_display")" "$(format_status "$language_check")" \
    "$(markdown_cell "$filemask_display")" \
    "$(markdown_cell "$indentation_display")" "$(format_status "$indentation_check")" \
    "$(format_status "$status")"
}

render_report_summary() {
  printf '\n## Summary\n\n'
  printf -- '- Components: %s\n' "$COMPONENT_COUNT"
  printf -- '- Failing components: %s\n' "$FAILED_COMPONENTS"
  printf -- '- Components with unverified settings: %s\n' "$UNKNOWN_COMPONENTS"
}

main() {
  local components_json component
  validate_arguments "$@"
  components_json=$(weblate_fetch_component_pages) || return $?

  COMPONENT_COUNT=0
  FAILED_COMPONENTS=0
  UNKNOWN_COMPONENTS=0
  render_report_header

  while IFS= read -r component; do
    [[ -n "$component" ]] || continue
    COMPONENT_COUNT=$((COMPONENT_COUNT + 1))
    render_component_markdown "$component"
  done <<<"$components_json"

  if [[ "$COMPONENT_COUNT" -eq 0 ]]; then
    printf '| No components found | | | | | | | | | | | | | | **❌ FAIL** |\n'
    FAILED_COMPONENTS=1
  fi

  render_report_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi