-- SERVICES — 0043 "Ehtiyat hissələri satışı" category. Read-only checks.
begin;
select tests.check((select count(*) = 1 from public.service_categories
                    where id = 'spare_parts' and name_az = 'Ehtiyat hissələri satışı' and icon = 'parts' and is_active),
  'P1 category "Ehtiyat hissələri satışı" exists and is active');
select tests.check((select id from public.service_categories where is_active order by sort_order, id limit 1) = 'spare_parts',
  'P2 it is the first category in Servislər');
select tests.check((select count(*) = 1 from public.service_categories where id = 'spare_parts'),
  'P3 re-running the migration does not duplicate it');
set role authenticated;
select tests.login('a0000000-0000-4000-8000-000000000021');
select tests.check((select count(*) = 1 from public.service_categories where id = 'spare_parts'),
  'P4 signed-in users see it in the list');
reset role;
select tests.summary('SERVICE CATEGORY SPARE PARTS (0043)');
rollback;
