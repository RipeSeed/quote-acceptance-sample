import { block, readInput } from './lib.mjs';

const input = await readInput();
const command = input.tool_input?.command ?? '';

const rules = [
  [/\bsupabase\s+(db\s+push|functions\s+deploy|link)\b/, 'Deploys and project links go through CI. Push a branch and open a PR.'],
  [/\bgit\s+push\b[^;&|]*\s(origin\s+)?(HEAD:)?(main|master)\b/, 'Never push to main. Push your branch and open a PR.'],
  [/\bgit\s+push\b[^;&|]*\s(-f|--force)(?=\s|$)/, 'No force pushes. Use --force-with-lease on your own branch if you must.'],
  [/--no-verify\b/, 'Do not skip git hooks.'],
  [/\bdisable\s+row\s+level\s+security\b/i, 'RLS stays on. Fix the policy or the test instead.'],
  [/\bsupabase\s+db\s+reset\b[^;&|]*--linked\b/, 'Never reset a linked (remote) database.'],
];

for (const [pattern, reason] of rules) {
  if (pattern.test(command)) block(`Blocked: ${reason}\nCommand: ${command}`);
}
