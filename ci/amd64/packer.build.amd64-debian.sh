#!/bin/bash -e

sudo apt-get update

# install packer
if ! packer version 2>/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
  sudo apt-add-repository -y "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  sudo apt-get update
  echo -e "\nInstalling packer..."
  sudo apt-get install -y packer
else
  echo "# Packer is installed"
fi

# install qemu
echo "# Install qemu ..."
sudo apt-get update
sudo apt-get install -y qemu-system

# set vars
echo "# Setting the variables: $*"
source ../set_variables.sh
set_variables "$@"

# Resolve latest Debian 13 amd64 netinst ISO from SHA256SUMS.
# This avoids 404s and checksum mismatches when Debian point releases rotate.
debian_major=${DEBIAN_MAJOR:-13}
debian_iso_dir="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
debian_sums_url="${debian_iso_dir}/SHA256SUMS"
debian_sums_sig_url="${debian_iso_dir}/SHA256SUMS.sign"
debian_cd_key_urls=(
  "https://www.debian.org/CD/key-DA87E80D6294BE9B.txt"
  "https://www.debian.org/CD/key-988021A964E6EA7D.txt"
)
debian_cd_expected_fprs=(
  "DF9B9C49EAA9298432589D76DA87E80D6294BE9B"
  "10460DAD76165AD81FBC0CE9988021A964E6EA7D"
)

if ! command -v gpgv >/dev/null 2>&1; then
  echo "# Installing gpgv"
  sudo apt-get install -y gpgv
fi

if ! command -v gpgv >/dev/null 2>&1; then
  echo "ERROR: gpgv is required for signature verification"
  exit 1
fi

tmp_checksums_dir=$(mktemp -d)
trap 'rm -rf "${tmp_checksums_dir}"' EXIT

echo "# Downloading checksum files"
curl -fsSL "${debian_sums_url}" -o "${tmp_checksums_dir}/SHA256SUMS"
curl -fsSL "${debian_sums_sig_url}" -o "${tmp_checksums_dir}/SHA256SUMS.sign"

echo "# Verifying SHA256SUMS signature (PGP)"
cd_keyring="${tmp_checksums_dir}/debian-cd-signing-keys.gpg"
tmp_gnupg_home="${tmp_checksums_dir}/gnupg-home"
mkdir -p "${tmp_gnupg_home}"
chmod 700 "${tmp_gnupg_home}"

for i in "${!debian_cd_key_urls[@]}"; do
  key_url="${debian_cd_key_urls[$i]}"
  expected_fpr="${debian_cd_expected_fprs[$i]}"
  key_file="${tmp_checksums_dir}/cd-key-${i}.asc"
  curl -fsSL "${key_url}" -o "${key_file}"
  actual_fpr=$(gpg --homedir "${tmp_gnupg_home}" --show-keys --with-colons "${key_file}" 2>/dev/null | awk -F: '/^fpr:/ {print $10; exit}')
  if [ -z "${actual_fpr}" ] || [ "${actual_fpr}" != "${expected_fpr}" ]; then
    echo "# SHA256SUMS signature: FAIL"
    echo "ERROR: Unexpected fingerprint for ${key_url}"
    exit 1
  fi
  gpg --homedir "${tmp_gnupg_home}" --no-default-keyring --keyring "${cd_keyring}" --import "${key_file}" >/dev/null 2>&1
done

if gpgv --keyring "${cd_keyring}" "${tmp_checksums_dir}/SHA256SUMS.sign" "${tmp_checksums_dir}/SHA256SUMS" >/dev/null 2>&1; then
  echo "# SHA256SUMS signature: PASS"
else
  echo "# SHA256SUMS signature: FAIL"
  echo "ERROR: PGP signature verification failed for ${debian_sums_url}"
  exit 1
fi

echo "# Resolving latest Debian ${debian_major} amd64 netinst ISO from ${debian_sums_url}"
latest_iso_line=$(awk -v major="${debian_major}" '$2 ~ ("^\\*?\\.?/?debian-" major "\\.[0-9]+\\.[0-9]+-amd64-netinst\\.iso$") {print $1 " " $2}' "${tmp_checksums_dir}/SHA256SUMS" | \
  sort -k2 -V | tail -1)

if [ -z "${latest_iso_line}" ]; then
  echo "ERROR: Could not resolve latest Debian ${debian_major} amd64 netinst ISO from ${debian_sums_url}"
  exit 1
fi

latest_iso_checksum=$(echo "${latest_iso_line}" | awk '{print $1}')
latest_iso_name=$(echo "${latest_iso_line}" | awk '{print $2}' | sed 's#^\*##; s#^\./##; s#^/##')

if [ -z "${latest_iso_name}" ] || [ -z "${latest_iso_checksum}" ]; then
  echo "ERROR: Failed parsing ISO name/checksum from: ${latest_iso_line}"
  exit 1
fi

resolved_checksum=$(awk -v iso="${latest_iso_name}" '($2 == iso || $2 == "*" iso || $2 == "./" iso || $2 == "/" iso) {print $1; exit}' "${tmp_checksums_dir}/SHA256SUMS")
if [ -z "${resolved_checksum}" ]; then
  echo "ERROR: Could not find checksum entry for ${latest_iso_name} in ${debian_sums_url}"
  exit 1
fi

echo "# Debian ISO selection"
echo "# ISO filename      : ${latest_iso_name}"
echo "# SHA256 (selected) : ${latest_iso_checksum}"
echo "# SHA256 (resolved) : ${resolved_checksum}"
if [ "${latest_iso_checksum}" = "${resolved_checksum}" ]; then
  echo "# Checksum verify   : PASS"
else
  echo "# Checksum verify   : FAIL"
  echo "ERROR: Checksum mismatch for ${latest_iso_name}"
  exit 1
fi

vars="${vars} -var iso_name=${latest_iso_name} -var iso_checksum=${latest_iso_checksum}"

# Build the image
echo "# Build the image ..."
cd debian
packer init -upgrade .
command="PACKER_LOG=1 packer build ${vars} -only=qemu.debian packer.build.amd64-debian.hcl"
echo "# Running: $command"
if [ ${#vars} -eq 0 ];then exit 1;fi
PACKER_LOG=1 packer build ${vars} -only=qemu.debian build.amd64-debian.pkr.hcl || exit 1
