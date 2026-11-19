# API responses

`GET /api/public/v1/servers` (tunnelsats-v2-web, `src/app/api/public/v1/servers/route.ts`; OpenAPI schema `Server`): `servers.json` is the live 200 body returning the 7 offered regions (`us-east` Ashburn, `us-west` Hillsboro, `eu-de` Nuremberg, `asia-sg` Singapore, `sa-br` Sao Paulo, `oc-au` Sydney, `eu-ch` Geneva) with `"status": "online"`.

Shapes of `POST /api/public/v1/subscription/status` (tunnelsats-v2-web, `src/app/api/public/v1/subscription/status/route.ts`): the 200 body is a flat object (`expiry`, `bandwidth_used_gb`, `bandwidth_limit_gb`, `bandwidth_resets_this_month`, `max_resets_per_month`, `status`, `server_domain`, `vpn_port`, `last_synced_at`); errors use `{"error": "ERR_...", "message": ...}` (404 `ERR_RESOURCE_NOT_FOUND`, 503 `ERR_SERVICE_UNAVAILABLE` with `Retry-After`, 429 `ERR_RATE_LIMIT_EXCEEDED`, 403 `ERR_MIGRATION_REQUIRED`, 500 `ERR_INTERNAL_ERROR`).

`POST /api/public/v1/subscription/claim` for an order created with a `wgPublicKey` (`src/lib/claim-service.ts`, `claimClientHeldKeyOrder`; API docs schema `ClaimResult`): `claim_client_held.json` is the 200 body (`server.endpoint`, `server.publicKey`, `server.allowedIPs` as the string `"0.0.0.0/0, ::/0"`, `peer.address` without a prefix length, `peer.publicKey`, `peer.presharedKey`, top-level `vpnPort`, `subscriptionEnd`, `fullConfig: null`). `claim_processing.json` is the 202 body while the tunnel is still provisioned ("retry the claim"), `error_payment_not_confirmed.json` the 402 body when the API does not see the payment yet.

`GET /api/public/v1/subscription/{paymentHash}` (`src/app/api/public/v1/subscription/[paymentHash]/route.ts`): `order_processing.json` is the 202 body of a paid order (or renewal) that the API is still provisioning.
