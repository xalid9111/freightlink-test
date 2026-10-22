-- LOAD PICTURES + FAVOURITE LOADS — 0058. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c5800000-0000-4000-8000-000000000001'''
\set pic '''https://p.supabase.co/storage/v1/object/public/cargo-photos/'''

begin;
select tests.check((select count(*) = 0 from public.cargo where image_url is not null),
  'P1 existing loads have no picture (nothing guessed)');

set role authenticated;
select tests.login(:owner);
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date);
select tests.check((select image_url is null from public.cargo where id = :c1), 'P2 a picture is not required');
update public.cargo set image_url = :pic || 'a0000000-0000-4000-8000-000000000012/1.jpg' where id = :c1;
select tests.check((select image_url like '%/cargo-photos/a0000000-0000-4000-8000-000000000012/1.jpg' from public.cargo where id = :c1),
  'P3 the owner sets his own picture');
update public.cargo set image_url = :pic || 'templates/tent/2.jpg' where id = :c1;
update public.cargo set image_url = null where id = :c1;
select tests.check((select image_url is null from public.cargo where id = :c1), 'P4 the owner changes or removes it later');
select tests.check(tests.err($$ update public.cargo set image_url = 'https://evil.example/x.jpg' where id = 'c5800000-0000-4000-8000-000000000001' $$)
  like '%cargo_image_url_check%', 'P5 only pictures from our cargo-photos bucket');
select tests.login(:other);
update public.cargo set image_url = :pic || 'x/hack.jpg' where id = :c1;
select tests.check((select image_url is null from public.cargo where id = :c1), 'P6 nobody else changes the picture of my load');

-- Templates: everybody reads, only an admin changes (max 10 per type).
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('tent', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/t.jpg') $$)
  like '%admin_only%', 'T1 a normal user cannot add a template');
select tests.check(tests.err($$ insert into public.cargo_image_templates (category, image_url) values ('tent', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/t.jpg') $$)
  like '%permission denied%', 'T2 nobody writes the table directly');
select tests.login(:admin);
select public.admin_add_cargo_image_template('tent', :pic || 'templates/tent/' || g || '.jpg') from generate_series(1, 10) g;
select tests.check((select count(*) = 10 from public.cargo_image_templates where category = 'tent'), 'T3 admin adds 10 tent pictures');
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('tent', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/11.jpg') $$)
  like '%template_limit%', 'T4 an 11th picture is refused');
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('plane', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/p.jpg') $$)
  like '%invalid_argument%', 'T5 only the 7 load types');
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('ref', 'https://evil.example/r.jpg') $$)
  like '%cargo_image_templates_image_url_check%', 'T6 only pictures from our bucket');
select public.admin_reorder_cargo_image_templates('tent',
  (select array_agg(id order by sort_order desc) from public.cargo_image_templates where category = 'tent'));
select tests.check((select image_url like '%/10.jpg' from public.cargo_image_templates where category = 'tent' order by sort_order, created_at limit 1),
  'T7 admin changes the order');
select tests.check(tests.err($$ select public.admin_reorder_cargo_image_templates('tent', array[gen_random_uuid()]) $$)
  like '%invalid_argument%', 'T8 a reorder must name every picture of that type');
select public.admin_delete_cargo_image_template((select id from public.cargo_image_templates where category = 'tent' order by sort_order limit 1));
select tests.check((select count(*) = 9 from public.cargo_image_templates where category = 'tent'), 'T9 admin removes a picture');
select tests.check((select count(*) >= 12 from public.admin_audit_log where action like 'cargo.template_%'), 'T10 template changes are logged');
select tests.login(:other);
select tests.check((select count(*) = 9 from public.cargo_image_templates where category = 'tent'), 'T11 everybody sees the templates');
reset role;
set role anon;
select tests.check((select count(*) = 9 from public.cargo_image_templates where category = 'tent'), 'T12 also before sign-in');
reset role;

-- Admin takes an unsuitable picture off a load.
set role authenticated;
select tests.login(:owner);
update public.cargo set image_url = :pic || 'a0000000-0000-4000-8000-000000000012/2.jpg' where id = :c1;
select tests.login(:other);
select tests.check(tests.err($$ select public.admin_clear_cargo_image('c5800000-0000-4000-8000-000000000001') $$) like '%admin_only%',
  'A1 only an admin can take a picture off');
select tests.login(:admin);
select public.admin_clear_cargo_image(:c1);
select tests.check((select image_url is null and weight_kg = 20000 and offered_price = 1500 from public.cargo where id = :c1),
  'A2 picture removed, the load itself unchanged');
select tests.check((select count(*) = 1 from public.admin_audit_log where action = 'cargo.image_clear'), 'A3 logged');

-- Favourite loads: own rows only.
select tests.login(:other);
insert into public.cargo_favorites (user_id, cargo_id) values (:other, :c1);
select tests.check((select count(*) = 1 from public.cargo_favorites), 'F1 I add a load to my favourites');
select tests.check(tests.err($$ insert into public.cargo_favorites (user_id, cargo_id) values ('a0000000-0000-4000-8000-000000000012', 'c5800000-0000-4000-8000-000000000001') $$)
  like '%row-level security%', 'F2 not for somebody else');
select tests.login(:owner);
select tests.check((select count(*) = 0 from public.cargo_favorites), 'F3 nobody sees my favourites');
insert into public.cargo_favorites (user_id, cargo_id) values (:owner, :c1);
select tests.login(:other);
delete from public.cargo_favorites where cargo_id = :c1;
select tests.check((select count(*) = 0 from public.cargo_favorites), 'F4 I remove it again');
reset role;
select tests.check((select count(*) = 1 from public.cargo_favorites where user_id = :owner), 'F5 my removal does not touch others');
delete from public.cargo where id = :c1;
select tests.check((select count(*) = 0 from public.cargo_favorites where cargo_id = :c1), 'F6 a deleted load leaves every list');

select tests.check((select public and file_size_limit = 5242880 from storage.buckets where id = 'cargo-photos'), 'B1 picture bucket: public, 5 MB');
select tests.summary('LOAD PICTURES + FAVOURITES (0058)');
rollback;
