#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  publisher="$BATS_TEST_DIRNAME/../home.admin/config.scripts/publish-web-ui.py"
  mkdir public build
  echo "previous" > public/index.html
  printf '<script type="module" src="/assets/app.js"></script>' > build/index.html
}

@test "a missing entry bundle leaves the previous nginx root in place" {
  run python3 "$publisher" build public
  [ "$status" -ne 0 ]
  [ "$(cat public/index.html)" = previous ]
}

@test "a complete bundle replaces the live tree and preserves existing hidden entries" {
  mkdir build/assets
  printf 'export {}' > build/assets/app.js
  echo preserved > public/.custom
  echo private > build/.env
  run python3 "$publisher" build public
  [ "$status" -eq 0 ]
  cmp build/index.html public/index.html
  cmp build/assets/app.js public/assets/app.js
  [ "$(cat public/.custom)" = preserved ]
  [ ! -e public/.env ]
}

@test "reject linked build assets without following or publishing them" {
  mkdir build/assets
  ln -s "$PWD/public/index.html" build/assets/app.js
  run python3 "$publisher" build public
  [ "$status" -ne 0 ]
  [ "$(cat public/index.html)" = previous ]
}
