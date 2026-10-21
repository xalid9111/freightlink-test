-- PAGE BANNER ZOOM — 0052. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
select public.admin_set_page_hero_zoom('services', 1.8, 2.5);
select tests.check((select zoom = 1.8::real and zoom_day = 2.5::real from public.services_hero), 'Z1 admin saves the zoom (night + day)');
select public.admin_set_page_hero_zoom('market', 9, 0);
select tests.check((select zoom = 3 and zoom_day = 1 from public.market_hero), 'Z2 limited to 1..3');
select public.admin_set_page_hero_focus('services', 0.4, 0, 0, 0);
select tests.check((select zoom = 1.8::real and focus_x = 0.4::real from public.services_hero), 'Z3 focus and zoom are kept together');
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_set_page_hero_zoom('services', 2, 2) $$) like '%admin_only%', 'Z4 only admins');
select tests.summary('PAGE BANNER ZOOM (0052)');
rollback;
