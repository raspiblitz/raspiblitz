#!/usr/bin/env bats

setup() {
  script="$BATS_TEST_DIRNAME/../build_sdcard.sh"
  repo="$BATS_TEST_TMPDIR/source"
  git init -q "$repo"
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m fixture
  head=$(git -C "$repo" rev-parse HEAD)
  # Use the actual guard that runs after clone and before copying home.admin.
  sed -n '/^if .*RASPIBLITZ_BUILD_COMMIT.*sudo -u admin git/,/^fi$/p' "$script" |
    sed "s|sudo -u admin git -C /home/admin/raspiblitz|git -C $repo|" > "$BATS_TEST_TMPDIR/check"
  [ -s "$BATS_TEST_TMPDIR/check" ]
}

@test "the named branch must still match the requested source revision" {
  run env RASPIBLITZ_BUILD_COMMIT="$head" bash "$BATS_TEST_TMPDIR/check"
  [ "$status" -eq 0 ]
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m moved
  run env RASPIBLITZ_BUILD_COMMIT="$head" bash "$BATS_TEST_TMPDIR/check"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no longer matches"* ]]
}

@test "optional commit check preserves existing branch-only callers" {
  run env -u RASPIBLITZ_BUILD_COMMIT bash "$BATS_TEST_TMPDIR/check"
  [ "$status" -eq 0 ]
}
