-- PROFILE ACTIVITIES — 0039: one account, any combination of
-- Daşıyıcı / Yük verən / Usta-Servis / Satış. Rolled back at the end.
-- Run with: psql -v mig39=<path to 0039_user_activities.sql>
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set owner2  '''a0000000-0000-4000-8000-000000000012'''
\set owner3  '''a0000000-0000-4000-8000-000000000013'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set cargo   '''c7700000-0000-4000-8000-000000000001'''

begin;
-- Existing accounts were filled from what they already are.
select tests.check((select 'carrier' = any(activities) from public.users where id = :owner1), 'U1 role carrier → Daşıyıcı');
select tests.check((select 'carrier' = any(activities) from public.users where id = :owner3), 'U1b role driver → Daşıyıcı');
select tests.check((select 'shipper' = any(activities) and not 'carrier' = any(activities) from public.users where id = :owner2),
  'U1c role cargo_owner → Yük verən');
select tests.check((select bool_and(('service' = any(u.activities)) = exists (select 1 from public.service_providers s where s.owner_id = u.id))
                    from public.users u), 'U1d service profile owners → Usta / Servis');
select tests.check((select count(*) = 0 from public.users where activities is null), 'U1e every existing account filled');
select tests.check((select coalesce(array_length(activities, 1), 0) = 0 from public.users where id = :other)
                   or (select activities = '{shipper}' from public.users where id = :other), 'U1f other: cargo_owner → Yük verən');
create temp table t_roles as select id, role from public.users;
grant select on t_roles to authenticated;

-- A load by owner2 (Yük verən).
set role authenticated;
select tests.login(:owner2);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:cargo, :owner2, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date);

-- "other" (old role cargo_owner) turns on ALL four activities at once.
select tests.login(:other);
select tests.check(not exists (select 1 from public.carriers where user_id = :other), 'U2a no carrier profile yet');
select tests.check(public.set_my_activities(array['seller','carrier','service','shipper','carrier']) = '{carrier,seller,service,shipper}',
  'U2 all four activities at once (duplicates removed)');
select tests.check((select activities = '{carrier,seller,service,shipper}' from public.users where id = :other), 'U2b saved');
select tests.check(exists (select 1 from public.carriers where user_id = :other), 'U3 Daşıyıcı on → carrier profile created');

-- The old role does not block the new activity: an offer and a chat.
insert into public.offers (cargo_id, carrier_id, offered_price, currency)
values (:cargo, public.current_carrier_id(), 1400, 'USD');
select tests.check((select count(*) = 1 from public.offers where cargo_id = :cargo), 'U4 old role cargo_owner can make an offer as Daşıyıcı');
create temp table t_conv as select id from public.get_or_create_conversation(:cargo);
select tests.check((select count(*) = 1 from t_conv), 'U5 … and write to the load owner');
select tests.check((select role from public.users where id = :other) = (select role from t_roles where id = :other), 'U6 old role unchanged');

-- Turning everything off deletes nothing and keeps the chat open.
select tests.check(public.set_my_activities('{}') = '{}', 'U7 all off');
select tests.check(exists (select 1 from public.carriers where user_id = :other), 'U8 carrier profile kept');
select tests.check((select count(*) = 1 from public.offers where cargo_id = :cargo), 'U9 offer kept and still visible');
select tests.check((select count(*) = 1 from public.conversations where id = (select id from t_conv)), 'U10 chat still open for the user');
select tests.check(public.set_my_activities(null) = '{}', 'U10b null = nothing selected');

select tests.check(tests.err($$ select public.set_my_activities(array['admin']) $$) like '%invalid_activity%', 'U11 only the four activities');
select tests.check(tests.err($$ update public.users set activities = array['admin'] where id = auth.uid() $$) like '%users_activities_check%',
  'U12 also a direct update cannot store anything else');
select tests.check((select role from public.users where id = :other) = (select role from t_roles where id = :other), 'U13 role still unchanged');

-- Public profile shows the activities.
select public.set_my_activities(array['seller']);
select tests.login(:owner1);
select tests.check((select activities = '{seller}' from public.user_activities where id = :other), 'U14 user_activities shows them to signed-in users');
reset role;
set role anon;
select tests.check(tests.err($$ select * from public.user_activities $$) like '%permission denied%', 'U14b not public to anonymous');
reset role;
set role authenticated;

select tests.login(null);
select tests.check(tests.err($$ select public.set_my_activities(array['seller']) $$) like '%not_authenticated%', 'U15 anonymous refused');
reset role;

-- Re-running 0039 keeps every user's own choice.
\i :mig39
select tests.check((select activities = '{seller}' from public.users where id = :other), 'U16 re-run keeps the user''s choice');
select tests.check((select activities is not null from public.users where id = :owner2), 'U17 re-run fine');

select tests.summary('PROFILE ACTIVITIES (0039)');
rollback;
