-- TIRPark map data from OpenStreetMap — 0117. Never Azerbaijan, one row
-- per OSM object, only the import writes, the map reads one screen,
-- nothing bookable. Rolled back.
\set seller '''a0000000-0000-4000-8000-000000000012'''
\set chief  '''a0000000-0000-4000-8000-0000000000f1'''
\set p1     '''b1170000-0000-4000-8000-000000000001'''

begin;
reset role;
insert into auth.users (instance_id, id, aud, role, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000000', :chief, 'authenticated', 'authenticated', 'Xelilov.1881@gmail.com', '{"full_name":"Founder","role":"cargo_owner"}')
  on conflict (id) do nothing;
update public.users set role = 'admin' where id = :chief;
select public.founder_sync();

-- The import (as the trusted backend, no signed-in user).
select tests.check((public.osm_truck_parks_upsert('ge', '[
    {"id":"node/1","lat":41.70,"lng":44.80,"name":"Tbilisi TIR","tags":{"fee":"yes","capacity:hgv":"40","phone":"+995 555","amenity":"parking"}},
    {"id":"way/2","lat":41.71,"lng":44.81,"tags":{"hgv":"designated"}},
    {"id":"bad/3","lat":41.7,"lng":44.8},
    {"id":"node/4","lat":95,"lng":44.8}
  ]'::jsonb, 'geofabrik', '2026-11-10') ->> 'rows')::int = 2, 'I1 two good rows in, broken ones skipped');
select tests.check((select country_code = 'GE' and name = 'Tbilisi TIR' and tags = '{"fee":"yes","capacity:hgv":"40"}'::jsonb
                    from public.osm_truck_parks where source_id = 'node/1'),
  'I2 only the allowed source tags are kept (no phone, nothing made up)');
select tests.check((select name is null from public.osm_truck_parks where source_id = 'way/2'), 'I3 no name in the source = no name');
select public.osm_truck_parks_upsert('GE', '[{"id":"node/1","lat":41.7001,"lng":44.8001,"name":"Tbilisi TIR 2"}]'::jsonb);
select tests.check((select count(*) = 1 from public.osm_truck_parks where source_id = 'node/1')
               and (select name = 'Tbilisi TIR 2' and lat = 41.7001 from public.osm_truck_parks where source_id = 'node/1'),
  'I4 a new import updates the same object, no duplicate');
select tests.check(tests.err($$ select public.osm_truck_parks_upsert('AZ', '[{"id":"node/9","lat":40.4,"lng":49.8}]'::jsonb) $$) like '%not_allowed_az%'
               and tests.err($$ insert into public.osm_truck_parks (source_id, country_code, lat, lng) values ('node/9', 'AZ', 40.4, 49.8) $$) is not null
               and not exists (select 1 from public.osm_truck_parks where country_code = 'AZ'),
  'I5 Azerbaijan never comes from OSM (function and table both refuse)');
select tests.check((select count(*) = 2 and sum(rows_in) = 3 from public.osm_truck_park_imports where country_code = 'GE'),
  'I6 every import is recorded');

-- A platform park right next to an OSM object: the platform park stands there.
insert into public.tir_parks (id, name, lat, lng, city, amenities, created_by, status)
values (:p1, 'Bizim Park', 41.7100, 44.8100, 'Tbilisi', '{}', :seller, 'approved');
insert into public.osm_truck_parks (source_id, country_code, lat, lng, last_seen_at) values ('node/5', 'TR', 41.0, 29.0, now() - interval '200 days');

-- Nobody signed in, a visitor, a user: no direct table, no import.
set role anon;
select tests.login(null);
select tests.check(tests.err($$ select count(*) from public.osm_truck_parks $$) is not null, 'R1 a visitor cannot read the table directly');
select tests.check(tests.err($$ select public.osm_truck_parks_upsert('GE', '[]'::jsonb) $$) is not null, 'R2 …nor import');
select tests.check((select jsonb_array_length(public.osm_truck_parks_in_bounds(41, 44, 42, 45) -> 'items') = 1), 'R3 a visitor sees the map data of one screen');
select tests.check((select x ->> 'id' = 'node/1' and x ->> 'name' = 'Tbilisi TIR 2'
                    from jsonb_array_elements(public.osm_truck_parks_in_bounds(41, 44, 42, 45) -> 'items') x),
  'R4 …without the object next to the approved platform park (way/2 stands on it)');
select tests.check(jsonb_array_length(public.osm_truck_parks_in_bounds(40, 28, 42, 30) -> 'items') = 0,
  'R5 an object the source has not had for 120 days does not show');
select tests.check((select r -> 'items' = '[]'::jsonb and (r ->> 'more')::boolean
                    from (select public.osm_truck_parks_in_bounds(30, 20, 50, 60) r) x),
  'R6 too big an area gives nothing (the app asks from zoom 7 on)');
select tests.check(tests.err($$ select public.osm_truck_parks_in_bounds(42, 44, 41, 45) $$) like '%invalid_argument%', 'R7 a wrong box is refused');

set role authenticated;
select tests.login(:seller);
select tests.check(tests.err($$ select count(*) from public.osm_truck_parks $$) is not null
               and tests.err($$ select public.osm_truck_parks_upsert('GE', '[]'::jsonb) $$) is not null
               and tests.err($$ select public.admin_osm_park_set_hidden('node/1', true) $$) like '%admin_only%'
               and tests.err($$ select public.admin_osm_parks_status() $$) like '%admin_only%',
  'U1 a user: no table, no import, no admin');
select tests.check(jsonb_array_length(public.osm_truck_parks_in_bounds(41, 44, 42, 45) -> 'items') = 1, 'U2 …reads the map');

-- Nothing bookable: the platform's booking / reviews refuse an OSM id.
select tests.check(not exists (select 1 from public.tir_parks where id::text = 'node/1'), 'U3 OSM objects are never platform parks');

select tests.login(:chief);
select public.admin_osm_park_set_hidden('node/1', true);
select tests.check(jsonb_array_length(public.osm_truck_parks_in_bounds(41, 44, 42, 45) -> 'items') = 0, 'A1 the admin hides a wrong object');
select tests.check((select (s ->> 'total')::int = 3 and (s ->> 'hidden')::int = 1 and jsonb_array_length(s -> 'countries') = 2
                    from (select public.admin_osm_parks_status() s) x), 'A2 the admin sees the totals per country');
select public.admin_osm_park_set_hidden('node/1', false);
select tests.check(jsonb_array_length(public.osm_truck_parks_in_bounds(41, 44, 42, 45) -> 'items') = 1, 'A3 …and shows it again');
reset role;
select tests.check((select count(*) = 2 from public.admin_audit_log where entity_type = 'osm_truck_parks'), 'A4 both in the Audit Log');

select tests.summary('OSM TIR DAYANACAQLARI (0117)');
rollback;
