#!/usr/bin/env bash
# Record the revision of the deployed scripts in the installed version file.
set -eu
checkout=${1:?Missing source checkout}
versionFile=${2:?Missing installed version file}
[[ -f "$versionFile" && ! -L "$versionFile" ]]
revision=$(git -C "$checkout" rev-parse --verify --short HEAD)
[[ $revision =~ ^[0-9a-f]{4,64}$ ]]

temp=$(mktemp -- "${versionFile}.XXXXXXXX")
trap 'rm -f -- "$temp"' EXIT
{
  printf 'installedCodeCommit=%s\n' "$revision"
  sed '/^installedCodeCommit=/d' -- "$versionFile"
} > "$temp"
chmod 0644 "$temp"
mv -fT -- "$temp" "$versionFile"
