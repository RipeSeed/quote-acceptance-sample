import { execFileSync, execSync } from 'node:child_process';
import { block, git, projectDir, readInput } from './lib.mjs';

const input = await readInput();

// Claude is already continuing because of this hook; do not loop.
if (input.stop_hook_active) process.exit(0);

let changed;
try {
  changed = git(input, ['status', '--porcelain'])
    .split('\n')
    .map((line) => line.slice(3).trim())
    .filter(Boolean);
} catch {
  process.exit(0);
}

const touchesCode = changed.some((path) => /^(tests\/|supabase\/functions\/)/.test(path));
const touchesSql = changed.some((path) => /^supabase\/(migrations|tests)\//.test(path));
if (!touchesCode && !touchesSql) process.exit(0);

const cwd = projectDir(input);

// Same CLI version as CI when it is not installed globally.
const supabase = onPath('supabase') ? ['supabase'] : ['npx', '--yes', 'supabase@3.1.0'];

if (touchesCode) {
  run('npm', ['test', '--silent'], 'Vitest');
}

if (touchesSql) {
  if (!supabaseRunning()) {
    block('Migrations or pgTAP tests changed, but the local database is not running. Run `supabase db start`, then `supabase test db`, before finishing.');
  }
  run(supabase[0], [...supabase.slice(1), 'test', 'db'], 'pgTAP');
}

function onPath(command) {
  try {
    execSync(`command -v ${command}`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function run(command, args, label) {
  try {
    execFileSync(command, args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    const output = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim().split('\n').slice(-40).join('\n');
    block(`${label} tests fail. Fix them before you finish:\n${output}`);
  }
}

function supabaseRunning() {
  try {
    execFileSync(supabase[0], [...supabase.slice(1), 'status'], { cwd, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}
