import assert from 'node:assert/strict';

const [base = 'https://hoike.dev', expectedCommit] = process.argv.slice(2);
const checks = [
  ['/', 'OCSP responder'],
  ['/doc/', 'hoike documentation'],
  ['/doc/quickstart/install.html', 'Installation'],
  ['/doc/operator/configuration.html', 'Configuration'],
  ['/api/', 'Rust API reference'],
  ['/api/ahu/index.html', 'BundleBuilder'],
];
for (const [path, marker] of checks) {
  const response = await fetch(new URL(path, base), { signal: AbortSignal.timeout(20000) });
  assert.equal(response.status, 200, `${path}: HTTP ${response.status}`);
  assert.ok((await response.text()).includes(marker), `${path}: expected content missing`);
}
const response = await fetch(new URL('/build-info.json', base), { cache: 'no-store', signal: AbortSignal.timeout(20000) });
assert.equal(response.status, 200, 'Missing deployment metadata');
const info = await response.json();
if (expectedCommit) assert.equal(info.site_commit, expectedCommit, 'Deployed commit does not match');
console.log(`Smoke checks passed: ${base} · ${JSON.stringify(info)}`);
