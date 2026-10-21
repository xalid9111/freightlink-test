-- PAGE BANNER TEXT TOGGLE — 0050. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:admin);
select public.admin_set_page_hero('services', 'https://x/n.jpg', 'https://x/d.jpg', null, null, null, false);
select tests.check((select not show_text and image_url = 'https://x/n.jpg' from public.services_hero), 'T1 admin: picture only, no texts');
select public.admin_set_page_hero('market', 'https://x/m.jpg', null, 'T', null, null, true);
select tests.check((select show_text and title = 'T' from public.market_hero), 'T2 admin: texts on');
-- The 0049 version keeps the setting.
select public.admin_set_page_hero('services', 'https://x/n2.jpg', null, null, null, null);
select tests.check((select not show_text and image_url = 'https://x/n2.jpg' from public.services_hero), 'T3 the 6-parameter save keeps "picture only"');
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_set_page_hero('services', null, null, null, null, null, true) $$) like '%admin_only%',
  'T4 only admins');
select tests.summary('PAGE BANNER TEXT TOGGLE (0050)');
rollback;
