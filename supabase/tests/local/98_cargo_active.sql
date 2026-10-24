-- LOAD ON / OFF BY ITS OWNER — 0061. Rolled back.
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c6100000-0000-4000-8000-000000000001'''

begin;
select tests.check((select count(*) = 0 from public.cargo where is_paused), 'P1 existing loads stay on (nothing switched off)');

set role authenticated;
select tests.login(:owner);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date - 3);
select tests.check((select not is_paused from public.cargo where id = :c1), 'P2 a new load is on');
update public.cargo set is_paused = true where id = :c1;
select tests.check((select is_paused from public.cargo where id = :c1), 'P3 the owner switches his load off');
update public.cargo set is_paused = false, pickup_date = current_date + 2 where id = :c1;
select tests.check((select not is_paused and pickup_date = current_date + 2 from public.cargo where id = :c1),
  'P4 "Aktiv et": on again with a new loading date');

select tests.login(:other);
update public.cargo set is_paused = true where id = :c1;   -- RLS: no row of his
select tests.check((select not is_paused from public.cargo where id = :c1), 'P5 nobody else switches it off');
select tests.check((select count(*) = 1 from public.cargo where id = :c1), 'P6 the load itself is never deleted');

reset role;
select tests.summary('LOAD ON / OFF (0061)');
rollback;
