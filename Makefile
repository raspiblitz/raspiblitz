SHELL = /bin/bash
GITHUB_ACTOR = $(shell git remote -v | grep origin | head -1 | cut -d/ -f4)
GITHUB_HEAD_REF = $(shell git rev-parse --abbrev-ref HEAD)

amd64-lean-desktop-uefi-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot uefi \
	  --desktop gnome

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.qcow2 > raspiblitz-amd64-debian-lean.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	gzip -v9 raspiblitz-amd64-debian-lean.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.qcow2.gz > raspiblitz-amd64-debian-lean.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu/raspiblitz-amd64-debian-lean.qcow2.*

amd64-lean-desktop-uefi-img:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot uefi \
	  --desktop gnome \
		--image_type raw

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.img > raspiblitz-amd64-debian-lean.img.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	gzip -v9 raspiblitz-amd64-debian-lean.img

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.img.gz > raspiblitz-amd64-debian-lean.img.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu/raspiblitz-amd64-debian-lean.img.*

amd64-lean-server-legacyboot-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	  --pack lean \
	  --github_user $(GITHUB_ACTOR) \
	  --branch $(GITHUB_HEAD_REF) \
	  --preseed_file preseed.cfg \
	  --boot bios-256k.bin \
	  --desktop none

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.qcow2 > raspiblitz-amd64-debian-lean.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	gzip -v9 raspiblitz-amd64-debian-lean.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu && \
	sha256sum raspiblitz-amd64-debian-lean.qcow2.gz > raspiblitz-amd64-debian-lean.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu/raspiblitz-amd64-debian-lean.qcow2.*

amd64-fatpack-desktop-uefi-image:
	# Run the build script
	cd ci/amd64 && \
	sudo bash packer.build.amd64-debian.sh \
	--pack fatpack \
	--github_user $(GITHUB_ACTOR) \
	--branch $(GITHUB_HEAD_REF) \
	--preseed_file preseed.cfg \
	--boot uefi \
	--desktop gnome

	# Compute the checksum of the qemu image
	cd ci/amd64/builds/raspiblitz-amd64-debian-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-fatpack.qcow2 > raspiblitz-amd64-debian-fatpack.qcow2.sha256

	# Compress the image
	cd ci/amd64/builds/raspiblitz-amd64-debian-fatpack-qemu && \
	gzip -v9 raspiblitz-amd64-debian-fatpack.qcow2

	# Compute the checksum of the compressed image
	cd ci/amd64/builds/raspiblitz-amd64-debian-fatpack-qemu && \
	sha256sum raspiblitz-amd64-debian-fatpack.qcow2.gz > raspiblitz-amd64-debian-fatpack.qcow2.gz.sha256

	# List the generated files
	ls -lah ci/amd64/builds/raspiblitz-amd64-debian-lean-qemu/raspiblitz-amd64-debian-fatpack.qcow2.*

arm64-rpi-lean-image:
	# Run the build script
	cd ci/arm64-rpi && \
	sudo bash packer.build.arm64-rpi.local.sh \
	--pack lean \
	--github_user $(GITHUB_ACTOR) \
	--branch $(GITHUB_HEAD_REF)

	# Compute the checksum of the raw image
	cd ci/arm64-rpi/packer-builder-arm && \
	sha256sum raspiblitz-arm64-rpi-lean.img > raspiblitz-arm64-rpi-lean.img.sha256

	# Compress the image
	cd ci/arm64-rpi/packer-builder-arm  && \
	gzip -v9 raspiblitz-arm64-rpi-lean.img

	# Compute the checksum of the compressed image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblitz-arm64-rpi-lean.img.gz > raspiblitz-arm64-rpi-lean.img.gz.sha256

	# List the generated files
	ls -lah ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-lean.img.*

arm64-rpi-fatpack-image:
	# Run the build script
	cd ci/arm64-rpi && \
	bash packer.build.arm64-rpi.local.sh \
	--pack fatpack \
	--github_user $(GITHUB_ACTOR) \
	--branch $(GITHUB_HEAD_REF)

	# Compute the checksum of the raw image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img > raspiblitz-arm64-rpi-fatpack.img.sha256

	# Compress the image
	cd ci/arm64-rpi/packer-builder-arm  && \
	gzip -v9 raspiblitz-arm64-rpi-fatpack.img

	# Compute the checksum of the compressed image
	cd ci/arm64-rpi/packer-builder-arm  && \
	sha256sum raspiblitz-arm64-rpi-fatpack.img.gz > raspiblitz-arm64-rpi-fatpack.img.gz.sha256

	# List the generated files
	ls -lah ci/arm64-rpi/packer-builder-arm/raspiblitz-arm64-rpi-fatpack.img.*
