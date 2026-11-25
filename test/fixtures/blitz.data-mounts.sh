#!/bin/bash
# Synthetic filesystems only. Called by Bats in a disposable mount namespace.
set -euo pipefail
mode=$1
script=$(cd "$(dirname "$0")/../.." && pwd)/home.admin/config.scripts/blitz.data.sh
mount --make-rprivate /
root=$(mktemp -d)
trap 'umount -R "$root"; rmdir "$root"' EXIT
mount -t tmpfs -o size=16m /dev/sda2 "$root"
mkdir -p "$root"/{usr,proc,dev,boot,home/admin/config.scripts,mockbin,mnt,tmp,var/tmp}
mount --bind /usr "$root/usr"
mount -o remount,bind,ro "$root/usr"
ln -s usr/bin "$root/bin"
ln -s usr/lib "$root/lib"
if [ -d /usr/lib64 ]; then ln -s usr/lib64 "$root/lib64"; fi
mount -t proc proc "$root/proc"
ln -s /proc/self/fd "$root/dev/fd"
mknod "$root/dev/null" c 1 3
chmod 666 "$root/dev/null"
cp "$script" "$root/home/admin/config.scripts/blitz.data.sh"
mkdir "$root/home/admin/raspiblitz"
printf '#!/bin/bash\necho "computerType=pc"\n' > "$root/home/admin/config.scripts/blitz.hardware.sh"
printf '#!/bin/bash\nexit 0\n' > "$root/home/admin/_cache.sh"
chmod +x "$root/home/admin/config.scripts/blitz.hardware.sh" "$root/home/admin/_cache.sh"

storage=/mnt/disk_storage
if [ "$mode" = spaces ]; then storage='/mnt/disk storage'; fi
mkdir -p "$root$storage" "$root/mnt/disk_data"
mount -t tmpfs -o size=1m /dev/sdb1 "$root$storage"
mount -t tmpfs -o size=1m /dev/sdc1 "$root/mnt/disk_data"
mkdir "$root$storage/app-storage" "$root/mnt/disk_data/app-data"
if [ "$mode" = private ]; then
  mkdir -p "$root/tmp/private-tmp" "$root/var/tmp/private-tmp"
  mount --bind "$root/tmp/private-tmp" "$root/tmp"
  mount --bind "$root/var/tmp/private-tmp" "$root/var/tmp"
fi
if [ "$mode" = bind-only ]; then
  mkdir -p "$root$storage/subdir/app-storage" "$root/mnt/storage_bind"
  mount --bind "$root$storage/subdir" "$root/mnt/storage_bind"
  umount "$root$storage"
  storage=/mnt/storage_bind
fi

# Only hardware enumeration and unrelated probes are stubbed. findmnt, the
# complete production status script, path tests, and sourcing are real.
cat > "$root/mockbin/lsblk" <<'MOCK'
#!/bin/bash
case "$*" in
  '-b -n -l -o NAME,SIZE,FSTYPE,TYPE')
    printf 'sda2 68719476736 ext4 part\nsdb1 1073741824000 ext4 part\nsdc1 68719476736 ext4 part\n'
    if [ "$FIXTURE_MODE" = unmounted ]; then echo 'sdd1 68719476736 ext4 part'; fi ;;
  '-dno NAME,SIZE') printf 'sda 64G\nsdb 1000G\nsdc 64G\n' ;;
esac
MOCK
for probe in swapon partx smartctl parted; do
  printf '#!/bin/bash\nexit 0\n' > "$root/mockbin/$probe"
done
# Never let the production fallback mount anything, even inside this fixture.
cat > "$root/mockbin/mount" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> /mount-attempts
exit 1
MOCK
chmod +x "$root"/mockbin/*
ln -s "$(readlink -f "$(command -v awk)")" "$root/mockbin/awk"

cat > "$root/check.sh" <<'CHECK'
#!/bin/bash
set -eu
export PATH=/mockbin:/usr/bin:/bin
# Record real kernel topology and the exact original query for diagnosis.
findmnt -n -o SOURCE,TARGET,FSROOT
status_exit=0
bash /home/admin/config.scripts/blitz.data.sh status > /status.out 2>/status.err || status_exit=$?
cat /status.out
cat /status.err >&2
test "$status_exit" = 0
test ! -s /status.err
# The debug report consumes this exact production output as shell input.
source_exit=0
source /status.out 2>/source.err || source_exit=$?
cat /source.err >&2
test "$source_exit" = 0
test ! -s /source.err
test "$systemMountedPath" = /
test "$storageMountedPath" = "$EXPECTED_STORAGE"
test "$dataMountedPath" = /mnt/disk_data
test "$scenario" = ready
# Extract, do not reimplement, the production source-to-target assignment.
assignment=$(grep 'mountPath=$(findmnt.*"/dev/${name}"' /home/admin/config.scripts/blitz.data.sh)
name=sdd1
# A missing source returns nonzero, as before; production is not under set -e.
set +e
eval "$assignment"
set -e
test -z "$mountPath"
if [ "$FIXTURE_MODE" = unmounted ]; then
  grep -Fx '/dev/sdd1 /mnt/temp' /mount-attempts
  grep -Fx "error='cannot mount /dev/sdd1'" /status.out
else
  test ! -e /mount-attempts
fi
printf 'verified system=%s storage=%s data=%s scenario=%s\n' "$systemMountedPath" "$storageMountedPath" "$dataMountedPath" "$scenario"
CHECK
FIXTURE_MODE=$mode EXPECTED_STORAGE=$storage chroot "$root" /bin/bash /check.sh
