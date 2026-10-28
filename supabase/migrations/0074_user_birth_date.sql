-- =====================================================================
-- 0074 — Age at registration and in Profil (owner, 28.10.2026)
--
-- "Yaş" is picked at registration (required) and can be set / changed in
-- Profil. Stored as users.birth_date (1 January of the year the picked
-- age gives, so the age grows by itself every year). It is private: the
-- public view user_profiles (0019) does not show it; only the user and
-- admins read their row (users_select_own / users_admin_full).
--
-- * New nullable column users.birth_date — older accounts stay without
--   it until they set it in Profil.
-- * A check (trigger): 16 – 100 years old.
-- * The signup trigger (0018) also stores the birth date sent with the
--   signup data; everything else in it is unchanged (only self-service
--   roles, default cargo_owner).
--
-- Safe: forward-only, re-runnable. No row is changed or deleted.
-- =====================================================================

begin;

alter table public.users add column if not exists birth_date date;

create or replace function public.users_birth_date_check()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.birth_date is not null
     and (new.birth_date > (current_date - interval '16 years')::date
          or new.birth_date < (current_date - interval '100 years')::date) then
    raise exception 'invalid_birth_date' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.users_birth_date_check() from public, anon, authenticated;

drop trigger if exists zz_users_birth_date_check on public.users;
create trigger zz_users_birth_date_check
  before insert or update of birth_date on public.users
  for each row execute function public.users_birth_date_check();

-- Signup: the same as 0018, plus the birth date (ignored if it is not a
-- plain YYYY-MM-DD date or out of range, so a signup never fails on it).
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := new.raw_user_meta_data->>'role';
  v_birth_text text := new.raw_user_meta_data->>'birth_date';
  v_birth date;
begin
  -- Only self-service roles are accepted from signup metadata.
  -- 'admin' (or anything unknown) silently becomes the default role.
  if v_role is null or v_role not in ('cargo_owner', 'carrier', 'driver') then
    v_role := 'cargo_owner';
  end if;
  if v_birth_text ~ '^\d{4}-\d{2}-\d{2}$' then
    begin
      v_birth := v_birth_text::date;
    exception when others then
      v_birth := null;
    end;
    if v_birth > (current_date - interval '16 years')::date
       or v_birth < (current_date - interval '100 years')::date then
      v_birth := null;
    end if;
  end if;
  insert into public.users (id, email, full_name, role, phone, birth_date)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    v_role,
    new.raw_user_meta_data->>'phone',
    v_birth
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'users' and column_name = 'birth_date')
     or exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'birth_date') then
    raise exception '0074: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
