-- LOAD CATEGORIES — 0055: big / small, QRUPAJ, size-card pictures. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c5500000-0000-4000-8000-000000000001'''
\set c2 '''c5500000-0000-4000-8000-000000000002'''
\set c3 '''c5500000-0000-4000-8000-000000000003'''

begin;
select tests.check((select count(*) = 0 from public.cargo where load_size is not null or groupage),
  'K1 existing loads: size not known, not groupage (nothing guessed)');

set role authenticated;
select tests.login(:owner);
-- An app without the new fields still posts a load.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date);
select tests.check((select load_size is null and not groupage from public.cargo where id = :c1), 'K2 a load without a size stays unknown');
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date,
                          truck_type, load_size)
values (:c2, :owner, 'Turkey', 'Istanbul', 'Azerbaijan', 'Baku', 20000, 3000, current_date, 'tent', 'big');
select tests.check((select load_size = 'big' and truck_type = 'tent' from public.cargo where id = :c2), 'K3 big load with a truck type');
-- QRUPAJ is always small, even when the app says big.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date,
                          groupage, load_size)
values (:c3, :owner, 'Azerbaijan', 'Ganja', 'Russia', 'Moscow', 2000, 400, current_date, true, 'big');
select tests.check((select groupage and load_size = 'small' and truck_type is null from public.cargo where id = :c3),
  'K4 QRUPAJ is a category on its own and always a small load');
update public.cargo set groupage = false, load_size = 'big' where id = :c3;
select tests.check((select not groupage and load_size = 'big' from public.cargo where id = :c3), 'K5 the owner can change it later');
select tests.check(tests.err($$ update public.cargo set load_size = 'huge' where id = 'c5500000-0000-4000-8000-000000000003' $$) like '%cargo_load_size_check%',
  'K6 only big / small');

-- The Loads page filters (same columns, indexed).
select tests.check((select count(*) = 1 from public.cargo where status = 'new' and load_size = 'big' and id in (:c1, :c2, :c3) and truck_type = 'tent'),
  'K7 filter by size + truck type');
select tests.check((select count(*) = 2 from public.cargo where status = 'new' and load_size is not null and id in (:c1, :c2, :c3)),
  'K8 unknown size is in neither big nor small');
reset role;
select tests.check((select count(*) = 3 from pg_indexes where tablename = 'cargo' and indexname in ('idx_cargo_open_truck', 'idx_cargo_open_size', 'idx_cargo_open_groupage')),
  'K9 filter indexes exist');

-- Size-card pictures: admins only.
set role authenticated;
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_set_cargo_size_card('big', 'https://x/b.jpg') $$) like '%admin_only%',
  'S1 a normal user cannot change a card picture');
select tests.check(tests.err($$ insert into public.cargo_size_cards (size, image_url) values ('big', 'hack') $$) like '%permission denied%',
  'S2 nobody writes the table directly');
select tests.login(:admin);
select public.admin_set_cargo_size_card('big', ' https://x/big.jpg ');
select public.admin_set_cargo_size_card('small', 'https://x/small.jpg');
select tests.check((select string_agg(size || '=' || image_url, ',' order by size) = 'big=https://x/big.jpg,small=https://x/small.jpg'
                      from public.cargo_size_cards), 'S3 admin sets both pictures');
select public.admin_set_cargo_size_card('small', null);
select tests.check((select image_url is null from public.cargo_size_cards where size = 'small'), 'S4 admin removes a picture');
select tests.check(tests.err($$ select public.admin_set_cargo_size_card('medium', null) $$) like '%invalid_argument%', 'S5 only big / small');
select tests.check((select count(*) >= 3 from public.admin_audit_log where action = 'cargo.size_card'), 'S6 changes are logged');
select tests.login(:other);
select tests.check((select image_url = 'https://x/big.jpg' from public.cargo_size_cards where size = 'big'), 'S7 everybody signed in sees it');
select tests.summary('LOAD CATEGORIES (0055)');
rollback;
