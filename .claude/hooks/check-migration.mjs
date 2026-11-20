import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { block, projectDir, readInput, relativePath } from './lib.mjs';

const input = await readInput();
const file = input.tool_input?.file_path;
if (!file) process.exit(0);

const path = relativePath(input, file);
if (!/^supabase\/migrations\/[^/]+\.sql$/.test(path)) process.exit(0);

const sql = stripComments(readFileSync(file, 'utf8')).toLowerCase();
const testsDir = join(projectDir(input), 'supabase/tests/database');
const tests = readdirSync(testsDir)
  .filter((name) => name.endsWith('.sql'))
  .map((name) => readFileSync(join(testsDir, name), 'utf8').toLowerCase())
  .join('\n');

const problems = [];

for (const [, raw] of sql.matchAll(/create\s+table\s+(?:if\s+not\s+exists\s+)?([\w."]+)/g)) {
  const table = qualify(raw);
  const [, name] = table.split('.');
  const ref = `(?:public\\.)?"?${name}"?`;

  if (!new RegExp(`alter\\s+table\\s+(?:only\\s+)?${ref}\\s+enable\\s+row\\s+level\\s+security`).test(sql)) {
    problems.push(`${table}: RLS is not enabled in this migration.`);
  }
  if (!new RegExp(`create\\s+policy\\s+"[^"]+"\\s+on\\s+${ref}\\b`).test(sql)) {
    problems.push(`${table}: no policy. Add one per command the app needs, or explain in the plan why there is none.`);
  }
  if (!new RegExp(`revoke\\s+all\\s+on\\s+[^;]*${ref}[^;]*from\\s+anon`).test(sql)) {
    problems.push(`${table}: start with "revoke all ... from anon, authenticated", then grant explicitly.`);
  }
  if (!tests.includes(table)) {
    problems.push(`${table}: no pgTAP test in supabase/tests/database/ mentions it.`);
  }
}

for (const fn of sql.match(/create\s+(?:or\s+replace\s+)?function[\s\S]*?\bas\s+\$[\w]*\$/g) ?? []) {
  if (fn.includes('security definer') && !/set\s+search_path\s*=\s*''/.test(fn)) {
    const name = fn.match(/function\s+([\w.]+)/)?.[1] ?? 'a function';
    problems.push(`${name}: security definer without set search_path = ''.`);
  }
}

if (problems.length > 0) {
  block(`${path} breaks the database rules (.claude/rules/database.md):\n- ${problems.join('\n- ')}`);
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/--[^\n]*/g, '');
}

function qualify(name) {
  const clean = name.replaceAll('"', '');
  return clean.includes('.') ? clean : `public.${clean}`;
}
