import { block, git, readInput, relativePath } from './lib.mjs';

const input = await readInput();
const file = input.tool_input?.file_path;
if (!file) process.exit(0);

const path = relativePath(input, file);

if (/(^|\/)\.env(\.|$)/.test(path)) {
  block(`${path} holds secrets. Change it by hand, not through Claude.`);
}

if (/^supabase\/migrations\/[^/]+\.sql$/.test(path) && isOnMain(path)) {
  block(
    `${path} is already on main, so it may have run in production. ` +
      'Leave it as it is and add a new migration with `supabase migration new <name>`.',
  );
}

function isOnMain(path) {
  for (const ref of ['origin/main', 'main']) {
    try {
      git(input, ['cat-file', '-e', `${ref}:${path}`]);
      return true;
    } catch {
      // not on this ref
    }
  }
  return false;
}
