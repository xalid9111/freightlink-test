-- CATALOG PHOTO ORDER — 0035. Rolled back at the end.
\set owner1  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set p1 '''f0000000-0000-4000-8000-000000000001'''
\set p2 '''f0000000-0000-4000-8000-000000000002'''
\set p3 '''f0000000-0000-4000-8000-000000000003'''
\set px '''f0000000-0000-4000-8000-0000000000aa'''

begin;
reset role;
delete from public.profile_catalog_items where user_id in (:owner1, :other);
insert into public.profile_catalog_items (id, user_id, image_path, caption, created_at) values
  (:p1, :owner1, :owner1 || '/catalog/1.jpg', 'bir',  now() - interval '3 hours'),
  (:p2, :owner1, :owner1 || '/catalog/2.jpg', null,   now() - interval '2 hours'),
  (:p3, :owner1, :owner1 || '/catalog/3.jpg', 'üç',   now() - interval '1 hour'),
  (:px, :other,  :other  || '/catalog/x.jpg', 'yad',  now());

-- order exactly as the app reads it
create temp view tests_cat as
  select id, row_number() over (order by sort_order asc nulls first, created_at desc) as pos
  from public.profile_catalog_items where user_id = :owner1;
grant select on tests_cat to authenticated;
set role authenticated;

select tests.login(:owner1);
select tests.check((select array_agg(id order by pos) = array[:p3, :p2, :p1]::uuid[] from tests_cat),
  'O1 before any saved order: newest first (unchanged behaviour)');
select tests.check(public.reorder_catalog(array[:p2, :p1, :p3]::uuid[]) = 3, 'O2 owner saves a new order');
select tests.check((select array_agg(id order by pos) = array[:p2, :p1, :p3]::uuid[] from tests_cat),
  'O3 saved order is what everyone reads (first = main photo)');
select tests.check((select count(*) = 3 and count(distinct image_path) = 3 from public.profile_catalog_items where user_id = :owner1),
  'O4 no photo lost or duplicated');
select tests.check((select caption = 'üç' from public.profile_catalog_items where id = :p3), 'O5 captions untouched');

select tests.check(tests.err(format($$ select public.reorder_catalog(array[%L, %L, %L]::uuid[]) $$, :p1, :p1, :p3)) like '%catalog_order_mismatch%',
  'O6 the same photo twice is refused');
select tests.check(tests.err(format($$ select public.reorder_catalog(array[%L, %L]::uuid[]) $$, :p1, :p3)) like '%catalog_order_mismatch%',
  'O7 a missing photo is refused (nothing can be lost)');
select tests.check(tests.err(format($$ select public.reorder_catalog(array[%L, %L, %L, %L]::uuid[]) $$, :p1, :p2, :p3, :px)) like '%catalog_order_mismatch%',
  'O8 another user''s photo is refused');
select tests.check((select array_agg(id order by pos) = array[:p2, :p1, :p3]::uuid[] from tests_cat),
  'O9 a refused call changes nothing');

-- a new upload after a saved order comes first (as uploads always did)
reset role;
insert into public.profile_catalog_items (id, user_id, image_path, created_at)
values ('f0000000-0000-4000-8000-000000000004', :owner1, :owner1 || '/catalog/4.jpg', now());
set role authenticated;
select tests.login(:owner1);
select tests.check((select id = 'f0000000-0000-4000-8000-000000000004'::uuid from tests_cat where pos = 1),
  'O10 a new photo appears first until the next save');
select tests.check(tests.err(format($$ select public.reorder_catalog(array[%L, %L, %L]::uuid[]) $$, :p2, :p1, :p3)) like '%catalog_order_mismatch%',
  'O11 an order made before that upload is refused (app reloads)');

select tests.login(:other);
select tests.check(tests.err(format($$ select public.reorder_catalog(array[%L, %L, %L]::uuid[]) $$, :p3, :p2, :p1)) like '%catalog_order_mismatch%',
  'O12 nobody can reorder someone else''s photos');
update public.profile_catalog_items set sort_order = 0 where id = :p3;
select tests.check((select sort_order = 2 from public.profile_catalog_items where id = :p3),
  'O13 …not even with a direct update (RLS)');

select tests.login(null);
set role anon;
select tests.check(tests.err($$ select public.reorder_catalog(array['f0000000-0000-4000-8000-000000000001']::uuid[]) $$) is not null,
  'O14 signed-out callers are refused');
reset role;

select tests.summary('CATALOG ORDER (0035)');
rollback;
