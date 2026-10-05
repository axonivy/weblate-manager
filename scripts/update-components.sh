#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/weblate-common.sh"

IGNORED_COMPONENTS=('axonivy/glossary')

is_ignored_component() {
  local component=$1 slug ignored_component
  slug=$(jq -r '.slug // empty' <<<"$component")

  for ignored_component in "${IGNORED_COMPONENTS[@]}"; do
    [[ "${PROJECT}/${slug}" == "$ignored_component" ]] && return 0
  done
  return 1
}

choose_component_scope() {
  local component name slug choice selection= selected_index=-1
  local -a choices=('All components')

  for component in "${COMPONENTS[@]}"; do
    name=$(jq -r '.name // .slug // "(unnamed)"' <<<"$component")
    slug=$(jq -r '.slug // "(no slug)"' <<<"$component")
    choices+=("$name ($slug)")
  done
  choices+=('Quit')

  PS3='Choose component(s) to update: '
  select choice in "${choices[@]}"; do
    if [[ ! "$REPLY" =~ ^[0-9]+$ ]] || ((REPLY < 1 || REPLY > ${#choices[@]})); then
      printf 'Choose one of the listed numbers.\n' >&2
      continue
    fi
    if ((REPLY == 1)); then
      selection=all
    elif ((REPLY == ${#choices[@]})); then
      selection=quit
    else
      selection=one
      selected_index=$((REPLY - 2))
    fi
    break
  done

  if [[ -z "$selection" ]]; then
    printf 'No component selected.\n' >&2
    return 1
  fi
  if [[ "$selection" == quit ]]; then
    return 2
  fi

  if [[ "$selection" == all ]]; then
    TARGET_COMPONENTS=("${COMPONENTS[@]}")
    REFERENCE_CONFIG=${COMPONENTS[0]}
  else
    TARGET_COMPONENTS=("${COMPONENTS[$selected_index]}")
    REFERENCE_CONFIG=${COMPONENTS[$selected_index]}
  fi
}

read_update_definition() {
  local new_value

  printf '\nCurrent component configuration:\n'
  jq . <<<"$REFERENCE_CONFIG"
  if ! IFS= read -r -p 'JSON key to change: ' UPDATE_KEY; then
    printf 'No key entered.\n' >&2
    return 1
  fi
  if ! jq -e --arg key "$UPDATE_KEY" 'has($key)' >/dev/null <<<"$REFERENCE_CONFIG"; then
    printf 'Unknown key. Available top-level keys: %s\n' \
      "$(jq -r 'keys | join(", ")' <<<"$REFERENCE_CONFIG")" >&2
    return 2
  fi

  if ! IFS= read -r -p 'New value (JSON): ' new_value; then
    printf 'No value entered.\n' >&2
    return 1
  fi
  if ! UPDATE_PAYLOAD=$(jq -cn --arg key "$UPDATE_KEY" --argjson value "$new_value" '{($key):$value}'); then
    printf 'Enter a valid JSON value.\n' >&2
    return 2
  fi
}

update_component() {
  local component=$1 slug response http_status response_body
  slug=$(jq -r '.name' <<<"$component")

  if ! response=$(curl --silent --show-error --output - --write-out $'\n%{http_code}' \
    --request PATCH \
    --header "Authorization: Token ${WEBLATE_TOKEN}" \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data-binary "$(jq -c '.patch' <<<"$component")" \
    "$(jq -r '.url' <<<"$component")"); then
    printf 'Failed to update %s.\n' "$slug" >&2
    return 1
  fi

  http_status=${response##*$'\n'}
  response_body=${response%$'\n'*}
  if [[ "$http_status" =~ ^2[0-9][0-9]$ ]]; then
    printf 'Updated %s.\n' "$slug"
    return 0
  fi

  printf 'Failed to update %s (HTTP %s): %s\n' "$slug" "$http_status" "$response_body" >&2
  return 1
}

create_update_plan() {
  local key=$1 payload=$2
  local component component_url plan_entry plan='' slug old_value new_value count=0

  for component in "${TARGET_COMPONENTS[@]}"; do
    if ! jq -e --arg key "$key" 'has($key)' >/dev/null <<<"$component"; then
      slug=$(jq -r '.slug // .name // "(unnamed)"' <<<"$component")
      printf 'Component %s has no key %s. Nothing was updated.\n' "$slug" "$key" >&2
      return 2
    fi
    if ! component_url=$(weblate_component_api_url "$component"); then
      return 2
    fi

    if ! plan_entry=$(jq -cn --argjson component "$component" --arg url "$component_url" \
      --arg key "$key" --argjson patch "$payload" \
      '{name:($component.name // $component.slug // "(unnamed)"),url:$url,old:$component[$key],patch:$patch}'); then
      return 2
    fi
    [[ -z "$plan" ]] || plan+=$'\n'
    plan+="$plan_entry"
    count=$((count + 1))
  done

  UPDATE_PLAN=$plan
  printf '\nPlanned update for %s component(s):\n' "$count"
  while IFS= read -r component; do
    slug=$(jq -r '.name' <<<"$component")
    old_value=$(jq -r '.old | tojson' <<<"$component")
    new_value=$(jq -r --arg key "$key" '.patch[$key] | tojson' <<<"$component")
    printf '  %s: %s -> %s\n' "$slug" "$old_value" "$new_value"
  done <<<"$UPDATE_PLAN"
}

main() {
  local components_json component answer failed=0 selection_status

  weblate_validate_configuration || return $?

  components_json=$(weblate_fetch_component_pages) || return $?

  COMPONENTS=()
  while IFS= read -r component; do
    [[ -n "$component" ]] || continue
    is_ignored_component "$component" || COMPONENTS+=("$component")
  done <<<"$components_json"
  if [[ "${#COMPONENTS[@]}" -eq 0 ]]; then
    printf 'No components available for updates.\n' >&2
    return 1
  fi

  if choose_component_scope; then
    :
  else
    selection_status=$?
    [[ "$selection_status" -eq 2 ]] && return 0
    return "$selection_status"
  fi

  read_update_definition || return $?
  create_update_plan "$UPDATE_KEY" "$UPDATE_PAYLOAD" || return $?

  read -r -p 'Send this update to Weblate? [y/N] ' answer || answer=
  case "$answer" in
    y|Y|yes|YES) ;;
    *) printf 'Cancelled; Weblate was not changed.\n'; return 0 ;;
  esac

  while IFS= read -r component; do
    update_component "$component" || failed=1
  done <<<"$UPDATE_PLAN"

  return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi