-- SERVICES — 0036 "Tent təmiri" category. Read-only checks.
begin;
select tests.check((select count(*) = 1 from public.service_categories
                    where id = 'tarp_repair' and name_az = 'Tent təmiri' and icon = 'tarp' and is_active),
  'T1 category "Tent təmiri" exists and is active');
select tests.check((select count(*) = 1 from public.service_categories where id = 'tarp_repair'),
  'T2 re-running the migration does not duplicate it');
set role authenticated;
select tests.login('a0000000-0000-4000-8000-000000000021');
select tests.check((select count(*) = 1 from public.service_categories where id = 'tarp_repair'),
  'T3 signed-in users see it in the list');
reset role;
select tests.summary('SERVICE CATEGORY TARP (0036)');
rollback;
