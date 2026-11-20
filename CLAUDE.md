# Quote acceptance

Customers accept a quote through a link with a secret token. Office staff manage quotes; technicians see accepted work only.

Stack: Supabase (Postgres 17, RLS, Edge Functions on Deno), TypeScript, Vitest, pgTAP.

## Commands
- `npm test`: Edge Function unit tests (Vitest)
- `npm run typecheck`
- `supabase db start`, then `supabase test db`: pgTAP tests (Docker must be running)
- `supabase db reset`: re-apply migrations and the seed
- `supabase migration new <name>`: create a new migration file

## How we work
- A change to tables, policies or functions starts with a plan in `docs/plans/<topic>.md`; use `/plan <topic>`. Write no migration before the plan is approved.
- One branch per task. Open a PR. Never push to `main`. Never run `supabase db push` or `supabase functions deploy` from a laptop: CI does that.
- "Done" means all of these:
  - typecheck, Vitest and pgTAP are green in CI
  - the Claude review has no open `[high]` finding
  - the PR description links the plan and lists the tests added
- Before opening a PR that touches `supabase/migrations/`, run the `rls-reviewer` agent.

## Rules
The detailed rules are in `.claude/rules/`. They load when you work on matching files. Here is the short version:
- **RLS:** turn RLS on for every table. Grant access explicitly, with one policy for each command a role is allowed.
- **pgTAP:** test every policy twice: once with a role that is allowed, once with a role that is denied.
- **Migrations:** never edit a migration that is already on `main`. Add a new one.
- **Failing tests:** never loosen a policy or a grant to make a test pass. Decide whether the policy or the test is wrong, and say why in the PR.

## Repository map
- `supabase/migrations/`: schema, RLS and functions, one file per change
- `supabase/tests/database/`: pgTAP tests, one file per area
- `supabase/functions/accept-quote/`: `handler.ts` holds the logic, `index.ts` wires it to Deno and Supabase
- `tests/`: Vitest tests for the Edge Function handlers
- `docs/plans/`: one plan per change
