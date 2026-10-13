-- =====================================================================
-- 0017 — SERVICES module (mechanics / service centres / tow trucks)
--
-- SAFE FORWARD MIGRATION: only creates new objects (or replaces the
-- functions it owns). Nothing existing is dropped, reset or deleted;
-- users.role is NOT changed — a service profile is a separate row
-- linked to an ordinary account (multi-role use). Re-runnable.
-- =====================================================================

-- 1) Categories (extensible; names per UI language) --------------------
create table if not exists public.service_categories (
  id text primary key check (id ~ '^[a-z0-9_]{2,40}$'),
  name_az text not null,
  name_tr text,
  name_en text,
  name_ru text,
  name_ka text,
  icon text not null default 'build',
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.service_categories enable row level security;
drop policy if exists "service_categories_read" on public.service_categories;
create policy "service_categories_read" on public.service_categories
  for select to authenticated using (true);
-- Writes only through admin_save_service_category() below.

insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order) values
  ('truck_repair', 'TIR və yük avtomobili təmiri', 'TIR ve kamyon tamiri', 'Truck & TIR repair', 'Ремонт фур и грузовиков', 'სატვირთოს და TIR-ის შეკეთება', 'truck', 10),
  ('engine',       'Mühərrik və mexanika',         'Motor ve mekanik',      'Engine & mechanics', 'Двигатель и механика',   'ძრავი და მექანიკა', 'engine', 20),
  ('electrical',   'Elektrik və elektronika',      'Elektrik ve elektronik','Electrical & electronics', 'Электрика и электроника', 'ელექტროობა და ელექტრონიკა', 'electrical', 30),
  ('tyres',        'Təkər təmiri',                 'Lastik tamiri',         'Tyre repair',        'Шиномонтаж',             'საბურავების შეკეთება', 'tyre', 40),
  ('battery',      'Akkumulyator',                 'Akü',                   'Battery',            'Аккумулятор',            'აკუმულატორი', 'battery', 50),
  ('tow',          'Evakuator',                    'Çekici',                'Tow truck',          'Эвакуатор',              'ევაკუატორი', 'tow', 60),
  ('reefer',       'Soyuducu qurğu təmiri',        'Frigorifik ünite tamiri','Reefer unit repair', 'Ремонт рефрижератора',  'მაცივარი დანადგარის შეკეთება', 'reefer', 70),
  ('roadside',     'Mobil yolüstü texniki yardım', 'Mobil yol yardımı',     'Mobile roadside assistance', 'Мобильная техпомощь на дороге', 'მობილური გზისპირა დახმარება', 'roadside', 80)
on conflict (id) do nothing;

-- 2) Service providers --------------------------------------------------
create table if not exists public.service_providers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references public.users(id) on delete set null,
  kind text not null default 'individual' check (kind in ('individual','center')),
  name text not null check (char_length(btrim(name)) between 2 and 120),
  specialty text check (specialty is null or char_length(specialty) <= 200),
  description text check (description is null or char_length(description) <= 2000),
  categories text[] not null default '{}',
  country text check (country is null or char_length(country) <= 60),
  city text check (city is null or char_length(city) <= 120),
  address text check (address is null or char_length(address) <= 300),
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  is_mobile boolean not null default false,
  service_radius_km integer check (service_radius_km is null or service_radius_km between 1 and 2000),
  phone text check (phone is null or char_length(phone) <= 40),
  whatsapp text check (whatsapp is null or char_length(whatsapp) <= 40),
  working_hours text check (working_hours is null or char_length(working_hours) <= 300),
  is_24h boolean not null default false,
  is_active boolean not null default true,          -- owner's "available now" switch
  status text not null default 'pending' check (status in ('pending','approved','rejected','suspended')),
  is_verified boolean not null default false,       -- ownership / identity confirmed by admin
  added_by_admin boolean not null default false,
  admin_note text,
  photos text[] not null default '{}' check (cardinality(photos) <= 10),
  rating_avg numeric(3,2) not null default 0,
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- One service profile per account (phase 1).
create unique index if not exists uq_service_providers_owner on public.service_providers(owner_id) where owner_id is not null;
create index if not exists idx_service_providers_lat on public.service_providers(lat);
create index if not exists idx_service_providers_lng on public.service_providers(lng);
create index if not exists idx_service_providers_status on public.service_providers(status, created_at desc);
create index if not exists idx_service_providers_categories on public.service_providers using gin (categories);

alter table public.service_providers enable row level security;

