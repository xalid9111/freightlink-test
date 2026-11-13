-- =====================================================================
-- 0119 — a deleted user's ads go with him; "Hesabı sil" (owner, 13.11.2026).
--
-- 1) _hide_user_ads(user): every ad of that user leaves the public lists —
--    loads hidden + paused, TIR Bazarı ads 'inactive', services / shops
--    'suspended', job vacancies closed + hidden, the driver profile off +
--    hidden, empty truck ads 'paused'.
--    Nothing is deleted: the rows stay (history, chats, payments), only
--    nobody sees them in the lists any more.
-- 2) admin_delete_user (0012) now hides ALL of the user's ads, not only
--    his new loads; users the admin deleted before get the same once.
-- 3) delete_my_account('DELETE'): a user deletes his own account from
--    Profil → Şəxsi məlumatlarım — the same as the admin's delete (name
--    "Silinmiş istifadəçi", phone / photo / birth date emptied, closed and
--    blocked, all ads hidden) and the sign-in is closed: the e-mail is
--    freed (a new account may use it), the Google link and the sessions are
--    removed, the login banned. Admins / the Founder cannot delete
--    themselves this way. Logged in the Audit Log (no personal data).
--
-- Safe: forward-only, re-runnable; no table dropped, no row deleted except
-- the auth sessions / identities of the account deleting itself.
-- =====================================================================

begin;

-- 1) Hide every ad of one user (server code only).
create or replace function public._hide_user_ads(p_user uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if p_user is null then return; end if;
  -- is_hidden (admin) + is_paused (the owner's own switch, 0061): the
  -- hidden flag is kept by its guard when the owner deletes himself.
  update cargo set is_hidden = true, is_paused = true where owner_id = p_user and (not is_hidden or not is_paused);
  perform set_config('app.market_trusted', '1', true);
  update market_listings set status = 'inactive', updated_at = now()
    where owner_id = p_user and status in ('draft', 'pending', 'active');
  update service_providers set status = 'suspended'
    where owner_id = p_user and status in ('pending', 'approved');
  if to_regclass('public.job_vacancies') is not null then
    execute 'update public.job_vacancies set is_hidden = true, status = ''closed'' where owner_id = $1 and (not is_hidden or status <> ''closed'')' using p_user;
  end if;
  if to_regclass('public.job_seeker_profiles') is not null then
    execute 'update public.job_seeker_profiles set is_hidden = true, is_active = false where user_id = $1 and (not is_hidden or is_active)' using p_user;
  end if;
  if to_regclass('public.empty_truck_ads') is not null then
    execute 'update public.empty_truck_ads set status = ''paused'', updated_at = now() where owner_id = $1 and status = ''active''' using p_user;
  end if;
end;
$$;
revoke all on function public._hide_user_ads(uuid) from public, anon, authenticated;

-- 2) The admin's delete hides everything.
create or replace function public.admin_delete_user(p_user uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb;
begin
  perform public._require_admin();
  if p_user = auth.uid() then raise exception 'cannot_delete_self'; end if;
  select to_jsonb(u) into v_old from users u where u.id = p_user;
  if v_old is null then raise exception 'not_found'; end if;
  perform public._admin_log('user.delete', 'user', p_user::text, v_old, null, p_reason);
  update users set
    full_name = 'Silinmiş istifadəçi',
    phone = null,
    avatar_url = null,
    is_active = false,
    is_blocked = true,
    block_reason = coalesce(nullif(p_reason,''), 'deleted'),
    updated_at = now()
  where id = p_user;
  perform public._hide_user_ads(p_user);
end;
$$;
grant execute on function public.admin_delete_user(uuid, text) to authenticated;

-- Users deleted before: their ads go too (once; re-running changes nothing).
do $$
declare r record;
begin
  for r in select id from public.users
           where full_name = 'Silinmiş istifadəçi' and not is_active and is_blocked loop
    perform public._hide_user_ads(r.id);
  end loop;
end $$;

-- 3) A user deletes his own account.
create or replace function public.delete_my_account(p_confirm text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_mail text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_confirm is distinct from 'DELETE' then raise exception 'confirm_required' using errcode = '22023'; end if;
  if not exists (select 1 from users where id = v_uid) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if public.is_admin() or public.is_founder(v_uid) then
    raise exception 'admin_cannot_delete' using errcode = '42501';
  end if;

  perform public._admin_log('account.self_delete', 'user', v_uid::text, null, null, 'self');
  v_mail := 'deleted-' || v_uid::text || '@deleted.tirlink.app';
  -- The ads first: a blocked account may not change its own rows.
  perform public._hide_user_ads(v_uid);

  update users set
    full_name = 'Silinmiş istifadəçi',
    email = v_mail,
    phone = null,
    avatar_url = null,
    birth_date = null,
    is_active = false,
    is_blocked = true,
    block_reason = 'self_deleted',
    updated_at = now()
  where id = v_uid;

  -- The sign-in is closed and the e-mail freed.
  update auth.users set email = v_mail, raw_user_meta_data = '{}'::jsonb, updated_at = now() where id = v_uid;
  if exists (select 1 from information_schema.columns
             where table_schema = 'auth' and table_name = 'users' and column_name = 'banned_until') then
    execute 'update auth.users set banned_until = ''infinity'' where id = $1' using v_uid;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'auth' and table_name = 'users' and column_name = 'phone') then
    execute 'update auth.users set phone = null where id = $1' using v_uid;
  end if;
  if to_regclass('auth.identities') is not null then
    execute 'delete from auth.identities where user_id = $1' using v_uid;
  end if;
  if to_regclass('auth.sessions') is not null then
    execute 'delete from auth.sessions where user_id = $1' using v_uid;
  end if;
end;
$$;
revoke all on function public.delete_my_account(text) from public, anon;
grant execute on function public.delete_my_account(text) to authenticated;

commit;

notify pgrst, 'reload schema';
