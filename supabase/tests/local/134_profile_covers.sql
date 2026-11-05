-- Profile backgrounds for Park / Servis / Mağaza — 0096. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set owner   '''a0000000-0000-4000-8000-000000000013'''
\set svcown  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set svc     '''5e000000-0000-4000-8000-000000000001'''

begin;
create temp table ids (k text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
create or replace function pg_temp.u(p_path text) returns text language sql as $$
  select 'https://x.supabase.co/storage/v1/object/public/profile-media/' || p_path;
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- A park with an approved manager.
set role authenticated;
select tests.login(:owner);
insert into ids values ('r', public.tir_park_owner_apply('Cover Park'));
select tests.login(:admin);
select public.admin_tir_park_owner_request_set((select id from ids where k='r'), 'approved');
select tests.login(:owner);
insert into ids values ('p', public.tir_park_owner_setup((select id from ids where k='r'), null, 40.5500, 46.3300, null, 10, 3, '+994501112233'));

-- Templates: admins only.
select tests.login(:other);
select tests.check(tests.err(format($$ select public.admin_cover_template_save(null, 'X', %L, array['park']) $$,
  pg_temp.u('a/x.jpg'))) like '%admin%', 'T1 a user cannot add a template');
select tests.login(:admin);
insert into ids select 'tp', (public.admin_cover_template_save(null, 'Gün batımı', pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg'), array['park', 'shop']) ->> 'id')::uuid;
insert into ids select 'ts', (public.admin_cover_template_save(null, 'Servis', pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/svc.jpg'), array['service']) ->> 'id')::uuid;
insert into ids select 'off', (public.admin_cover_template_save(null, 'Köhnə', pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/old.jpg'), array['park'], false) ->> 'id')::uuid;
select tests.check(tests.err(format($$ select public.admin_cover_template_save(null, 'Y', %L, array['loads']) $$,
  pg_temp.u('a/y.jpg'))) like '%invalid_sections%', 'T2 only Park / Servis / Mağaza');
select tests.check(tests.err($$ select public.admin_cover_template_save(null, 'Y', 'https://evil.example/y.jpg', array['park']) $$) like '%invalid_url%',
  'T3 only a picture of the app''s own storage');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'cover.template_add'), 'T4 written to the Audit Log');

-- Users see only active templates.
select tests.login(:other);
select tests.check((select count(*) from public.cover_templates) = 2, 'T5 only active templates are visible');

-- The park: its manager only, to an active park template or his own picture.
select tests.login(:other);
select tests.check(tests.err(format($$ select public.tir_park_set_cover(%L, %L) $$, (select id from ids where k='p'),
  pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg'))) like '%not_allowed%', 'C1 not someone else''s park');
select tests.login(:owner);
select public.tir_park_set_cover((select id from ids where k='p'), pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg?ax=0.2&ay=0&z=1.3'));
select tests.check((select cover_url like '%sunset.jpg?ax=0.2%' from public.tir_parks where id = (select id from ids where k='p')),
  'C2 the manager picks a park template (with its place / zoom)');
select tests.check(tests.err(format($$ select public.tir_park_set_cover(%L, %L) $$, (select id from ids where k='p'),
  pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/svc.jpg'))) like '%invalid_url%', 'C3 not a template of another section');
select tests.check(tests.err(format($$ select public.tir_park_set_cover(%L, %L) $$, (select id from ids where k='p'),
  pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/old.jpg'))) like '%invalid_url%', 'C4 not a switched-off template');
select tests.check(tests.err(format($$ select public.tir_park_set_cover(%L, %L) $$, (select id from ids where k='p'),
  pg_temp.u('a0000000-0000-4000-8000-000000000021/x.jpg'))) like '%invalid_url%', 'C5 not another user''s picture');
select public.tir_park_set_cover((select id from ids where k='p'), pg_temp.u('a0000000-0000-4000-8000-000000000013/covers/own.jpg?v=1'));
select public.tir_park_set_logo((select id from ids where k='p'), pg_temp.u('a0000000-0000-4000-8000-000000000013/logo.png'));
select tests.check((select cover_url like '%000013/covers/own.jpg%' and logo_url like '%000013/logo.png' from public.tir_parks
                     where id = (select id from ids where k='p')), 'C6 his own picture; the round picture apart');
select tests.check(tests.err(format($$ select public.tir_park_set_logo(%L, %L) $$, (select id from ids where k='p'),
  pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg'))) like '%invalid_url%', 'C7 the round picture is never a template');
select tests.check((select photo_urls = '{}'::text[] from public.tir_parks where id = (select id from ids where k='p')),
  'C8 the gallery is not touched');

-- The service: its owner only.
select tests.login(:svcown);
update public.service_providers set cover_url = pg_temp.u('a0000000-0000-4000-8000-000000000011/x.jpg'), description = 'Yeni' where id = :svc;
select tests.check((select cover_url is null and description = 'Yeni' from public.service_providers where id = :svc),
  'S1 a direct edit cannot set the background (other edits still work)');
select public.service_set_cover(:svc, pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/svc.jpg'));
select tests.check((select cover_url like '%covers/svc.jpg' from public.service_providers where id = :svc), 'S2 the owner picks a service template');
select tests.check(tests.err(format($$ select public.service_set_cover(%L, %L) $$, :svc,
  pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg'))) like '%invalid_url%', 'S3 not a park / shop template');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.service_set_cover(%L, null) $$, :svc)) like '%not_allowed%', 'S4 not someone else''s service');
select tests.login(:svcown);
select public.service_set_cover(:svc, null);
select tests.check((select cover_url is null from public.service_providers where id = :svc), 'S5 back to the default picture');

-- Admin edits / switches off / deletes a template; profiles keep their picture.
select tests.login(:admin);
select public.admin_cover_template_save((select id from ids where k='tp'), 'Axşam', pg_temp.u('a0000000-0000-4000-8000-000000000001/covers/sunset.jpg'), array['park'], false);
select tests.check((select name = 'Axşam' and not is_active and sections = array['park'] from public.cover_templates where id = (select id from ids where k='tp')),
  'A1 the admin renames, changes sections, switches off');
select public.admin_cover_template_delete((select id from ids where k='ts'));
select tests.check(not exists (select 1 from public.cover_templates where id = (select id from ids where k='ts')), 'A2 the admin deletes a template');
select tests.check(exists (select 1 from public.admin_audit_log where action = 'cover.template_delete'), 'A3 deletion in the Audit Log');

select tests.summary('PROFİL FONU: PARK · SERVİS · MAĞAZA (0096)');
rollback;
