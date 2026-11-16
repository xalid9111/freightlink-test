-- =====================================================================
-- 0126 — UTEP Reklam: the Baş admin deletes a company by a long press
-- (owner, 16.11.2026: "şirkətləri basıb saxlayaraq silə bilməliyəm";
-- chosen way A: off the list, its people lose access, its data stays).
--
--   * adbiz_companies.deleted_at: set once by adbiz_admin_company_delete
--     (Baş admin only, _adbiz_require_chief); the company is also switched
--     off (is_active = false), so its owner / workers lose the module at
--     once (every check already needs c.is_active).
--   * Nothing is deleted: days, jobs, rasxod, expenses, the old account and
--     the history stay in the database; the whole company row is kept in
--     adbiz_audit ('company.delete'). Brought back only in the SQL editor.
--   * A deleted company cannot be switched on again or get new people.
--
-- Safe: forward-only, re-runnable; one column, one new function, two
-- functions replaced with the same body + the deleted check.
-- =====================================================================

begin;

alter table public.adbiz_companies add column if not exists deleted_at timestamptz;

create or replace function public.adbiz_admin_company_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_companies;
begin
  perform public._adbiz_require_chief();
  select * into v_old from adbiz_companies where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_old.deleted_at is not null then return; end if; -- a second tap: already done
  update adbiz_companies set deleted_at = now(), is_active = false, updated_at = now() where id = p_id;
  perform public._adbiz_log(p_id, 'company.delete', 'company', p_id::text, to_jsonb(v_old),
    jsonb_build_object('deleted_at', now(), 'is_active', false));
end $$;

-- 0110's switch, refusing a deleted company.
create or replace function public.adbiz_admin_company_set_active(p_id uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old boolean; v_deleted timestamptz;
begin
  perform public._adbiz_require_chief();
  select is_active, deleted_at into v_old, v_deleted from adbiz_companies where id = p_id for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  if v_deleted is not null then raise exception 'company_deleted' using errcode = 'P0001'; end if;
  update adbiz_companies set is_active = coalesce(p_on, false), updated_at = now() where id = p_id;
  perform public._adbiz_log(p_id, 'company.active', 'company', p_id::text,
    jsonb_build_object('is_active', v_old), jsonb_build_object('is_active', coalesce(p_on, false)));
end $$;

-- 0110's member_set, refusing a deleted company.
create or replace function public.adbiz_admin_member_set(p_user uuid, p_company uuid, p_role text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_members;
begin
  perform public._adbiz_require_chief();
  if p_role not in ('owner', 'worker') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  if not exists (select 1 from users where id = p_user) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if not exists (select 1 from adbiz_companies where id = p_company) then raise exception 'not_found' using errcode = 'P0002'; end if;
  if exists (select 1 from adbiz_companies where id = p_company and deleted_at is not null) then
    raise exception 'company_deleted' using errcode = 'P0001';
  end if;
  select * into v_old from adbiz_members where user_id = p_user for update;
  insert into adbiz_members (user_id, company_id, role, is_active, added_by)
  values (p_user, p_company, p_role, true, auth.uid())
  on conflict (user_id) do update set company_id = excluded.company_id, role = excluded.role,
    is_active = true, updated_at = now();
  perform public._adbiz_log(p_company, case when v_old.user_id is null then 'member.add' else 'member.change' end,
    'member', p_user::text,
    case when v_old.user_id is null then null
      else jsonb_build_object('company_id', v_old.company_id, 'role', v_old.role, 'is_active', v_old.is_active) end,
    jsonb_build_object('company_id', p_company, 'role', p_role, 'is_active', true));
end $$;

revoke all on function public.adbiz_admin_company_delete(uuid) from public, anon;
grant execute on function public.adbiz_admin_company_delete(uuid) to authenticated;
revoke all on function public.adbiz_admin_company_set_active(uuid, boolean) from public, anon;
grant execute on function public.adbiz_admin_company_set_active(uuid, boolean) to authenticated;
revoke all on function public.adbiz_admin_member_set(uuid, uuid, text) from public, anon;
grant execute on function public.adbiz_admin_member_set(uuid, uuid, text) to authenticated;

commit;

notify pgrst, 'reload schema';
