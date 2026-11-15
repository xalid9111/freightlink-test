-- =====================================================================
-- 0124 — the site's logos, changed by the Baş admin (owner, 15.11.2026:
-- "Baş admin paneline loqoları yükləyib düzəldə biləcəyim panel … 3 hissə:
-- Telefon · Ana səhifədəki loqo · Yüklənmə səhifəsi").
--
-- site_logos: one row per place —
--   * app_icon  — the Home Screen / tab icon (square, not transparent);
--   * home_logo — the logo left of "TırLink" (Yüklər, the computer's
--                 sidebar, the login page);
--   * splash    — the logo on the dark start-up screen.
-- url = the picture (already framed in the admin's editor and uploaded to
-- the public "market-photos" bucket); null = the app's own built-in logo.
-- Everybody (also visitors) reads it; only the Baş admin (is_chief_admin,
-- 0104) changes it, through admin_site_logo_set, every change in the Audit
-- Log. No direct writes.
--
-- Safe: forward-only, re-runnable; one new table and one function. No other
-- row is changed or deleted.
-- =====================================================================

begin;

create table if not exists public.site_logos (
  slot text primary key check (slot in ('app_icon', 'home_logo', 'splash')),
  url text check (url is null or (url ~ '^https://' and char_length(url) <= 600)),
  updated_by uuid references public.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.site_logos enable row level security;
revoke all on public.site_logos from anon, authenticated;
grant select on public.site_logos to anon, authenticated;
drop policy if exists "site_logos_read" on public.site_logos;
create policy "site_logos_read" on public.site_logos for select to anon, authenticated using (true);

-- Change one place's logo (null = back to the built-in logo).
create or replace function public.admin_site_logo_set(p_slot text, p_url text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_old text;
  v_url text := nullif(btrim(coalesce(p_url, '')), '');
begin
  if not public.is_chief_admin() then raise exception 'chief_admin_only' using errcode = '42501'; end if;
  if p_slot is null or p_slot not in ('app_icon', 'home_logo', 'splash') then
    raise exception 'invalid_slot' using errcode = '22023';
  end if;
  if v_url is not null and (v_url !~ '^https://' or char_length(v_url) > 600) then
    raise exception 'invalid_url' using errcode = '22023';
  end if;
  select url into v_old from site_logos where slot = p_slot;
  insert into site_logos (slot, url, updated_by, updated_at)
  values (p_slot, v_url, auth.uid(), now())
  on conflict (slot) do update set url = excluded.url, updated_by = excluded.updated_by, updated_at = now();
  perform public._admin_log('site_logo.set', 'site_logo', p_slot,
    jsonb_build_object('url', v_old), jsonb_build_object('url', v_url), null);
end;
$$;
revoke all on function public.admin_site_logo_set(text, text) from public, anon;
grant execute on function public.admin_site_logo_set(text, text) to authenticated;

commit;

notify pgrst, 'reload schema';
