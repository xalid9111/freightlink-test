-- =====================================================================
-- 0069 — İş Mərkəzi (SmartMatch): drivers looking for work, employers
-- looking for drivers (owner, 26.10.2026)
--
-- * job_specialties / job_skills: the catalogues (Tent, REF … ; licence
--   categories, documents, skills). An admin can add more later.
-- * job_seeker_profiles: one work profile per user ("İş axtarıram").
--   skills = { code: 'yes' | 'no' | 'ready' } — a code that is missing
--   means "not given" (never the same as 'no').
-- * job_vacancies: an employer's vacancies ("İşçi axtarıram").
--   requirements = { code: 'must' | 'nice' }; can_help = codes the
--   employer can help to obtain. A vacancy with no requirements is fine.
-- * Published at once; an admin can hide / show (logged).
-- * Privacy on the server: other people read profiles and vacancies only
--   through job_seekers_list() / job_vacancies_list() — signed in only,
--   no birth date (age only), the phone only when its owner turned
--   "show phone" on (off by default). The tables themselves are readable
--   only by their owner (and admins).
-- * job_applications: applications / job offers with statuses; hired
--   only when both sides confirm (job_application_send / _set_status).
-- * Notifications (existing table notifications): a new or re-opened
--   vacancy / work profile notifies only the other side with a matching
--   specialty and country; each notice at most once (data.dedupe key with
--   a unique index).
-- * Matching percentages are worked out in the app (explainable rules,
--   no paid AI); nothing is ever hidden because of a missing requirement.
--
-- Safe: forward-only, re-runnable. New tables, functions, triggers and
-- one new unique index on notifications (only rows that carry a dedupe
-- key, i.e. none of the existing ones). No row is changed or deleted.
-- =====================================================================

begin;

-- 1) Catalogues -------------------------------------------------------------
create table if not exists public.job_specialties (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  name text not null check (char_length(name) between 1 and 60),
  sort_order integer not null default 100,
  is_active boolean not null default true
);
insert into public.job_specialties (code, name, sort_order) values
  ('tent', 'Tent', 10), ('ref', 'REF', 20), ('tow', 'Evakuator', 30), ('container', 'Konteyner', 40),
  ('dump', 'Samosval', 50), ('tanker', 'Sistern', 60), ('car_carrier', 'Avtovoz', 70), ('bus', 'Avtobus', 80),
  ('excavator', 'Ekskavator', 90), ('other', 'Digər', 1000)
on conflict (code) do nothing;

create table if not exists public.job_skills (
  code text primary key check (code ~ '^[a-z0-9_]{2,30}$'),
  kind text not null check (kind in ('license', 'document', 'skill')),
  name text not null check (char_length(name) between 1 and 80),
  sort_order integer not null default 100,
  is_active boolean not null default true
);
insert into public.job_skills (code, kind, name, sort_order) values
  ('lic_b', 'license', 'B', 10), ('lic_c1', 'license', 'C1', 20), ('lic_c', 'license', 'C', 30),
  ('lic_ce', 'license', 'CE', 40), ('lic_d', 'license', 'D', 50),
  ('tachograph', 'document', 'Taxoqraf kartı', 110), ('cpc', 'document', 'Peşə sertifikatı', 120),
  ('intl_exp', 'skill', 'Beynəlxalq daşıma təcrübəsi', 210), ('tech', 'skill', 'Nəqliyyatın texniki quruluşundan anlayış', 220),
  ('discipline', 'skill', 'Nizam-intizam', 230), ('responsibility', 'skill', 'Məsuliyyətli yanaşma', 240)
on conflict (code) do nothing;

alter table public.job_specialties enable row level security;
alter table public.job_skills enable row level security;
revoke all on public.job_specialties from anon, authenticated;
revoke all on public.job_skills from anon, authenticated;
grant select on public.job_specialties to authenticated;
grant select on public.job_skills to authenticated;
drop policy if exists "job_specialties_read" on public.job_specialties;
create policy "job_specialties_read" on public.job_specialties for select to authenticated using (true);
drop policy if exists "job_skills_read" on public.job_skills;
create policy "job_skills_read" on public.job_skills for select to authenticated using (true);