drop policy if exists "service_providers_select" on public.service_providers;
create policy "service_providers_select" on public.service_providers
  for select to authenticated
  using (status in ('pending','approved') or owner_id = auth.uid() or public.is_admin());

drop policy if exists "service_providers_insert_own" on public.service_providers;
create policy "service_providers_insert_own" on public.service_providers
  for insert to authenticated
  with check ((owner_id = auth.uid() and not public.is_blocked()) or public.is_admin());

drop policy if exists "service_providers_update_own" on public.service_providers;
create policy "service_providers_update_own" on public.service_providers
  for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

drop policy if exists "service_providers_delete_own" on public.service_providers;
create policy "service_providers_delete_own" on public.service_providers
  for delete to authenticated
  using (owner_id = auth.uid() or public.is_admin());

-- Owners cannot set moderation / rating fields themselves.
create or replace function public.guard_service_provider()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;
  -- Admins (and server-side SECURITY DEFINER code without a user) may set anything.
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  -- Rating recalculation from recalc_service_rating(): only the two
  -- rating columns may change.
  if tg_op = 'UPDATE' and coalesce(current_setting('app.service_rating_sync', true), 'off') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'pending';
    new.is_verified := false;
    new.added_by_admin := false;
    new.admin_note := null;
    new.rating_avg := 0;
    new.rating_count := 0;
  else
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.is_verified := old.is_verified;
    new.added_by_admin := old.added_by_admin;
    new.admin_note := old.admin_note;
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.created_at := old.created_at;
  end if;
  -- Only known categories are kept.
  new.categories := coalesce(array(
    select distinct c from unnest(new.categories) c
    where exists (select 1 from public.service_categories sc where sc.id = c)
  ), '{}');
  return new;
end;
$$;
drop trigger if exists trg_guard_service_provider on public.service_providers;
create trigger trg_guard_service_provider
  before insert or update on public.service_providers
  for each row execute function public.guard_service_provider();

-- 3) Reviews + rating aggregate ----------------------------------------
create table if not exists public.service_reviews (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.service_providers(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_id, user_id)
);
create index if not exists idx_service_reviews_provider on public.service_reviews(provider_id, created_at desc);
alter table public.service_reviews enable row level security;

create or replace function public.is_service_owner(p_provider uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.service_providers where id = p_provider and owner_id = auth.uid());
$$;

drop policy if exists "service_reviews_read" on public.service_reviews;
create policy "service_reviews_read" on public.service_reviews
  for select to authenticated using (true);
drop policy if exists "service_reviews_insert_own" on public.service_reviews;
create policy "service_reviews_insert_own" on public.service_reviews
  for insert to authenticated
  with check (user_id = auth.uid() and not public.is_blocked() and not public.is_service_owner(provider_id));
drop policy if exists "service_reviews_update_own" on public.service_reviews;
create policy "service_reviews_update_own" on public.service_reviews
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "service_reviews_delete_own_or_admin" on public.service_reviews;
create policy "service_reviews_delete_own_or_admin" on public.service_reviews
  for delete to authenticated using (user_id = auth.uid() or public.is_admin());

create or replace function public.touch_service_review()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.provider_id := old.provider_id;
  new.user_id := old.user_id;
  return new;
end;
$$;

create or replace function public.recalc_service_rating()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  v_id := case when tg_op = 'DELETE' then old.provider_id else new.provider_id end;
  -- Lets guard_service_provider() accept this rating update.
  perform set_config('app.service_rating_sync', 'on', true);
  update public.service_providers p set
    rating_avg = coalesce((select round(avg(rating)::numeric, 2) from public.service_reviews where provider_id = v_id), 0),
    rating_count = (select count(*) from public.service_reviews where provider_id = v_id)
  where p.id = v_id;
  perform set_config('app.service_rating_sync', 'off', true);
  return null;
end;
$$;
drop trigger if exists trg_service_review_touch on public.service_reviews;
create trigger trg_service_review_touch
  before update on public.service_reviews
  for each row execute function public.touch_service_review();
drop trigger if exists trg_service_review_rating on public.service_reviews;
create trigger trg_service_review_rating
  after insert or update or delete on public.service_reviews
  for each row execute function public.recalc_service_rating();

-- 4) Ownership claims (for services added by the admin) ----------------
create table if not exists public.service_claims (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.service_providers(id) on delete cascade,
  user_id uuid not null default auth.uid() references public.users(id) on delete cascade,
  message text check (message is null or char_length(message) <= 1000),
  phone text check (phone is null or char_length(phone) <= 40),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);
create unique index if not exists uq_service_claims_pending
  on public.service_claims(provider_id, user_id) where status = 'pending';
create index if not exists idx_service_claims_status on public.service_claims(status, created_at desc);
alter table public.service_claims enable row level security;

create or replace function public.service_is_unclaimed(p_provider uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.service_providers where id = p_provider and owner_id is null);
$$;

drop policy if exists "service_claims_insert_own" on public.service_claims;
create policy "service_claims_insert_own" on public.service_claims
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending' and not public.is_blocked()
              and public.service_is_unclaimed(provider_id));
drop policy if exists "service_claims_select_own_or_admin" on public.service_claims;
create policy "service_claims_select_own_or_admin" on public.service_claims
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- 5) Complaints reuse public.reports (target_type 'service') -----------
do $$
declare c text;
begin
  for c in
    select con.conname from pg_constraint con
    where con.conrelid = 'public.reports'::regclass and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%target_type%'
  loop
    execute format('alter table public.reports drop constraint %I', c);
  end loop;
  alter table public.reports add constraint reports_target_type_check
    check (target_type in ('cargo','user','message','offer','shipment','service','other'));
end $$;

-- 6) Nearby search (bounding box + great-circle distance) --------------
create or replace function public.nearby_services(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision default 100,
  p_category text default null,
  p_min_rating numeric default 0,
  p_only_active boolean default false,
  p_kind text default null,
  p_query text default null,
  p_limit integer default 200
) returns jsonb
language sql stable security invoker set search_path = public as $$
  with params as (
    select greatest(1, least(coalesce(p_radius_km, 100), 3000))::double precision as r,
           greatest(1, least(coalesce(p_limit, 200), 500)) as lim,
           nullif(btrim(coalesce(p_query, '')), '') as q
  ), box as (
    select r, lim, q,
           r / 111.0 as dlat,
           r / (111.0 * greatest(cos(radians(p_lat)), 0.02)) as dlng
    from params
  ), hits as (
    select s.*,
           2 * 6371 * asin(sqrt(
             power(sin(radians(s.lat - p_lat) / 2), 2) +
             cos(radians(p_lat)) * cos(radians(s.lat)) * power(sin(radians(s.lng - p_lng) / 2), 2)
           )) as distance_km
    from public.service_providers s, box b
    where s.status in ('pending','approved')
      and s.lat between p_lat - b.dlat and p_lat + b.dlat
      and (b.dlng >= 180 or s.lng between p_lng - b.dlng and p_lng + b.dlng)
      and (p_category is null or p_category = any(s.categories))
      and (p_kind is null or s.kind = p_kind)
      and s.rating_avg >= coalesce(p_min_rating, 0)
      and (not coalesce(p_only_active, false) or s.is_active)
      and (s.owner_id is null or not public.is_blocked(s.owner_id))
      and (b.q is null or s.name ilike '%' || b.q || '%' or s.city ilike '%' || b.q || '%'
           or s.specialty ilike '%' || b.q || '%')
  )
  select coalesce(jsonb_agg(to_jsonb(h) order by h.distance_km), '[]'::jsonb)
  from (
    select h.* from hits h, box b
    where h.distance_km <= b.r
    order by h.distance_km
    limit (select lim from box)
  ) h;
$$;
grant execute on function public.nearby_services(double precision, double precision, double precision, text, numeric, boolean, text, text, integer) to authenticated;

