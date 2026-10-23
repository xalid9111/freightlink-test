-- VIP LOADS — 0059: admin VIP on / off, VIP row interval, no VIP by
-- posting a load. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c5900000-0000-4000-8000-000000000001'''

begin;
select tests.check((select vip_every_rows = 3 from public.cargo_feed_settings where id = 1), 'V1 default: a VIP row after every 3 rows');

set role authenticated;
select tests.login(:owner);
-- Posting a load "as VIP" does not make it VIP.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date,
                          is_featured, featured_until)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Russia', 'Moscow', 20000, 990, current_date, true, now() + interval '30 days');
select tests.check((select not is_featured and featured_until is null from public.cargo where id = :c1), 'V2 a user cannot post a VIP load');
select tests.check(tests.err($$ update public.cargo set is_featured = true where id = 'c5900000-0000-4000-8000-000000000001' $$)
  like '%can only be changed by an admin%', 'V3 nor make his load VIP later');
select tests.check(tests.err($$ select public.admin_set_cargo_vip('c5900000-0000-4000-8000-000000000001', true, null) $$) like '%admin_only%',
  'V4 only an admin gives VIP');
select tests.check(tests.err($$ select public.admin_set_cargo_vip_every(2) $$) like '%admin_only%', 'V5 only an admin changes the interval');
select tests.check(tests.err($$ update public.cargo_feed_settings set vip_every_rows = 2 $$) like '%permission denied%', 'V6 nobody writes the setting directly');

select tests.login(:admin);
select public.admin_set_cargo_vip(:c1, true, now() + interval '7 days');
select tests.check((select is_featured and featured_until > now() from public.cargo where id = :c1), 'V7 admin makes a load VIP until a date');
select tests.check(tests.err($$ select public.admin_set_cargo_vip('c5900000-0000-4000-8000-000000000001', true, now() - interval '1 day') $$)
  like '%invalid_argument%', 'V8 an end date in the past is refused');
select public.admin_set_cargo_vip(:c1, false, null);
select tests.check((select not is_featured and featured_until is null and offered_price = 990 from public.cargo where id = :c1),
  'V9 admin turns VIP off; the load itself unchanged');
select public.admin_set_cargo_vip_every(2);
select tests.check((select vip_every_rows = 2 from public.cargo_feed_settings), 'V10 admin sets 2 rows');
select tests.check(tests.err($$ select public.admin_set_cargo_vip_every(5) $$) like '%invalid_argument%', 'V11 only 2 / 3 / 4');
select tests.check((select count(*) = 3 from public.admin_audit_log where action in ('cargo.vip_on', 'cargo.vip_off', 'cargo.vip_every')),
  'V12 every change is logged');
select tests.login(:other);
select tests.check((select vip_every_rows = 2 from public.cargo_feed_settings), 'V13 everybody reads the interval');
reset role;
set role anon;
select tests.check((select count(*) = 1 from public.cargo_feed_settings), 'V14 also before sign-in');
reset role;
select tests.summary('VIP LOADS (0059)');
rollback;
