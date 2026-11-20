create type public.app_role as enum ('admin', 'office', 'technician');

create table public.staff (
  user_id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role public.app_role not null
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_number text not null unique,
  name text not null,
  email text,
  created_at timestamptz not null default now()
);

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  quote_number text not null unique,
  customer_id uuid not null references public.customers (id),
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'accepted', 'cancelled')),
  valid_until date not null,
  net_total numeric(12, 2) not null default 0,
  accept_token uuid not null unique default gen_random_uuid(),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotes_accepted_has_timestamp
    check (status <> 'accepted' or accepted_at is not null)
);

create table public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  position integer not null,
  description text not null,
  quantity numeric(10, 2) not null check (quantity > 0),
  unit_price numeric(12, 2) not null check (unit_price >= 0),
  line_total numeric(12, 2) generated always as (round(quantity * unit_price, 2)) stored,
  unique (quote_id, position)
);

-- quote_items.quote_id is covered by the unique (quote_id, position) index.
create index quotes_customer_id_idx on public.quotes (customer_id);
create index quotes_status_idx on public.quotes (status);

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger quotes_set_updated_at
  before update on public.quotes
  for each row execute function public.set_updated_at();

-- Runs as owner because clients have no update privilege on quotes.net_total
-- (see grants below); this trigger is the only thing that writes it.
create function public.refresh_quote_net_total()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.quotes q
  set net_total = (
    select coalesce(sum(i.line_total), 0)
    from public.quote_items i
    where i.quote_id = q.id
  )
  where q.id in (old.quote_id, new.quote_id);

  return null;
end;
$$;

create trigger quote_items_refresh_net_total
  after insert or update or delete on public.quote_items
  for each row execute function public.refresh_quote_net_total();

-- Security definer so policies can look up the caller's role without going
-- through the RLS on staff (which itself depends on this function).
-- The empty search_path stops callers from shadowing objects referenced here.
create function public.current_staff_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select role from public.staff where user_id = auth.uid();
$$;

alter table public.staff enable row level security;
alter table public.customers enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;

-- Grants are explicit so access does not depend on project defaults. anon gets
-- nothing. Column grants on quotes keep net_total, accept_token and accepted_at
-- server-controlled, which RLS alone cannot do because it filters rows, not columns.
revoke all on public.staff, public.customers, public.quotes, public.quote_items
  from anon, authenticated;

grant select on public.staff to authenticated;
grant select, insert, update, delete on public.customers to authenticated;
grant select, delete on public.quotes to authenticated;
grant insert (quote_number, customer_id, status, valid_until),
      update (quote_number, customer_id, status, valid_until)
  on public.quotes to authenticated;
grant select, insert, update, delete on public.quote_items to authenticated;

create policy "Staff can read their own row, admins can read all"
  on public.staff for select to authenticated
  using (
    user_id = (select auth.uid())
    or (select public.current_staff_role()) = 'admin'
  );

create policy "Staff can read customers"
  on public.customers for select to authenticated
  using ((select public.current_staff_role()) in ('admin', 'office', 'technician'));

create policy "Office can create customers"
  on public.customers for insert to authenticated
  with check ((select public.current_staff_role()) in ('admin', 'office'));

create policy "Office can update customers"
  on public.customers for update to authenticated
  using ((select public.current_staff_role()) in ('admin', 'office'))
  with check ((select public.current_staff_role()) in ('admin', 'office'));

create policy "Office can delete customers"
  on public.customers for delete to authenticated
  using ((select public.current_staff_role()) in ('admin', 'office'));

create policy "Office reads all quotes, technicians read accepted ones"
  on public.quotes for select to authenticated
  using (
    (select public.current_staff_role()) in ('admin', 'office')
    or ((select public.current_staff_role()) = 'technician' and status = 'accepted')
  );

create policy "Office can create quotes"
  on public.quotes for insert to authenticated
  with check ((select public.current_staff_role()) in ('admin', 'office'));

create policy "Office can update quotes"
  on public.quotes for update to authenticated
  using ((select public.current_staff_role()) in ('admin', 'office'))
  with check ((select public.current_staff_role()) in ('admin', 'office'));

create policy "Admins can delete draft quotes"
  on public.quotes for delete to authenticated
  using ((select public.current_staff_role()) = 'admin' and status = 'draft');

-- The subquery on quotes is itself filtered by the quotes policies, so items
-- are visible exactly when their quote is.
create policy "Items are visible with their quote"
  on public.quote_items for select to authenticated
  using (exists (select 1 from public.quotes q where q.id = quote_id));

create policy "Office can add items to draft quotes"
  on public.quote_items for insert to authenticated
  with check (
    (select public.current_staff_role()) in ('admin', 'office')
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  );

create policy "Office can change items of draft quotes"
  on public.quote_items for update to authenticated
  using (
    (select public.current_staff_role()) in ('admin', 'office')
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  )
  with check (
    (select public.current_staff_role()) in ('admin', 'office')
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  );

create policy "Office can remove items from draft quotes"
  on public.quote_items for delete to authenticated
  using (
    (select public.current_staff_role()) in ('admin', 'office')
    and exists (select 1 from public.quotes q where q.id = quote_id and q.status = 'draft')
  );

create function public.accept_quote(p_token uuid)
returns table (outcome text, quote_number text, accepted_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote public.quotes;
begin
  -- The row lock makes a second, concurrent click on the same link wait here
  -- and then see the committed acceptance instead of accepting twice.
  select * into v_quote
  from public.quotes
  where accept_token = p_token
  for update;

  if not found then
    return query select 'not_found'::text, null::text, null::timestamptz;
  elsif v_quote.status = 'accepted' then
    return query select 'already_accepted'::text, v_quote.quote_number, v_quote.accepted_at;
  elsif v_quote.status in ('draft', 'cancelled') then
    return query select 'not_open'::text, v_quote.quote_number, null::timestamptz;
  elsif v_quote.valid_until < current_date then
    return query select 'expired'::text, v_quote.quote_number, null::timestamptz;
  else
    update public.quotes
    set status = 'accepted', accepted_at = now()
    where id = v_quote.id;

    return query select 'accepted'::text, v_quote.quote_number, now();
  end if;
end;
$$;

-- Customers have no session, so the Edge Function (service role) is the only
-- caller. Keeping the RPC off the public API means every acceptance goes
-- through the function's validation and logging.
revoke execute on function public.accept_quote(uuid) from public, anon, authenticated;
grant execute on function public.accept_quote(uuid) to service_role;
