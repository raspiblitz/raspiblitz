# Historical JDK is intentional: it must reproduce accepted-before PKIX paths.
FROM eclipse-temurin:17.0.19_10-jdk-jammy@sha256:9283f99ad21802850dd7420a865c495642a804c5a201f73377aef232ef12bccb AS baseline
FROM node:22.23.4-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 bats shellcheck git ca-certificates openssl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=baseline /opt/java/openjdk /opt/baseline-java
ENV PATH="/opt/baseline-java/bin:${PATH}"
WORKDIR /src
COPY . /src
# Fetch third-party public certificate data rather than redistribute an archive
# without explicit licensing terms. A changed or unavailable fixture fails build.
RUN python3 -c 'import hashlib,pathlib,urllib.request; data=urllib.request.urlopen("https://emudhra.we-have-a-problem.com/chains.zip", timeout=60).read(); assert hashlib.sha256(data).hexdigest()=="afb9d69e8e5fc9eb0c08d5fe4baafc67edbcced2d63af2f9deb62edb6431d4a9", "Incident fixture digest mismatch"; pathlib.Path("test/fixtures/incident-chains.zip").write_bytes(data)'
CMD ["bash", "test/run-trust-tests.sh"]
