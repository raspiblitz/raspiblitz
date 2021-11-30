#!/bin/bash

# command info
if [ $# -lt 3 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "script use to verify a git commit or tag"
  echo "Usage:"
  echo "Run after 'git reset --hard VERSION' with the user running the installation"
  echo "To verify the checked out commit:"
  echo "blitz.git-verify.sh [PGPsigner] [PGPpubkeyLink] [PGPpubkeyFingerprint]"
  echo "To use 'git verify-tag' add the 'tag':"
  echo "blitz.git-verify.sh [PGPsigner] [PGPpubkeyLink] [PGPpubkeyFingerprint] <tag>"
  exit 1
fi

# Example for commits created on GitHub:
# PGPsigner="web-flow"
# PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
# PGPpubkeyFingerprint="4AEE18F83AFDEB23"

# Example for commits signed with a personal PGP key:
# PGPsigner="janoside"
# PGPpubkeyLink="https://github.com/${PGPsigner}.gpg"
# PGPpubkeyFingerprint="F579929B39B119CC7B0BB71FB326ACF51F317B69"

# Run with the insatting user to clear permissions:
# sudo -u btcrpcexplorer /home/admin/config.scripts/blitz.git-verify.sh \
#  "${PGPsigner}" "${PGPpubkeyLink}" "${PGPpubkeyFingerprint}" || exit 1

PGPsigner="$1"
PGPpubkeyLink="$2"
PGPpubkeyFingerprint="$3"

wget -O pgp_keys.asc "${PGPpubkeyLink}"
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(gpg pgp_keys.asc 2>/dev/null | grep "${PGPpubkeyFingerprint}" -c)
if [ "${fingerprint}" -lt 1 ]; then
  echo
  echo "# !!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}" >&2
  echo "# Should contain PGP: ${PGPpubkeyFingerprint}" >&2
  echo "# Exiting" >&2
  exit 7
fi
gpg --import ./pgp_keys.asc

trap 'rm -f "$_temp"' EXIT
_temp="$(mktemp -p /dev/shm/)"

if [ $# -eq 3 ]; then
  commitHash="$(git log --oneline | head -1 | awk '{print $1}')"
  gitCommand="git verify-commit $commitHash"
elif [ $# -eq 4 ]; then
  gitCommand="git verify-tag $4"
fi
if ${gitCommand} 2>&1 >&"$_temp"; then
  goodSignature=1
else
  goodSignature=0
fi
echo
cat $_temp
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
