-- PAGE BANNERS — 0049: TIR Bazarı and Services banners, night and day
-- pictures, admins only. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''

begin;
set role authenticated;
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_set_page_hero('services', 'https://x/n.jpg', null, 'a', 'b', 'c') $$) like '%admin_only%',
  'B1 a normal user cannot change a banner');
select tests.check(tests.err($$ insert into public.services_hero (id, title) values (1, 'hack') $$) like '%permission denied%',
  'B2 nobody writes the banner table directly');

select tests.login(:admin);
select public.admin_set_page_hero('services', ' https://x/night.jpg ', 'https://x/day.jpg', 'Ustalar', 'yanınızda', '  ');
select tests.check((select image_url = 'https://x/night.jpg' and image_url_day = 'https://x/day.jpg' and title = 'Ustalar' and subtitle is null
                      from public.services_hero), 'B3 admin saves the Services banner: night + day picture, texts (trimmed, empty = default)');
select public.admin_set_page_hero('market', 'https://x/mn.jpg', 'https://x/md.jpg', 'T', 'A', 'S');
select tests.check((select image_url = 'https://x/mn.jpg' and image_url_day = 'https://x/md.jpg' from public.market_hero),
  'B4 admin saves both TIR Bazarı pictures');
-- The 0044 function keeps the day picture.
select public.admin_market_set_hero('https://x/mn2.jpg', 'T', 'A', 'S');
select tests.check((select image_url = 'https://x/mn2.jpg' and image_url_day = 'https://x/md.jpg' from public.market_hero),
  'B5 the old TIR Bazarı save keeps the day picture');
select tests.check(tests.err($$ select public.admin_set_page_hero('users', null, null, null, null, null) $$) like '%invalid_argument%',
  'B6 only the two banners');
select tests.check((select count(*) >= 2 from public.admin_audit_log where action in ('services.hero', 'market.hero')), 'B7 changes are logged');

select tests.login(:other);
select tests.check((select title = 'Ustalar' from public.services_hero), 'B8 everybody signed in reads it');

select tests.summary('PAGE BANNERS (0049)');
rollback;
