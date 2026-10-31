-- TIRPark comments and pictures — 0078. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''
\set user2  '''a0000000-0000-4000-8000-000000000021'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
set role authenticated;
select tests.login(:user1);
insert into ids values ('p', public.tir_park_add('Utep TIR Parkı', 40.4560, 49.7300, 'Xırdalan', array['secure']));
-- Pictures: admins only (owner, 31.10.2026), only profile-media links, at most 10.
select tests.check(tests.err($$ select public.tir_park_set_photos((select id from ids where k='p'),
  array['https://x.supabase.co/storage/v1/object/public/profile-media/u/1.jpg']) $$) like '%admin_only%',
  'F0 not even the author changes the pictures (admins only)');
select tests.login(:admin);
select public.tir_park_set_photos((select id from ids where k='p'),
  array['https://x.supabase.co/storage/v1/object/public/profile-media/a0000000-0000-4000-8000-000000000001/tirpark/1.gif']);
select tests.check((select cardinality(photo_urls) = 1 from public.tir_parks where id = (select id from ids where k='p')), 'F1 an admin adds a picture (a GIF too)');
select tests.check(tests.err($$ select public.tir_park_set_photos((select id from ids where k='p'), array['https://evil.example/x.jpg']) $$) like '%invalid_url%',
  'F2 links from elsewhere are refused');
select tests.check(tests.err(format($$ select public.tir_park_set_photos(%L, %L::text[]) $$, (select id from ids where k='p'),
  (select array_agg('https://x.supabase.co/storage/v1/object/public/profile-media/u/' || g || '.jpg') from generate_series(1, 11) g)))
  like '%too_many%', 'F3 more than 10 pictures are refused');
select tests.login(:user1);
-- Comments only on approved parks.
select tests.check(tests.err($$ insert into public.tir_park_reviews (park_id, rating, comment) values ((select id from ids where k='p'), 5, 'Əla') $$)
  like '%row-level security%', 'R1 no comments while the park waits for approval');
select tests.login(:admin);
select public.admin_tir_park_set_status((select id from ids where k='p'), 'approved');

select tests.login(:user2);
select tests.check(tests.err($$ select public.tir_park_set_photos((select id from ids where k='p'), '{}') $$) like '%admin_only%',
  'F4 others cannot change the pictures');
insert into public.tir_park_reviews (park_id, rating, comment) values ((select id from ids where k='p'), 4, 'Təmiz, təhlükəsiz');
select tests.check(tests.err($$ insert into public.tir_park_reviews (park_id, rating) values ((select id from ids where k='p'), 5) $$) like '%duplicate%'
                   or tests.err($$ insert into public.tir_park_reviews (park_id, rating) values ((select id from ids where k='p'), 5) $$) like '%unique%',
  'R2 one comment per user and park');
select tests.check(tests.err($$ insert into public.tir_park_reviews (park_id, rating) values ((select id from ids where k='p'), 6) $$) like '%check%',
  'R3 stars are 1…5');
select tests.login(:user1);
insert into public.tir_park_reviews (park_id, rating) values ((select id from ids where k='p'), 5);
select tests.check((select rating_avg = 4.5 and rating_count = 2 from public.tir_parks where id = (select id from ids where k='p')),
  'R4 the rating is recalculated by the server (4.5 from 2)');
update public.tir_parks set rating_avg = 1, rating_count = 99 where id = (select id from ids where k='p');
select tests.check((select rating_avg = 4.5 and rating_count = 2 from public.tir_parks where id = (select id from ids where k='p')),
  'R5 nobody sets the rating by hand');
select tests.login(:user2);
update public.tir_park_reviews set rating = 2, user_id = :user1 where user_id = :user2;
select tests.check((select rating = 2 and user_id = :user2 from public.tir_park_reviews where park_id = (select id from ids where k='p') and rating = 2),
  'R6 the writer changes his comment; the author stays his');
select tests.check((select rating_avg = 3.5 from public.tir_parks where id = (select id from ids where k='p')), 'R7 …and the rating follows (3.5)');
select tests.check((select jsonb_array_length(public.tir_park_reviews_list((select id from ids where k='p'))) = 2
                     and public.tir_park_reviews_list((select id from ids where k='p')) -> 0 ? 'name'), 'R8 the list shows both, with names');
update public.tir_park_reviews set comment = 'hack' where user_id = :user1;
select tests.check((select comment is null from public.tir_park_reviews where user_id = :user1 and park_id = (select id from ids where k='p')),
  'R9 nobody edits another one''s comment');
select tests.login(:admin);
delete from public.tir_park_reviews where user_id = :user2 and park_id = (select id from ids where k='p');
select tests.check((select rating_avg = 5 and rating_count = 1 from public.tir_parks where id = (select id from ids where k='p')), 'R10 an admin removes a comment; rating follows');
select public.tir_park_set_photos((select id from ids where k='p'), '{}');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'tir_park.photos'), 'F5 an admin changing pictures is logged');
-- TIRPark page banner: admins only; market / services unchanged.
set role authenticated;
select tests.login(:user1);
select tests.check(tests.err($$ select public.admin_set_page_hero('tirpark', 'https://x/a.gif', null, 'A', 'B', 'C', true) $$) like '%admin_only%',
  'B1 a user cannot change the TIRPark banner');
select tests.login(:admin);
select public.admin_set_page_hero('tirpark', 'https://x.supabase.co/storage/v1/object/public/market-photos/a/hero.gif', null, 'Yolda', 'park tap', 'Alt', true);
select public.admin_set_page_hero_focus('tirpark', 0.5, -0.2, 0, 0);
select public.admin_set_page_hero_zoom('tirpark', 1.4, 1);
select tests.check((select image_url like '%hero.gif' and focus_x = 0.5 and zoom between 1.39 and 1.41 from public.tirpark_hero where id = 1),
  'B2 the admin sets the TIRPark banner picture (GIF), place and zoom');
select public.admin_set_page_hero('services', null, null, 'S', 'A', 'B', true);
select tests.check((select title = 'S' from public.services_hero where id = 1), 'B3 the Servislər banner still works');
select tests.check(tests.err($$ select public.admin_set_page_hero('other', null, null, null, null, null, true) $$) like '%invalid_argument%',
  'B4 unknown pages are refused');
reset role;
select tests.summary('TIRPARK ŞƏRH / ŞƏKİL (0078)');
rollback;
