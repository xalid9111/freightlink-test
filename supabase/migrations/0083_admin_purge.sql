-- =====================================================================
-- 0083 — Admin: delete test data for good (owner, 02.11.2026).
--
-- The owner added fake profiles, loads, services, TIR Bazarı sale ads and
-- job ads to test the app. Admin → "Test məlumatlarını sil" removes one
-- of them completely, with everything that hangs on it. The owner chose
-- "Hamısını sil": a deleted user's account and sign-in, loads, services,
-- sale and job ads, messages and the chats he was in (also with real
-- people), comments, bookings and test payments all go. Only the admin
-- log keeps "who deleted what, when".
--
-- Nothing is deleted by running this file. It only creates functions; a
-- deletion happens only when an admin presses "Sil" and types SİL.
--
--   * admin_purge_list(kind, query, limit) — what can be deleted (search);
--   * admin_purge(kind, id, confirm) — deletes one item and everything
--     that depends on it, in one transaction (all or nothing). The server
--     checks: admin only (_require_admin), confirm = 'SİL', never oneself,
--     never the founder, never another admin (take the role first);
--   * _purge_rows(table, where) — internal: deletes the rows that point at
--     the item first (following the foreign keys), then the item. For a
--     user also what he owns but Postgres would only unlink: his services,
--     his driver row, the TIR parks he added.
--
-- kinds: user · cargo · service · market · job_vacancy · job_seeker
--
-- Pictures already uploaded to Storage are not removed by SQL (Supabase
-- does not allow it); nothing in the app shows them any more.
--
-- Safe: forward-only, re-runnable. Functions only. No table, column or
-- row is changed by running it.
-- =====================================================================

begin;

-- Internal: delete rows of p_table matching p_where, children first.
create or replace function public._purge_rows(p_table regclass, p_where text, p_depth integer default 0)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c record;
  n bigint;
begin
  if p_depth > 8 then raise exception 'purge_too_deep: %', p_table using errcode = '54001'; end if;
  for c in
    select con.conrelid::regclass as child, a.attname as col, af.attname as refcol
      from pg_constraint con
      join pg_attribute a on a.attrelid = con.conrelid and a.attnum = con.conkey[1]
      join pg_attribute af on af.attrelid = con.confrelid and af.attnum = con.confkey[1]
     where con.contype = 'f'
       and con.confrelid = p_table
       and cardinality(con.conkey) = 1
       and con.confdeltype in ('a', 'r', 'c')      -- no action / restrict / cascade (set null is left to Postgres)
       and con.conrelid <> p_table
  loop
    perform public._purge_rows(c.child,
      format('%I in (select %I from %s where %s)', c.col, c.refcol, p_table, p_where), p_depth + 1);
  end loop;
  execute format('delete from %s where %s', p_table, p_where);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public._purge_rows(regclass, text, integer) from public, anon, authenticated;

-- What can be deleted: newest first, with a search.
create or replace function public.admin_purge_list(p_kind text, p_query text default null, p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  q text := '%' || coalesce(nullif(btrim(p_query), ''), '') || '%';
  l integer := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  perform public._require_admin();
  return coalesce(case p_kind
    when 'user' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', u.id, 'title', u.full_name,
               'sub', concat_ws(' · ', u.email, u.phone, u.role), 'at', u.created_at) x
        from users u
       where u.full_name ilike q or u.email ilike q or coalesce(u.phone, '') ilike q
       order by u.created_at desc limit l) t)
    when 'cargo' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', c.id, 'title', concat(c.pickup_city, ' → ', c.destination_city),
               'sub', coalesce(u.full_name, ''), 'at', c.created_at) x
        from cargo c left join users u on u.id = c.owner_id
       where c.pickup_city ilike q or c.destination_city ilike q or coalesce(u.full_name, '') ilike q
       order by c.created_at desc limit l) t)
    when 'service' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', s.id, 'title', s.name,
               'sub', concat_ws(' · ', s.city, u.full_name), 'at', s.created_at) x
        from service_providers s left join users u on u.id = s.owner_id
       where s.name ilike q or coalesce(s.city, '') ilike q or coalesce(u.full_name, '') ilike q
       order by s.created_at desc limit l) t)
    when 'market' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', m.id, 'title', concat_ws(' ', '#' || m.listing_no, m.brand, m.model),
               'sub', coalesce(u.full_name, ''), 'at', m.created_at) x
        from market_listings m left join users u on u.id = m.owner_id
       where concat_ws(' ', m.listing_no, m.brand, m.model) ilike q or coalesce(u.full_name, '') ilike q
       order by m.created_at desc limit l) t)
    when 'job_vacancy' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', v.id, 'title', v.company_name,
               'sub', coalesce(u.full_name, ''), 'at', v.created_at) x
        from job_vacancies v left join users u on u.id = v.owner_id
       where v.company_name ilike q or coalesce(u.full_name, '') ilike q
       order by v.created_at desc limit l) t)
    when 'job_seeker' then (select jsonb_agg(x order by x ->> 'at' desc) from (
      select jsonb_build_object('id', p.user_id, 'title', coalesce(u.full_name, ''),
               'sub', coalesce(u.phone, u.email, ''), 'at', p.created_at) x
        from job_seeker_profiles p left join users u on u.id = p.user_id
       where coalesce(u.full_name, '') ilike q or coalesce(u.phone, '') ilike q
       order by p.created_at desc limit l) t)
    else null end, '[]'::jsonb);
