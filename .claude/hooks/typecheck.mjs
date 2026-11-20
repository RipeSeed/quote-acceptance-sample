import { execFileSync } from 'node:child_process';
import { block, projectDir, readInput } from './lib.mjs';

const input = await readInput();
const file = input.tool_input?.file_path ?? '';
if (!/\.(ts|mts|tsx)$/.test(file)) process.exit(0);

try {
  execFileSync('npx', ['--no-install', 'tsc', '--noEmit'], {
    cwd: projectDir(input),
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
} catch (error) {
  const output = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim().split('\n').slice(0, 40).join('\n');
  block(`Typecheck failed after editing ${file}:\n${output}`);
}
