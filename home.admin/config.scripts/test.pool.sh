$ pool -n=testnet accounts new --amt=15000000 --expiry_blocks=2016
-- Account Funding Details --
Amount: 0.15 BTC
Confirmation target: 6 blocks
Fee rate (estimated): 1.0 sat/vByte
Total miner fee (estimated): 0.00000293 BTC
Confirm account (yes/no): yes
{
	"trader_key": "036e6696df4fcbd777817fa66119bdb6ded29eb8d70333393264954c94982bce5f",
	"outpoint": "fe2243f049f1c17513481a8fecf3b6522dd19786741e2db5e54ad4913d2f1c66:0",
	"value": 15000000,
	"available_balance": 0,
	"expiration_height": 1837962,
	"state": "PENDING_OPEN",
	"latest_txid": "fe2243f049f1c17513481a8fecf3b6522dd19786741e2db5e54ad4913d2f1c66"
}


pool orders submit ask 10000000 036e6696df4fcbd777817fa66119bdb6ded29eb8d70333393264954c94982bce5f --interest_rate_percent=0.3 --max_duration_blocks=3000