#!/usr/bin/env bats

# Define common paths
SOUND_PATH="./sounds"
LOG_FILE="application_size_checker.log"

# Setup and Teardown
setup() {
  # Create necessary files and directories for testing
  mkdir -p ./sounds
  touch "$SOUND_PATH/switch.wav"
  touch "$LOG_FILE"
}

teardown() {
  # Cleanup test artifacts
  rm -rf ./sounds
  rm -f "$LOG_FILE"
}

@test "Test play_key_sound: Sound file exists" {
  run bash -c "source application_size_checker.sh; play_key_sound"
  [ "$status" -eq 0 ]
}

@test "Test play_key_sound: Sound file missing" {
  rm -f "$SOUND_PATH/switch.wav"
  run bash -c "source application_size_checker.sh; play_key_sound"
  [ "$status" -eq 0 ]
  [ "$(grep 'Sound file not found' $LOG_FILE)" ]
}

@test "Test calculate_size with valid path" {
  mkdir -p ./test_app
  run bash -c "source application_size_checker.sh; calculate_size './test_app'"
  [ "$status" -eq 0 ]
  [[ "$output" -eq 0 ]]
  rmdir ./test_app
}

@test "Test calculate_size with invalid path" {
  run bash -c "source application_size_checker.sh; calculate_size './nonexistent'"
  [ "$status" -eq 0 ]
  [ "$output" == "?" ]
}

@test "Test format_size for KB" {
  run bash -c "source application_size_checker.sh; format_size 512"
  [ "$status" -eq 0 ]
  [ "$output" == "512K" ]
}

@test "Test format_size for MB" {
  run bash -c "source application_size_checker.sh; format_size 2048"
  [ "$status" -eq 0 ]
  [ "$output" == "2.00M" ]
}

@test "Test format_size for GB" {
  run bash -c "source application_size_checker.sh; format_size 1048576"
  [ "$status" -eq 0 ]
  [ "$output" == "1.00G" ]
}

@test "Test calculate_brew_formula_size: Formula exists" {
  run bash -c "source application_size_checker.sh; calculate_brew_formula_size 'jq'"
  [ "$status" -eq 0 ]
  [[ "$output" -gt 0 ]]
}

@test "Test calculate_brew_formula_size: Formula missing" {
  run bash -c "source application_size_checker.sh; calculate_brew_formula_size 'nonexistent-formula'"
  [ "$status" -eq 0 ]
  [ "$output" == "?" ]
}

@test "Test calculate_brew_cask_size: Cask exists" {
  run bash -c "source application_size_checker.sh; calculate_brew_cask_size 'docker'"
  [ "$status" -eq 0 ]
  [[ "$output" -gt 0 ]]
}

@test "Test calculate_brew_cask_size: Cask missing" {
  run bash -c "source application_size_checker.sh; calculate_brew_cask_size 'nonexistent-cask'"
  [ "$status" -eq 0 ]
  [ "$output" == "?" ]
}
