-- =====================================================================
-- 0020 — Advertiser-submitted banner details, targeting, destinations,
--        and privacy-safe impression/click counts.
-- Forward-only and idempotent. Existing orders and ads remain valid.
-- =====================================================================

alter table public.ad_orders
  add column if not exists title text,
  add column if not exists image_url text,
  add column if not exists destination_type text not null default 'profile'
    check (destination_type in ('profile','external')),
  add column if not exists destination_url text,
  add column if not exists target_countries text[] not null default '{}',
  add column if not exists route_from text,
  add column if not exists route_to text;

alter table public.ads
  add column if not exists destination_type text not null default 'profile'
    check (destination_type in ('profile','external')),
  add column if not exists destination_url text,
  add column if not exists target_countries text[] not null default '{}',
  add column if not exists route_from text,
  add column if not exists route_to text;

-- Advertisers can upload only within their own request folder. Admins keep
-- their existing banners/ upload policy from migration 0015.
drop policy if exists "ads_images_owner_insert" on storage.objects;
create policy "ads_images_owner_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ads'
    and (storage.foldername(name))[1] = 'requests'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create or replace function public.create_ad_order_request(
  p_package text,
  p_title text,
  p_image_url text,
  p_destination_type text,
  p_destination_url text default null,
  p_target_countries text[] default '{}',
  p_route_from text default null,
  p_route_to text default null,
  p_note text default null
)
returns public.ad_orders
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_pkg public.ad_packages;
  v_order public.ad_orders;
  v_company uuid;
  v_destination text := nullif(btrim(p_destination_url), '');
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if public.is_blocked(auth.uid()) then raise exception 'account_blocked' using errcode = '42501'; end if;
  if nullif(btrim(p_title), '') is null or char_length(btrim(p_title)) > 100 then
    raise exception 'invalid_title' using errcode = '22023';
  end if;
  if p_image_url is null or p_image_url !~ ('/ads/requests/' || auth.uid()::text || '/[^/]+$') then
    raise exception 'invalid_image' using errcode = '22023';
  end if;
  if p_destination_type is null or p_destination_type not in ('profile','external') then
    raise exception 'invalid_destination' using errcode = '22023';
  end if;
  if p_destination_type = 'external' and
     (v_destination is null or v_destination !~* '^https://([a-z0-9-]+\.)+[a-z0-9-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$') then
    raise exception 'invalid_external_url' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(coalesce(p_target_countries, '{}')) c where c !~ '^[A-Z]{2}$') then
    raise exception 'invalid_target_country' using errcode = '22023';
  end if;
  if char_length(coalesce(p_route_from, '')) > 100 or char_length(coalesce(p_route_to, '')) > 100 then
    raise exception 'invalid_route' using errcode = '22023';
  end if;
  if p_destination_type = 'profile' then v_destination := null; end if;
  select * into v_pkg from public.ad_packages where id = p_package and is_active;
  if v_pkg.id is null then raise exception 'package_not_found' using errcode = 'P0002'; end if;
  select id into v_company from public.companies where owner_user_id = auth.uid() order by created_at limit 1;
  insert into public.ad_orders (
    advertiser_id, company_id, package_id, package_name, days, price, currency,
    status, title, image_url, destination_type, destination_url,
    target_countries, route_from, route_to, customer_note
  ) values (
    auth.uid(), v_company, v_pkg.id, v_pkg.name, v_pkg.days, v_pkg.price, v_pkg.currency,
    'awaiting_approval', btrim(p_title), p_image_url, p_destination_type, v_destination,
    coalesce(p_target_countries, '{}'), nullif(btrim(p_route_from), ''), nullif(btrim(p_route_to), ''),
    nullif(btrim(p_note), '')
  ) returning * into v_order;
  return v_order;
end;
$$;
revoke all on function public.create_ad_order_request(text,text,text,text,text,text[],text,text,text) from public, anon;
grant execute on function public.create_ad_order_request(text,text,text,text,text,text[],text,text,text) to authenticated;

-- New ads created from advertiser orders inherit the submitted creative and
-- targeting unless the admin supplies a replacement banner/title.
create or replace function public.admin_save_ad(
  p_ad uuid, p_order uuid, p_advertiser uuid, p_title text, p_image_url text,
  p_starts timestamptz, p_ends timestamptz, p_active boolean)
