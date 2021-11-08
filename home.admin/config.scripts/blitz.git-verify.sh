#!/bin/bash

# command info
if [ $# -lt 3 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "script use to verify git commits"
  echo "Usage:"
  echo "Run after 'git reset --hard VERSION' with the user running the installation"
  echo "blitz.git-verify.sh [PGPsigner] [PGPpubkeyLink] [PGPpubkeyFingerprint]"
  exit 1
fi

PGPsigner="$1"
PGPpubkeyLink="$2"
PGPpubkeyFingerprint="$3"

commitHash="$(git log --oneline | head -1 | awk '{print $1}')"

wget -O pgp_keys.asc "${PGPpubkeyLink}"
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(gpg pgp_keys.asc 2>/dev/null | grep "${PGPpubkeyFingerprint}" -c)
if [ "${fingerprint}" -lt 1 ]; then
  echo
  echo "# !!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
  echo "# Should contain PGP: ${PGPpubkeyFingerprint}"
  echo "# Type: 'Accept risk' and press ENTER to TAKE THE RISK if you think all is OK"
  read -r confirmation
  if [ "$confirmation" != "Accept risk" ]; then exit 1; fi
fi
gpg --import ./pgp_keys.asc

trap 'rm -f "$_temp"' EXIT
_temp="$(mktemp -p /dev/shm/)"

if git verify-commit "$commitHash" 2>&1 >&"$_temp"; then
  goodSignature=1
else
  goodSignature=0
fi
echo "# goodSignature(${goodSignature})"

correctKey=$(tr -d " \t\n\r" < "$_temp" | grep "${PGPpubkeyFingerprint}" -c)
echo "# correctKey(${correctKey})"

if [ "${correctKey}" -lt 1 ] || [ "${goodSignature}" -lt 1 ]; then
  echo
  echo "# !!! BUILD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo
  echo "##########################################################################"
  echo "# OK --> the PGP signature of the checked out $commitHash commit is correct"
  echo "##########################################################################"
  echo
  exit 0
fi
