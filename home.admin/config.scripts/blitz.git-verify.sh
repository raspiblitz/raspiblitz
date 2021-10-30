#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
  echo "script use to verify git commits"
  echo "Usage:"
  echo "Run after 'git reset --hard VERSION' with the user used for installation"
  echo "blitz.git-verify.sh [PGPsigner] [PGPpubkeyLink] [PGPpubkeyFingerprint]"
  exit 1
fi

PGPsigner="$1"
PGPpubkeyLink="$2"
PGPpubkeyFingerprint="$3"
commitHash="$(git log --oneline | head -1 | awk '{print $1}')"

wget -O "pgp_keys.asc" ${PGPpubkeyLink}
gpg --import --import-options show-only ./pgp_keys.asc
fingerprint=$(gpg "pgp_keys.asc" 2>/dev/null | grep "${PGPpubkeyFingerprint}" -c)
if [ ${fingerprint} -lt 1 ]; then
  echo
  echo "# !!! WARNING --> the PGP fingerprint is not as expected for ${PGPsigner}"
  echo "# Should contain PGP: ${PGPpubkeyFingerprint}"
  echo "# PRESS ENTER to TAKE THE RISK if you think all is OK"
  read key
fi
gpg --import ./pgp_keys.asc

verifyResult=$(git verify-commit $commitHash 2>&1)

goodSignature=$(echo ${verifyResult} | grep 'Good signature' -c)
echo "# goodSignature(${goodSignature})"
correctKey=$(echo ${verifyResult} | tr -d " \t\n\r" | grep "${PGPpubkeyFingerprint}" -c)
echo "# correctKey(${correctKey})"
if [ ${correctKey} -lt 1 ] || [ ${goodSignature} -lt 1 ]; then
  echo 
  echo "# !!! BUILD FAILED --> PGP verification not OK / signature(${goodSignature}) verify(${correctKey})"
  exit 1
else
  echo 
  echo "##########################################################################"
  echo "# OK --> the PGP signature of the checked out $commitHash commit is correct #"
  echo "##########################################################################"
  echo
  exit 0
fi