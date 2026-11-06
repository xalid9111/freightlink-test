-- Usta / Servis and Mağaza profiles — 0097. Rolled back.
\set svcown  '''a0000000-0000-4000-8000-000000000011'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set svc     '''5e000000-0000-4000-8000-000000000001'''

begin;
create temp table seen (k text primary key, v text) on commit drop;
grant all on seen to authenticated;
create or replace function pg_temp.u(p_path text) returns text language sql as $$
  select 'https://x.supabase.co/storage/v1/object/public/profile-media/' || p_path;
$$;
grant execute on all functions in schema pg_temp to authenticated;
insert into seen select 'cover', cover_url from public.service_providers where id = :svc;

set role authenticated;

-- The logo: only through service_set_logo.
select tests.login(:svcown);
update public.service_providers set logo_url = pg_temp.u('a0000000-0000-4000-8000-000000000011/x.jpg'), description = 'Mağaza' where id = :svc;
select tests.check((select logo_url is null and description = 'Mağaza' from public.service_providers where id = :svc),
  'L1 a direct update never sets the logo (the rest is saved)');
select public.service_set_logo(:svc, pg_temp.u('a0000000-0000-4000-8000-000000000011/covers/service-logo.jpg?ax=0&ay=0&z=1'));
select tests.check((select logo_url like '%covers/service-logo.jpg%' from public.service_providers where id = :svc), 'L2 the owner sets his own logo');
select tests.check(tests.err(format($$ select public.service_set_logo(%L, %L) $$, :svc,
  pg_temp.u('a0000000-0000-4000-8000-000000000021/x.jpg'))) like '%invalid_url%', 'L3 never someone else''s picture');
select tests.check(tests.err(format($$ select public.service_set_logo(%L, 'https://evil.example/x.jpg') $$, :svc)) like '%invalid_url%',
  'L4 only the app''s own storage');
select tests.check((select cover_url is not distinct from (select v from seen where k = 'cover') from public.service_providers where id = :svc),
  'L5 the background is untouched');
select tests.login(:other);
select tests.check(tests.err(format($$ select public.service_set_logo(%L, null) $$, :svc)) like '%not_allowed%', 'L6 not someone else''s service');
select tests.check((select logo_url is not null from public.service_providers where id = :svc), 'L7 everybody may read the logo');
select tests.login(null);
select tests.check(tests.err(format($$ select public.service_set_logo(%L, null) $$, :svc)) like '%not_authenticated%', 'L8 signed out: refused');
select tests.login(:svcown);
select public.service_set_logo(:svc, null);
select tests.check((select logo_url is null from public.service_providers where id = :svc), 'L9 removed again');

-- The shop's product kinds: new and used together, unknown ones dropped.
update public.service_providers set categories = array['spare_parts', 'shop_new', 'shop_used', 'shop_tyres', 'nonsense'] where id = :svc;
select tests.check((select categories @> array['spare_parts', 'shop_new', 'shop_used', 'shop_tyres']
  and not ('nonsense' = any (categories)) from public.service_providers where id = :svc), 'K1 new and used parts both kept');
select tests.check((select count(*) = 8 from public.service_categories where id like 'shop\_%' and is_active), 'K2 eight shop kinds');
select tests.check((select min(sort_order) > (select max(sort_order) from public.service_categories where id not like 'shop\_%')
  from public.service_categories where id like 'shop\_%'), 'K3 after every service kind');

select tests.summary('USTA / SERVİS VƏ MAĞAZA PROFİLİ (0097)');
rollback;
