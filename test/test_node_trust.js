'use strict';
// Synthetic loopback fixtures qualify store failure handling, not the incident.
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const https = require('node:https');
const {probe, assertResult} = require('./trust_tls_probe');
let directory, server, port, certificate, other;

before(async () => {
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'node-trust-'));
  for (const name of ['local', 'other']) {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
      '-keyout', path.join(directory, `${name}.key`), '-out', path.join(directory, `${name}.pem`),
      '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost'], {stdio: 'ignore'});
  }
  certificate = fs.readFileSync(path.join(directory, 'local.pem'));
  other = fs.readFileSync(path.join(directory, 'other.pem'));
  server = https.createServer({key: fs.readFileSync(path.join(directory, 'local.key')), cert: certificate},
    (_req, res) => { res.writeHead(200); res.end('fixture'); });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  port = server.address().port;
});
after(async () => {
  if (server) await new Promise((resolve) => server.close(resolve));
  if (directory) fs.rmSync(directory, {recursive: true, force: true});
});

test('explicit correct private CA authorizes actual HTTPS', async () => {
  const result = await probe('localhost', port, certificate);
  assertResult(result, false);
});
for (const kind of ['missing', 'wrong', 'malformed']) {
  test(`${kind} Node CA store rejects actual HTTPS, never an authorized response`, async () => {
    const ca = kind === 'missing' ? undefined : kind === 'wrong' ? other : Buffer.from('not a PEM CA');
    const result = await probe('localhost', port, ca);
    assert.equal(result.error, 'DEPTH_ZERO_SELF_SIGNED_CERT');
    assert.throws(() => assertResult(result, false));
  });
}
test('network failures and accepted negative controls cannot satisfy incident rejection', () => {
  for (const result of [{error: 'ECONNREFUSED'}, {error: 'ENOTFOUND'}, {error: 'timeout'},
    {authorized: true, status: 200}, {error: 'CERT_HAS_EXPIRED'}]) {
    assert.throws(() => assertResult({host: 'fixture', ...result}, true));
  }
  for (const error of ['CERT_REVOKED', 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY', 'UNABLE_TO_VERIFY_LEAF_SIGNATURE']) {
    assertResult({host: 'fixture', error}, true);
  }
});
test('positive controls require both authorization and HTTP 200', () => {
  assert.throws(() => assertResult({host: 'fixture', authorized: false, status: 200}, false));
  assert.throws(() => assertResult({host: 'fixture', authorized: true, status: 503}, false));
});
