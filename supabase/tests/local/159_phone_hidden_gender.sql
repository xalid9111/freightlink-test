-- 0122: "Telefon nömrəmi gizlət" and Kişi / Qadın. Rolled back.
\set p       '''f0000000-0000-4000-8000-0000000004a1'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set admin   '''a0000000-0000-4000-8000-000000000001'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-000000000000', :p, 'authenticated', 'authenticated', 'phone-owner@t.test', '{"full_name":"Nömrə Sahibi"}');
update public.users set phone = '+994501112233' where id = :p;
update public.users set role = 'admin' where id = :admin;
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values ('c0000000-0000-4000-8000-0000000004a1', :p, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 1000, 100, current_date);
insert into public.cargo_contacts (cargo_id, phone) values ('c0000000-0000-4000-8000-0000000004a1', '+994552223344');
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status, phone)
values ('e0000000-0000-4000-8000-0000000004a1', :p, 'truck', 'DAF', 'XF', 100, 'AZN', 'active', '+994501112233');
set local app.market_trusted = '';
insert into public.service_providers (id, owner_id, name, lat, lng, status, categories, phone, whatsapp)
values ('5e000000-0000-4000-8000-0000000004a1', :p, 'Gizli Servis', 40.5, 49.9, 'approved', '{engine}', '+994501112233', '+994501112233');
insert into public.empty_truck_ads (id, owner_id, from_city, from_country, any_direction, truck_type, free_tons, phone, whatsapp)
values ('7c000000-0000-4000-8000-0000000004a1', :p, 'Baku', 'Azerbaijan', true, 'tent', 10, '+994501112233', '+994501112233');
create temp table other_before on commit drop as
  select (select count(*) from public.market_listings where owner_id = :other and phone is not null) m;

-- 1) He hides his number.
set role authenticated;
select tests.login(:p);
select public.my_set_phone_hidden(true);
reset role;
select tests.check((select phone is null from public.market_listings where id = 'e0000000-0000-4000-8000-0000000004a1'), 'H1 TIR Bazarı ad: no number in the ad');
select tests.check((select phone is null and whatsapp is null from public.service_providers where id = '5e000000-0000-4000-8000-0000000004a1'), 'H2 service page: no number / WhatsApp');
select tests.check((select phone is null and whatsapp is null from public.empty_truck_ads where id = '7c000000-0000-4000-8000-0000000004a1'), 'H3 empty truck ad: no number');
select tests.check((select count(*) = 3 from public.hidden_ad_phones where owner_id = :p), 'H4 the numbers are kept safe (not lost)');
-- A new ad while hidden stays without a number.
set local app.market_trusted = '1';
insert into public.market_listings (id, owner_id, category, brand, model, price, currency, status, phone)
values ('e0000000-0000-4000-8000-0000000004a2', :p, 'truck', 'MAN', 'TGX', 100, 'AZN', 'active', '+994501112233');
set local app.market_trusted = '';
select tests.check((select phone is null from public.market_listings where id = 'e0000000-0000-4000-8000-0000000004a2'), 'H5 a new ad stays hidden too');

-- 2) Others: no number on the load, the profile or the chat; he and the admins still see it.
set role authenticated;
select tests.login(:other);
select tests.check((select (j->>'phone') is null and (j->>'contact_phone') is null and (j->>'phone_hidden')::boolean
                    from (select public.get_cargo_contact('c0000000-0000-4000-8000-0000000004a1') j) x), 'O1 the load: no number, "hidden"');
select tests.check((select public.get_user_contact(:p) ->> 'phone') is null, 'O2 profile / chat: no number');
select tests.check((select phone_hidden from public.user_phone_privacy where id = :p), 'O3 the app knows to say "Nömrə gizlidir"');
select tests.check(tests.err($$ select * from public.hidden_ad_phones $$) is not null, 'O4 nobody reads the kept numbers');
select tests.check((select count(*) = 0 from public.users where id = 'f0000000-0000-4000-8000-0000000004a1'), 'O5 his private row stays private');
reset role;
set role authenticated;
select tests.login(:p);
select tests.check((select (public.get_cargo_contact('c0000000-0000-4000-8000-0000000004a1') ->> 'phone') = '+994501112233'), 'O6 he still sees his own number');
reset role;
set role authenticated;
select tests.login(:admin);
select tests.check((select (public.get_user_contact(:p) ->> 'phone') = '+994501112233'), 'O7 admins still see it');
reset role;
set role anon;
select tests.check(tests.err($$ select public.my_set_phone_hidden(false) $$) is not null, 'O8 visitors cannot');
select tests.check((select count(*) >= 1 from public.user_profiles), 'O9 visitors still read public profiles (0107)');
reset role;

-- 3) He shows it again: every number back where it was.
set role authenticated;
select tests.login(:p);
select public.my_set_phone_hidden(false);
reset role;
select tests.check((select phone = '+994501112233' from public.market_listings where id = 'e0000000-0000-4000-8000-0000000004a1')
               and (select phone = '+994501112233' from public.market_listings where id = 'e0000000-0000-4000-8000-0000000004a2')
               and (select phone = '+994501112233' and whatsapp = '+994501112233' from public.service_providers where id = '5e000000-0000-4000-8000-0000000004a1')
               and (select phone = '+994501112233' from public.empty_truck_ads where id = '7c000000-0000-4000-8000-0000000004a1'),
  'R1 all numbers back');
select tests.check((select count(*) = 0 from public.hidden_ad_phones where owner_id = :p), 'R2 the store is empty again');
set role authenticated;
select tests.login(:other);
select tests.check((select public.get_cargo_contact('c0000000-0000-4000-8000-0000000004a1') ->> 'contact_phone') = '+994552223344', 'R3 the load shows it again');
reset role;
select tests.check((select m = (select count(*) from public.market_listings where owner_id = :other and phone is not null) from other_before), 'R4 other users untouched');

-- 4) Kişi / Qadın: private.
set role authenticated;
select tests.login(:p);
select public.my_set_gender('female');
select tests.check((select gender = 'female' from public.users where id = :p), 'G1 saved, he reads it');
select tests.check(tests.err($$ select public.my_set_gender('other') $$) like '%invalid_argument%', 'G2 only Kişi / Qadın');
select public.my_set_gender(null);
select tests.check((select gender is null from public.users where id = :p), 'G3 can be taken off');
reset role;
rollback;
