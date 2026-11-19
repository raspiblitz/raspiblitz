#!/usr/bin/env bats
# Bats deliberately isolates each @test in a subshell; setup exports its fixture
# state to each test. Cross-test SC2030/SC2031 state-leak warnings are inapplicable.
# shellcheck disable=SC2030,SC2031

setup() {
  export TRUST_LOG="$BATS_TEST_TMPDIR/commands"
  export MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  ln -s "$(command -v dpkg)" "$MOCK_BIN/dpkg"
  export PATH="$MOCK_BIN:$PATH"
  export NODE_STATUS="install ok installed" CA_STATUS=installed JAVA_STATUS=not-installed
  export JAVA_FAIL=0
  export NODE_VERSION=v22.23.4 CA_VERSION='20250419~deb12u2'
  export FAIL_STEP="" INSTALLED_VERSION=""
  export NODE_FILE="$BATS_TEST_TMPDIR/node-version"
  export OS_FILE="$BATS_TEST_TMPDIR/os-release"
  printf 'ID=debian\nVERSION_ID=12\n' > "$OS_FILE"
  export SCRIPT="$BATS_TEST_TMPDIR/blitz.trust.sh"
  export INSTALLER="$BATS_TEST_TMPDIR/bonus.nodejs.sh"
  export PROVISION="$BATS_TEST_TMPDIR/_provision.setup.sh"
  # Redirect hardcoded system paths in scratch copies, not production overrides.
  python3 - "$BATS_TEST_DIRNAME/.." "$SCRIPT" "$INSTALLER" "$PROVISION" <<'PY'
import os, pathlib, sys
root, helper, installer, provision = sys.argv[1:]
text = pathlib.Path(root, 'home.admin/config.scripts/blitz.trust.sh').read_text()
text = text.replace('/home/admin/config.scripts/blitz.trust.java.py', helper + '.java.py')
# Do not let the test host's unrelated Java installation affect image fixtures.
text = text.replace('command -v java >/dev/null 2>&1', '[ \"${MOCK_JAVA_PRESENT:-0}\" = 1 ]')
pathlib.Path(helper).write_text(text.replace('/etc/os-release', os.environ['OS_FILE']))
pathlib.Path(helper + '.java.py').write_text('import os, sys\nwith open(os.environ["TRUST_LOG"], "a") as f: f.write("java-helper " + sys.argv[1] + "\\n")\nsys.exit(int(os.environ["JAVA_FAIL"]))\n')
for source, target in [('home.admin/config.scripts/bonus.nodejs.sh', installer),
                       ('home.admin/_provision.setup.sh', provision)]:
    text = pathlib.Path(root, source).read_text()
    text = text.replace('/home/admin/config.scripts/blitz.trust.sh', helper)
    if target == provision:
        text = text.replace('[ "$EUID" -ne 0 ]', '[ 0 -ne 0 ]')
    pathlib.Path(target).write_text(text)
PY
  chmod +x "$SCRIPT"
  cat > "$MOCK_BIN/sudo" <<'MOCK'
#!/bin/bash
# Never touch system keyrings or sources in installer tests.
if [ "$1" = chmod ]; then exit 0; fi
exec "$@"
MOCK
  cat > "$MOCK_BIN/dpkg-query" <<'MOCK'
#!/bin/bash
case "$*" in
  *'${db:Status-Status}'*nodejs) printf '%s' "${NODE_STATUS##* }" ;;
  *'${db:Status-Status}'*ca-certificates-java) printf '%s' "$JAVA_STATUS" ;;
  *'${db:Status-Status}'*ca-certificates) printf '%s' "$CA_STATUS" ;;
  *'${Version}'*ca-certificates) printf '%s' "$CA_VERSION" ;;
  *) exit 1 ;;
esac
MOCK
  cat > "$MOCK_BIN/node" <<'MOCK'
#!/bin/bash
if [ -e "$NODE_FILE" ]; then read -r NODE_VERSION < "$NODE_FILE"; fi
[ -n "$NODE_VERSION" ] || exit 1
printf '%s\n' "$NODE_VERSION"
MOCK
  cat > "$MOCK_BIN/apt-get" <<'MOCK'
#!/bin/bash
printf 'apt-get %s\n' "$*" >> "$TRUST_LOG"
if [[ "$*" == *update ]] && [ "$FAIL_STEP" = update ]; then exit 100; fi
if [ "$1" = install ] && [ "$FAIL_STEP" = install ]; then exit 100; fi
if [[ "$*" == *nodejs* ]] && [ -n "$INSTALLED_VERSION" ]; then
  printf '%s\n' "$INSTALLED_VERSION" > "$NODE_FILE"
