#!/usr/bin/env bash
# Run from any directory; use the repository's existing ShellCheck error gate.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

scripts=(
  alternative.platforms/amd64/packer/scripts/init.sh
  home.admin/config.scripts/lnd.install.sh
  home.admin/config.scripts/lnd.update.sh
  home.admin/config.scripts/bonus.pool.sh
  home.admin/config.scripts/bonus.chantools.sh
  home.admin/config.scripts/bonus.sphinxrelay.sh
  test/public-download-tls.sh
)
for script in "${scripts[@]}"; do
  bash -n "$script"
done
shellcheck --shell=bash --severity=error "${scripts[@]}"
shellcheck --shell=bash test/public-download-tls.sh
python3 -c 'import ast; from pathlib import Path; ast.parse(Path("test/public-download-tls.py").read_text())'
printf 'Bash syntax, ShellCheck and Python syntax: PASS\n'
wget --version
python3 test/public-download-tls.py
