import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const revision = (cwd) => execFileSync('git', ['rev-parse', 'HEAD'], { cwd, encoding: 'utf8' }).trim();
writeFileSync('deploy/build-info.json', JSON.stringify({
  site_commit: revision(process.cwd()),
  api_commit: revision(process.argv[2]),
  built_at: new Date().toISOString(),
}, null, 2) + '\n');
