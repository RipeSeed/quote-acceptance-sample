begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'admin@example.com'),
  ('00000000-0000-4000-8000-0000000000a2', 'office@example.com'),
  ('00000000-0000-4000-8000-0000000000a3', 'technician@example.com');

insert into public.staff (user_id, full_name, role) values
  ('00000000-0000-4000-8000-0000000000a1', 'Admin User', 'admin'),
  ('00000000-0000-4000-8000-0000000000a2', 'Office User', 'office'),
  ('00000000-0000-4000-8000-0000000000a3', 'Technician User', 'technician');

insert into public.customers (id, customer_number, name)
values ('00000000-0000-4000-8000-0000000000c1', 'T-C1', 'Test Customer');

select is(
  (select relrowsecurity from pg_class where oid = 'public.quote_status_events'::regclass),
  true,
  'RLS is enabled on quote_status_events'
);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a2", "role": "authenticated", "email": "office@example.com"}';

insert into public.quotes (quote_number, customer_id, valid_until)
values ('T-HISTORY', '00000000-0000-4000-8000-0000000000c1', current_date + 30);

select results_eq(
  $$select e.from_status, e.to_status, e.changed_by
    from public.quote_status_events e
    join public.quotes q on q.id = e.quote_id
    where q.quote_number = 'T-HISTORY'$$,
  $$values (null::text, 'draft'::text, '00000000-0000-4000-8000-0000000000a2'::uuid)$$,
  'Creating a quote logs its first status and who created it'
);

update public.quotes set status = 'sent' where quote_number = 'T-HISTORY';
update public.quotes set valid_until = current_date + 60 where quote_number = 'T-HISTORY';
update public.quotes set status = 'sent' where quote_number = 'T-HISTORY';

select results_eq(
  $$select e.from_status, e.to_status
    from public.quote_status_events e
    join public.quotes q on q.id = e.quote_id
    where q.quote_number = 'T-HISTORY'
    order by e.id$$,
  $$values (null::text, 'draft'::text), ('draft', 'sent')$$,
  'Only real status changes are logged'
);

select throws_ok(
  $$insert into public.quote_status_events (quote_id, to_status)
    select id, 'accepted' from public.quotes where quote_number = 'T-HISTORY'$$,
  '42501',
  'permission denied for table quote_status_events',
  'Office staff cannot write status events directly'
);

select throws_ok(
  $$update public.quote_status_events set to_status = 'accepted'$$,
  '42501',
  'permission denied for table quote_status_events',
  'Office staff cannot change status events'
);

select throws_ok(
  $$delete from public.quote_status_events$$,
  '42501',
  'permission denied for table quote_status_events',
  'Office staff cannot delete status events'
);

reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a1", "role": "authenticated", "email": "admin@example.com"}';

select is(
  (select count(*)::int
   from public.quote_status_events e
   join public.quotes q on q.id = e.quote_id
   where q.quote_number = 'T-HISTORY'),
  2,
  'Admins can read status events'
);

reset role;

update public.quotes
set accept_token = '00000000-0000-4000-8000-000000000001'
where quote_number = 'T-HISTORY';

set local role service_role;
set local request.jwt.claims = '{"role": "service_role"}';

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000001')),
  'accepted',
  'The customer accepts the quote through the Edge Function role'
);

reset role;

select results_eq(
  $$select e.from_status, e.to_status, e.changed_by
    from public.quote_status_events e
    join public.quotes q on q.id = e.quote_id
    where q.quote_number = 'T-HISTORY'
    order by e.id desc
    limit 1$$,
  $$values ('sent'::text, 'accepted'::text, null::uuid)$$,
  'Accepting through the link logs sent to accepted without a staff user'
);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a3", "role": "authenticated", "email": "technician@example.com"}';

select is_empty(
  $$select 1 from public.quote_status_events$$,
  'Technicians cannot read status events, even of accepted quotes'
);

reset role;

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select throws_ok(
  $$select 1 from public.quote_status_events$$,
  '42501',
  'permission denied for table quote_status_events',
  'Anonymous users cannot read status events'
);

reset role;

select * from finish();
rollback;
