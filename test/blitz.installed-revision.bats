#!/usr/bin/env bats

setup() {
  checkout="$BATS_TEST_TMPDIR/checkout"
  metadata="$BATS_TEST_TMPDIR/_version.info"
  writer="$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.installed-revision.sh"
  git init -q "$checkout"
  commit_fixture
  printf 'codeVersion="1.12.1"\ncodeRelease="abcd"\n# last line\n' > "$metadata"
}

commit_fixture() {
  git -C "$checkout" -c user.name=Test -c user.email=test@example.invalid \
    commit --quiet --allow-empty -m 'Test revision'
}

@test "record the installed revision on build and replace it after a code update" {
  cp "$metadata" "$metadata.original"
  for i in 1 2; do
    bash "$writer" "$checkout" "$metadata"
    expected=$(git -C "$checkout" rev-parse --short HEAD)
    [ "$(grep '^installedCodeCommit=' "$metadata")" = "installedCodeCommit=$expected" ]
    sed '/^installedCodeCommit=/d' "$metadata" | cmp - "$metadata.original"
    [ "$(stat -c '%a' "$metadata")" = 644 ]
    commit_fixture
  done
}

@test "failed lookup and symlink destinations leave existing metadata intact" {
  cp "$metadata" "$metadata.original"
  run bash "$writer" "$BATS_TEST_TMPDIR/missing-checkout" "$metadata"
  [ "$status" -ne 0 ]
  cmp "$metadata" "$metadata.original"
  ln -s "$metadata" "$metadata.link"
  run bash "$writer" "$checkout" "$metadata.link"
  [ "$status" -ne 0 ]
  [ -L "$metadata.link" ]
  cmp "$metadata" "$metadata.original"
}
