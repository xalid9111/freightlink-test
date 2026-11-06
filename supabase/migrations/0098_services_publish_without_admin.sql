-- =====================================================================
-- 0098 — Services and shops are published without the admin (owner,
-- 06.11.2026). Since 0028 a NEW profile is published at once; profiles
-- made before 0028 could still wait as 'pending' ("Profiliniz hələ dərc
-- olunmayıb"). Now:
-- the owner's save ("Yadda saxla") publishes such a waiting profile at
-- once — no admin needed.
-- Rejected / suspended profiles stay as the admin set them; the admin can
-- still reject / suspend afterwards (Admin → Servislər). Owners still
-- cannot change status, verification, PRO or rating themselves.
-- Safe: forward-only, re-runnable; replaces one trigger function only. No
-- row is changed by running it.
-- =====================================================================

create or replace function public.guard_service_provider()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    new.updated_at := now();
  end if;

  if current_user not in ('anon', 'authenticated') then
    return new;                       -- trusted server-side caller
  end if;
  if public.is_admin() then
    return new;                       -- admin using the API directly
  end if;
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if public.is_blocked(auth.uid()) then
    raise exception 'account_blocked' using errcode = '42501';
  end if;

  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'approved';         -- 0028: published at once, no waiting
    new.is_verified := false;
    new.is_pro := false;
    new.added_by_admin := false;
    new.admin_note := null;
    new.rating_avg := 0;
    new.rating_count := 0;
    new.created_at := now();
    new.updated_at := now();
  else
    new.id := old.id;
    new.owner_id := old.owner_id;
    -- 0098: the owner's save publishes a profile still waiting from the
    -- time before 0028; rejected / suspended stay as the admin set them.
    new.status := case when old.status = 'pending' then 'approved' else old.status end;
    new.is_verified := old.is_verified;
    new.is_pro := old.is_pro;
    new.added_by_admin := old.added_by_admin;
    new.admin_note := old.admin_note;
    new.rating_avg := old.rating_avg;
    new.rating_count := old.rating_count;
    new.created_at := old.created_at;
  end if;

  -- Only known categories are kept (unchanged from 0017).
  new.categories := coalesce(array(
    select distinct c from unnest(new.categories) c
    where exists (select 1 from public.service_categories sc where sc.id = c)
  ), '{}');
  return new;
end;
$$;

notify pgrst, 'reload schema';
