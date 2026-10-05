#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/defaults.sh"

API_BASE=${WEBLATE_API_URL:-$WEBLATE_DEFAULT_API_URL}
PROJECT=${WEBLATE_PROJECT:-$WEBLATE_DEFAULT_PROJECT}
GITHUB_API_BASE=${GITHUB_API_URL:-https://api.github.com}

usage() {
  cat <<'EOF'
Usage: WEBLATE_TOKEN=... ./onboard-component.sh

Interactively creates a Weblate component. GitHub repository permissions,
GitHub App connection, and webhooks are not changed by this script.
EOF
}

prompt() {
  local label=$1 default=${2:-} answer
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " answer
    REPLY=${answer:-$default}
  else
    read -r -p "$label: " REPLY
  fi
}

prompt_required() {
  local label=$1 default=${2:-}
  while :; do
    prompt "$label" "$default"
    [[ -n "$REPLY" ]] && return
    printf 'A value is required.\n' >&2
  done
}

encode_uri() {
  jq -nr --arg value "$1" '$value | @uri'
}

parse_github_repository() {
  local path
  case "$1" in
    https://github.com/*) path=${1#https://github.com/} ;;
    http://github.com/*) path=${1#http://github.com/} ;;
    git@github.com:*) path=${1#git@github.com:} ;;
    github.com:*) path=${1#github.com:} ;;
    */*) path=$1 ;;
    *) return 1 ;;
  esac
  path=${path%.git}
  path=${path%/}
  if [[ "$path" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
    GITHUB_OWNER=${BASH_REMATCH[1]}
    GITHUB_REPOSITORY=${BASH_REMATCH[2]}
    return 0
  fi
  return 1
}

fetch_github_tree() {
  local tree_url response
  tree_url="$GITHUB_API_BASE/repos/$GITHUB_OWNER/$GITHUB_REPOSITORY/git/trees/$(encode_uri "$BRANCH")?recursive=1"
  response=$(curl --fail --silent --show-error \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' "$tree_url") || return 1
  if ! jq -e '.tree | type == "array"' >/dev/null <<<"$response"; then
    printf 'GitHub returned an unexpected repository tree response.\n' >&2
    return 1
  fi
  if [[ $(jq -r '.truncated // false' <<<"$response") == true ]]; then
    printf 'Warning: GitHub returned a truncated tree; some files may be missing from suggestions.\n' >&2
  fi
  GITHUB_TREE=$response
}

suggest_template() {
  local source_pattern=${FILEMASK/\*/$SOURCE_LANGUAGE} path count=0 first_candidate=
  while IFS= read -r path; do
    if [[ "$path" == $source_pattern ]]; then
      count=$((count + 1))
      [[ -n "$first_candidate" ]] || first_candidate=$path
      printf '  %s\n' "$path"
    fi
  done < <(jq -r '.tree[] | select(.type == "blob") | .path' <<<"$GITHUB_TREE")
  if [[ "$count" -eq 0 ]]; then
    printf 'No file matched the source-language version of the mask (%s).\n' "$source_pattern"
  fi
  TEMPLATE_DEFAULT=
  if [[ "$count" -eq 1 ]]; then
    TEMPLATE_DEFAULT=$first_candidate
  fi
}

detect_i18next_files() {
  local path filemask index
  I18NEXT_MASKS=()
  I18NEXT_TEMPLATES=()
  while IFS= read -r path; do
    filemask="${path%"$SOURCE_LANGUAGE".json}*.json"
    I18NEXT_MASKS+=("$filemask")
    I18NEXT_TEMPLATES+=("$path")
  done < <(jq -r --arg source "$SOURCE_LANGUAGE" \
    '.tree[] | select(.type == "blob") | .path | select(. == ($source + ".json") or endswith("/" + $source + ".json"))' \
    <<<"$GITHUB_TREE")

  if [[ "${#I18NEXT_MASKS[@]}" -eq 0 ]]; then
    printf 'No %s.json files found; enter the translation file mask manually.\n' "$SOURCE_LANGUAGE"
    return
  fi

  printf '\nDetected i18next source files and suggested masks:\n'
  for index in "${!I18NEXT_MASKS[@]}"; do
    printf '  %s (template: %s)\n' "${I18NEXT_MASKS[$index]}" "${I18NEXT_TEMPLATES[$index]}"
  done
  if [[ "${#I18NEXT_MASKS[@]}" -eq 1 ]]; then
    FILEMASK_DEFAULT=${I18NEXT_MASKS[0]}
    TEMPLATE_DEFAULT=${I18NEXT_TEMPLATES[0]}
  fi
}

