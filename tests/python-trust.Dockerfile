# Disposable Debian system-Python acceptance; never run against a live node.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 python3-pip python3-venv ca-certificates openssl git \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir /wheels && python3 -m pip download --no-deps --dest /wheels 'pip==26.2.2'
WORKDIR /src
COPY home.admin/config.scripts/blitz.python-trust.sh home.admin/config.scripts/blitz.python-trust.sh
COPY tests/python-trust-system.py tests/python-trust-system.py
ENV PYTHONDONTWRITEBYTECODE=1 PIP_CONFIG_FILE=/dev/null PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_INDEX=1 PIP_FIND_LINKS=/wheels
CMD ["python3", "tests/python-trust-system.py", "-v"]
