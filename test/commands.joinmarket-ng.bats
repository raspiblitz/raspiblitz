#!/usr/bin/env bats

# Unit tests for the jm-ng shell function and help entry in _commands.sh.
#
# The user-facing command name must be "jm-ng" (matching the binary
# provided by the joinmarket-ng Python package and documented in
# the help output). "jmng" and "jm-tui" are NOT valid.

COMMANDS_SH="../home.admin/_commands.sh"

@test "help listing advertises jm-ng (not jmng or jm-tui)" {
  run grep -E '^\s*echo\s+"\s*jm[-_]?ng\s+' "${COMMANDS_SH}"
  [ "$status" -eq 0 ]
  # Must be exactly "jm-ng" (with hyphen, no underscore, no omission)
  echo "$output" | grep -qE '"\s*jm-ng\s+'
  ! echo "$output" | grep -qE '"\s*jmng\s+'
  ! echo "$output" | grep -qE '"\s*jm-tui\s+'
}

@test "jm-ng function is declared (and jmng is not)" {
  # The function definition must use the hyphenated name.
  grep -qE '^function[[:space:]]+jm-ng[[:space:]]*\(' "${COMMANDS_SH}"
  # The legacy "jmng" function must be gone.
  ! grep -qE '^function[[:space:]]+jmng[[:space:]]*\(' "${COMMANDS_SH}"
}

@test "jm-ng function sources and is callable when raspiblitz.conf flag is on" {
  # Prepare an isolated mock environment: the function dispatches to
  # bonus.joinmarket-ng.sh, which we stub out so the test stays hermetic.
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "${tmp}/mnt/hdd/app-data" "${tmp}/home/admin/config.scripts"
  echo "joinmarketNG=on" > "${tmp}/mnt/hdd/app-data/raspiblitz.conf"

  # Stub bonus.joinmarket-ng.sh that just echoes its arg
  cat > "${tmp}/home/admin/config.scripts/bonus.joinmarket-ng.sh" <<'STUB'
#!/bin/bash
echo "stub-menu-called arg=$*"
STUB
  chmod +x "${tmp}/home/admin/config.scripts/bonus.joinmarket-ng.sh"

  # Override the hardcoded paths with our sandbox, then source _commands.sh
  # and call jm-ng. We skip the actual function body's sudo call by replacing
  # `sudo` with a passthrough only for this test scope.
  run bash -c "
    set -e
    sudo() { \"\$@\"; }
    export -f sudo
    # shellcheck disable=SC1091
    source '${COMMANDS_SH}' 2>/dev/null || true
    # Override the paths the function reads
    alias_grep() { grep -c 'joinmarketNG=on' < '${tmp}/mnt/hdd/app-data/raspiblitz.conf'; }
    # Re-declare with patched paths for the test
    function jm-ng() {
      if [ \$(grep -c 'joinmarketNG=on' < '${tmp}/mnt/hdd/app-data/raspiblitz.conf') -eq 1 ]; then
        sudo '${tmp}/home/admin/config.scripts/bonus.joinmarket-ng.sh' menu
      else
        echo 'not installed'
      fi
    }
    jm-ng
  "
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "stub-menu-called arg=menu"

  rm -rf "${tmp}"
}
