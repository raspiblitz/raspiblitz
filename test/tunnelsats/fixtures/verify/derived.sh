#!/bin/bash
# Derives verify documents from real ones, one jq edit each (see README.md). They cover states the
# pinned tool cannot produce on its own (impl_mismatch: it refuses an inventory that pairs cln with
# lnd.service) and deliberately broken or hostile documents.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

src="activating_tunnel_up.json"
jq -c '.contract = 2' "$src" > contract2.json
jq -r 'tojson | .[0:300]' "$src" > malformed.json
jq -c '(.checks[] | select(.id == "attest")) |= (.result = "fail")' "$src" > unsafe_fail_rc5.json
jq -c '.checks |= map(select(.id != "slice_id"))' "$src" > missing_check.json
jq -c '., .' "$src" > two_documents.json
jq -c '.impl = "cln"' "$src" > impl_mismatch.json
jq -c '.endpoint.host = "de2.tunnelsats.com --externalip=$(id)"' "$src" > host_injection.json
jq -c '.endpoint.host = "DE2.tunnelsats.com"' "$src" > host_uppercase.json
jq -c '.endpoint.vpn_port = "24556"' "$src" > vpn_port_string.json
jq -c '.endpoint.vpn_port = 70000' "$src" > vpn_port_range.json
jq -c '.probes = "run"' "$src" > probes_run.json
jq -c '.verdict = "protected"' "$src" > verdict_mismatch.json
jq -c '.exit_code = 6' not_installed.json > failed_rc6.json
jq -c '.endpoint.ipv4 = "192.168.1.20"' cln_activating_tunnel_up.json > cln_ipv4_private.json
echo "wrote the derived documents"
