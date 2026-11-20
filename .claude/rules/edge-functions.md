---
paths:
  - "supabase/functions/**"
  - "tests/**"
---

# Edge Function rules
- Put the logic in `handler.ts`. It takes its dependencies (the database call, the clock) as parameters. `index.ts` only wires up Deno and the Supabase client.
- Validate the request body before touching the database: it must be JSON, have the required fields, and use the right format for UUIDs.
- Respond with an `{ outcome }` code from a fixed list. Log the details on the server; never return raw errors.
- Read the service role key from the environment inside the function only. It never appears in client code, tests or logs.
- Give every response code a Vitest case in `tests/`.
