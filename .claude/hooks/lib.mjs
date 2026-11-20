import { execFileSync } from 'node:child_process';
import { relative } from 'node:path';

export async function readInput() {
  let raw = '';
  for await (const chunk of process.stdin) raw += chunk;
  return raw ? JSON.parse(raw) : {};
}

export function projectDir(input) {
  return process.env.CLAUDE_PROJECT_DIR ?? input.cwd ?? process.cwd();
}

export function relativePath(input, file) {
  return relative(projectDir(input), file).split('\\').join('/');
}

export function git(input, args) {
  return execFileSync('git', args, { cwd: projectDir(input), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
}

// Exit code 2 blocks the tool call (PreToolUse) or hands the message back to
// Claude to act on (PostToolUse, Stop). stderr is what Claude reads.
export function block(message) {
  process.stderr.write(`${message}\n`);
  process.exit(2);
}
