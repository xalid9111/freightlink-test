-- =====================================================================
-- 0063 — Six new load types (owner, 25.10.2026)
--
-- Qazel · Manipulyator · Evakuator · Furqon · Lowbed · Avtodaşıyıcı
-- (codes gazelle, manipulator, tow_truck, van, lowbed, car_carrier) join
-- the 7 existing ones (tent, ref, container, dump, groupage, open, tanker).
--
-- * public.cargo.truck_type is free text without a check — loads with the
--   new codes need no change here.
-- * Only the admin's template pictures were limited to the 7 types
--   (0058): the category check of cargo_image_templates and the admin
--   function admin_add_cargo_image_template now accept all 13.
--
-- Safe: forward-only, re-runnable. No table, column, row, policy or grant
-- is removed; no existing row is changed. Only the 0058 7-type check is
-- replaced by the 13-type check, in one step (every existing row passes);
-- every other constraint stays untouched.
-- =====================================================================

-- Exactly one constraint is replaced: cargo_image_templates_category_check
-- (the name Postgres gave the 7-type check of 0058), and only while its
-- rule is exactly the 0058 rule. No other constraint is looked at.
--   * already the 13-type rule  -> nothing to do (re-run is safe);
--   * exactly the 0058 rule     -> dropped and re-added with 13 types,
--                                  in one transaction;
--   * anything else / missing   -> stop with an error, nothing changed.
do $$
declare
  v_old constant text := 'CHECK ((category = ANY (ARRAY[''tent''::text, ''ref''::text, ''container''::text, ''dump''::text, ''groupage''::text, ''open''::text, ''tanker''::text])))';
  v_new constant text := 'CHECK ((category = ANY (ARRAY[''tent''::text, ''ref''::text, ''container''::text, ''dump''::text, ''groupage''::text, ''open''::text, ''tanker''::text, ''gazelle''::text, ''manipulator''::text, ''tow_truck''::text, ''van''::text, ''lowbed''::text, ''car_carrier''::text])))';
  v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conrelid = 'public.cargo_image_templates'::regclass
     and c.conname = 'cargo_image_templates_category_check'
     and c.contype = 'c';
  if v_def = v_new then
    return;
  end if;
  if v_def is distinct from v_old then
    raise exception '0063: cargo_image_templates_category_check is not the 0058 rule (found: %) — nothing changed', coalesce(v_def, 'none');
  end if;
  alter table public.cargo_image_templates drop constraint cargo_image_templates_category_check;
  alter table public.cargo_image_templates add constraint cargo_image_templates_category_check
    check (category in ('tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker',
                        'gazelle', 'manipulator', 'tow_truck', 'van', 'lowbed', 'car_carrier'));
end $$;

-- Admins only: add one picture (at most 10 per load type). Same as 0058,
-- only the list of load types is longer.
create or replace function public.admin_add_cargo_image_template(p_category text, p_image_url text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_row cargo_image_templates; v_n integer;
begin
  perform public._require_admin();
  if p_category is null or p_category not in ('tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker',
                                             'gazelle', 'manipulator', 'tow_truck', 'van', 'lowbed', 'car_carrier') then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  -- One admin at a time per load type, so the limit holds.
  perform pg_advisory_xact_lock(hashtext('cargo_image_templates:' || p_category));
  select count(*) into v_n from cargo_image_templates where category = p_category;
  if v_n >= 10 then raise exception 'template_limit' using errcode = '22023'; end if;
  insert into cargo_image_templates (category, image_url, sort_order, created_by)
  values (p_category, btrim(p_image_url), v_n, auth.uid())
  returning * into v_row;
  perform public._admin_log('cargo.template_add', 'cargo_image_template', v_row.id::text, null, to_jsonb(v_row));
  return to_jsonb(v_row);
end $$;

revoke all on function public.admin_add_cargo_image_template(text, text) from public, anon;
grant execute on function public.admin_add_cargo_image_template(text, text) to authenticated;
