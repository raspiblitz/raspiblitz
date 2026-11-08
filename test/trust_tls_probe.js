'use strict';

// Read-only, opt-in network regression. Run with the candidate Node binary.
const https = require('node:https');
const assert = require('node:assert/strict');
const blocked = [];
for (const kind of ['dv', 'ov', 'ev']) {
  for (const gen of ['g3b', 'g3c']) {
    for (const cross of ['', '-aaa']) {
      blocked.push(`${kind}-${gen}${cross}-emudhra.we-have-a-problem.com`);
    }
  }
}
blocked.push('dv-g3b-noct-emudhra.we-have-a-problem.com');
blocked.push('dv-g3b-aaa-noct-emudhra.we-have-a-problem.com');
const allowed = ['bitcoincore.org', 'api.github.com', 'registry.npmjs.org', 'pypi.org'];

function probe(host, port = 443, ca = undefined) {
  return new Promise((resolve) => {
    const req = https.get({hostname: host, path: '/', port, ca,
      headers: {'User-Agent': 'RaspiBlitz-trust-regression'}}, (res) => {
      res.resume();
      resolve({host, status: res.statusCode, authorized: res.socket.authorized});
    });
    req.setTimeout(20000, () => req.destroy(new Error('timeout')));
    req.on('error', (err) => resolve({host, error: err.code || err.message}));
  });
}

function assertResult(result, isBlocked) {
  if (isBlocked) {
    assert.ok(['CERT_REVOKED', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY',
      'UNABLE_TO_VERIFY_LEAF_SIGNATURE'].includes(result.error),
    `Expected certificate rejection for ${result.host}, not a network failure`);
  } else {
    assert.equal(result.authorized, true, result.host);
    assert.equal(result.status, 200, result.host);
  }
}

async function main() {
  const results = await Promise.all([...blocked, ...allowed].map((host) => probe(host)));
  for (const result of results) {
    console.log(JSON.stringify(result));
    assertResult(result, blocked.includes(result.host));
  }
  console.log(`PASS ${blocked.length} negative and ${allowed.length} positive TLS controls on ${process.version}`);
}

module.exports = {probe, assertResult};
if (require.main === module) {
  main().catch((err) => { console.error(err.message); process.exitCode = 1; });
}
