-- LOAD PAYMENT CHOICES — 0047: cash / after delivery / bank are just
-- ticked. Rolled back at the end.
\set owner1 '''a0000000-0000-4000-8000-000000000011'''
\set owner2 '''a0000000-0000-4000-8000-000000000012'''
\set cargo  '''c8500000-0000-4000-8000-000000000001'''
\set cargo2 '''c8500000-0000-4000-8000-000000000002'''

begin;
set role authenticated;
select tests.login(:owner2);

-- An app that does not send the new fields still works; nothing is ticked.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:cargo, :owner2, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date);
select tests.check((select not pay_cash_on and not pay_on_delivery and not pay_bank_on from public.cargo where id = :cargo),
  'C1 a load without choices: nothing ticked');

insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date,
                          pay_advance, pay_cash_on, pay_on_delivery, pay_bank_on)
values (:cargo2, :owner2, 'Azerbaijan', 'Baku', 'Turkey', 'Istanbul', 20000, 2000, current_date, 400, true, true, false);
select tests.check((select pay_advance = 400 and pay_cash_on and pay_on_delivery and not pay_bank_on from public.cargo where id = :cargo2),
  'C2 advance amount and ticked ways are saved');

update public.cargo set pay_cash_on = false, pay_bank_on = true where id = :cargo2;
select tests.check((select not pay_cash_on and pay_on_delivery and pay_bank_on from public.cargo where id = :cargo2), 'C3 the owner changes them');

select tests.check(tests.err(format($$ update public.cargo set pay_bank_on = null where id = %L $$, :cargo2)) like '%null%',
  'C4 a choice is yes or no, never empty');

select tests.login(:owner1);
update public.cargo set pay_cash_on = true where id = :cargo2;
reset role;
select tests.check((select not pay_cash_on from public.cargo where id = :cargo2), 'R1 another user cannot change them');

select tests.summary('LOAD PAYMENT CHOICES (0047)');
rollback;
