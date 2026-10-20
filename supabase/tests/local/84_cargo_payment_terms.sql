-- LOAD PAYMENT TERMS — 0046: advance / cash / bank amounts and free
-- waiting time on a load. Rolled back at the end.
\set owner1 '''a0000000-0000-4000-8000-000000000011'''
\set owner2 '''a0000000-0000-4000-8000-000000000012'''
\set cargo  '''c8400000-0000-4000-8000-000000000001'''
\set cargo2 '''c8400000-0000-4000-8000-000000000002'''

begin;
set role authenticated;
select tests.login(:owner2);

-- Old-style insert (an app without the new fields) still works; nothing is invented.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:cargo, :owner2, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date);
select tests.check((select pay_advance is null and pay_cash is null and pay_bank is null and free_wait_hours is null
                      from public.cargo where id = :cargo), 'P1 a load without terms stays empty (no invented values)');

-- New load with terms.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date,
                          pay_advance, pay_cash, pay_bank, free_wait_hours)
values (:cargo2, :owner2, 'Azerbaijan', 'Baku', 'Turkey', 'Istanbul', 20000, 2000, current_date, 500, null, 1500, 48);
select tests.check((select pay_advance = 500 and pay_cash is null and pay_bank = 1500 and free_wait_hours = 48
                      from public.cargo where id = :cargo2), 'P2 amounts and waiting time are saved');

-- Editing.
update public.cargo set pay_cash = 250.5, pay_bank = null, free_wait_hours = 24 where id = :cargo2;
select tests.check((select pay_cash = 250.5 and pay_bank is null and free_wait_hours = 24 from public.cargo where id = :cargo2),
  'P3 the owner edits them');

-- Only positive amounts and only 24 / 36 / 48 hours.
select tests.check(tests.err(format($$ update public.cargo set pay_advance = 0 where id = %L $$, :cargo2)) like '%cargo_pay_advance_positive%',
  'V1 zero amount refused');
select tests.check(tests.err(format($$ update public.cargo set pay_cash = -5 where id = %L $$, :cargo2)) like '%cargo_pay_cash_positive%',
  'V2 negative amount refused');
select tests.check(tests.err(format($$ update public.cargo set pay_bank = -1 where id = %L $$, :cargo2)) like '%cargo_pay_bank_positive%',
  'V3 negative bank amount refused');
select tests.check(tests.err(format($$ update public.cargo set free_wait_hours = 12 where id = %L $$, :cargo2)) like '%cargo_free_wait_hours_choice%',
  'V4 only 24 / 36 / 48 hours');

-- Somebody else cannot change them (existing RLS).
select tests.login(:owner1);
update public.cargo set pay_advance = 1, free_wait_hours = 36 where id = :cargo2;
reset role;
select tests.check((select pay_advance = 500 and free_wait_hours = 24 from public.cargo where id = :cargo2),
  'R1 another user cannot change a load''s terms');

select tests.summary('LOAD PAYMENT TERMS (0046)');
rollback;
