-- SIX NEW LOAD TYPES — 0063. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set owner  '''a0000000-0000-4000-8000-000000000012'''
\set pic '''https://p.supabase.co/storage/v1/object/public/cargo-photos/'''

begin;
select tests.check((select pg_get_constraintdef(oid) like '%''car_carrier''%' from pg_constraint
                     where conrelid = 'public.cargo_image_templates'::regclass
                       and conname = 'cargo_image_templates_category_check'),
  'N1 the 0058 category check now has the 13 types');
select tests.check((select count(*) = 1 from pg_constraint
                     where conrelid = 'public.cargo_image_templates'::regclass and contype = 'c'
                       and pg_get_constraintdef(oid) like '%''tanker''%'),
  'N1b one category check (replaced, not doubled)');
select tests.check((select pg_get_constraintdef(oid) like '%cargo-photos%' from pg_constraint
                     where conrelid = 'public.cargo_image_templates'::regclass
                       and conname = 'cargo_image_templates_image_url_check'),
  'N1c the picture URL check is untouched');

set role authenticated;
select tests.login(:owner);
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('van', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/v.jpg') $$)
  like '%admin_only%', 'N2 a normal user still cannot add a template');
insert into public.cargo (owner_id, pickup_country, pickup_city, destination_country, destination_city, weight_kg, offered_price, pickup_date, truck_type)
values (:owner, 'Azerbaijan', 'Baku', 'Georgia', 'Tbilisi', 3000, 500, current_date, 'gazelle');
select tests.check((select count(*) = 1 from public.cargo where truck_type = 'gazelle'), 'N3 a load with a new type is posted');

select tests.login(:admin);
select public.admin_add_cargo_image_template(c, :pic || 'templates/' || c || '/1.jpg')
  from unnest(array['tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker',
                    'gazelle', 'manipulator', 'tow_truck', 'van', 'lowbed', 'car_carrier']) c;
select tests.check((select count(distinct category) = 13 from public.cargo_image_templates
                     where image_url like '%/templates/%/1.jpg'),
  'N4 admin adds a template for all 13 types (old 7 still work)');
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('plane', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/p.jpg') $$)
  like '%invalid_argument%', 'N5 an unknown type is still refused');
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('van', 'https://evil.example/v.jpg') $$)
  like '%cargo_image_templates_image_url_check%', 'N6 still only pictures from our bucket');
select public.admin_add_cargo_image_template('lowbed', :pic || 'templates/lowbed/' || g || '.jpg') from generate_series(2, 10) g;
select tests.check(tests.err($$ select public.admin_add_cargo_image_template('lowbed', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/templates/11.jpg') $$)
  like '%template_limit%', 'N7 still at most 10 per type');
reset role;
select tests.check(tests.err($$ insert into public.cargo_image_templates (category, image_url) values ('plane', 'https://p.supabase.co/storage/v1/object/public/cargo-photos/x.jpg') $$)
  like '%cargo_image_templates_category_check%', 'N8 the table itself refuses an unknown type');
rollback;

-- Only the 0058 constraint is touched: put the 0058 rule back, add another
-- check that also names "category", and run 0063 again.
begin;
alter table public.cargo_image_templates drop constraint cargo_image_templates_category_check;
alter table public.cargo_image_templates add constraint cargo_image_templates_category_check
  check (category in ('tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker'));
alter table public.cargo_image_templates add constraint cargo_image_templates_category_len
  check (char_length(category) <= 40);
\ir ../../migrations/0063_cargo_new_types.sql
\ir ../../migrations/0063_cargo_new_types.sql
select tests.check((select pg_get_constraintdef(oid) like '%''car_carrier''%' from pg_constraint
                     where conname = 'cargo_image_templates_category_check'),
  'N9 from the 0058 rule 0063 makes the 13-type rule (run twice: same result)');
select tests.check(exists (select 1 from pg_constraint where conname = 'cargo_image_templates_category_len'),
  'N10 another check naming "category" is left alone');
select tests.check(exists (select 1 from pg_constraint where conname = 'cargo_image_templates_image_url_check'),
  'N11 the picture URL check is left alone');
rollback;
