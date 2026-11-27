#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p bin www/public lock
  # Exercise the installed script against a disposable checkout and document
  # root. The VM acceptance run also exercises the unmodified absolute paths.
  sed -e 's|/home/blitzapi/blitz_web|'"$PWD"'/web|g' \
      -e 's|/var/www|'"$PWD"'/www|g' -e 's|/run/raspiblitz-webui|'"$PWD"'/lock/webui|g' \
      -e 's/\[ "\$EUID" -ne 0 \]/false/' \
      "$BATS_TEST_DIRNAME/../home.admin/config.scripts/blitz.web.ui.sh" > updater
  cp "$BATS_TEST_DIRNAME/../home.admin/config.scripts/publish-web-ui.py" .
  export PATH="$PWD/bin:$PATH"
  git init -q -b release origin
  git -C origin -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m original
  git clone -q origin web
  git -C origin -c user.name=Test -c user.email=test@example.invalid commit -q --allow-empty -m update
  echo previous > www/public/index.html
  cat > bin/npm <<'SH'
#!/bin/bash
if [ "$*" = "run build" ]; then
  [ "$BUILD_FAIL" != yes ] || exit 73
  mkdir -p build/assets
  echo '<script src="/assets/app.js"></script>' > build/index.html
  echo 'export {}' > build/assets/app.js
fi
SH
  chmod +x bin/npm
}

@test "a failed update keeps the served UI and the same upstream commit can be retried" {
  export BUILD_FAIL=yes
  run bash updater update
  [ "$status" -ne 0 ]
  [ "$(cat www/public/index.html)" = previous ]
  [ "$(git -C web rev-parse HEAD)" = "$(git -C origin rev-parse HEAD)" ]
  export BUILD_FAIL=no
  run bash updater update
  [ "$status" -eq 0 ]
  [ -s www/public/assets/app.js ]
  [ ! -e www/.raspiblitz-webui-update-pending ]
}
