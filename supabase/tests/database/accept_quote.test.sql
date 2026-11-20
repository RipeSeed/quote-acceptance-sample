begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into public.customers (id, customer_number, name)
values ('00000000-0000-4000-8000-0000000000c1', 'T-C1', 'Test Customer');

insert into public.quotes (quote_number, customer_id, status, valid_until, accept_token) values
  ('T-OPEN', '00000000-0000-4000-8000-0000000000c1', 'sent', current_date + 14, '00000000-0000-4000-8000-000000000001'),
  ('T-LAST-DAY', '00000000-0000-4000-8000-0000000000c1', 'sent', current_date, '00000000-0000-4000-8000-000000000002'),
  ('T-EXPIRED', '00000000-0000-4000-8000-0000000000c1', 'sent', current_date - 1, '00000000-0000-4000-8000-000000000003'),
  ('T-DRAFT', '00000000-0000-4000-8000-0000000000c1', 'draft', current_date + 14, '00000000-0000-4000-8000-000000000004'),
  ('T-CANCELLED', '00000000-0000-4000-8000-0000000000c1', 'cancelled', current_date + 14, '00000000-0000-4000-8000-000000000005');

select results_eq(
  $$select outcome, quote_number from public.accept_quote('00000000-0000-4000-8000-000000000001')$$,
  $$values ('accepted', 'T-OPEN')$$,
  'A sent quote within its validity is accepted'
);

select results_eq(
  $$select status, accepted_at from public.quotes where quote_number = 'T-OPEN'$$,
  $$values ('accepted', now())$$,
  'The acceptance is stored with a timestamp'
);

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000001')),
  'already_accepted',
  'Accepting the same quote again reports already_accepted'
);

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000002')),
  'accepted',
  'A quote can still be accepted on its last valid day'
);

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000003')),
  'expired',
  'A quote past its validity date is expired'
);

select is(
  (select status from public.quotes where quote_number = 'T-EXPIRED'),
  'sent',
  'An expired quote is left unchanged'
);

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000004')),
  'not_open',
  'A draft quote cannot be accepted'
);

select is(
  (select outcome from public.accept_quote('00000000-0000-4000-8000-000000000005')),
  'not_open',
  'A cancelled quote cannot be accepted'
);

select results_eq(
  $$select outcome, quote_number from public.accept_quote(gen_random_uuid())$$,
  $$values ('not_found', null::text)$$,
  'An unknown token is not found and reveals no quote number'
);

set local role authenticated;

select throws_ok(
  $$select public.accept_quote('00000000-0000-4000-8000-000000000002')$$,
  '42501',
  'permission denied for function accept_quote',
  'Signed-in users cannot call accept_quote directly'
);

reset role;
set local role anon;

select throws_ok(
  $$select public.accept_quote('00000000-0000-4000-8000-000000000002')$$,
  '42501',
  'permission denied for function accept_quote',
  'Anonymous users cannot call accept_quote directly'
);

reset role;
set local role service_role;

select lives_ok(
  $$select public.accept_quote(gen_random_uuid())$$,
  'The service role can call accept_quote'
);

reset role;

select * from finish();
rollback;