fi
MOCK
  cat > "$MOCK_BIN/update-ca-certificates" <<'MOCK'
#!/bin/bash
printf 'update-ca-certificates %s\n' "$*" >> "$TRUST_LOG"
[ "$FAIL_STEP" != refresh ]
MOCK
  # Installer-only prerequisites and tee must have no network/system effects.
  for cmd in curl gpg tee; do
    printf '#!/bin/bash\nexit 0\n' > "$MOCK_BIN/$cmd"
  done
  chmod +x "$MOCK_BIN/"*
}

@test "refreshes only CA and installed Node packages" {
  run bash "$SCRIPT" update
  [ "$status" -eq 0 ]
  expected=$(printf '%s\n' 'apt-get -o APT::Update::Error-Mode=any update' 'apt-get install --only-upgrade -y ca-certificates nodejs' 'update-ca-certificates --fresh')
  [ "$(< "$TRUST_LOG")" = "$expected" ]
}

@test "held Node is installed independently of selection state" {
  export NODE_STATUS='hold ok installed'
  run bash "$SCRIPT" update
  [ "$status" -eq 0 ]
  grep -q 'ca-certificates nodejs' "$TRUST_LOG"
  export NODE_VERSION=v22.23.1
  run bash "$SCRIPT" update
  [ "$status" -ne 0 ]
  [[ "$output" == *'Node.js v22.23.1 needs >= 22.23.4'* ]]
  run grep -Eq 'allow-change-held|ignore-hold|unhold' "$TRUST_LOG"
  [ "$status" -eq 1 ]
}

@test "minimal image and residual Node config do not install Node" {
  rm "$MOCK_BIN/node"
  for NODE_STATUS in 'unknown ok not-installed' 'deinstall ok config-files'; do
    export NODE_STATUS
    run env PATH="$MOCK_BIN" /bin/bash "$SCRIPT" update
    [ "$status" -eq 0 ]
    run grep -q nodejs "$TRUST_LOG"
    [ "$status" -eq 1 ]
  done
}

@test "APT and trust-refresh errors stop execution" {
  for FAIL_STEP in update install refresh; do
    export FAIL_STEP
    : > "$TRUST_LOG"
    run bash "$SCRIPT" update
    [ "$status" -ne 0 ]
    [[ "$output" != *'baselines verified'* ]]
    if [ "$FAIL_STEP" = update ]; then
      [ "$(wc -l < "$TRUST_LOG" | tr -d ' ')" -eq 1 ]
    elif [ "$FAIL_STEP" = install ]; then
      run grep -q update-ca-certificates "$TRUST_LOG"
      [ "$status" -eq 1 ]
    fi
  done
}

@test "successful stale CA no-op fails closed on both Debian baselines" {
  for version in 12 13; do
    printf 'ID=debian\nVERSION_ID=%s\n' "$version" > "$OS_FILE"
    if [ "$version" = 12 ]; then
      export CA_VERSION='20250419~deb12u1'
    else
      export CA_VERSION=20250419
    fi
    run bash "$SCRIPT" update
    [ "$status" -ne 0 ]
    [[ "$output" == *"ca-certificates $CA_VERSION needs >="* ]]
  done
  export CA_VERSION=20250419+deb13u1
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
}

@test "missing CA and unreviewed OS fail offline" {
  export CA_STATUS=config-files
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *'ca-certificates is not installed'* ]]
  export CA_STATUS=installed
  printf 'ID=debian\nVERSION_ID=11\n' > "$OS_FILE"
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *'No reviewed CA package baseline'* ]]
  [ ! -e "$TRUST_LOG" ]
}

@test "offline Node checks reject stale unsupported and malformed versions" {
  for NODE_VERSION in v22.23.3 v24.22.0 v26.12.0 v20.99.0 v27.0.0 v22.23.4-rc.1 ''; do
    export NODE_VERSION
    run bash "$SCRIPT" check
    [ "$status" -ne 0 ]
  done
  for NODE_VERSION in v22.23.4 v24.22.1 v26.12.1 v22.24.0; do
    export NODE_VERSION
    run bash "$SCRIPT" check
    [ "$status" -eq 0 ]
  done
  [ ! -e "$TRUST_LOG" ]
}

@test "executable shadowing a fixed package is checked" {
  export NODE_STATUS='deinstall ok config-files' NODE_VERSION=v22.23.1
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
}