-- A { code: value } map with known values only (codes are checked by format).
create or replace function public.job_valid_map(p jsonb, p_values text[])
returns boolean language sql immutable set search_path = public, pg_temp as $$
  select jsonb_typeof(p) = 'object'
     and (select count(*) from jsonb_object_keys(p)) <= 60
     and not exists (select 1 from jsonb_each(p) e
                      where e.key !~ '^[a-z0-9_]{2,30}$' or jsonb_typeof(e.value) <> 'string'
                         or not ((e.value #>> '{}') = any (p_values)));
$$;

-- 2) Work profiles (drivers) -------------------------------------------------
create table if not exists public.job_seeker_profiles (
  user_id uuid primary key references public.users(id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 1 and 120),
  birth_date date,
  country text check (country is null or char_length(country) <= 80),
  city text check (city is null or char_length(city) <= 80),
  experience_years integer check (experience_years is null or experience_years between 0 and 60),
  specialties text[] not null default '{}' check (cardinality(specialties) <= 20),
  skills jsonb not null default '{}'::jsonb check (public.job_valid_map(skills, array['yes', 'no', 'ready'])),
  other_docs text check (other_docs is null or char_length(other_docs) <= 300),
  countries text[] not null default '{}' check (cardinality(countries) <= 30),
  routes text check (routes is null or char_length(routes) <= 300),
  salary_min numeric(12,2) check (salary_min is null or salary_min between 0 and 10000000),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  schedule text check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible')),
  note text check (note is null or char_length(note) <= 1000),
  phone text check (phone is null or char_length(phone) <= 30),
  show_phone boolean not null default false,
  whatsapp boolean not null default false,
  is_active boolean not null default true,
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists job_seeker_profiles_active_idx on public.job_seeker_profiles (updated_at desc) where is_active and not is_hidden;

-- 3) Vacancies (employers) -----------------------------------------------------
create table if not exists public.job_vacancies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  company_name text not null check (char_length(btrim(company_name)) between 1 and 120),
  country text check (country is null or char_length(country) <= 80),
  city text check (city is null or char_length(city) <= 80),
  specialties text[] not null default '{}' check (cardinality(specialties) <= 20),
  requirements jsonb not null default '{}'::jsonb check (public.job_valid_map(requirements, array['must', 'nice'])),
  can_help text[] not null default '{}' check (cardinality(can_help) <= 60),
  min_experience integer check (min_experience is null or min_experience between 0 and 60),
  countries text[] not null default '{}' check (cardinality(countries) <= 30),
  routes text check (routes is null or char_length(routes) <= 300),
  salary_min numeric(12,2) check (salary_min is null or salary_min between 0 and 10000000),
  salary_max numeric(12,2) check (salary_max is null or salary_max between 0 and 10000000),
  currency text check (currency is null or currency ~ '^[A-Z]{3}$'),
  schedule text check (schedule is null or schedule in ('full_time', 'part_time', 'rotation', 'flexible')),
  conditions text check (conditions is null or char_length(conditions) <= 1000),
  phone text check (phone is null or char_length(phone) <= 30),
  show_phone boolean not null default false,
  whatsapp boolean not null default false,
  status text not null default 'active' check (status in ('active', 'closed')),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (salary_min is null or salary_max is null or salary_max >= salary_min)
);
create index if not exists job_vacancies_owner_idx on public.job_vacancies (owner_id, created_at desc);
create index if not exists job_vacancies_active_idx on public.job_vacancies (updated_at desc) where status = 'active' and not is_hidden;

-- Only an admin hides / shows; the owner never changes is_hidden, owner or
-- created_at. Birth date: 16–90 years old.
create or replace function public.job_seeker_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then new.is_hidden := false; else new.is_hidden := old.is_hidden; end if;
  end if;
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.created_at := old.created_at;
  end if;
  if new.birth_date is not null
     and (new.birth_date > (current_date - interval '16 years') or new.birth_date < (current_date - interval '90 years')) then
    raise exception 'invalid_birth_date' using errcode = '22023';
  end if;
  new.full_name := btrim(new.full_name);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists job_seeker_guard on public.job_seeker_profiles;
create trigger job_seeker_guard before insert or update on public.job_seeker_profiles
  for each row execute function public.job_seeker_guard();

create or replace function public.job_vacancy_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then new.is_hidden := false; else new.is_hidden := old.is_hidden; end if;
  end if;
  if tg_op = 'UPDATE' then
    new.owner_id := old.owner_id;
    new.created_at := old.created_at;
  elsif (select count(*) from public.job_vacancies where owner_id = new.owner_id) >= 20 then
    raise exception 'too_many_vacancies' using errcode = '22023';
  end if;
  new.company_name := btrim(new.company_name);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists job_vacancy_guard on public.job_vacancies;
create trigger job_vacancy_guard before insert or update on public.job_vacancies
  for each row execute function public.job_vacancy_guard();

-- Own rows only (admins read all); no deleting — switch off / close instead.
alter table public.job_seeker_profiles enable row level security;
alter table public.job_vacancies enable row level security;
revoke all on public.job_seeker_profiles from anon, authenticated;
revoke all on public.job_vacancies from anon, authenticated;
grant select, insert, update on public.job_seeker_profiles to authenticated;
grant select, insert, update on public.job_vacancies to authenticated;

drop policy if exists "job_seeker_read_own" on public.job_seeker_profiles;
create policy "job_seeker_read_own" on public.job_seeker_profiles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "job_seeker_insert_own" on public.job_seeker_profiles;
create policy "job_seeker_insert_own" on public.job_seeker_profiles for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "job_seeker_update_own" on public.job_seeker_profiles;
create policy "job_seeker_update_own" on public.job_seeker_profiles for update to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "job_vacancy_read_own" on public.job_vacancies;
create policy "job_vacancy_read_own" on public.job_vacancies for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists "job_vacancy_insert_own" on public.job_vacancies;
create policy "job_vacancy_insert_own" on public.job_vacancies for insert to authenticated
  with check (owner_id = (select auth.uid()));
drop policy if exists "job_vacancy_update_own" on public.job_vacancies;
create policy "job_vacancy_update_own" on public.job_vacancies for update to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_admin()))
  with check (owner_id = (select auth.uid()) or (select public.is_admin()));

-- 4) What others see (signed in only) ------------------------------------------
create or replace function public.job_seekers_list(p_limit integer default 300, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_admin boolean := public.is_admin();
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return coalesce((
    select jsonb_agg(r order by r ->> 'updated_at' desc)
      from (
        select jsonb_build_object(
                 'user_id', p.user_id, 'full_name', p.full_name, 'avatar_url', u.avatar_url,
                 'age', case when p.birth_date is not null then date_part('year', age(current_date, p.birth_date))::int end,
                 'country', p.country, 'city', p.city, 'experience_years', p.experience_years,
                 'specialties', p.specialties, 'skills', p.skills, 'other_docs', p.other_docs,
                 'countries', p.countries, 'routes', p.routes, 'salary_min', p.salary_min, 'currency', p.currency,
                 'schedule', p.schedule, 'note', p.note,
                 'phone', case when p.show_phone or v_admin or p.user_id = auth.uid() then p.phone end,
                 'whatsapp', p.whatsapp and (p.show_phone or v_admin or p.user_id = auth.uid()),
                 'is_hidden', p.is_hidden and v_admin,
                 'updated_at', p.updated_at) r
          from public.job_seeker_profiles p
          join public.users u on u.id = p.user_id
         where p.is_active
           and (not p.is_hidden or v_admin)
           and (not coalesce(u.is_blocked, false) or v_admin)
         order by p.updated_at desc
         limit least(greatest(coalesce(p_limit, 300), 1), 500) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.job_seekers_list(integer, integer) from public, anon;
grant execute on function public.job_seekers_list(integer, integer) to authenticated;

create or replace function public.job_vacancies_list(p_limit integer default 300, p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_admin boolean := public.is_admin();
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  return coalesce((
    select jsonb_agg(r order by r ->> 'updated_at' desc)
      from (
        select jsonb_build_object(
                 'id', v.id, 'owner_id', v.owner_id, 'owner_name', u.full_name, 'avatar_url', u.avatar_url,
                 'company_name', v.company_name, 'country', v.country, 'city', v.city,
                 'specialties', v.specialties, 'requirements', v.requirements, 'can_help', v.can_help,
                 'min_experience', v.min_experience, 'countries', v.countries, 'routes', v.routes,
                 'salary_min', v.salary_min, 'salary_max', v.salary_max, 'currency', v.currency,
                 'schedule', v.schedule, 'conditions', v.conditions,
                 'phone', case when v.show_phone or v_admin or v.owner_id = auth.uid() then v.phone end,
                 'whatsapp', v.whatsapp and (v.show_phone or v_admin or v.owner_id = auth.uid()),
                 'status', v.status, 'is_hidden', v.is_hidden and v_admin,
                 'updated_at', v.updated_at) r
          from public.job_vacancies v
          join public.users u on u.id = v.owner_id
         where v.status = 'active'
           and (not v.is_hidden or v_admin)
           and (not coalesce(u.is_blocked, false) or v_admin)
         order by v.updated_at desc
         limit least(greatest(coalesce(p_limit, 300), 1), 500) offset greatest(coalesce(p_offset, 0), 0)
      ) x), '[]'::jsonb);
end $$;
revoke all on function public.job_vacancies_list(integer, integer) from public, anon;
grant execute on function public.job_vacancies_list(integer, integer) to authenticated;

-- 5) Admin moderation (logged) ----------------------------------------------------
create or replace function public.admin_job_set_hidden(p_kind text, p_id uuid, p_hidden boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public._require_admin();
  if p_hidden is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if p_kind = 'seeker' then
    update job_seeker_profiles set is_hidden = p_hidden where user_id = p_id;
  elsif p_kind = 'vacancy' then
    update job_vacancies set is_hidden = p_hidden where id = p_id;
  else
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  perform public._admin_log(case when p_hidden then 'job.hide' else 'job.show' end, 'job_' || p_kind, p_id::text,
    jsonb_build_object('is_hidden', not p_hidden), jsonb_build_object('is_hidden', p_hidden));
end $$;
revoke all on function public.admin_job_set_hidden(text, uuid, boolean) from public, anon;
grant execute on function public.admin_job_set_hidden(text, uuid, boolean) to authenticated;

-- 6) Notifications: each notice at most once ---------------------------------------
create unique index if not exists notifications_dedupe_key on public.notifications ((data ->> 'dedupe'))
  where data ? 'dedupe';

-- Same country rule as the app's "Yer" line: either side not given, the
-- same country, or the vacancy's country is one the driver wants.
create or replace function public.job_country_fits(p_seeker public.job_seeker_profiles, p_vacancy public.job_vacancies)
returns boolean language sql stable set search_path = public, pg_temp as $$
  select p_vacancy.country is null or p_seeker.country is null
      or lower(p_seeker.country) = lower(p_vacancy.country)
      or exists (select 1 from unnest(p_seeker.countries) c where lower(c) = lower(p_vacancy.country));
$$;

-- A vacancy that is (again) active: the drivers with a matching specialty
-- and country hear about it — once per vacancy and driver.
create or replace function public.job_vacancy_notify()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status <> 'active' or new.is_hidden or cardinality(new.specialties) = 0 then return null; end if;
  if tg_op = 'UPDATE' and old.status = 'active' and not old.is_hidden and old.specialties @> new.specialties then
    return null;
  end if;
  insert into notifications (user_id, type, title, body, data)
  select p.user_id, 'job_match_vacancy', 'Yeni uyğun vakansiya',
         new.company_name || coalesce(' · ' || new.city, ''),
         jsonb_build_object('vacancy_id', new.id, 'dedupe', 'job_vac:' || new.id || ':' || p.user_id)
    from job_seeker_profiles p
   where p.is_active and not p.is_hidden and p.user_id <> new.owner_id
     and p.specialties && new.specialties
     and public.job_country_fits(p, new)
   limit 300
  on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  return null;
end $$;
drop trigger if exists job_vacancy_notify on public.job_vacancies;
create trigger job_vacancy_notify after insert or update on public.job_vacancies
  for each row execute function public.job_vacancy_notify();

-- A driver (again) looking for work: employers with an active vacancy of
-- a matching specialty and country hear about him — once per driver and
-- employer.
create or replace function public.job_seeker_notify()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not new.is_active or new.is_hidden or cardinality(new.specialties) = 0 then return null; end if;
  if tg_op = 'UPDATE' and old.is_active and not old.is_hidden and old.specialties @> new.specialties then
    return null;
  end if;
  insert into notifications (user_id, type, title, body, data)
  select distinct on (v.owner_id) v.owner_id, 'job_match_seeker', 'Yeni uyğun sürücü',
         new.full_name || coalesce(' · ' || new.city, ''),
         jsonb_build_object('seeker_id', new.user_id, 'vacancy_id', v.id, 'dedupe', 'job_seeker:' || new.user_id || ':' || v.owner_id)
    from job_vacancies v
   where v.status = 'active' and not v.is_hidden and v.owner_id <> new.user_id
     and v.specialties && new.specialties
     and public.job_country_fits(new, v)
   order by v.owner_id, v.updated_at desc
   limit 300
  on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
  return null;
end $$;
drop trigger if exists job_seeker_notify on public.job_seeker_profiles;
create trigger job_seeker_notify after insert or update on public.job_seeker_profiles
  for each row execute function public.job_seeker_notify();

-- 7) Applications and job offers -------------------------------------------------------
create table if not exists public.job_applications (
  id uuid primary key default gen_random_uuid(),
  vacancy_id uuid not null references public.job_vacancies(id) on delete cascade,
  seeker_id uuid not null references public.users(id) on delete cascade,
  employer_id uuid not null references public.users(id) on delete cascade,
  initiated_by text not null check (initiated_by in ('seeker', 'employer')),
  status text not null default 'sent' check (status in ('sent', 'seen', 'talking', 'accepted', 'rejected', 'closed')),
  seeker_ok boolean not null default false,
  employer_ok boolean not null default false,
  message text check (message is null or char_length(message) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (vacancy_id, seeker_id)
);
create index if not exists job_applications_seeker_idx on public.job_applications (seeker_id, updated_at desc);
create index if not exists job_applications_employer_idx on public.job_applications (employer_id, updated_at desc);
alter table public.job_applications enable row level security;
revoke all on public.job_applications from anon, authenticated;
grant select on public.job_applications to authenticated;
drop policy if exists "job_applications_read" on public.job_applications;
create policy "job_applications_read" on public.job_applications for select to authenticated
  using (seeker_id = (select auth.uid()) or employer_id = (select auth.uid()) or (select public.is_admin()));

create or replace function public._job_application_notify(a public.job_applications, p_to uuid, p_title text)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into notifications (user_id, type, title, body, data)
  values (p_to, 'job_application', p_title, null,
          jsonb_build_object('application_id', a.id, 'vacancy_id', a.vacancy_id, 'status', a.status,
                             'dedupe', 'job_app:' || a.id || ':' || a.status || ':' || p_to || ':' || a.seeker_ok || a.employer_ok))
  on conflict ((data ->> 'dedupe')) where data ? 'dedupe' do nothing;
$$;
revoke all on function public._job_application_notify(public.job_applications, uuid, text) from public, anon, authenticated;

-- A driver applies (p_seeker null) or an employer offers the job to a
-- driver (p_seeker set). One row per vacancy and driver; a rejected or
-- closed one can be sent again.
create or replace function public.job_application_send(p_vacancy uuid, p_seeker uuid default null, p_message text default null)
returns public.job_applications language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_v public.job_vacancies;
  v_seeker uuid;
  v_by text;
  v_a public.job_applications;
  v_msg text := nullif(btrim(coalesce(p_message, '')), '');
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if v_msg is not null and char_length(v_msg) > 1000 then raise exception 'message_too_long' using errcode = '22023'; end if;
  select * into v_v from job_vacancies where id = p_vacancy;
  if v_v.id is null or v_v.is_hidden then raise exception 'vacancy_not_found' using errcode = 'P0002'; end if;
  if p_seeker is null then
    v_seeker := v_uid; v_by := 'seeker';
    if v_v.owner_id = v_uid then raise exception 'own_vacancy' using errcode = '22023'; end if;
    if v_v.status <> 'active' then raise exception 'vacancy_closed' using errcode = '22023'; end if;
  else
    v_seeker := p_seeker; v_by := 'employer';
    if v_v.owner_id <> v_uid then raise exception 'vacancy_not_found' using errcode = 'P0002'; end if;
    if p_seeker = v_uid then raise exception 'own_vacancy' using errcode = '22023'; end if;
    if not exists (select 1 from job_seeker_profiles where user_id = p_seeker and is_active and not is_hidden) then
      raise exception 'seeker_not_found' using errcode = 'P0002';
    end if;
  end if;

  select * into v_a from job_applications where vacancy_id = p_vacancy and seeker_id = v_seeker for update;
  if v_a.id is not null and v_a.status not in ('rejected', 'closed') then return v_a; end if;
  if v_a.id is null then
    insert into job_applications (vacancy_id, seeker_id, employer_id, initiated_by, message)
    values (p_vacancy, v_seeker, v_v.owner_id, v_by, v_msg)
    returning * into v_a;
  else
    update job_applications
       set initiated_by = v_by, status = 'sent', seeker_ok = false, employer_ok = false, message = v_msg, updated_at = now()
     where id = v_a.id returning * into v_a;
  end if;
  perform public._job_application_notify(v_a, case when v_by = 'seeker' then v_v.owner_id else v_seeker end,
    case when v_by = 'seeker' then 'Yeni müraciət' else 'Yeni iş təklifi' end);
  return v_a;
end $$;
revoke all on function public.job_application_send(uuid, uuid, text) from public, anon;
grant execute on function public.job_application_send(uuid, uuid, text) to authenticated;

-- Statuses: seen (the side that received it) → talking → accepted (only
-- when BOTH sides confirmed) / rejected / closed. Each change tells the
-- other side once.
create or replace function public.job_application_set_status(p_id uuid, p_status text)
returns public.job_applications language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_a public.job_applications;
  v_side text;
  v_other uuid;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  select * into v_a from job_applications where id = p_id for update;
  if v_a.id is null or v_uid not in (v_a.seeker_id, v_a.employer_id) then
    raise exception 'application_not_found' using errcode = 'P0002';
  end if;
  v_side := case when v_uid = v_a.seeker_id then 'seeker' else 'employer' end;
  v_other := case when v_side = 'seeker' then v_a.employer_id else v_a.seeker_id end;
  if v_a.status in ('rejected', 'closed') or (v_a.status = 'accepted' and p_status <> 'closed') then
    raise exception 'application_final' using errcode = '22023';
  end if;

  if p_status = 'seen' then
    if v_side = v_a.initiated_by or v_a.status <> 'sent' then return v_a; end if;
    update job_applications set status = 'seen', updated_at = now() where id = p_id returning * into v_a;
    return v_a;  -- "seen" is not announced
  elsif p_status = 'talking' then
    update job_applications set status = 'talking', updated_at = now() where id = p_id returning * into v_a;
  elsif p_status = 'accepted' then
    update job_applications
       set seeker_ok = seeker_ok or v_side = 'seeker',
           employer_ok = employer_ok or v_side = 'employer',
           updated_at = now()
     where id = p_id returning * into v_a;
    update job_applications
       set status = case when seeker_ok and employer_ok then 'accepted' else 'talking' end
     where id = p_id returning * into v_a;
  elsif p_status in ('rejected', 'closed') then
    update job_applications set status = p_status, updated_at = now() where id = p_id returning * into v_a;
  else
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  perform public._job_application_notify(v_a, v_other, case v_a.status
    when 'accepted' then 'İşə qəbul təsdiqləndi'
    when 'rejected' then 'Müraciət rədd edildi'
    when 'closed' then 'Müraciət bağlandı'
    else 'Müraciətdə yenilik' end);
  return v_a;
end $$;
revoke all on function public.job_application_set_status(uuid, text) from public, anon;
grant execute on function public.job_application_set_status(uuid, text) to authenticated;

-- 8) Final check: everything in place.
do $$
begin
  if to_regclass('public.job_specialties') is null
     or to_regclass('public.job_skills') is null
     or to_regclass('public.job_seeker_profiles') is null
     or to_regclass('public.job_vacancies') is null
     or to_regclass('public.job_applications') is null
     or to_regprocedure('public.job_seekers_list(integer, integer)') is null
     or to_regprocedure('public.job_vacancies_list(integer, integer)') is null
     or to_regprocedure('public.admin_job_set_hidden(text, uuid, boolean)') is null
     or to_regprocedure('public.job_application_send(uuid, uuid, text)') is null
     or to_regprocedure('public.job_application_set_status(uuid, text)') is null
     or to_regclass('public.notifications_dedupe_key') is null
     or (select count(*) from public.job_specialties) < 10
     or (select count(*) from public.job_skills) < 11 then
    raise exception '0069: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
