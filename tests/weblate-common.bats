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
  [ "$(jq -r -s '.[0].license' <<<"$output")" = "$(weblate_default license)" ]
  [ "$(jq -r -s '.[0].vcs' <<<"$output")" = "$(weblate_default vcs)" ]
  [ "$(jq -r -s '.[0].new_lang' <<<"$output")" = "$(weblate_default new_lang)" ]
  [ "$(jq -r -s '.[0].file_format_params.json_indent' <<<"$output")" -eq "$(weblate_default json_indent)" ]
  [ "$(jq -r -s '.[0].file_format_params.json_indent_style' <<<"$output")" = "$(weblate_default json_indent_style)" ]
  [ "$(jq -r -s '.[1].file_format_params.yaml_indent' <<<"$output")" -eq "$(weblate_default yaml_indent)" ]
  [ "$(jq -r -s '.[0].commit_pending_age' <<<"$output")" -eq "$(weblate_default commit_pending_age)" ]
  [ "$(jq -r -s '.[0].branch' <<<"$output")" = "$(weblate_default source_branch)" ]
  [ "$(jq -r -s '.[0].push_branch' <<<"$output")" = "$(weblate_default push_branch)" ]
  [ "$(jq -r -s '.[0].push_on_commit' <<<"$output")" = "$(weblate_default push_on_commit)" ]
  [ "$(jq -r -s '.[0].merge_style' <<<"$output")" = "$(weblate_default merge_style)" ]
  [ "$(jq -r -s '.[0].language_regex' <<<"$output")" = "$(weblate_default language_regex)" ]
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