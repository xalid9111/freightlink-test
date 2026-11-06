-- =====================================================================
-- 0097 — Usta / Servis and Mağaza profile forms (owner, 06.11.2026).
-- * service_providers.logo_url: the profile's own round picture (logo),
--   set only through service_set_logo (its owner or an admin), from the
--   owner's own profile-media folder — the same rules as the park's logo
--   (0096).
-- * The shop's product kinds as service categories (shop_*): "Yeni
--   ehtiyat hissələri" and "İşlənmiş ehtiyat hissələri" (both may be
--   chosen), Mühərrik, Elektrik, Təkər və disk, Yağlar, Aksesuarlar, Digər.
--   A shop stays a service with the spare_parts category (0043); the
--   Servislər form never shows the shop_* kinds.
-- Safe: forward-only, re-runnable; adds one column, eight category rows
-- and one function; the guard keeps working for covers as in 0096. No
-- existing row is changed.
-- =====================================================================

alter table public.service_providers add column if not exists logo_url text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'service_providers_logo_url_check') then
    alter table public.service_providers add constraint service_providers_logo_url_check check (logo_url is null or
      (char_length(logo_url) <= 1000 and logo_url ~ '^https://[^ ]+/storage/v1/object/public/profile-media/'));
  end if;
end $$;

-- The service table is readable column by column (0018 / 0028).
grant select (logo_url) on table public.service_providers to authenticated;

-- 0096's guard, now also for the service's logo.
create or replace function public.place_cover_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or public.is_admin() or current_setting('app.place_cover_trusted', true) = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.cover_url := null;
    new.logo_url := null;
  else
    new.cover_url := old.cover_url;
    new.logo_url := old.logo_url;
  end if;
  return new;
end $$;
revoke all on function public.place_cover_guard() from public, anon, authenticated;

-- The service's / shop's logo (p_url null = none): its owner or an admin,
-- only the owner's own picture.
create or replace function public.service_set_logo(p_service uuid, p_url text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not (public.is_admin() or exists (select 1 from service_providers where id = p_service and owner_id = auth.uid())) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_url is not null and not public._place_cover_ok(p_url, 'service', false) then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  perform set_config('app.place_cover_trusted', '1', true);
  update service_providers set logo_url = p_url where id = p_service;
  perform set_config('app.place_cover_trusted', '0', true);
end $$;
revoke all on function public.service_set_logo(uuid, text) from public, anon;
grant execute on function public.service_set_logo(uuid, text) to authenticated;

-- The shop's product kinds (after every service kind).
insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order) values
  ('shop_new',         'Yeni ehtiyat hissələri',      'Yeni yedek parçalar',    'New spare parts',  'Новые запчасти',   'ახალი სათადარიგო ნაწილები', 'parts', 200),
  ('shop_used',        'İşlənmiş ehtiyat hissələri',  'İkinci el yedek parçalar','Used spare parts', 'Б/у запчасти',     'მეორადი სათადარიგო ნაწილები', 'parts', 201),
  ('shop_engine',      'Mühərrik',                    'Motor',                  'Engine',           'Двигатель',        'ძრავი', 'engine', 202),
  ('shop_electric',    'Elektrik',                    'Elektrik',               'Electrical',       'Электрика',        'ელექტროობა', 'electrical', 203),
  ('shop_tyres',       'Təkər və disk',               'Lastik ve jant',         'Tyres & wheels',   'Шины и диски',     'საბურავები და დისკები', 'tyre', 204),
  ('shop_oils',        'Yağlar',                      'Yağlar',                 'Oils',             'Масла',            'ზეთები', 'parts', 205),
  ('shop_accessories', 'Aksesuarlar',                 'Aksesuarlar',            'Accessories',      'Аксессуары',       'აქსესუარები', 'parts', 206),
  ('shop_other',       'Digər',                       'Diğer',                  'Other',            'Другое',           'სხვა', 'parts', 207)
on conflict (id) do nothing;

notify pgrst, 'reload schema';