@test "invalid invocation makes no package changes" {
  run bash "$SCRIPT" invalid
  [ "$status" -ne 0 ]
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [ ! -e "$TRUST_LOG" ]
}

@test "repeated refreshes use the same scoped vendor operations" {
  run bash "$SCRIPT" update
  [ "$status" -eq 0 ]
  first=$(< "$TRUST_LOG")
  : > "$TRUST_LOG"
  run bash "$SCRIPT" update
  [ "$status" -eq 0 ]
  [ "$(< "$TRUST_LOG")" = "$first" ]
}

@test "image release and provision entry points gate trust refresh" {
  for file in build_sdcard.sh home.admin/config.scripts/blitz.release.sh home.admin/_provision.update.sh home.admin/_provision.setup.sh; do
    run grep -E '^ */home/admin/config.scripts/blitz.trust.sh update.*\|\| exit 1$' "$BATS_TEST_DIRNAME/../$file"
    [ "$status" -eq 0 ]
  done
  # Execute actual fresh-setup code with only root guard and helper path redirected.
  export CA_VERSION='20250419~deb12u1'
  run bash "$PROVISION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ca-certificates $CA_VERSION needs >="* ]]
  [[ "$output" != *'No such file'* ]]
}

@test "actual installer cannot accept stale existing major via its early return" {
  export NODE_VERSION=v22.23.1
  run bash "$INSTALLER" on
  [ "$status" -ne 0 ]
  [[ "$output" == *'Node.js v22.23.1 needs >= 22.23.4'* ]]
  export INSTALLED_VERSION=v22.23.4
  run bash "$INSTALLER" on
  [ "$status" -eq 0 ]
}

@test "actual installer checks newly installed Node after earlier image refresh" {
  export NODE_VERSION='' INSTALLED_VERSION=v22.23.1
  run bash "$INSTALLER" on
  [ "$status" -ne 0 ]
  [[ "$output" == *'Node.js v22.23.1 needs >= 22.23.4'* ]]
  rm "$NODE_FILE"
  export INSTALLED_VERSION=v22.23.4
  run bash "$INSTALLER" on
  [ "$status" -eq 0 ]
}

@test "installed Java has scoped update and offline check with fatal failures" {
  export JAVA_STATUS=installed
  run bash "$SCRIPT" update
  [ "$status" -eq 0 ]
  grep -q 'ca-certificates nodejs ca-certificates-java' "$TRUST_LOG"
  grep -q 'java-helper update' "$TRUST_LOG"
  : > "$TRUST_LOG"
  run bash "$SCRIPT" check
  [ "$status" -eq 0 ]
  [ "$(< "$TRUST_LOG")" = 'java-helper check' ]
  export JAVA_FAIL=1
  run bash "$SCRIPT" update
  [ "$status" -ne 0 ]
  [[ "$output" == *'Java trust remediation failed'* ]]
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *'Java trust check failed'* ]]
}

@test "Java executable without installed Java CA package still gates" {
  export MOCK_JAVA_PRESENT=1 JAVA_FAIL=1
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *'Java trust check failed'* ]]
}

@test "Java overrides are rejected before sudo can discard them" {
  export JAVA_STATUS=installed JAVA_HOME=/custom/jre
  run bash "$SCRIPT" check
  [ "$status" -ne 0 ]
  [[ "$output" == *'Explicit JAVA_HOME needs separate Java trust review'* ]]
  [ ! -e "$TRUST_LOG" ]
}

@test "installed Node that cannot execute fails both update and check" {
  printf '#!/bin/bash\nexit 126\n' > "$MOCK_BIN/node"
  for mode in update check; do
    run bash "$SCRIPT" "$mode"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Installed Node.js cannot run'* ]]
  done
}

@test "successful stale Node APT no-op fails the final executable postcondition" {
  export NODE_VERSION=v22.23.3
  run bash "$SCRIPT" update
  [ "$status" -ne 0 ]
  grep -q 'update-ca-certificates --fresh' "$TRUST_LOG"
  [[ "$output" == *'Node.js v22.23.3 needs >= 22.23.4'* ]]
}

@test "fixed existing installer is offline and still enforces CA baseline" {
  run bash "$INSTALLER" on
  [ "$status" -eq 0 ]
  [ ! -e "$TRUST_LOG" ]
  export CA_VERSION='20250419~deb12u1'
  run bash "$INSTALLER" on
  [ "$status" -ne 0 ]
}
