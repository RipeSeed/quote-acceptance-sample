create table public.quote_status_events (
  id bigint generated always as identity primary key,
  quote_id uuid not null references public.quotes (id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid references auth.users (id) on delete set null,
  changed_at timestamptz not null default now()
);

create index quote_status_events_quote_id_idx
  on public.quote_status_events (quote_id, changed_at);

create index quote_status_events_changed_by_idx
  on public.quote_status_events (changed_by);

alter table public.quote_status_events enable row level security;

revoke all on public.quote_status_events from anon, authenticated;
grant select on public.quote_status_events to authenticated;

create policy "Office can read quote status events"
  on public.quote_status_events for select to authenticated
  using ((select public.current_staff_role()) in ('admin', 'office'));

-- Security definer because clients have no insert grant on the events table:
-- this trigger is the only writer, so clients cannot add or change history.
-- Events go only with their quote, and admins can delete draft quotes only.
-- auth.uid() is null when the Edge Function accepts with the service role.
create function public.log_quote_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.quote_status_events (quote_id, from_status, to_status, changed_by)
    values (new.id, null, new.status, auth.uid());
  elsif new.status is distinct from old.status then
    insert into public.quote_status_events (quote_id, from_status, to_status, changed_by)
    values (new.id, old.status, new.status, auth.uid());
  end if;

  return null;
end;
$$;

revoke execute on function public.log_quote_status_change() from public, anon, authenticated;

create trigger quotes_log_status_change
  after insert or update of status on public.quotes
  for each row execute function public.log_quote_status_change();
