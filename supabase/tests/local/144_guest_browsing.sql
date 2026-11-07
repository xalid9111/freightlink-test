-- Browsing without an account — 0107. A visitor (anon) reads what a
-- signed-in stranger reads on the public catalogue, nothing private, and
-- writes nothing. Rolled back.
\set seller '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set m1 '''b1070000-0000-4000-8000-000000000001'''
\set m2 '''b1070000-0000-4000-8000-000000000002'''
\set s1 '''b1070000-0000-4000-8000-000000000011'''
\set s2 '''b1070000-0000-4000-8000-000000000012'''
\set p1 '''b1070000-0000-4000-8000-000000000021'''
\set p2 '''b1070000-0000-4000-8000-000000000022'''

begin;
reset role;
insert into public.market_listings (id, owner_id, category, brand, model, year, price, currency, city, photos, phone, status)
values (:m1, :seller, 'truck', 'Volvo', 'FH', 2018, 50000, 'EUR', 'Baku', '{a.jpg}', '+994501112233', 'active'),
       (:m2, :seller, 'truck', 'DAF', 'XF', 2017, 40000, 'EUR', 'Baku', '{a.jpg}', '+994501112233', 'draft');
insert into public.service_providers (id, owner_id, name, lat, lng, categories, status, admin_note)
values (:s1, null, 'Açıq Servis', 40.4, 49.8, '{tyres}', 'approved', 'gizli qeyd'),
       (:s2, null, 'Gizli Servis', 40.5, 49.9, '{tyres}', 'rejected', null);
insert into public.tir_parks (id, name, lat, lng, city, amenities, created_by, status)
values (:p1, 'Açıq Park', 40.3, 49.7, 'Bakı', '{}', :seller, 'approved'),
       (:p2, 'Gözləyən Park', 40.2, 49.6, 'Bakı', '{}', :seller, 'pending');

set role anon;
select tests.login(null);

-- What a visitor may look at
select tests.check((select count(*) = 1 from public.market_listings where id in (:m1, :m2)), 'G1 TIR Bazarı: an active ad yes, a draft no');
select tests.check(exists (select 1 from public.market_search() where id = :m1)
                   and not exists (select 1 from public.market_search() where id = :m2), 'G2 the TIR Bazarı search works for a visitor (active ads only)');
select tests.check((select array_agg(id) = array[:s1]::uuid[] from public.service_providers where id in (:s1, :s2)), 'G3 Servislər: an open service yes, a rejected one no');
select tests.check(tests.err($$ select admin_note from public.service_providers $$) like '%permission denied%', 'G4 the admin''s note on a service stays hidden');
select tests.check((select array_agg(id) = array[:p1]::uuid[] from public.tir_parks where id in (:p1, :p2)), 'G5 TIRPark: an approved park yes, a waiting one no');
select tests.check(tests.err($$ select count(*) from public.cargo $$) is null, 'G6 Yüklər: loads can be read');
select tests.check(tests.err($$ select id, full_name, avatar_url, is_verified from public.user_profiles limit 1 $$) is null, 'G7 public profile view (name, picture, badge)');
select tests.check(tests.err($$ select * from public.nearby_services(40.4, 49.8, 50) $$) is null, 'G8 nearby services work for a visitor');

-- Nothing private
select tests.check((select count(*) = 0 from public.users), 'G9 no users rows (phone, e-mail)');
select tests.check(tests.err($$ select 1 from public.messages $$) like '%permission denied%'
                   or (select count(*) = 0 from public.messages), 'G10 no messages');
select tests.check(tests.err($$ select 1 from public.conversations $$) like '%permission denied%'
                   or (select count(*) = 0 from public.conversations), 'G11 no conversations');
select tests.check(tests.err($$ select 1 from public.tir_park_bookings $$) like '%permission denied%', 'G12 no park bookings');
select tests.check(tests.err($$ select 1 from public.user_favorites $$) like '%permission denied%', 'G13 no favourites');
select tests.check(tests.err($$ select 1 from public.job_seeker_profiles $$) like '%permission denied%', 'G14 no job centre');
select tests.check(tests.err($$ select public.get_user_contact('a0000000-0000-4000-8000-000000000012') $$) like '%permission denied%', 'G15 no contact numbers through the contact function');

-- Writes nothing
select tests.check(tests.err($$ insert into public.market_listings (owner_id, category, brand, model, price, currency, city) values ('a0000000-0000-4000-8000-000000000012', 'truck', 'X', 'Y', 1, 'EUR', 'Baku') $$) is not null, 'G16 cannot post an ad');
select tests.check(tests.err($$ update public.service_providers set name = 'x' where id = 'b1070000-0000-4000-8000-000000000011' $$) is not null
                   or (select name = 'Açıq Servis' from public.service_providers where id = :s1), 'G17 cannot change a service');
select tests.check(tests.err($$ select public.favorite_set('user', 'a0000000-0000-4000-8000-000000000012', true) $$) like '%permission denied%', 'G18 cannot like');
reset role;
select tests.check((select name = 'Açıq Servis' from public.service_providers where id = :s1), 'G19 nothing changed');

-- Signed-in users: as before
set role authenticated;
select tests.login(:other);
select tests.check((select count(*) = 1 from public.market_listings where id in (:m1, :m2)), 'G20 a signed-in stranger sees the same as before');
reset role;
select tests.check((select count(*) >= 1 from pg_policies where schemaname = 'public' and tablename = 'market_listings' and policyname = 'market_select_guest'), 'G21 the guest rule is a twin of the signed-in rule');
select tests.summary('QEYDİYYATSIZ BAXIŞ (0107)');
rollback;
