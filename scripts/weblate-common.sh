WEBLATE_COMMON_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$WEBLATE_COMMON_DIR/defaults.sh"

API_BASE=${WEBLATE_API_URL:-$WEBLATE_DEFAULT_API_URL}
PROJECT=${WEBLATE_PROJECT:-$WEBLATE_DEFAULT_PROJECT}
API_ORIGIN=

weblate_validate_configuration() {
  if [[ -z "${WEBLATE_TOKEN:-}" ]]; then
    printf 'WEBLATE_TOKEN is required.\n' >&2
    return 2
  fi

  API_BASE=${WEBLATE_API_URL:-$WEBLATE_DEFAULT_API_URL}
  PROJECT=${WEBLATE_PROJECT:-$WEBLATE_DEFAULT_PROJECT}
if [[ "$API_BASE" =~ ^(https?://[^/]+)(/.*)?$ ]]; then
  API_ORIGIN=${BASH_REMATCH[1]}
else
  printf 'WEBLATE_API_URL must be an absolute HTTP(S) URL.\n' >&2
  return 2
fi
}

weblate_fetch_component_pages() {
  local output_file=$1
  local next_url="${API_BASE%/}/projects/${PROJECT}/components/?page_size=1000"
  local response

  : >"$output_file"
  while [[ -n "$next_url" ]]; do
    if [[ "$next_url" != "$API_ORIGIN"/* ]]; then
      printf 'Refusing pagination URL outside Weblate API origin: %s\n' "$next_url" >&2
      return 2
    fi

    response=$(curl --fail --silent --show-error \
      --header "Authorization: Token ${WEBLATE_TOKEN}" \
      --header 'Accept: application/json' \
      "$next_url")

    if ! jq -e '.results | type == "array"' >/dev/null <<<"$response"; then
      printf 'Unexpected response from Weblate components API.\n' >&2
      return 2
    fi

    jq -c '.results[]' <<<"$response" >>"$output_file"
    next_url=$(jq -r '.next // empty' <<<"$response")
  done
}

weblate_component_api_url() {
  local component=$1 url
  url=$(jq -r '.url // empty' <<<"$component")
  if [[ "$url" == /* ]]; then
    url="${API_ORIGIN}${url}"
  fi
  if [[ "$url" != "$API_ORIGIN"/* ]]; then
    printf 'Refusing component API URL outside Weblate API origin: %s\n' "$url" >&2
    return 2
  fi
  printf '%s' "$url"
}