main() {
  local format_choice backend_choice=$WEBLATE_DEFAULT_VCS repository_url repo_browser push_url push_url_default push_branch
  local component_name component_slug license language_filter payload format_params
  local response http_status response_body project_url task_url template_path
  local FILEMASK_DEFAULT= TEMPLATE_DEFAULT= GITHUB_TREE_AVAILABLE=false

  if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then usage; return 0; fi
  if [[ $# -gt 0 ]]; then usage >&2; return 2; fi
  if [[ -z "${WEBLATE_TOKEN:-}" ]]; then
    printf 'WEBLATE_TOKEN is required.\n' >&2
    return 2
  fi
  if ! command -v curl >/dev/null || ! command -v jq >/dev/null; then
    printf 'Both curl and jq are required.\n' >&2
    return 2
  fi

  prompt_required 'GitHub repository URL or owner/repository'
  repository_url=$REPLY
  if ! parse_github_repository "$repository_url"; then
    printf 'Enter a GitHub URL, SSH URL, or owner/repository.\n' >&2
    return 2
  fi
  if [[ "$repository_url" != http://* && "$repository_url" != https://* && "$repository_url" != git@* ]]; then
    repository_url="git@github.com:${GITHUB_OWNER}/${GITHUB_REPOSITORY}.git"
  fi
  repo_browser="https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/blob/{{branch}}"

  prompt_required 'Repository branch' master
  BRANCH=$REPLY
  prompt_required 'Component name' "$GITHUB_REPOSITORY"
  component_name=$REPLY
  prompt 'Component URL slug' "$(printf '%s' "$component_name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g')"
  component_slug=$REPLY
  if [[ ! "$component_slug" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    printf 'Component slug may contain only letters, digits, period, underscore, and hyphen.\n' >&2
    return 2
  fi
  push_url_default="git@github.com:${GITHUB_OWNER}/${GITHUB_REPOSITORY}.git"

  prompt 'File format (i18next, i18nextv4, yaml)' i18next
  format_choice=$REPLY
  case "$format_choice" in
    i18next|i18nextv4|yaml) ;;
    *) printf 'Unsupported format identifier: %s\n' "$format_choice" >&2; return 2 ;;
  esac
  case "$format_choice" in
    i18next|i18nextv4)
      format_params=$(jq -n \
        --argjson indent "$WEBLATE_DEFAULT_JSON_INDENT" \
        --arg style "$WEBLATE_DEFAULT_JSON_INDENT_STYLE" \
        '{json_indent:$indent,json_indent_style:$style}')
      ;;
    yaml)
      format_params=$(jq -n \
        --argjson indent "$WEBLATE_DEFAULT_YAML_INDENT" \
        '{yaml_indent:$indent}')
      ;;
  esac
  prompt_required 'Source language code' en
  SOURCE_LANGUAGE=$REPLY

  if fetch_github_tree; then
    GITHUB_TREE_AVAILABLE=true
    if [[ "$format_choice" == i18next || "$format_choice" == i18nextv4 ]]; then
      detect_i18next_files
    fi
  else
    printf 'Could not inspect the GitHub tree; enter the translation paths manually.\n' >&2
  fi

  prompt_required 'Translation file mask (include *)' "$FILEMASK_DEFAULT"
  FILEMASK=$REPLY
  if [[ "$FILEMASK" != *\** ]]; then
    printf 'The file mask must contain at least one * wildcard.\n' >&2
    return 2
  fi

  if [[ "$GITHUB_TREE_AVAILABLE" == true ]]; then
    printf '\nSource-language file candidates for %s:\n' "$FILEMASK"
    suggest_template
  else
    TEMPLATE_DEFAULT=
  fi
  prompt_required 'Base-language file path (template)' "${TEMPLATE_DEFAULT:-}"
  template_path=$REPLY

  prompt 'Repository push URL (enter - to disable direct push)' "$push_url_default"
  push_url=$REPLY
  [[ "$push_url" != '-' ]] || push_url=
  prompt 'Push branch' "$WEBLATE_DEFAULT_PUSH_BRANCH"
  push_branch=$REPLY
  prompt 'Translation license' Apache-2.0
  license=$REPLY
  prompt 'Language filter' "$WEBLATE_DEFAULT_LANGUAGE_REGEX"
  language_filter=$REPLY

  payload=$(jq -n \
    --arg name "$component_name" --arg slug "$component_slug" \
    --arg repo "$repository_url" --arg branch "$BRANCH" \
    --arg repoweb "$repo_browser" \
    --arg filemask "$FILEMASK" --arg template "$template_path" \
    --arg file_format "$format_choice" --arg vcs "$backend_choice" \
    --arg push "$push_url" --arg push_branch "$push_branch" \
    --arg source_language "$SOURCE_LANGUAGE" --arg license "$license" \
    --argjson file_format_params "$format_params" \
    --argjson push_on_commit "$WEBLATE_DEFAULT_PUSH_ON_COMMIT" \
    --argjson commit_pending_age "$WEBLATE_DEFAULT_COMMIT_PENDING_AGE" \
    --arg merge_style "$WEBLATE_DEFAULT_MERGE_STYLE" \
    --arg language_regex "$language_filter" \
    --arg new_lang "$WEBLATE_DEFAULT_NEW_LANG" \
    '{name:$name,slug:$slug,repo:$repo,branch:$branch,repoweb:$repoweb,filemask:$filemask,template:$template,file_format:$file_format,file_format_params:$file_format_params,vcs:$vcs,push:$push,push_branch:$push_branch,source_language:$source_language,license:$license,new_lang:$new_lang,edit_template:true,push_on_commit:$push_on_commit,commit_pending_age:$commit_pending_age,merge_style:$merge_style,auto_lock_error:true,language_regex:$language_regex}')

  printf '\nComponent configuration to create:\n'
  jq . <<<"$payload"
  read -r -p 'Create this component in Weblate? [y/N] ' REPLY
  case "$REPLY" in
    y|Y|yes|YES) ;;
    *) printf 'Cancelled; Weblate was not changed.\n'; return 0 ;;
  esac

  project_url="${API_BASE%/}/projects/$(encode_uri "$PROJECT")/components/"
  response=$(curl --silent --show-error --output - --write-out $'\n%{http_code}' \
    --request POST \
    --header "Authorization: Token ${WEBLATE_TOKEN}" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data-binary "$payload" "$project_url") || return 1
  http_status=${response##*$'\n'}
  response_body=${response%$'\n'*}
  if [[ ! "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    printf 'Weblate component creation failed (HTTP %s):\n%s\n' "$http_status" "$response_body" >&2
    return 1
  fi
  if ! jq -e 'type == "object"' >/dev/null <<<"$response_body"; then
    printf 'Weblate returned an unexpected response:\n%s\n' "$response_body" >&2
    return 1
  fi

  printf '\nComponent created: %s\n' "$(jq -r '.web_url // .url // "(URL not returned)"' <<<"$response_body")"
  task_url=$(jq -r '.task_url // empty' <<<"$response_body")
  [[ -z "$task_url" ]] || printf 'Background setup task: %s\n' "$task_url"
  printf '\nGitHub setup is not automated. Confirm repository access and notifications manually.\n'
  printf 'Hosted Weblate recommends connecting its GitHub App in the workspace.\n'
  printf 'For the legacy SSH workflow, grant the Hosted Weblate user repository access and configure https://hosted.weblate.org/hooks/github/.\n'
  printf 'The GitHub pull-request backend also requires GitHub API credentials configured for this Weblate instance.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi