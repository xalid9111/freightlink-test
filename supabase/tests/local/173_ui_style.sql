-- NEUMORF LOOK SWITCH — 0137. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set u1     '''a0000000-0000-4000-8000-000000000021'''

begin;
set role anon;
select tests.login(null);
select tests.check((select (public.ui_style_current() ->> 'neumorph') = 'false'), 'S1 off by default; a visitor reads it');
select tests.check(tests.err($$ select public.admin_ui_style_set(true) $$) like '%permission denied%', 'S2 a visitor cannot switch it');
reset role;
set role authenticated;
select tests.login(:u1);
select tests.check(tests.err($$ select public.admin_ui_style_set(true) $$) is not null, 'S3 a user cannot switch it');
select tests.check(tests.err($$ update public.ui_style_state set neumorph = true $$) like '%permission denied%', 'S4 no direct write');
select tests.login(:admin);
select public.admin_ui_style_set(true);
select tests.check((select (public.ui_style_current() ->> 'neumorph') = 'true'), 'S5 an admin switches it on');
select public.admin_ui_style_set(false);
select tests.check((select (public.ui_style_current() ->> 'neumorph') = 'false'), 'S6 …and off');
reset role;
select tests.check((select count(*) = 2 from public.admin_audit_log where action = 'ui_style.neumorph'), 'S7 both changes logged');
select tests.summary('NEUMORF SWITCH (0137)');
rollback;
