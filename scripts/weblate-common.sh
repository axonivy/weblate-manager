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
  local next_url="${API_BASE%/}/projects/${PROJECT}/components/?page_size=1000"
  local response

  while [[ -n "$next_url" ]]; do
    response=$(curl --fail --silent --show-error \
      --header "Authorization: Token ${WEBLATE_TOKEN}" \
      --header 'Accept: application/json' \
      "$next_url")

    if ! jq -e '.results | type == "array"' >/dev/null <<<"$response"; then
      printf 'Unexpected response from Weblate components API.\n' >&2
      return 2
    fi

    jq -c '.results[]' <<<"$response"
    next_url=$(jq -r '.next // empty' <<<"$response")
  done
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
