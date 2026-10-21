-- PAGE BANNER FOCUS — 0051. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
select public.admin_set_page_hero_focus('services', 0.5, -0.25, -1, 1);
select tests.check((select focus_x = 0.5 and focus_y = -0.25 and focus_day_x = -1 and focus_day_y = 1 from public.services_hero),
  'F1 admin saves the part in front (night + day)');
select public.admin_set_page_hero_focus('market', 3, -7, null, null);
select tests.check((select focus_x = 1 and focus_y = -1 and focus_day_x = 0 and focus_day_y = 0 from public.market_hero),
  'F2 out of range is clamped, empty = middle');
select public.admin_set_page_hero('services', 'https://x/n.jpg', null, 'A', null, null, true);
select tests.check((select focus_x = 0.5 and image_url = 'https://x/n.jpg' from public.services_hero), 'F3 saving the picture keeps the focus');
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_set_page_hero_focus('services', 0, 0, 0, 0) $$) like '%admin_only%', 'F4 only admins');
select tests.summary('PAGE BANNER FOCUS (0051)');
rollback;
