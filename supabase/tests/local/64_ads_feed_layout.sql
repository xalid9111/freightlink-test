-- ADS — 0025: feed position and rotation settings. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:other);
select tests.check(public.ads_feed_layout() @> '{"first_after":6,"every":6,"rotate_minutes":0}'::jsonb,
  'L1 defaults = previous behaviour (6 / 6 / no rotation)');
select tests.check(tests.err($$ select public.admin_set_ads_feed_layout(3, 5, 10) $$) like '%admin_only%',
  'L2 only admins change the layout');
select tests.login(:admin);
select tests.check(public.admin_set_ads_feed_layout(3, 5, 10) @> '{"first_after":3,"every":5,"rotate_minutes":10}'::jsonb,
  'L3 admin saves first ad after 3 loads, then every 5, 10 minutes each');
select tests.login(:other);
select tests.check((public.ads_feed_layout()->>'every')::int = 5, 'L4 every user reads the new layout');
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_set_ads_feed_layout(0, 5, 10) $$) like '%invalid_first_after%', 'L5 first ad after at least 1 load');
select tests.check(tests.err($$ select public.admin_set_ads_feed_layout(3, 1, 10) $$) like '%invalid_every%', 'L6 never two ads in a row');
select tests.check(tests.err($$ select public.admin_set_ads_feed_layout(3, 5, -1) $$) like '%invalid_rotate_minutes%', 'L7 minutes 0–1440');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'ads_feed_layout.update'), 'L8 change is in the audit log');
select tests.login(null);
reset role;
set role anon;
select tests.check(tests.err($$ select public.ads_feed_layout() $$) is not null, 'L9 not callable without login');
reset role;
select tests.summary('ADS FEED LAYOUT (0025)');
rollback;
