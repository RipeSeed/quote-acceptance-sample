---
paths:
  - "supabase/**/*.sql"
---

# Database rules

## Tables
- Enable row level security (`alter table ... enable row level security`) in the same migration that creates the table.
- First run `revoke all ... from anon, authenticated`. Then grant only what the app needs. `anon` gets nothing unless the plan explains why.
- Keep server-controlled columns out of the client column grants. These are totals, tokens, and timestamps that functions set.
- Index every foreign key, unless it is already the leading column of another index.

## Policies
- Write one policy per command (select, insert, update, delete). The name says who can do what, for example "Office can update quotes".
- Call `(select auth.uid())` and `(select public.current_staff_role())`, not the bare functions. Then they run once per query, not once per row.
- Give update policies both `using` and `with check`.

## Functions and triggers
- Use `security definer` only when the function must bypass RLS. When you do:
  - add `set search_path = ''`
  - use schema-qualified names
  - write a comment saying why it is needed
- Run `revoke execute ... from public, anon, authenticated`, then grant to the one role that calls the function.
- If a function checks a row and then changes it, lock the row first with `select ... for update`.

## pgTAP tests
- Every policy gets two tests: one with a role that is allowed, one with a role that is denied.
- A denial test checks the SQLSTATE (`42501`) and the message, not just that something throws.
- Each test file runs inside `begin; ... rollback;` and creates its own users and rows. Never rely on `seed.sql`.
- Update `plan(n)` when you add tests.
