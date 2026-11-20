begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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

insert into public.quotes (id, quote_number, customer_id, status, valid_until, accepted_at) values
  ('00000000-0000-4000-8000-0000000000e1', 'T-DRAFT', '00000000-0000-4000-8000-0000000000c1', 'draft', current_date + 30, null),
  ('00000000-0000-4000-8000-0000000000e2', 'T-SENT', '00000000-0000-4000-8000-0000000000c1', 'sent', current_date + 30, null),
  ('00000000-0000-4000-8000-0000000000e3', 'T-ACCEPTED', '00000000-0000-4000-8000-0000000000c1', 'accepted', current_date + 30, now());

insert into public.quote_items (quote_id, position, description, quantity, unit_price) values
  ('00000000-0000-4000-8000-0000000000e1', 1, 'Ridge repair', 1, 100.00),
  ('00000000-0000-4000-8000-0000000000e2', 1, 'Chimney flashing', 1, 250.00),
  ('00000000-0000-4000-8000-0000000000e3', 1, 'Skylight installation', 1, 900.00);

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a3", "role": "authenticated", "email": "technician@example.com"}';

select results_eq(
  $$select user_id from public.staff$$,
  array['00000000-0000-4000-8000-0000000000a3'::uuid],
  'A technician reads only their own staff row'
);

select results_eq(
  $$select quote_number from public.quotes where customer_id = '00000000-0000-4000-8000-0000000000c1'$$,
  array['T-ACCEPTED'],
  'A technician sees accepted quotes only'
);

select results_eq(
  $$select quote_id from public.quote_items
    where quote_id in ('00000000-0000-4000-8000-0000000000e1',
                       '00000000-0000-4000-8000-0000000000e2',
                       '00000000-0000-4000-8000-0000000000e3')$$,
  array['00000000-0000-4000-8000-0000000000e3'::uuid],
  'A technician sees items of accepted quotes only'
);

select throws_ok(
  $$insert into public.quotes (quote_number, customer_id, valid_until)
    values ('T-NEW', '00000000-0000-4000-8000-0000000000c1', current_date + 30)$$,
  '42501',
  'new row violates row-level security policy for table "quotes"',
  'A technician cannot create quotes'
);

select isnt_empty(
  $$select 1 from public.customers where id = '00000000-0000-4000-8000-0000000000c1'$$,
  'A technician can read customers'
);

select throws_ok(
  $$insert into public.customers (customer_number, name) values ('T-C2', 'Another Customer')$$,
  '42501',
  'new row violates row-level security policy for table "customers"',
  'A technician cannot create customers'
);

reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a2", "role": "authenticated", "email": "office@example.com"}';

select results_eq(
  $$select quote_number from public.quotes
    where customer_id = '00000000-0000-4000-8000-0000000000c1'
    order by quote_number$$,
  array['T-ACCEPTED', 'T-DRAFT', 'T-SENT'],
  'Office staff see quotes in every status'
);

select throws_ok(
  $$insert into public.quote_items (quote_id, position, description, quantity, unit_price)
    values ('00000000-0000-4000-8000-0000000000e2', 2, 'Extra work', 1, 50.00)$$,
  '42501',
  'new row violates row-level security policy for table "quote_items"',
  'Office staff cannot add items to a sent quote'
);

update public.quote_items set quantity = 5
where quote_id = '00000000-0000-4000-8000-0000000000e2';

select is(
  (select quantity from public.quote_items where quote_id = '00000000-0000-4000-8000-0000000000e2'),
  1.00,
  'Office staff cannot change items of a sent quote'
);

insert into public.quote_items (quote_id, position, description, quantity, unit_price)
values ('00000000-0000-4000-8000-0000000000e1', 2, 'Gutter guard', 3, 12.50);

select is(
  (select net_total from public.quotes where id = '00000000-0000-4000-8000-0000000000e1'),
  137.50,
  'Adding an item updates the quote net total'
);

update public.quote_items set quantity = 2
where quote_id = '00000000-0000-4000-8000-0000000000e1' and position = 1;

select is(
  (select net_total from public.quotes where id = '00000000-0000-4000-8000-0000000000e1'),
  237.50,
  'Changing an item updates the quote net total'
);

delete from public.quote_items
where quote_id = '00000000-0000-4000-8000-0000000000e1' and position = 1;

select is(
  (select net_total from public.quotes where id = '00000000-0000-4000-8000-0000000000e1'),
  37.50,
  'Removing an item updates the quote net total'
);

select throws_ok(
  $$update public.quotes set net_total = 0 where id = '00000000-0000-4000-8000-0000000000e1'$$,
  '42501',
  'permission denied for table quotes',
  'Office staff cannot write the net total directly'
);

delete from public.quotes where id = '00000000-0000-4000-8000-0000000000e1';

select isnt_empty(
  $$select 1 from public.quotes where id = '00000000-0000-4000-8000-0000000000e1'$$,
  'Office staff cannot delete quotes'
);

reset role;

set local role authenticated;
set local request.jwt.claims = '{"sub": "00000000-0000-4000-8000-0000000000a1", "role": "authenticated", "email": "admin@example.com"}';

select results_eq(
  $$select user_id from public.staff
    where user_id in ('00000000-0000-4000-8000-0000000000a1',
                      '00000000-0000-4000-8000-0000000000a2',
                      '00000000-0000-4000-8000-0000000000a3')
    order by user_id$$,
  array['00000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-0000000000a2',
        '00000000-0000-4000-8000-0000000000a3']::uuid[],
  'Admins read every staff row'
);

delete from public.quotes where id = '00000000-0000-4000-8000-0000000000e2';

select isnt_empty(
  $$select 1 from public.quotes where id = '00000000-0000-4000-8000-0000000000e2'$$,
  'Admins cannot delete a sent quote'
);

delete from public.quotes where id = '00000000-0000-4000-8000-0000000000e1';

select is_empty(
  $$select 1 from public.quotes where id = '00000000-0000-4000-8000-0000000000e1'$$,
  'Admins can delete a draft quote'
);

reset role;

set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select throws_ok(
  $$select * from public.quotes$$,
  '42501',
  'permission denied for table quotes',
  'Anonymous users cannot read quotes'
);

reset role;

select * from finish();
rollback;
