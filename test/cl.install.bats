#!/usr/bin/env bats
# Tests for cl.install.sh update / update-binary pre-flight checks
# These only exercise the version / asset existence checks, so no root
# and no lightning install is needed - but they do access github.com

SCRIPT="$BATS_TEST_DIRNAME/../home.admin/config.scripts/cl.install.sh"

@test "update with a nonexistent version exits 1 with a clear error" {
  run bash "$SCRIPT" update v99.99.99-notreal
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "update with an embargoed release points to update-binary" {
  # v26.06.7 was released under embargo: the source zip was not published,
  # only prebuilt tarballs. Once the source zip is published upstream this
  # test needs a newer embargoed release as its example.
  run bash "$SCRIPT" update v26.06.7
  [ "$status" -eq 1 ]
  [[ "$output" == *"source zip clightning-v26.06.7.zip is not published"* ]]
  [[ "$output" == *"update-binary v26.06.7"* ]]
}

@test "update-binary with a nonexistent version exits 1 with a clear error" {
  run bash "$SCRIPT" update-binary v99.99.99-notreal
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "update-binary with a published release passes the pre-flight checks" {
  # must not fail before the interactive confirmation prompt
  run bash -c "echo | bash '$SCRIPT' update-binary v26.06.7"
  [[ "$output" == *"OK version exists"* ]]
}
