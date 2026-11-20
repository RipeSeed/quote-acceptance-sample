# Quote status history

## Goal
Record every status change of a quote, with the old status, the new status, who made the change and when. The office can then see when a quote was sent and when the customer accepted it.

## Tables and columns
`public.quote_status_events`:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `bigint generated always as identity` | primary key |
| `quote_id` | `uuid not null` | references `quotes (id)` on delete cascade |
| `from_status` | `text` | null for the first event, when the quote is created |
| `to_status` | `text not null` | |
| `changed_by` | `uuid` | references `auth.users (id)` on delete set null. Null when the customer accepts through the Edge Function (service role), or when the change comes from a migration or the seed. |
| `changed_at` | `timestamptz not null default now()` | |

Index `(quote_id, changed_at)`. It covers the foreign key and the history query.

## Access
| Role | select | insert | update | delete |
| --- | --- | --- | --- | --- |
| admin | all rows | denied | denied | denied |
| office | all rows | denied | denied | denied |
| technician | denied (no rows) | denied | denied | denied |
| anon | denied | denied | denied | denied |
| service_role | not needed | via trigger only | – | – |

Only the trigger writes rows, so nobody can rewrite the history.

## Grants and policies
- `revoke all on public.quote_status_events from anon, authenticated`
- `grant select on public.quote_status_events to authenticated`
- Policy "Office can read quote status events" (select, `admin` and `office`)

## Functions and triggers
`public.log_quote_status_change()` is a trigger function that runs after `insert or update of status on public.quotes`.
- It runs as `security definer`, because clients have no insert grant on the events table and the trigger is the only writer. It sets `search_path = ''`, and execute is revoked from `public`, `anon` and `authenticated`.
- On insert, it logs `null → status`. On update, it logs only when the status actually changes.
- `changed_by` comes from `auth.uid()`.

## Tests (pgTAP, `supabase/tests/database/quote_status_events.test.sql`)
- RLS is enabled on the table.
- Office creates a quote: `null → draft` is logged, with the office user.
- Office sends the quote: `draft → sent` is logged. Changing `valid_until`, or setting the same status again, logs nothing.
- **Allowed:** office and admin read events.
- **Denied:** a technician reads no events, even for an accepted quote.
- **Denied:** anon gets `42501`.
- **Denied:** an authenticated user cannot insert, update or delete events (`42501`).
- `accept_quote` through the service role logs `sent → accepted` with `changed_by` null.

## Out of scope and open questions
- Showing the history in the office UI.
- A free-text reason on cancellation. That needs a column on `quotes` and its own plan.
