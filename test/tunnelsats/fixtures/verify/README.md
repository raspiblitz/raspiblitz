# Verify documents for the start guard tests

Each `*.json` here is a `tunnelsats.sh verify --json --no-probe` document as the start guard reads it.

## Real documents (`generate.sh`)

Produced by TunnelSats' own unprivileged harness (`scripts/test_managed_dataplane.sh`: the production functions of `tunnelsats.sh` against a fixture tree with stateful stubs for `ip`, `nft`, `systemctl`, `getent` and `wg`) at the pinned commit. `generate.sh` refuses a checkout whose `scripts/tunnelsats.sh` does not match `TS_PIN_SHA256` in `internet.tunnelsats.sh`. Regenerate after every re-pin:

```sh
test/tunnelsats/fixtures/verify/generate.sh <tunnelsats checkout at the pinned commit>
```

The fixture is a managed `raspiblitz` install (endpoint `de2.tunnelsats.com:51820` resolving to `1.2.3.4`, `# Port Forwarding: 24556`), with the Lightning unit in `ExecStartPre` (`ActiveState=activating`) unless noted.

| File | State | Exit |
| :-- | :-- | :-- |
| `activating_tunnel_up.json`, `cln_activating_tunnel_up.json` | kill switch armed, tunnel up, fresh handshake, live endpoint equals the resolved one | 5 |
| `protected.json`, `cln_protected.json` | as above with the unit active (outside `ExecStartPre`) | 0 |
| `activating_no_handshake.json`, `cln_...` | interface up, endpoint matching, no handshake yet | 5 |
| `activating_endpoint_none.json`, `cln_...` | interface up, no live endpoint yet | 5 |
| `activating_tunnel_down.json`, `cln_...` | interface down | 5 |
| `activating_dns_unresolved.json`, `cln_...` | the endpoint host does not resolve (`ipv4: null`) | 5 |
| `activating_dns_timeout.json`, `cln_...` | the name server does not answer: verify cuts the endpoint lookup off (`ipv4: null`, `wg_endpoint` names the lookup; generated with `TS_VERIFY_RESOLVE_TIMEOUT=1`, the default is 5 s) | 5 |
| `activating_endpoint_mismatch.json`, `cln_...` | live endpoint differs from the resolved one | 5 |
| `activating_emergency_block.json`, `cln_...` | kill switch table gone, uid emergency block in effect (`emergency_block: true`) | 5 |
| `activating_route_missing.json` | tunnel up, its route in table 51820 missing (degraded class) | 5 |
| `activating_emergency_leftover.json` | emergency rules left beside an armed kill switch (`emergency_block: false`) | 5 |
| `dropin_missing.json` | Lightning drop-in not loaded | 4 |
| `state_removing.json` | inventory state `removing` | 4 |
| `unit_tlnd.json` | managed install for `tlnd.service` | 5 |
| `vpn_port_null.json` | config without `# Port Forwarding:` | 5 |
| `host_foreign.json` | endpoint host outside `*.tunnelsats.com` | 5 |
| `damaged_record.json` | inventory missing, emergency block for the kill switch unit's fallback uid (`unit: null`) | 5 |
| `not_installed.json` | no install | 3 |
| `unmanaged.json` | standard (legacy v3) install | 9 |

## Derived documents (`derived.sh`, one `jq` edit each)

| File | Source | Edit |
| :-- | :-- | :-- |
| `contract2.json` | `activating_tunnel_up.json` | `.contract = 2` |
| `malformed.json` | `activating_tunnel_up.json` | `tojson \| .[0:300]` (truncated text) |
| `unsafe_fail_rc5.json` | `activating_tunnel_up.json` | `(.checks[] \| select(.id == "attest")) \|= (.result = "fail")` |
| `missing_check.json` | `activating_tunnel_up.json` | `.checks \|= map(select(.id != "slice_id"))` |
| `two_documents.json` | `activating_tunnel_up.json` | `., .` |
| `impl_mismatch.json` | `activating_tunnel_up.json` | `.impl = "cln"` (the pinned tool refuses such an inventory, so only a derived document has this state) |
| `host_injection.json` | `activating_tunnel_up.json` | `.endpoint.host = "de2.tunnelsats.com --externalip=$(id)"` |
| `host_uppercase.json` | `activating_tunnel_up.json` | `.endpoint.host = "DE2.tunnelsats.com"` |
| `vpn_port_string.json` | `activating_tunnel_up.json` | `.endpoint.vpn_port = "24556"` |
| `vpn_port_range.json` | `activating_tunnel_up.json` | `.endpoint.vpn_port = 70000` |
| `probes_run.json` | `activating_tunnel_up.json` | `.probes = "run"` |
| `verdict_mismatch.json` | `activating_tunnel_up.json` | `.verdict = "protected"` |
| `failed_rc6.json` | `not_installed.json` | `.exit_code = 6` |
| `cln_ipv4_private.json` | `cln_activating_tunnel_up.json` | `.endpoint.ipv4 = "192.168.1.20"` |

No document holds key material: `verify` never prints the private key.
