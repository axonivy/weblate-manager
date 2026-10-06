WEBLATE_DEFAULTS_FILE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/defaults.json"

weblate_default() {
  jq -r --arg key "$1" \
    'if has($key) then .[$key] else error("Missing Weblate default: " + $key) end' \
    "$WEBLATE_DEFAULTS_FILE"
}