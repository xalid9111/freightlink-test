-- 0035 — Catalog photo order (drag & drop in "Kataloq").
--
-- Forward-only, re-runnable, no data rewritten: existing photos keep
-- sort_order = NULL and are shown exactly as before (newest first) until
-- their owner saves a new order. Run once in the Supabase SQL editor.
--
-- Order everybody sees: sort_order ascending, photos without a saved
-- position (new uploads) first, newest first among them.

alter table public.profile_catalog_items add column if not exists sort_order integer;

do $$ begin
  alter table public.profile_catalog_items
    add constraint profile_catalog_items_sort_order_check check (sort_order is null or sort_order between 0 and 999);
exception when duplicate_object then null;
end $$;

create index if not exists profile_catalog_items_user_sort_idx
  on public.profile_catalog_items (user_id, sort_order);

-- Save the owner's new order in one step. p_ids must be exactly the
-- caller's own photos, each once: nothing can be lost, duplicated or
-- taken from another user. If a photo was added or deleted meanwhile
-- (other device), nothing is changed and 'catalog_order_mismatch' is
-- raised so the app reloads and the user saves again.
create or replace function public.reorder_catalog(p_ids uuid[])
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_n integer;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 60 then
    raise exception 'catalog_order_mismatch' using errcode = '22023';
  end if;
  if (select count(distinct x) from unnest(p_ids) x) <> cardinality(p_ids) then
    raise exception 'catalog_order_mismatch' using errcode = '22023';
  end if;

  -- Lock the owner's rows so a parallel add/delete waits for this step.
  perform 1 from public.profile_catalog_items where user_id = v_uid for update;

  select count(*) into v_n from public.profile_catalog_items where user_id = v_uid;
  if v_n <> cardinality(p_ids)
     or exists (select 1 from unnest(p_ids) x
                where not exists (select 1 from public.profile_catalog_items c where c.id = x and c.user_id = v_uid)) then
    raise exception 'catalog_order_mismatch' using errcode = '22023';
  end if;

  update public.profile_catalog_items c
     set sort_order = o.pos - 1
    from unnest(p_ids) with ordinality as o(id, pos)
   where c.id = o.id and c.user_id = v_uid;
  return v_n;
end $$;

revoke all on function public.reorder_catalog(uuid[]) from public, anon;
grant execute on function public.reorder_catalog(uuid[]) to authenticated;
