# Running tests

## Install bats
```
sudo apt install bats
```

## Data-drive mount detection

`blitz.data-mounts.bats` runs the actual `blitz.data.sh status` script against
small tmpfs filesystems, with hardware enumeration and unrelated probes stubbed.
It checks ordinary root/storage/data mounts, PrivateTmp-style bind mounts,
mount paths containing spaces, an unmounted source, and a bind-only source.
It also sources the status output in the same way the debug report does.

Run it only in a disposable Linux container with mount-namespace privileges,
not on a RaspiBlitz or a container with host directories or devices attached.
For example, from the repository root (Docker must be using a Linux engine):

```sh
docker build -t raspiblitz-mount-tests - <<'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bats util-linux mawk && rm -rf /var/lib/apt/lists/*
DOCKERFILE
tar -cf - home.admin/config.scripts/blitz.data.sh test/blitz.data-mounts.bats test/fixtures/blitz.data-mounts.sh | \
  docker run --rm -i --privileged --network none -e BLITZ_DISPOSABLE_MOUNT_TEST=1 \
    raspiblitz-mount-tests bash -c 'mkdir /work; tar -xf - -C /work; bats --verbose-run /work/test/blitz.data-mounts.bats'
```

The tar stream copies only test inputs into the container. There are no host
bind mounts or real block-device fixtures. The opt-in environment variable
prevents accidental execution during ordinary Bats runs. No PostgreSQL tests
or services are needed.

## Run tests manually
```
bats --verbose-run ./bonus.postgresql-13.bats
bats --verbose-run ./bonus.postgresql-15.bats
```
