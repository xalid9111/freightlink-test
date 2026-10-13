-- AUTOFIX — 0034. Rolled back at the end.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;

-- ---- reports -------------------------------------------------------------
select tests.login(:other);
select tests.check(public.autofix_report('[{"fingerprint":"api:pgrst301:cargo","kind":"api","code":"PGRST301","message":"JWT expired","route":"/cargo"},
                                          {"fingerprint":"runtime:typeerror:abc","kind":"runtime","code":"TypeError","message":"Null check","file":"lib/features/x.dart","line":"42","stack":"#0 x"},
                                          {"fingerprint":"BAD FP!","kind":"api"},
                                          {"fingerprint":"ok:kind","kind":"hack"}]') = 2,
  'A1 valid reports are stored, malformed ones are skipped');
select tests.check(public.autofix_report('[{"fingerprint":"api:pgrst301:cargo","kind":"api","message":"JWT expired","count":3}]') = 1,
  'A2 same problem again → counted');
select tests.check((select count(*) = 0 from public.app_errors), 'A3 normal users cannot read the error list');
select tests.check(tests.err($$ select public.admin_autofix_run((select id from public.app_errors limit 1)) $$) like '%admin_only%',
  'A4 normal users cannot run fixes');
select tests.check(tests.err($$ insert into public.app_errors (fingerprint, kind) values ('x:y:z', 'api') $$) is not null,
  'A5 nobody writes the table directly');

select tests.login(:owner1);
select public.autofix_report('[{"fingerprint":"api:pgrst301:cargo","kind":"api","message":"JWT expired"}]');

select tests.login(:admin);
select tests.check((select count = 5 and users = 2 and file is null from public.app_errors where fingerprint = 'api:pgrst301:cargo'),
  'A6 admin sees one row per problem with count and number of users');
select tests.check((select file = 'lib/features/x.dart' and line = 42 from public.app_errors where fingerprint = 'runtime:typeerror:abc'),
  'A7 file and line are kept for code errors');

-- ---- recovery --------------------------------------------------------------
select tests.check(public.admin_autofix_run((select id from public.app_errors where fingerprint = 'api:pgrst301:cargo')) = 'refresh_data',
  'R1 API problem → pre-defined safe action "refresh_data"');
select tests.check((select status = 'fixed' from public.app_errors where fingerprint = 'api:pgrst301:cargo'), 'R2 marked fixed');
select tests.check(public.admin_autofix_run((select id from public.app_errors where fingerprint = 'runtime:typeerror:abc')) = 'none'
  and (select status = 'open' from public.app_errors where fingerprint = 'runtime:typeerror:abc'),
  'R3 code error → no automatic fix (manual)');
select tests.check((select count(*) = 1 from public.autofix_actions where action = 'none' and not ok), 'R4 the refused attempt is logged');

select tests.login(:other);
select tests.check((select action = 'refresh_data' from public.autofix_latest_command()), 'R5 apps see the newest command');
select tests.check(tests.err($$ select count(*) from public.autofix_commands $$) is not null, 'R6 …but cannot read the command table itself');
select public.autofix_report('[{"fingerprint":"api:pgrst301:cargo","kind":"api","message":"JWT expired"}]');
select tests.login(:admin);
select tests.check((select status = 'open' from public.app_errors where fingerprint = 'api:pgrst301:cargo'), 'R7 a fixed problem that comes back is open again');
select public.admin_autofix_set_status((select id from public.app_errors where fingerprint = 'runtime:typeerror:abc'), 'fixed');
select tests.check((select status = 'fixed' from public.app_errors where fingerprint = 'runtime:typeerror:abc'), 'R8 admin marks a manual fix as fixed');

-- ---- CI results ----------------------------------------------------------
reset role;
set role anon;
select tests.check(tests.err($$ select public.autofix_ci_report('wrong', 'abcdef1', true, 0, 0, 5, 0, 'x') $$) like '%invalid_token%',
  'C1 CI report needs the token (none set yet)');
reset role;
set role authenticated;
select tests.login(:admin);
select public.admin_autofix_set_ci_token('test-token-0123456789abcdefgh');
reset role;
set role anon;
select tests.check(public.autofix_ci_report('test-token-0123456789abcdefgh', 'abcdef1', false, 1, 2, 10, 1, 'lib/a.dart:3:1 error') > 0,
  'C2 CI with the right token can post results');
select tests.check(tests.err($$ select public.autofix_ci_report('wrong-token-0123456789abcd', 'abcdef1', true, 0, 0, 5, 0, 'x') $$) like '%invalid_token%',
  'C3 a wrong token is refused');
reset role;
set role authenticated;
select tests.login(:admin);
select tests.check((select not ok and tests_failed = 1 from public.autofix_ci_runs order by id desc limit 1), 'C4 admin sees the CI run');

-- ---- rate limit -----------------------------------------------------------
select tests.login(:owner1);
select public.autofix_report((select jsonb_agg(jsonb_build_object('fingerprint', 'rt:flood:' || g, 'kind', 'runtime')) from generate_series(1, 20) g));
select public.autofix_report((select jsonb_agg(jsonb_build_object('fingerprint', 'rt:flood2:' || g, 'kind', 'runtime')) from generate_series(1, 20) g));
select public.autofix_report((select jsonb_agg(jsonb_build_object('fingerprint', 'rt:flood3:' || g, 'kind', 'runtime')) from generate_series(1, 20) g));
select tests.check(public.autofix_report('[{"fingerprint":"rt:flood:x","kind":"runtime"}]') = 0, 'L1 max 60 reports per 10 minutes per user');

reset role;
select tests.summary('AUTOFIX (0034)');
rollback;
