-- AUTOFIX CLEANUP — 0042 + 0057 (old hidden ones too): solved problems found automatically, deleted
-- only on the admin's request, only status 'fixed'. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:other);
select public.autofix_report('[{"fingerprint":"rt:old:open","kind":"runtime","message":"old"},
                               {"fingerprint":"rt:new:open","kind":"runtime","message":"new"},
                               {"fingerprint":"rt:old:ignored","kind":"runtime","message":"hidden"},
                               {"fingerprint":"rt:manual:fixed","kind":"runtime","message":"manual"}]');
reset role;
-- As the database: make three of them old (not seen for 5 days).
update public.app_errors set last_seen_at = now() - interval '5 days'
 where fingerprint in ('rt:old:open', 'rt:old:ignored', 'rt:manual:fixed');
update public.app_errors set status = 'ignored' where fingerprint = 'rt:old:ignored';
update public.app_errors set status = 'fixed', resolved_at = now() where fingerprint = 'rt:manual:fixed';

set role authenticated;
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_autofix_auto_resolve(3) $$) like '%admin_only%',
  'D1 normal users cannot run the automatic check');
select tests.check(tests.err($$ select public.admin_autofix_delete_fixed() $$) like '%admin_only%',
  'D2 normal users cannot delete');

select tests.login(:admin);
select tests.check(public.admin_autofix_auto_resolve(3) = 2, 'D3 the old open and the old hidden problem are found (0057)');
select tests.check((select status = 'fixed' and resolved_by is null and resolved_at is not null
                      from public.app_errors where fingerprint = 'rt:old:open'), 'D4 …and marked fixed by the system');
select tests.check((select status = 'open' from public.app_errors where fingerprint = 'rt:new:open'), 'D5 a recent open problem stays open');
select tests.check((select status = 'fixed' and resolved_by is null from public.app_errors where fingerprint = 'rt:old:ignored'),
  'D6 an old hidden problem is moved to solved too (0057)');
select tests.check((select count(*) = 2 from public.autofix_actions where note = 'auto_not_seen'), 'D7 the automatic change is logged');
select tests.check(public.admin_autofix_auto_resolve(3) = 0, 'D8 running it again changes nothing');

select tests.login(:other);
select public.autofix_report('[{"fingerprint":"rt:old:open","kind":"runtime","message":"old"}]');
select tests.login(:admin);
select tests.check((select status = 'open' from public.app_errors where fingerprint = 'rt:old:open'),
  'D9 an auto-fixed problem that happens again is open again');
select public.admin_autofix_set_status((select id from public.app_errors where fingerprint = 'rt:old:open'), 'fixed');

select tests.check(public.admin_autofix_delete_fixed() = 3, 'D10 delete removes exactly the three fixed problems');
select tests.check((select count(*) = 0 from public.app_errors where status = 'fixed'), 'D11 no fixed problem is left');
select tests.check((select count(*) = 1 from public.app_errors where fingerprint = 'rt:new:open'),
  'D12 the recent open problem is kept');
select tests.check((select count(*) >= 1 from public.autofix_actions where note = 'auto_not_seen'), 'D13 the action log is kept');
select tests.check(public.admin_autofix_delete_fixed() = 0, 'D14 deleting again deletes nothing');

reset role;
select tests.summary('AUTOFIX CLEANUP (0042)');
rollback;
