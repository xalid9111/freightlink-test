-- "Daşıyıcılar" — 0118: empty truck ads, their own kind; the owner edits,
-- pauses, closes ("Maşın doldu"); visitors read without contacts. Rolled back.
\set carrier '''a0000000-0000-4000-8000-000000000012'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set chief   '''a0000000-0000-4000-8000-0000000000f1'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}')
  on conflict (id) do nothing;
update public.users set role = 'admin' where id = :chief;
create temp table t (k text primary key, id uuid) on commit drop;
grant all on t to authenticated, anon;
select count(*) as cargo_before from public.cargo \gset

set role authenticated;
select tests.login(:carrier);
insert into t values ('a', public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'az', 40.4, 49.8, false, 'Istanbul', 'Turkey', 'TR',
  'tent', 20, '{tent,groupage}', null, '+994 50 111 22 33', '+994501112233', null));
insert into t values ('b', public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, 'X', 'Y', 'ZZ',
  'ref', 5.5, '{}', now() + interval '2 days', null, null, 'Soyuducu'));
select tests.check((select from_code = 'AZ' and to_city = 'Istanbul' and status = 'active' and owner_id = :carrier
                    from public.empty_truck_ads where id = (select id from t where k = 'a')),
  'A1 an ad: where now, where to, the truck, active');
select tests.check((select any_direction and to_city is null and to_country is null and to_code is null
                    from public.empty_truck_ads where id = (select id from t where k = 'b')),
  'A2 "İstiqamət fərq etmir": no destination kept');
select tests.check(tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, false, null, null, null, 'tent', 10, '{}', null, null, null, null) $$) like '%to_required%'
               and tests.err($$ select public.empty_truck_save(null, ' ', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 10, '{}', null, null, null, null) $$) like '%from_required%'
               and tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 0, '{}', null, null, null, null) $$) like '%invalid_tons%'
               and tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 150, '{}', null, null, null, null) $$) like '%invalid_tons%'
               and tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, '', 10, '{}', null, null, null, null) $$) like '%truck_required%'
               and tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 10, '{}', null, 'abc', null, null) $$) is not null
               and tests.err($$ select public.empty_truck_save(null, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 10, '{}', now() - interval '3 days', null, null, null) $$) like '%invalid_time%',
  'A3 the server checks every field');
select public.empty_truck_save((select id from t where k = 'a'), 'Gəncə', 'Azerbaijan', 'AZ', null, null, false, 'Tbilisi', 'Georgia', 'GE',
  'tent', 18, '{tent}', null, '+994501112233', null, null);
select tests.check((select from_city = 'Gəncə' and to_city = 'Tbilisi' and free_tons = 18 from public.empty_truck_ads where id = (select id from t where k = 'a')),
  'A4 the owner edits his ad');
select tests.check(tests.err($$ insert into public.empty_truck_ads (from_city, from_country, truck_type, free_tons, any_direction) values ('a','bb','tent',1,true) $$) is not null,
  'A5 no direct writes, only the server function');

select public.empty_truck_set_status((select id from t where k = 'b'), 'paused');
select tests.check((select status = 'paused' from public.empty_truck_ads where id = (select id from t where k = 'b')), 'S1 the owner pauses');

-- Another user: only active ads; cannot edit or close someone's ad.
select tests.login(:other);
select tests.check((select count(*) = 1 from public.empty_truck_ads where owner_id = :carrier), 'R1 others see only the active ads');
select tests.check((select phone = '+994501112233' from public.empty_truck_ads where id = (select id from t where k = 'a')),
  'R2 a signed-in user sees the contact');
select tests.check(tests.err(format($$ select public.empty_truck_set_status(%L, 'filled') $$, (select id from t where k = 'a'))) like '%not_allowed%'
               and tests.err(format($$ select public.empty_truck_save(%L, 'Baku', 'Azerbaijan', 'AZ', null, null, true, null, null, null, 'tent', 9, '{}', null, null, null, null) $$, (select id from t where k = 'a'))) like '%not_allowed%',
  'R3 nobody else edits or closes it');

-- Visitor: the active ads, never the contact numbers.
set role anon;
select tests.login(null);
select tests.check((select count(*) = 1 from public.empty_truck_ads e where e.owner_id = :carrier), 'G1 a visitor sees the active ads');
select tests.check(tests.err($$ select phone from public.empty_truck_ads limit 1 $$) is not null
               and tests.err($$ select whatsapp from public.empty_truck_ads limit 1 $$) is not null,
  'G2 …but not the phone / WhatsApp');
select tests.check(tests.err($$ select public.empty_truck_set_status(gen_random_uuid(), 'filled') $$) is not null, 'G3 …and writes nothing');

set role authenticated;
select tests.login(:carrier);
select public.empty_truck_set_status((select id from t where k = 'a'), 'filled');
select tests.check((select count(*) = 2 from public.empty_truck_ads where owner_id = :carrier), 'O1 the owner still sees his closed / paused ads');
select tests.login(:other);
select tests.check((select count(*) = 0 from public.empty_truck_ads where owner_id = :carrier), 'O2 "Maşın doldu": gone from the list');

select tests.login(:chief);
select public.empty_truck_set_status((select id from t where k = 'b'), 'active');
reset role;
select tests.check((select count(*) = 1 from public.admin_audit_log where entity_type = 'empty_truck_ads'), 'M1 an admin''s change is logged');
select tests.check((select count(*) from public.cargo) = :cargo_before, 'M2 loads untouched');

select tests.summary('BOŞ MAŞIN ELANLARI (0118)');
rollback;
