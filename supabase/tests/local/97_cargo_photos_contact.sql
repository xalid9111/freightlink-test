-- UP TO 6 LOAD PICTURES + OPTIONAL CONTACT NUMBER — 0060. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set other  '''a0000000-0000-4000-8000-000000000021'''
\set c1 '''c6000000-0000-4000-8000-000000000001'''
\set c2 '''c6000000-0000-4000-8000-000000000002'''
\set p '''https://p.supabase.co/storage/v1/object/public/cargo-photos/a0000000-0000-4000-8000-000000000012/'''

begin;
select tests.check((select count(*) = 0 from public.cargo where cardinality(image_urls) > 0),
  'G1 existing loads are not rewritten (no pictures added)');

set role authenticated;
select tests.login(:owner);
-- New app: several pictures, the first is the main one.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date, image_urls)
values (:c1, :owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 20000, 1500, current_date, array[:p || '1.jpg', :p || '2.jpg', :p || '3.jpg']);
select tests.check((select image_url = :p || '1.jpg' and cardinality(image_urls) = 3 from public.cargo where id = :c1),
  'G2 3 pictures saved, image_url = the first (main) picture');
update public.cargo set image_urls = array[:p || '3.jpg', :p || '1.jpg'] where id = :c1;
select tests.check((select image_url = :p || '3.jpg' and cardinality(image_urls) = 2 from public.cargo where id = :c1),
  'G3 reorder / remove: image_url follows the new first picture');
select tests.check(tests.err($$ update public.cargo set image_urls = array(select 'https://p.supabase.co/storage/v1/object/public/cargo-photos/x/' || g || '.jpg' from generate_series(1, 7) g)
  where id = 'c6000000-0000-4000-8000-000000000001' $$) like '%cargo_image_urls_check%', 'G4 at most 6 pictures');
-- (refused by the 0060 list check or, first, by the 0058 image_url check)
select tests.check(tests.err($$ update public.cargo set image_urls = array['https://evil.example/x.jpg'] where id = 'c6000000-0000-4000-8000-000000000001' $$)
  similar to '%cargo_image_urls?_check%', 'G5 only pictures from our cargo-photos bucket');
update public.cargo set image_urls = '{}' where id = :c1;
select tests.check((select image_url is null and cardinality(image_urls) = 0 from public.cargo where id = :c1), 'G6 all pictures removed');

-- Older app: writes only image_url.
insert into public.cargo (id, owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date, image_url)
values (:c2, :owner, 'Turkey', 'Istanbul', 'Azerbaijan', 'Baku', 18000, 900, current_date, :p || 'old.jpg');
select tests.check((select image_urls = array[:p || 'old.jpg'] from public.cargo where id = :c2), 'G7 older app: image_url becomes the first picture');
update public.cargo set image_urls = array[:p || 'old.jpg', :p || 'b.jpg'] where id = :c2;
update public.cargo set image_url = :p || 'new.jpg' where id = :c2;
select tests.check((select image_urls = array[:p || 'new.jpg', :p || 'b.jpg'] and image_url = :p || 'new.jpg' from public.cargo where id = :c2),
  'G8 older app changes the main picture, the others stay');
update public.cargo set image_url = null where id = :c2;
select tests.check((select image_urls = array[:p || 'b.jpg'] and image_url = :p || 'b.jpg' from public.cargo where id = :c2),
  'G9 older app removes the main picture: the next one becomes main');

-- Optional contact number: owner only, international format.
insert into public.cargo_contacts (cargo_id, phone) values (:c1, '+994551112233');
select tests.check(tests.err($$ insert into public.cargo_contacts (cargo_id, phone) values ('c6000000-0000-4000-8000-000000000002', '0551112233') $$)
  like '%cargo_contacts_phone_check%', 'K1 international format only (+994…)');
select tests.check((select phone = '+994551112233' from public.cargo_contacts where cargo_id = :c1), 'K2 the owner saves and reads it');
select tests.login(:other);
select tests.check((select count(*) = 0 from public.cargo_contacts), 'K3 nobody else reads the table');
select tests.check(tests.err($$ insert into public.cargo_contacts (cargo_id, phone) values ('c6000000-0000-4000-8000-000000000002', '+994509998877') $$)
  like '%row-level security%', 'K4 nobody else writes a number for my load');
update public.cargo_contacts set phone = '+994500000000' where cargo_id = :c1;
select tests.check((select get_cargo_contact->>'contact_phone' = '+994551112233' from public.get_cargo_contact(:c1)),
  'K5 others get it only through get_cargo_contact (and could not change it)');
select tests.check((select public.get_cargo_contact(:c1) ? 'phone' and public.get_cargo_contact(:c2)->>'contact_phone' is null),
  'K6 registered phone still returned; no number set = null');
reset role;
set role anon;
select tests.check(tests.err($$ select public.get_cargo_contact('c6000000-0000-4000-8000-000000000001') $$) like '%permission denied%',
  'K7 not signed in: no contact at all');
select tests.check(tests.err($$ select count(*) from public.cargo_contacts $$) like '%permission denied%', 'K8 anon cannot read numbers');
reset role;

-- Admin: takes every picture off.
set role authenticated;
select tests.login(:admin);
select public.admin_clear_cargo_image(:c2);
select tests.check((select image_url is null and cardinality(image_urls) = 0 and offered_price = 900 from public.cargo where id = :c2),
  'A1 admin removes all pictures; the load itself unchanged');
reset role;
delete from public.cargo where id = :c1;
select tests.check((select count(*) = 0 from public.cargo_contacts where cargo_id = :c1), 'K9 a deleted load takes its number with it');
select tests.summary('LOAD PICTURES x6 + CONTACT (0060)');
rollback;
