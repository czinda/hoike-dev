import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const required = ['index.html', 'favicon.svg', 'doc/index.html', 'doc/quickstart/install.html',
  'doc/operator/configuration.html', 'doc/compliance/rfc-support.html', 'api/index.html',
  'api/ahu/index.html', 'api/hoike_core/index.html', 'api/hoike_server/index.html',
  'api/hoike_sign/index.html', 'api/hoike_gossip/index.html', 'api/hoike/index.html'];
for (const path of required) assert.ok(statSync(join('deploy', path)).size > 0, `Missing output: ${path}`);
assert.ok(readFileSync('deploy/api/index.html', 'utf8').includes('Rust API reference'), 'API root must be a real index');
assert.ok(readFileSync('deploy/api/ahu/index.html', 'utf8').includes('BundleBuilder'), 'ahu library documentation was replaced by CLI documentation');
const info = JSON.parse(readFileSync('deploy/build-info.json', 'utf8'));
assert.match(info.site_commit, /^[0-9a-f]{40}$/);
assert.match(info.api_commit, /^[0-9a-f]{40}$/);
let count = 0;
function inspect(directory) {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) inspect(path);
    else {
      assert.ok(entry.isFile(), `Unexpected non-file asset: ${path}`);
      assert.ok(statSync(path).size <= 25 * 1024 * 1024, `Asset exceeds 25 MiB: ${path}`);
      count++;
    }
  }
}
inspect('deploy');
assert.ok(count <= 20000, `Too many static assets: ${count}`);
console.log(`Site checks passed: ${required.length} entry points, ${count} assets, API commit ${info.api_commit}`);
