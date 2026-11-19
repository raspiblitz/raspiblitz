FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends bash coreutils grep sed jq python3 shellcheck && rm -rf /var/lib/apt/lists/*
