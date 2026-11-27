#!/usr/bin/env bats

setup() {
  export FIXTURE="$BATS_TEST_TMPDIR"
  mkdir -p "$FIXTURE/admin/config.scripts" "$FIXTURE/bin" "$FIXTURE/state"
  touch "$FIXTURE/admin/raspiblitz.info" "$FIXTURE/dialogs"
  printf 'setPasswordA=1\nsetPasswordB=1\nsetPasswordC=1\nhostname=lab\n' > "$FIXTURE/state/raspiblitz.setup"
  sed -e "s|/home/admin|$FIXTURE/admin|g" -e "s|/run/raspiblitz-setup|$FIXTURE/state|g" \
    "$BATS_TEST_DIRNAME/../home.admin/setup.scripts/dialogPasswords.sh" > "$FIXTURE/dialog.sh"
  cat > "$FIXTURE/admin/config.scripts/blitz.passwords.sh" <<'SH'
#!/bin/sh
printf '%s\n' 'Fixture-Input' > "$4"
SH
  cat > "$FIXTURE/bin/dialog" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$FIXTURE/dialogs"
case "$*" in *"Could not save"*) exit 1;; esac
SH
  printf '#!/bin/sh\nexec "$@"\n' > "$FIXTURE/bin/sudo"
  printf '#!/bin/sh\nexit 0\n' > "$FIXTURE/bin/clear"
  chmod +x "$FIXTURE/admin/config.scripts/blitz.passwords.sh" "$FIXTURE"/bin/*
  PATH="$FIXTURE/bin:$PATH"
}

@test "each accepted record is stored once, privately, with unrelated settings preserved" {
  echo "passwordA='Old-Input'" >> "$FIXTURE/state/raspiblitz.setup"
  run bash "$FIXTURE/dialog.sh"
  [ "$status" -eq 0 ]
  for key in A B C; do
    grep -Fxq "password$key='Fixture-Input'" "$FIXTURE/state/raspiblitz.setup"
    [ "$(grep -c "^password$key=" "$FIXTURE/state/raspiblitz.setup")" = 1 ]
    grep -q "Password $key accepted" "$FIXTURE/dialogs"
  done
  grep -Fxq hostname=lab "$FIXTURE/state/raspiblitz.setup"
  [ "$(stat -c %a "$FIXTURE/state/raspiblitz.setup")" = 640 ]
  [[ "$output" != *Fixture-Input* ]]
}

@test "failed replacement offers a retry and never acknowledges an unsaved password" {
  printf '#!/bin/sh\nexit 1\n' > "$FIXTURE/bin/mv"
  chmod +x "$FIXTURE/bin/mv"
  cp "$FIXTURE/state/raspiblitz.setup" "$FIXTURE/original"
  run bash "$FIXTURE/dialog.sh"
  [ "$status" -ne 0 ]
  cmp "$FIXTURE/original" "$FIXTURE/state/raspiblitz.setup"
  grep -q 'Could not save Password A' "$FIXTURE/dialogs"
  ! grep -q 'Password A accepted' "$FIXTURE/dialogs"
  [ -z "$(find "$FIXTURE/state" -mindepth 1 ! -name raspiblitz.setup -print -quit)" ]
  [[ "$output" != *Fixture-Input* ]]
}
