#!/usr/bin/env bats

setup_mock_weblate() {
  export WEBLATE_TOKEN=test-token
  export WEBLATE_API_URL=https://hosted.weblate.org/api
  export WEBLATE_PROJECT=axonivy
  source "$BATS_TEST_DIRNAME/../scripts/weblate-common.sh"
  source "$BATS_TEST_DIRNAME/../scripts/defaults.sh"

  weblate_fetch() {
    case "$1" in
      https://hosted.weblate.org/api/projects/axonivy/components/?page_size=1000)
        cat "$BATS_TEST_DIRNAME/mock/components.json"
        ;;
      https://hosted.weblate.org/api/components/axonivy/doc/translations/)
        cat "$BATS_TEST_DIRNAME/mock/translations.json"
        ;;
      *)
        printf 'Unexpected mock Weblate URL: %s\n' "$1" >&2
        return 1
        ;;
    esac
  }
}

@test "fetches component results from an offline API response" {
  setup_mock_weblate

  run weblate_fetch_component_pages

  [ "$status" -eq 0 ]
  [ "$(jq -r -s 'length' <<<"$output")" -eq 2 ]
  [ "$(jq -r -s '.[0].slug' <<<"$output")" = "website" ]
  [ "$(jq -r -s '.[1].name' <<<"$output")" = "Mobile App" ]
  [ "$(jq -r -s '.[0].vcs' <<<"$output")" = "$WEBLATE_DEFAULT_VCS" ]
  [ "$(jq -r -s '.[0].new_lang' <<<"$output")" = "$WEBLATE_DEFAULT_NEW_LANG" ]
  [ "$(jq -r -s '.[0].file_format_params.json_indent' <<<"$output")" -eq "$WEBLATE_DEFAULT_JSON_INDENT" ]
  [ "$(jq -r -s '.[0].file_format_params.json_indent_style' <<<"$output")" = "$WEBLATE_DEFAULT_JSON_INDENT_STYLE" ]
  [ "$(jq -r -s '.[1].file_format_params.yaml_indent' <<<"$output")" -eq "$WEBLATE_DEFAULT_YAML_INDENT" ]
  [ "$(jq -r -s '.[0].commit_pending_age' <<<"$output")" -eq "$WEBLATE_DEFAULT_COMMIT_PENDING_AGE" ]
  [ "$(jq -r -s '.[0].branch' <<<"$output")" = "$WEBLATE_DEFAULT_SOURCE_BRANCH" ]
  [ "$(jq -r -s '.[0].push_branch' <<<"$output")" = "$WEBLATE_DEFAULT_PUSH_BRANCH" ]
  [ "$(jq -r -s '.[0].push_on_commit' <<<"$output")" = "$WEBLATE_DEFAULT_PUSH_ON_COMMIT" ]
  [ "$(jq -r -s '.[0].merge_style' <<<"$output")" = "$WEBLATE_DEFAULT_MERGE_STYLE" ]
  [ "$(jq -r -s '.[0].language_regex' <<<"$output")" = "$WEBLATE_DEFAULT_LANGUAGE_REGEX" ]
}

@test "fetches component results from the live Weblate API" {
  [[ "${WEBLATE_LIVE_TESTS:-}" == "1" ]] || skip "set WEBLATE_LIVE_TESTS=1 to call Weblate"
  [[ -n "${WEBLATE_TOKEN:-}" ]] || skip "WEBLATE_TOKEN is required for live API tests"

  source "$BATS_TEST_DIRNAME/../scripts/weblate-common.sh"
  run weblate_fetch_component_pages

  [ "$status" -eq 0 ]
  [ "$(jq -e -s 'length > 0 and all(.[]; (.slug | type == "string") and (.name | type == "string"))' <<<"$output")" = true ]
}

@test "fetches translation languages from an offline API response" {
  setup_mock_weblate

  component=$(jq -c '.results[0]' "$BATS_TEST_DIRNAME/mock/components.json")
  run weblate_fetch_component_languages "$component" en

  [ "$status" -eq 0 ]
  [ "$output" = "ja" ]
}