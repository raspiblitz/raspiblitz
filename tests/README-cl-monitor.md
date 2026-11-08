# Core Lightning monitor readiness

Run the real monitor status entrypoint with synthetic service/RPC fixtures:

```sh
docker build -f tests/cl-monitor.Dockerfile -t raspiblitz-cl-monitor-tests .
python3 tests/test_cl_monitor_status.py home.admin/config.scripts/cl.monitor.sh
```

Thirteen cases cover normal and zero-peer responses, empty/malformed/multiple
responses, missing fields, fractional/negative peer counts, stderr and silent
nonzero exits, including failures that still emit valid JSON. A running service
must not become ready merely because its RPC stderr is empty.

The execution container has no network or host mounts, a read-only root,
no capabilities and disposable tmpfs fixture directories. Root is used only
inside that container because the production monitor requires it. No actual
Lightning daemon, wallet or node is accessed. This is focused status coverage,
not full monitor/background-loop or appliance acceptance. Set
`CL_MONITOR_TEST_IMAGE` only to reuse an equivalent local test dependency image.