end $$;
revoke all on function public.admin_purge_list(text, text, integer) from public, anon;
grant execute on function public.admin_purge_list(text, text, integer) to authenticated;

-- Delete one item completely (all or nothing).
create or replace function public.admin_purge(p_kind text, p_id uuid, p_confirm text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_table regclass;
  v_key text;
  v_old jsonb;
  n bigint;
begin
  perform public._require_admin();
  if p_confirm is distinct from 'SİL' then raise exception 'confirm_required' using errcode = '22023'; end if;
  if p_id is null then raise exception 'invalid_argument' using errcode = '22023'; end if;
  case p_kind
    when 'user' then v_table := 'public.users'; v_key := 'id';
    when 'cargo' then v_table := 'public.cargo'; v_key := 'id';
    when 'service' then v_table := 'public.service_providers'; v_key := 'id';
    when 'market' then v_table := 'public.market_listings'; v_key := 'id';
    when 'job_vacancy' then v_table := 'public.job_vacancies'; v_key := 'id';
    when 'job_seeker' then v_table := 'public.job_seeker_profiles'; v_key := 'user_id';
    else raise exception 'invalid_argument' using errcode = '22023';
  end case;

  execute format('select to_jsonb(t) from %s t where %I = $1', v_table, v_key) into v_old using p_id;
  if v_old is null then raise exception 'not_found' using errcode = 'P0002'; end if;

  if p_kind = 'user' then
    if p_id = auth.uid() then raise exception 'cannot_delete_self' using errcode = '42501'; end if;
    if public.is_founder(p_id) then raise exception 'founder_protected' using errcode = '42501'; end if;
    if v_old ->> 'role' = 'admin' then raise exception 'admin_protected' using errcode = '42501'; end if;
  end if;

  perform public._admin_log('purge.' || p_kind, p_kind, p_id::text,
    jsonb_strip_nulls(jsonb_build_object(
      'name', coalesce(v_old ->> 'full_name', v_old ->> 'name', v_old ->> 'company_name'),
      'email', v_old ->> 'email', 'phone', v_old ->> 'phone',
      'route', case when p_kind = 'cargo' then concat(v_old ->> 'pickup_city', ' → ', v_old ->> 'destination_city') end,
      'listing_no', v_old ->> 'listing_no', 'brand', v_old ->> 'brand', 'model', v_old ->> 'model',
      'owner_id', coalesce(v_old ->> 'owner_id', v_old ->> 'user_id'))),
    null, 'admin_purge');

  if p_kind = 'user' then
    -- What the profile owns but Postgres would only unlink (set null):
    -- its services, its driver row and the TIR parks it added.
    perform public._purge_rows('public.service_providers', format('owner_id = %L::uuid', p_id));
    perform public._purge_rows('public.drivers', format('user_id = %L::uuid', p_id));
    perform public._purge_rows('public.tir_parks', format('created_by = %L::uuid', p_id));
  end if;
  n := public._purge_rows(v_table, format('%I = %L::uuid', v_key, p_id));
  if p_kind = 'user' then
    -- The sign-in account too (Supabase Auth); anything left on it goes with it.
    delete from auth.users where id = p_id;
  end if;
  return jsonb_build_object('deleted', n, 'kind', p_kind, 'id', p_id);
end $$;
revoke all on function public.admin_purge(text, uuid, text) from public, anon;
grant execute on function public.admin_purge(text, uuid, text) to authenticated;

-- Final check.
do $$
begin
  if to_regprocedure('public.admin_purge(text, uuid, text)') is null
     or to_regprocedure('public.admin_purge_list(text, text, integer)') is null then
    raise exception '0083: final check failed — nothing changed';
  end if;
end $$;

commit;