-- 7) Admin functions (server-checked, audit-logged) ---------------------
create or replace function public.admin_save_service(p_id uuid, p_data jsonb)
returns public.service_providers
language plpgsql security definer set search_path = public as $$
declare v_old public.service_providers; v_row public.service_providers;
begin
  perform public._require_admin();
  if p_id is null then
    insert into public.service_providers (
      kind, name, specialty, description, categories, country, city, address, lat, lng,
      is_mobile, service_radius_km, phone, whatsapp, working_hours, is_24h, is_active,
      status, is_verified, added_by_admin, admin_note, photos)
    values (
      coalesce(p_data->>'kind', 'center'),
      p_data->>'name', p_data->>'specialty', p_data->>'description',
      coalesce(array(select jsonb_array_elements_text(p_data->'categories')), '{}'),
      p_data->>'country', p_data->>'city', p_data->>'address',
      (p_data->>'lat')::double precision, (p_data->>'lng')::double precision,
      coalesce((p_data->>'is_mobile')::boolean, false),
      nullif(p_data->>'service_radius_km', '')::integer,
      p_data->>'phone', p_data->>'whatsapp', p_data->>'working_hours',
      coalesce((p_data->>'is_24h')::boolean, false),
      coalesce((p_data->>'is_active')::boolean, true),
      coalesce(p_data->>'status', 'approved'),
      coalesce((p_data->>'is_verified')::boolean, false),
      true, p_data->>'admin_note',
      coalesce(array(select jsonb_array_elements_text(p_data->'photos')), '{}'))
    returning * into v_row;
    perform public._admin_log('service.create', 'service', v_row.id::text, null, to_jsonb(v_row));
  else
    select * into v_old from public.service_providers where id = p_id for update;
    if not found then raise exception 'service_not_found'; end if;
    update public.service_providers set
      kind = coalesce(p_data->>'kind', kind),
      name = coalesce(p_data->>'name', name),
      specialty = case when p_data ? 'specialty' then p_data->>'specialty' else specialty end,
      description = case when p_data ? 'description' then p_data->>'description' else description end,
      categories = case when p_data ? 'categories' then coalesce(array(select jsonb_array_elements_text(p_data->'categories')), '{}') else categories end,
      country = case when p_data ? 'country' then p_data->>'country' else country end,
      city = case when p_data ? 'city' then p_data->>'city' else city end,
      address = case when p_data ? 'address' then p_data->>'address' else address end,
      lat = coalesce((p_data->>'lat')::double precision, lat),
      lng = coalesce((p_data->>'lng')::double precision, lng),
      is_mobile = coalesce((p_data->>'is_mobile')::boolean, is_mobile),
      service_radius_km = case when p_data ? 'service_radius_km' then nullif(p_data->>'service_radius_km', '')::integer else service_radius_km end,
      phone = case when p_data ? 'phone' then p_data->>'phone' else phone end,
      whatsapp = case when p_data ? 'whatsapp' then p_data->>'whatsapp' else whatsapp end,
      working_hours = case when p_data ? 'working_hours' then p_data->>'working_hours' else working_hours end,
      is_24h = coalesce((p_data->>'is_24h')::boolean, is_24h),
      is_active = coalesce((p_data->>'is_active')::boolean, is_active),
      status = coalesce(p_data->>'status', status),
      is_verified = coalesce((p_data->>'is_verified')::boolean, is_verified),
      admin_note = case when p_data ? 'admin_note' then p_data->>'admin_note' else admin_note end,
      photos = case when p_data ? 'photos' then coalesce(array(select jsonb_array_elements_text(p_data->'photos')), '{}') else photos end
    where id = p_id
    returning * into v_row;
    perform public._admin_log('service.update', 'service', p_id::text, to_jsonb(v_old), to_jsonb(v_row));
  end if;
  return v_row;
end;
$$;

