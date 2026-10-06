API_BASE=${WEBLATE_API_URL:-https://hosted.weblate.org/api}
PROJECT=${WEBLATE_PROJECT:-axonivy}
API_ORIGIN=

weblate_validate_configuration() {
  if [[ -z "${WEBLATE_TOKEN:-}" ]]; then
    printf 'WEBLATE_TOKEN is required.\n' >&2
    return 2
  fi
}

weblate_fetch_component_pages() {
  weblate_validate_configuration
  local next_url="${API_BASE%/}/projects/${PROJECT}/components/?page_size=1000"
  local response

  while [[ -n "$next_url" ]]; do
    response=$(weblate_fetch "$next_url")

    if ! jq -e '.results | type == "array"' >/dev/null <<<"$response"; then
      printf 'Unexpected response from Weblate components API.\n' >&2
      return 2
    fi

    jq -c '.results[]' <<<"$response"
    next_url=$(jq -r '.next // empty' <<<"$response")
  done
}

weblate_fetch() {
  local url=$1
  curl --fail --silent --show-error \
      --header "Authorization: Token ${WEBLATE_TOKEN}" \
      --header 'Accept: application/json' \
      "$url"
}

weblate_fetch_component_languages() {
  local component=$1 source_language=$2
  local translations_url url response

  translations_url=$(jq -r '.translations_url // empty' <<<"$component")
  url=$(weblate_url "$translations_url")
  response=$(weblate_fetch "$url")

  jq -r --arg source "$source_language" \
    '[.results[] | select(.language_code != null and .language_code != $source and .is_source != true) | .language_code] | join(", ")' \
    <<<"$response"
}

weblate_component_api_url() {
  local component=$1 url
  url=$(jq -r '.url // empty' <<<"$component")
  weblate_url "$url"
}

weblate_url() {
  local url=$1
  if [[ -z "${API_ORIGIN:-}" ]]; then
    if [[ "$API_BASE" =~ ^(https?://[^/]+)(/.*)?$ ]]; then
      API_ORIGIN=${BASH_REMATCH[1]}
    else
      printf 'WEBLATE_API_URL must be an absolute HTTP(S) URL.\n' >&2
      return 2
    fi
  fi
  if [[ "$url" == /* ]]; then
    url="${API_ORIGIN}${url}"
  fi
  if [[ "$url" != "$API_ORIGIN"/* ]]; then
    printf 'Refusing API URL outside Weblate API origin: %s\n' "$url" >&2
    return 2
  fi
  printf '%s' "$url"
}
