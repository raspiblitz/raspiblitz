SHELL = /bin/bash
GITHUB_USER = $(shell git remote -v | grep origin | head -1 | cut -d/ -f4)
CURRENT_BRANCH = $(shell git rev-parse --abbrev-ref HEAD)

amd64-lean-image:
	# Run the build script
	cd ci/amd64 && \
	bash packer.build.amd64-debian.sh lean $(GITHUB_USER) $(CURRENT_BRANCH) 0

	# Compute checksum of the raw image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-lean.qcow2 > raspiblitz-amd64-debian-11.5-lean.qcow2.sha256

	# Compress image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	gzip -v9 raspiblitz-amd64-debian-11.5-lean.qcow2

	# Compute checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-lean.qcow2.gz > raspiblitz-amd64-debian-11.5-lean.qcow2.gz.sha256

amd64-fatpack-image:
	# Run the build script
	cd ci/amd64 && \
	bash packer.build.amd64-debian.sh fatpack $(GITHUB_USER) $(CURRENT_BRANCH)

	# Compute checksum of the raw image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-fatpack.qcow2 > raspiblitz-amd64-debian-11.5-fatpack.qcow2.sha256

	# Compress image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	gzip -v9 raspiblitz-amd64-debian-11.5-fatpack.qcow2

	# Compute checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-11.5-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-11.5-fatpack.qcow2.gz > raspiblitz-amd64-debian-11.5-fatpack.qcow2.gz.sha256

arm64-rpi-lean-image:
	# Run the build script
	cd ci/arm64-rpi && \
	bash packer.build.arm64-rpi.sh lean $(GITHUB_USER) $(CURRENT_BRANCH)

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
	bash packer.build.arm64-rpi.sh fatpack $(GITHUB_USER) $(CURRENT_BRANCH)

	# Compute checksum of the raw image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img > raspiblitz-arm64-rpi-fatpack.img.sha256

	# Compress image
	cd ci/arm64-rpi && \
	gzip -v9 raspiblitz-arm64-rpi-fatpack.img

	# Compute checksum of the compressed image
	cd ci/arm64-rpi && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img.gz > raspiblitz-arm64-rpi-fatpack.img.gz.sha256
