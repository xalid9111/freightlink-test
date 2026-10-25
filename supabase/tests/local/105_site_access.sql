-- SITE OPEN / CLOSED — 0068. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''

begin;
set role anon;
select tests.login(null);
select tests.check((select (public.site_status() ->> 'closed')::boolean = false), 'S1 the site starts open');
select tests.check((select (public.site_status() ->> 'admin')::boolean = false), 'S2 a visitor is not an admin');
select tests.check(tests.err($$ select * from public.site_settings $$) like '%permission denied%', 'S3 no direct reading (anon)');
select tests.check(tests.err($$ select public.admin_set_site_status(true, 'x') $$) like '%permission denied%', 'S4 a visitor cannot close the site');
reset role;

set role authenticated;
select tests.login(:user1);
select tests.check(tests.err($$ select public.admin_set_site_status(true, 'x') $$) like '%admin_only%', 'U1 a user cannot close the site');
select tests.check(tests.err($$ update public.site_settings set closed = true $$) like '%permission denied%', 'U2 …nor write the table');
select tests.check((select (public.site_status() ->> 'closed')::boolean = false), 'U3 still open');

select tests.login(:admin);
select tests.check((select (public.admin_set_site_status(true, '  Texniki işlər: saat 18:00-a qədər.  ') ->> 'closed')::boolean),
  'A1 the admin closes the site');
select tests.check((select (public.site_status() ->> 'admin')::boolean), 'A2 …and is told he is an admin (keeps using the app)');
select tests.login(:user1);
select tests.check((select public.site_status() ->> 'message' = 'Texniki işlər: saat 18:00-a qədər.'
                      and (public.site_status() ->> 'closed')::boolean
                      and not (public.site_status() ->> 'admin')::boolean), 'A3 a user sees closed + the notice as typed');
reset role;
set role anon;
select tests.login(null);
select tests.check((select (public.site_status() ->> 'closed')::boolean), 'A4 …a visitor too (login page)');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'site.closed'), 'A5 closing is logged');

set role authenticated;
select tests.login(:admin);
select tests.check(tests.err(format($$ select public.admin_set_site_status(true, %L) $$, repeat('x', 1001))) like '%message_too_long%',
  'A6 a notice longer than 1000 letters is refused');
select tests.check((select not (public.admin_set_site_status(false) ->> 'closed')::boolean), 'A7 the admin opens the site');
select tests.check((select public.site_status() ->> 'message' = 'Texniki işlər: saat 18:00-a qədər.'), 'A8 the last notice is kept for next time');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'site.opened'), 'A9 opening is logged');
select tests.summary('SITE OPEN / CLOSED (0068)');
rollback;