create or replace function public.admin_set_service_status(p_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.service_providers;
begin
  perform public._require_admin();
  if p_status not in ('pending','approved','rejected','suspended') then raise exception 'bad_status'; end if;
  select * into v_old from public.service_providers where id = p_id for update;
  if not found then raise exception 'service_not_found'; end if;
  update public.service_providers set
    status = p_status,
    -- Approving a self-registered profile confirms its owner.
    is_verified = case when p_status = 'approved' and owner_id is not null then true else is_verified end,
    admin_note = coalesce(p_note, admin_note)
  where id = p_id;
  perform public._admin_log('service.status', 'service', p_id::text,
    jsonb_build_object('status', v_old.status), jsonb_build_object('status', p_status), p_note);
end;
$$;

create or replace function public.admin_set_service_verified(p_id uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  update public.service_providers set is_verified = p_verified where id = p_id;
  if not found then raise exception 'service_not_found'; end if;
  perform public._admin_log(case when p_verified then 'service.verify' else 'service.unverify' end,
    'service', p_id::text, null, jsonb_build_object('is_verified', p_verified));
end;
$$;

create or replace function public.admin_delete_service(p_id uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.service_providers;
begin
  perform public._require_admin();
  select * into v_old from public.service_providers where id = p_id;
  if not found then raise exception 'service_not_found'; end if;
  delete from public.service_providers where id = p_id;
  perform public._admin_log('service.delete', 'service', p_id::text, to_jsonb(v_old), null, p_reason);
end;
$$;

create or replace function public.admin_resolve_service_claim(p_claim uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_claim public.service_claims;
begin
  perform public._require_admin();
  select * into v_claim from public.service_claims where id = p_claim for update;
  if not found then raise exception 'claim_not_found'; end if;
  if v_claim.status <> 'pending' then raise exception 'claim_already_resolved'; end if;
  if p_approve then
    if exists (select 1 from public.service_providers where owner_id = v_claim.user_id and id <> v_claim.provider_id) then
      raise exception 'user_already_has_service';
    end if;
    update public.service_providers
      set owner_id = v_claim.user_id, is_verified = true, status = 'approved'
      where id = v_claim.provider_id and owner_id is null;
    if not found then raise exception 'service_already_owned'; end if;
    update public.service_claims set status = 'approved', admin_note = p_note, resolved_at = now() where id = p_claim;
    update public.service_claims set status = 'rejected', admin_note = 'other_claim_approved', resolved_at = now()
      where provider_id = v_claim.provider_id and status = 'pending' and id <> p_claim;
  else
    update public.service_claims set status = 'rejected', admin_note = p_note, resolved_at = now() where id = p_claim;
  end if;
  perform public._admin_log(case when p_approve then 'service_claim.approve' else 'service_claim.reject' end,
    'service', v_claim.provider_id::text, to_jsonb(v_claim), jsonb_build_object('approved', p_approve), p_note);
end;
$$;

create or replace function public.admin_save_service_category(p_id text, p_data jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public._require_admin();
  insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order, is_active)
  values (p_id, coalesce(p_data->>'name_az', p_id), p_data->>'name_tr', p_data->>'name_en', p_data->>'name_ru',
          p_data->>'name_ka', coalesce(p_data->>'icon', 'build'), coalesce((p_data->>'sort_order')::integer, 100),
          coalesce((p_data->>'is_active')::boolean, true))
  on conflict (id) do update set
    name_az = coalesce(p_data->>'name_az', service_categories.name_az),
    name_tr = case when p_data ? 'name_tr' then p_data->>'name_tr' else service_categories.name_tr end,
    name_en = case when p_data ? 'name_en' then p_data->>'name_en' else service_categories.name_en end,
    name_ru = case when p_data ? 'name_ru' then p_data->>'name_ru' else service_categories.name_ru end,
    name_ka = case when p_data ? 'name_ka' then p_data->>'name_ka' else service_categories.name_ka end,
    icon = coalesce(p_data->>'icon', service_categories.icon),
    sort_order = coalesce((p_data->>'sort_order')::integer, service_categories.sort_order),
    is_active = coalesce((p_data->>'is_active')::boolean, service_categories.is_active);
  perform public._admin_log('service_category.save', 'service_category', p_id, null, p_data);
end;
$$;

create or replace function public.admin_service_counts()
returns jsonb language sql stable security definer set search_path = public as $$
  select case when public.is_admin() then jsonb_build_object(
    'pending', (select count(*) from public.service_providers where status = 'pending'),
    'claims', (select count(*) from public.service_claims where status = 'pending'),
    'reports', (select count(*) from public.reports where target_type = 'service' and status in ('new','reviewing')),
    'total', (select count(*) from public.service_providers)
  ) else '{}'::jsonb end;
$$;

grant execute on function public.admin_save_service(uuid, jsonb) to authenticated;
grant execute on function public.admin_set_service_status(uuid, text, text) to authenticated;
grant execute on function public.admin_set_service_verified(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_service(uuid, text) to authenticated;
grant execute on function public.admin_resolve_service_claim(uuid, boolean, text) to authenticated;
grant execute on function public.admin_save_service_category(text, jsonb) to authenticated;
grant execute on function public.admin_service_counts() to authenticated;

-- 8) Photos: public bucket "service-photos", folder = provider id -------
insert into storage.buckets (id, name, public, file_size_limit)
values ('service-photos', 'service-photos', true, 5242880)
on conflict (id) do nothing;

create or replace function public.can_manage_service_folder(p_folder text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (
    select 1 from public.service_providers where id::text = p_folder and owner_id = auth.uid()
  );
$$;

drop policy if exists "service_photos_insert" on storage.objects;
create policy "service_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'service-photos' and public.can_manage_service_folder((storage.foldername(name))[1]));
drop policy if exists "service_photos_update" on storage.objects;
create policy "service_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'service-photos' and public.can_manage_service_folder((storage.foldername(name))[1]));
drop policy if exists "service_photos_delete" on storage.objects;
create policy "service_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'service-photos' and public.can_manage_service_folder((storage.foldername(name))[1]));
drop policy if exists "service_photos_read" on storage.objects;
create policy "service_photos_read" on storage.objects
  for select using (bucket_id = 'service-photos');

-- 9) Table privileges (Supabase grants these by default; explicit for safety)
grant select, insert, update, delete on public.service_providers to authenticated;
grant select, insert, update, delete on public.service_reviews to authenticated;
grant select, insert on public.service_claims to authenticated;
grant select on public.service_categories to authenticated;