returns public.ads
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_ad public.ads; v_ord public.ad_orders;
begin
  perform public._require_admin();
  if p_ends <= p_starts then raise exception 'invalid_dates'; end if;
  if p_order is not null then
    select * into v_ord from public.ad_orders where id = p_order;
    if v_ord.id is null then raise exception 'not_found'; end if;
    if v_ord.payment_status <> 'paid' or v_ord.status not in ('approved','active') then
      raise exception 'invalid_order_state';
    end if;
  end if;
  if p_ad is null then
    if coalesce(nullif(btrim(p_image_url), ''), v_ord.image_url) is null then raise exception 'invalid_image'; end if;
    insert into public.ads (
      order_id, advertiser_id, title, image_url, destination_type, destination_url,
      target_countries, route_from, route_to, starts_at, ends_at, is_active
    ) values (
      p_order, coalesce(p_advertiser, v_ord.advertiser_id),
      coalesce(nullif(btrim(p_title), ''), v_ord.title), coalesce(nullif(btrim(p_image_url), ''), v_ord.image_url),
      coalesce(v_ord.destination_type, 'profile'), v_ord.destination_url,
      coalesce(v_ord.target_countries, '{}'), v_ord.route_from, v_ord.route_to,
      p_starts, p_ends, coalesce(p_active, false)
    ) returning * into v_ad;
    if p_order is not null then update public.ad_orders set status = 'active', updated_at = now() where id = p_order; end if;
    perform public._admin_log('ad.create', 'ad', v_ad.id::text, null, to_jsonb(v_ad));
  else
    select to_jsonb(a) into v_old from public.ads a where id = p_ad;
    if v_old is null then raise exception 'not_found'; end if;
    update public.ads set
      title = nullif(btrim(p_title), ''), image_url = coalesce(nullif(btrim(p_image_url), ''), image_url),
      starts_at = p_starts, ends_at = p_ends, is_active = coalesce(p_active, is_active), updated_at = now()
    where id = p_ad returning * into v_ad;
    perform public._admin_log('ad.update', 'ad', p_ad::text, v_old, to_jsonb(v_ad));
  end if;
  return v_ad;
end;
$$;
revoke all on function public.admin_save_ad(uuid,uuid,uuid,text,text,timestamptz,timestamptz,boolean) from public, anon;
grant execute on function public.admin_save_ad(uuid,uuid,uuid,text,text,timestamptz,timestamptz,boolean) to authenticated;

create table if not exists public.ad_events (
  id bigint generated always as identity primary key,
  ad_id uuid not null references public.ads(id) on delete cascade,
  event_type text not null check (event_type in ('impression','click')),
  viewer_id uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists idx_ad_events_ad_type on public.ad_events(ad_id, event_type, created_at desc);
alter table public.ad_events enable row level security;
-- No direct table access; writes and aggregate reads go through guarded RPCs.
revoke all on public.ad_events from public, anon, authenticated;

create or replace function public.record_ad_event(p_ad uuid, p_type text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_type not in ('impression','click') then raise exception 'invalid_event'; end if;
  if not exists (select 1 from public.ads a where a.id = p_ad and a.is_active
    and now() >= a.starts_at and now() < a.ends_at) then return; end if;
  if exists (
    select 1 from public.ad_events e
    where e.ad_id = p_ad and e.viewer_id = auth.uid() and e.event_type = p_type
      and e.created_at > now() - interval '30 seconds'
  ) then return; end if;
  insert into public.ad_events(ad_id, event_type, viewer_id)
  values (p_ad, p_type, auth.uid());
end;
$$;
revoke all on function public.record_ad_event(uuid,text) from public, anon;
grant execute on function public.record_ad_event(uuid,text) to authenticated;

create or replace function public.get_my_ad_stats()
returns table(order_id uuid, impressions bigint, clicks bigint)
language sql stable security definer set search_path = public, pg_temp as $$
  select o.id,
    count(e.id) filter (where e.event_type = 'impression'),
    count(e.id) filter (where e.event_type = 'click')
  from public.ad_orders o
  left join public.ads a on a.order_id = o.id
  left join public.ad_events e on e.ad_id = a.id
  where o.advertiser_id = auth.uid() or public.is_admin()
  group by o.id;
$$;
grant execute on function public.get_my_ad_stats() to authenticated;
revoke all on function public.get_my_ad_stats() from public, anon;
grant execute on function public.get_my_ad_stats() to authenticated;

comment on table public.ad_events is 'Ad impression/click metrics; direct access is revoked and counts are owner/admin-only.';
