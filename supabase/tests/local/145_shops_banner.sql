-- Mağazalar's own map banner — 0108. Rolled back.
\set admin '''a0000000-0000-4000-8000-000000000001'''
\set user1 '''a0000000-0000-4000-8000-000000000012'''

begin;
reset role;
insert into public.services_hero (id, image_url, title) values (1, 'https://x/services.jpg', 'Servis')
  on conflict (id) do update set image_url = excluded.image_url, title = excluded.title;
insert into public.tirpark_hero (id, image_url, title) values (1, 'https://x/park.jpg', 'Park')
  on conflict (id) do update set image_url = excluded.image_url, title = excluded.title;

set role authenticated;
select tests.login(:admin);
select public.admin_set_page_hero('shops', 'https://x/shop-night.jpg', 'https://x/shop-day.jpg', 'TIR ehtiyat', 'hissələri', 'Mağazalar', true);
select public.admin_set_page_hero_focus('shops', 0.2, -0.3, 0.1, 0.0);
select public.admin_set_page_hero_zoom('shops', 1.5, 1.2);
select tests.check((select image_url = 'https://x/shop-night.jpg' and image_url_day = 'https://x/shop-day.jpg' and title = 'TIR ehtiyat'
                     and abs(focus_x - 0.2) < 0.001 and abs(zoom - 1.5) < 0.001 from public.shops_hero where id = 1),
  'B1 the admin saves the Mağazalar banner (picture, texts, place, zoom)');
select tests.check((select image_url = 'https://x/services.jpg' and title = 'Servis' and zoom = 1 from public.services_hero where id = 1),
  'B2 the Servislər banner is untouched');
select tests.check((select image_url = 'https://x/park.jpg' and title = 'Park' from public.tirpark_hero where id = 1),
  'B3 the TIRPark banner is untouched');
select public.admin_set_page_hero('services', 'https://x/services2.jpg', null, 'Servis 2', null, null, true);
select tests.check((select image_url = 'https://x/shop-night.jpg' from public.shops_hero where id = 1),
  'B4 a Servislər edit does not touch Mağazalar');
select tests.check(tests.err($$ select public.admin_set_page_hero('nope', null, null, null, null, null, true) $$) like '%invalid_argument%',
  'B5 unknown page refused as before');

select tests.login(:user1);
select tests.check(tests.err($$ select public.admin_set_page_hero('shops', 'https://x/hack.jpg', null, null, null, null, true) $$) is not null,
  'B6 a non-admin cannot change it');
select tests.check((select count(*) = 1 from public.shops_hero), 'B7 signed-in users read it');
reset role;
set role anon;
select tests.login(null);
select tests.check((select count(*) = 1 from public.shops_hero), 'B8 visitors read it (0107)');
select tests.check(tests.err($$ update public.shops_hero set title = 'x' $$) is not null
                   or (select title = 'TIR ehtiyat' from public.shops_hero), 'B9 visitors cannot change it');
reset role;
select tests.check((select count(*) >= 1 from public.admin_audit_log where action = 'shops.hero'), 'B10 every change in the Audit Log');
select tests.summary('MAĞAZALAR BANNERİ (0108)');
rollback;
