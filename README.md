# Quote acceptance sample

A customer gets a quote with a link that contains a secret token. Clicking "Accept" calls an Edge Function, which accepts the quote in a single database call. Office staff manage quotes; technicians only see accepted work.

## What's inside

| Requested | Where |
| --- | --- |
| Migration | `supabase/migrations/20261111090000_quotes_and_acceptance.sql` |
| RLS policies | Same migration, after the tables and helper functions |
| Edge Function | `supabase/functions/accept-quote/` (`handler.ts` holds the logic, `index.ts` wires it to Deno and Supabase) |
| Tests | `supabase/tests/database/*.test.sql` (pgTAP) and `tests/accept-quote.test.ts` (Vitest) |

Also included: `supabase/seed.sql` (demo data) and `.github/workflows/ci.yml` (runs both test suites on pull requests).

## Access rules

- **admin, office**: manage customers and quotes. Quote items can only be changed while the quote is a draft.
- **technician**: reads customers and accepted quotes only.
- **delete**: only admins, and only draft quotes.
- **anonymous**: no table access. Customers accept through the Edge Function, which is the only caller of `accept_quote`.

`quotes.net_total` is kept up to date by a trigger. Clients cannot write it, the token, or the acceptance time directly.

## Edge Function responses

`POST /functions/v1/accept-quote` with `{"token": "<uuid>"}`:

| Status | Meaning |
| --- | --- |
| 200 | `accepted` |
| 404 | `not_found` |
| 409 | `already_accepted` or `not_open` (draft or cancelled) |
| 410 | `expired` |
| 400 | Body is not JSON, or the token is missing or not a UUID |
| 405 | Method other than `POST` (or `OPTIONS` for CORS) |
| 500 | Unexpected error; details are logged, not returned |

## Prerequisites

- Node.js 20 or newer
- Docker, running
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) (or put `npx` in front of the `supabase` commands below)

## Running it

**1. Edge Function unit tests** (no Docker needed)

```sh
npm install
npm test
npm run typecheck
```

**2. Database tests**

```sh
supabase start
supabase test db
```

`supabase start` applies the migration and loads `supabase/seed.sql`.

**3. Try the Edge Function**

```sh
supabase functions serve
```

In a second terminal, accept the seeded quote:

```sh
curl -i -X POST http://127.0.0.1:54321/functions/v1/accept-quote \
  -H 'Content-Type: application/json' \
  -d '{"token":"11111111-1111-4111-8111-111111111111"}'
```

You get `200` with `"outcome":"accepted"`. Run the same command again and you get `409` with `"outcome":"already_accepted"`.

The seed also has a quote that expired yesterday:

```sh
curl -i -X POST http://127.0.0.1:54321/functions/v1/accept-quote \
  -H 'Content-Type: application/json' \
  -d '{"token":"22222222-2222-4222-8222-222222222222"}'
```

This returns `410` with `"outcome":"expired"`.

No `Authorization` header is needed: JWT verification is turned off for this function in `supabase/config.toml`, because customers are not signed in. Everything else (the REST API, Studio) still uses the local anon key that `supabase status` prints.

To reset the demo data, run `supabase db reset`.

**4. Stop the stack**

```sh
supabase stop
```

## Working with Claude Code

| File | What it does |
| --- | --- |
| `CLAUDE.md` | Project rules: commands, workflow (plan → branch → PR), definition of done |
| `.claude/rules/database.md`, `edge-functions.md` | Detailed rules, loaded only when Claude works on matching paths |
| `.claude/settings.json` | Allowed and denied commands, plus the hooks below |
| `.claude/hooks/guard-files.mjs` | Blocks edits to migrations already on `main` and to `.env` files |
| `.claude/hooks/guard-bash.mjs` | Blocks deploys from a laptop, pushes to `main`, force pushes, `--no-verify`, disabling RLS |
| `.claude/hooks/check-migration.mjs` | After every migration edit: RLS on, `revoke all` first, a policy, a pgTAP test, `search_path` on security definer functions |
| `.claude/hooks/typecheck.mjs` | Typechecks after every TypeScript edit |
| `.claude/hooks/tests-before-done.mjs` | Claude cannot finish while Vitest or pgTAP fail for the files it changed |
| `.claude/agents/rls-reviewer.md` | Subagent that reviews migrations for RLS and test gaps before a PR |
| `.claude/commands/plan.md` | `/plan <topic>` writes `docs/plans/<topic>.md` before any migration |
| `.mcp.json` | Supabase MCP server, read-only, on the dev project |
| `.github/workflows/claude-review.yml` | Claude reviews every PR against the same rules and comments inline |

## Design notes

- `accept_quote` locks the quote row (`select ... for update`) before checking it, so two clicks at the same time cannot both accept. The second one waits and then gets `already_accepted`.
- Functions that run as `security definer` also set an empty `search_path`, so callers cannot redirect the names they use.
- Policies call `(select auth.uid())` and `(select public.current_staff_role())` so Postgres evaluates them once per query, not once per row.
- The Edge Function logic lives in `handler.ts` and takes the database call as a parameter, so it is tested with plain `Request` objects and no running Supabase.
