#!/usr/bin/env bats

# Run only in a disposable Linux container with CAP_SYS_ADMIN, never on a node.
setup() {
  if [ "${BLITZ_DISPOSABLE_MOUNT_TEST:-}" != "1" ]; then
    skip "requires BLITZ_DISPOSABLE_MOUNT_TEST=1 in a disposable privileged container"
  fi
}

check_status() {
  run unshare --mount bash "$BATS_TEST_DIRNAME/fixtures/blitz.data-mounts.sh" "$1"
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
}

@test "status selects ordinary root, storage, and data mount paths" {
  check_status ordinary
}

@test "PrivateTmp bind mounts do not break sourced status output" {
  check_status private
}

@test "status preserves spaces in the selected mount path" {
  check_status spaces
}

@test "an unmounted source is empty and still follows the mount fallback" {
  check_status unmounted
}

@test "a source mounted only through a bind mount remains discoverable" {
  check_status bind-only
}
