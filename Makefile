SHELL = /bin/bash
GITHUB_USER = $(shell git remote -v | grep origin | head -1 | cut -d/ -f4)
CURRENT_BRANCH = $(shell git rev-parse --abbrev-ref HEAD)

amd64-lean-image:
	cd ci && \
	bash packer.build.amd64-lean.sh $(GITHUB_USER) $(CURRENT_BRANCH)

	cd builds/packer-debian-11.5-amd64-lean-qemu && \
	sha256sum debian-11.5-amd64-lean.qcow2 > debian-11.5-amd64-lean.qcow2.sha256

	cd builds/packer-debian-11.5-amd64-lean-qemu && \
	gzip -v9 debian-11.5-amd64-lean.qcow2

	cd builds/packer-debian-11.5-amd64-lean-qemu && \
	sha256sum debian-11.5-amd64-lean.qcow2.gz > debian-11.5-amd64-lean.qcow2.gz.sha256

amd64-fatpack-image:
	cd ci && \
	bash packer.build.amd64-fatpack.sh $(GITHUB_USER) $(CURRENT_BRANCH)

	cd builds/packer-debian-11.5-amd64-fatpack-qemu && \
	sha256sum debian-11.5-amd64-fatpack.qcow2 > debian-11.5-amd64-fatpack.qcow2.sha256

	cd builds/packer-debian-11.5-amd64-fatpack-qemu && \
	gzip -v9 debian-11.5-amd64-fatpack.qcow2

	cd builds/packer-debian-11.5-amd64-fatpack-qemu && \
	sha256sum debian-11.5-amd64-fatpack.qcow2.gz > debian-11.5-amd64-fatpack.qcow2.gz.sha256
