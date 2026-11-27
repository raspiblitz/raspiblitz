#!/usr/bin/env bats

setup() {
  root="$BATS_TEST_TMPDIR/storage"
  mkdir -p "$root/app-storage/bitcoin/blocks"
  source <(sed -n '/^has_reusable_blocks() {/,/^}/p' "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.data.sh")
}

@test "small or pruned data on either dedicated or combined STORAGE can be reused" {
  printf fixture > "$root/app-storage/bitcoin/blocks/blk00123.dat"
  run has_reusable_blocks "$root"
  [ "$status" = 0 ]
  mkdir "$root/app-data"
  run has_reusable_blocks "$root"
  [ "$status" = 0 ]
}

@test "empty or ambiguous layouts cannot authorize a clean" {
  touch "$root/app-storage/bitcoin/blocks/blk00000.dat"
  run has_reusable_blocks "$root"
  [ "$status" -ne 0 ]
  printf data > "$root/unrelated"
  ln -s "$root/unrelated" "$root/app-storage/bitcoin/blocks/blk00001.dat"
  run has_reusable_blocks "$root"
  [ "$status" -ne 0 ]
  mv "$root/app-storage/bitcoin/blocks" "$root/custom"
  printf data > "$root/custom/blk00000.dat"
  ln -s "$root/custom" "$root/app-storage/bitcoin/blocks"
  run has_reusable_blocks "$root"
  [ "$status" -ne 0 ]
}
