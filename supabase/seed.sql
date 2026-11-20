insert into public.customers (id, customer_number, name, email)
values ('c0000000-0000-4000-8000-000000000001', 'C-1001', 'Jordan Miller', 'jordan.miller@example.com');

insert into public.quotes (id, quote_number, customer_id, status, valid_until, accept_token)
values
  ('a0000000-0000-4000-8000-000000000001', 'Q-2026-0001', 'c0000000-0000-4000-8000-000000000001',
   'sent', current_date + 30, '11111111-1111-4111-8111-111111111111'),
  ('a0000000-0000-4000-8000-000000000002', 'Q-2026-0002', 'c0000000-0000-4000-8000-000000000001',
   'sent', current_date - 1, '22222222-2222-4222-8222-222222222222');

insert into public.quote_items (quote_id, position, description, quantity, unit_price)
values
  ('a0000000-0000-4000-8000-000000000001', 1, 'Roof tile replacement, per m2', 12.5, 64.00),
  ('a0000000-0000-4000-8000-000000000001', 2, 'Scaffolding, per day', 2, 180.00),
  ('a0000000-0000-4000-8000-000000000002', 1, 'Gutter cleaning and inspection', 1, 145.00);
