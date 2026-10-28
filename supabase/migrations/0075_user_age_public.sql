-- =====================================================================
-- 0075 — Age (years only) on other users' profiles (owner, 28.10.2026)
--
-- "Yaş tarix olaraq yox, sadəcə yaş olaraq görünsün": a signed-in user
-- sees another user's age as a number ("48 yaş"); the birth date itself
-- stays private (users.birth_date, 0074; not in user_profiles).
-- Phone / e-mail keep the rules of get_user_contact (0019), unchanged.
--
-- * New function user_age(user) -> whole years, or null when the user
--   has not given a birth date. Signed-in users only.
--
-- Safe: forward-only, re-runnable. No table or row is changed.
-- =====================================================================

begin;

create or replace function public.user_age(p_user uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_birth date;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  select u.birth_date into v_birth from public.users u where u.id = p_user;
  if v_birth is null then
    return null;
  end if;
  return extract(year from age(current_date, v_birth))::integer;
end;
$$;

revoke execute on function public.user_age(uuid) from public, anon;
grant execute on function public.user_age(uuid) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';
