-- =====================================================================
-- 0055 — Load categories: big / small loads and QRUPAJ (owner, 21.10.2026)
--
-- One load pool (public.cargo) — no second table for loads.
-- * cargo.load_size: 'big' | 'small'; NULL = not known. Loads posted
--   before 0055 stay NULL: no size is guessed for them; they are shown in
--   the general list only.
-- * cargo.groupage: QRUPAJ, a load category (NOT a truck type). A
--   groupage load is always a small load — set here, on the server.
-- * Indexes for the Loads page filters (open loads by truck type, by
--   size, groupage).
-- * cargo_size_cards: the pictures of the "Böyük yüklər" / "Kiçik yüklər"
--   cards. Everybody signed in reads them; only an admin changes them
--   (admin_set_cargo_size_card, checked on the server, logged).
--
-- Safe: forward-only, re-runnable. New nullable / default-false columns,
-- new indexes, one new table and function. No row is changed or deleted
-- (the trigger only acts on rows saved from now on).
-- =====================================================================

alter table public.cargo add column if not exists load_size text;
alter table public.cargo add column if not exists groupage boolean not null default false;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'cargo_load_size_check') then
    alter table public.cargo add constraint cargo_load_size_check check (load_size is null or load_size in ('big', 'small'));
  end if;
end $$;

-- QRUPAJ is always small, whatever the app sends.
create or replace function public.zz_cargo_groupage_small()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.groupage then new.load_size := 'small'; end if;
  return new;
end $$;
drop trigger if exists zz_cargo_groupage_small on public.cargo;
create trigger zz_cargo_groupage_small before insert or update on public.cargo
  for each row execute function public.zz_cargo_groupage_small();

-- Loads page: open loads, newest first, by truck type / size / groupage.
create index if not exists idx_cargo_open_truck on public.cargo (status, truck_type, created_at desc);
create index if not exists idx_cargo_open_size on public.cargo (status, load_size, created_at desc) where load_size is not null;
create index if not exists idx_cargo_open_groupage on public.cargo (status, created_at desc) where groupage;

-- Pictures of the big / small cards ------------------------------------------
create table if not exists public.cargo_size_cards (
  size text primary key check (size in ('big', 'small')),
  image_url text check (image_url is null or char_length(image_url) <= 1000),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on delete set null
);
alter table public.cargo_size_cards enable row level security;
revoke all on public.cargo_size_cards from anon, authenticated;
grant select on public.cargo_size_cards to authenticated;
drop policy if exists "cargo_size_cards_read" on public.cargo_size_cards;
create policy "cargo_size_cards_read" on public.cargo_size_cards for select to authenticated using (true);

-- Admins only: set (or, with NULL, remove) the picture of one card.
create or replace function public.admin_set_cargo_size_card(p_size text, p_image_url text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old jsonb; v_new jsonb;
begin
  perform public._require_admin();
  if p_size is null or p_size not in ('big', 'small') then raise exception 'invalid_argument' using errcode = '22023'; end if;
  select to_jsonb(c) into v_old from cargo_size_cards c where size = p_size;
  insert into cargo_size_cards (size, image_url, updated_at, updated_by)
  values (p_size, nullif(btrim(p_image_url), ''), now(), auth.uid())
  on conflict (size) do update set image_url = excluded.image_url, updated_at = now(), updated_by = auth.uid();
  select to_jsonb(c) into v_new from cargo_size_cards c where size = p_size;
  perform public._admin_log('cargo.size_card', 'cargo_size_card', p_size, v_old, v_new);
  return v_new;
end $$;
revoke all on function public.admin_set_cargo_size_card(text, text) from public, anon;
grant execute on function public.admin_set_cargo_size_card(text, text) to authenticated;

notify pgrst, 'reload schema';
