#!/usr/bin/env bats
# Tests for cl.install.sh update / update-binary pre-flight checks
# Only exercises the version / release-asset existence checks:
# no root and no lightning install needed, but requires network access
# to github.com. Safe to run on a live node - stdin is redirected from
# /dev/null so no test can get past a confirmation prompt.

SCRIPT="$BATS_TEST_DIRNAME/../home.admin/config.scripts/cl.install.sh"
REPO="https://github.com/ElementsProject/lightning"

latestReleaseTag() {
  curl -sf "https://api.github.com/repos/ElementsProject/lightning/releases/latest" |
    grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4
}

assetExists() {
  # $1 release tag, $2 asset filename
  curl --output /dev/null --silent --head --fail \
    "${REPO}/releases/download/$1/$2"
}

@test "update with a nonexistent version exits 1 with a clear error" {
  run bash "$SCRIPT" update v99.99.99-notreal </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "update-binary with a nonexistent version exits 1 with a clear error" {
  run bash "$SCRIPT" update-binary v99.99.99-notreal </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "update with an existing release passes the version check" {
  # v26.06.7 exists as a release tag - tags are permanent, safe as a fixture
  run bash "$SCRIPT" update v26.06.7 </dev/null
  [[ "$output" == *"OK version exists"* ]]
}

@test "update falls back to update-binary when the source zip is not published" {
  # Uses the latest release so the test adapts automatically:
  # skips when there is no embargoed release to test with
  latest=$(latestReleaseTag)
  [ -n "$latest" ] || skip "could not query the latest release"
  if assetExists "$latest" "clightning-${latest}.zip"; then
    skip "latest release ${latest} has a source zip (no embargoed release to test with)"
  fi
  if ! assetExists "$latest" "SHA256SUMS-${latest}"; then
    skip "latest release ${latest} has no checksum manifest (no prebuilt tarballs to test with)"
  fi
  run bash "$SCRIPT" update "$latest" </dev/null
  [ "$status" -eq 1 ]
  [[ "$output" == *"Falling back to the prebuilt binary tarball"* ]]
  [[ "$output" == *"update-binary"* ]]
}

@test "update-binary aborts without confirmation instead of installing" {
  latest=$(latestReleaseTag)
  [ -n "$latest" ] || skip "could not query the latest release"
  run bash "$SCRIPT" update-binary "$latest" </dev/null
  [ "$status" -eq 1 ]
  # must never reach the download step without a TTY confirmation
  [[ "$output" != *"Downloading Core Lightning"* ]]
}
