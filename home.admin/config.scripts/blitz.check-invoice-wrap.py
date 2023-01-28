#!/usr/bin/env python3
# adapted from: https://github.com/lnproxy/lnproxy-cli/blob/fe18d16e42b58f635b94c7da59a34d5e092e4d56/check-wrap.py
# Parses payment hashes and amounts in bolt11 invoices to check lnproxy
# Can skip most bolt11 checks since both the user's wallet and lnproxy will do that

from decimal import Decimal

CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
units = {
	'p': 10**12,
	'n': 10**9,
	'u': 10**6,
	'm': 10**3,
}

def parse(invoice):
	invoice = invoice.lower()
	pos = invoice.rfind('1')
	amount = invoice[4:pos]
	if amount == '':
		amount = Decimal(0)
	else:
		amount = Decimal(amount[:-1]) / units[amount[-1]]
	data = invoice[pos+1+7:]
	i = 0
	while i < len(data):
		if data[i] == 'p' and data[i+1:i+1+2] == 'p5':
			payment_hash = data[i+1+2:i+1+2+52]
			break
		else:
			i += 3 + CHARSET.find(data[i+1]) * 32 + CHARSET.find(data[i+1+1])
	return (amount, payment_hash)

from sys import stderr, argv
try:
	if len(argv) != 3:
		raise Exception("Incorrect number of arguments")

	amt1, hash1 = parse(argv[1])
	amt2, hash2 = parse(argv[2])

	if hash1 != hash2:
		print(f"Payment hashes do not match!", file=stderr)
		exit(3)

	if amt1 != Decimal(0):
		print(f"Hashes match, routing fee is {(amt2-amt1)*10**8:0,.0f} sat ({(amt2-amt1)/amt1*100:0.2f}%)")
	else:
		print(f"Hashes match")

except Exception as err:
	print('Error:', err)
	print(f"usage: {argv[0]} <original invoice> <wrapped invoice>", file=stderr)
	exit(2)
