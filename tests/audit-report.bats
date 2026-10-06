#!/usr/bin/env bats

@test "audit header shows defaults JSON on demand" {
  source "$BATS_TEST_DIRNAME/../scripts/check-components.sh"
  run render_report_header

  [ "$status" -eq 0 ]
  [[ "$output" == *'<summary>defaults.json</summary>'* ]]
  [[ "$output" == *'```json'* ]]
  [[ "$output" == *"$(cat "$BATS_TEST_DIRNAME/../scripts/defaults.json")"* ]]
  [[ "$output" == *'</details>'* ]]
}