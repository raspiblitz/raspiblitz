FROM ubuntu:22.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 bash jq dpkg sudo \
    && useradd --uid 1000 --no-create-home bitcoin \
    && rm -rf /var/lib/apt/lists/*
ENV FEEADJUSTER_TEST_CONTAINER=1
