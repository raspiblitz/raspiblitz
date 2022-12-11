SHELL = /bin/bash
GITHUB_ACTOR = $(shell git remote -v | grep origin | head -1 | cut -d/ -f4)
GITHUB_HEAD_REF = $(shell git rev-parse --abbrev-ref HEAD)

amd64-lean-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh lean $(GITHUB_ACTOR) $(GITHUB_HEAD_REF) 0

	# Compute checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-lean.qemu > raspiblitz-amd64-debian-11.5-lean.qemu.sha256

	# Compress image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	gzip -v9 raspiblitz-amd64-debian-11.5-lean.qemu

	# Compute checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-lean.qemu.gz > raspiblitz-amd64-debian-11.5-lean.qemu.gz.sha256

amd64-fatpack-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh fatpack $(GITHUB_ACTOR) $(GITHUB_HEAD_REF)

	# Compute checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-fatpack.qemu > raspiblitz-amd64-debian-11.5-fatpack.qemu.sha256

	# Compress image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	gzip -v9 raspiblitz-amd64-debian-11.5-fatpack.qemu

	# Compute checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-fatpack.qemu.gz > raspiblitz-amd64-debian-11.5-fatpack.qemu.gz.sha256

arm64-rpi-lean-image:
	# Run the build script
	cd ci/arm64-rpi && \
	sudo bash packer.build.arm64-rpi.local.sh lean $(GITHUB_ACTOR) $(GITHUB_HEAD_REF)

	# Compute checksum of the raw image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-lean.img > raspiblitz-arm64-rpi-lean.img.sha256

	# Compress image
	cd ci/arm64-rpi && \
	gzip -v9 raspiblitz-arm64-rpi-lean.img

	# Compute checksum of the compressed image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-lean.img.gz > raspiblitz-arm64-rpi-lean.img.gz.sha256

arm64-rpi-fatpack-image:
	# Run the build script
	cd ci/arm64-rpi && \
	sudo bash packer.build.arm64-rpi.local.sh fatpack $(GITHUB_ACTOR) $(GITHUB_HEAD_REF)

	# Compute checksum of the raw image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img > raspiblitz-arm64-rpi-fatpack.img.sha256

	# Compress image
	cd ci/arm64-rpi && \
	gzip -v9 raspiblitz-arm64-rpi-fatpack.img

	# Compute checksum of the compressed image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img.gz > raspiblitz-arm64-rpi-fatpack.img.gz.sha256
