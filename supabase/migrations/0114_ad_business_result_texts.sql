-- =====================================================================
-- 0114 — UTEP Reklam: the owner writes the day's result message
-- (owner, 10.11.2026: "Bu paneldeki yazini redakte ede bilmirem").
--
-- Run AFTER 0113.
--
-- The company's owner (and the Baş admin) writes what the worker sees when
-- a day closes below the target (adbiz_companies.result_miss_text) and at /
-- over it (result_hit_text). {qalan}, {gəlir} and {hədəf} in the text are
-- replaced in the app by the day's numbers. Empty = the app's own words.
-- adbiz_company_result_texts_save — owner / Baş admin, audited.
--
-- Safe: forward-only, re-runnable. Two nullable columns, one function.
-- Nothing deleted or rewritten.
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.adbiz_company_texts_save(uuid, text, text)') is null then
    raise exception '0114: run 0113 first — nothing changed';
  end if;
end $$;

alter table public.adbiz_companies add column if not exists result_miss_text text;
alter table public.adbiz_companies add column if not exists result_hit_text text;
alter table public.adbiz_companies enable row level security;

create or replace function public.adbiz_company_result_texts_save(p_company uuid, p_miss text, p_hit text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_old adbiz_companies; v_miss text := public._adbiz_text(p_miss, 200); v_hit text := public._adbiz_text(p_hit, 200);
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if not public.adbiz_can_manage(p_company) then raise exception 'not_allowed' using errcode = '42501'; end if;
  select * into v_old from adbiz_companies where id = p_company for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  update adbiz_companies set result_miss_text = v_miss, result_hit_text = v_hit, updated_at = now() where id = p_company;
  perform public._adbiz_log(p_company, 'company.result_texts', 'company', p_company::text,
    jsonb_build_object('result_miss_text', v_old.result_miss_text, 'result_hit_text', v_old.result_hit_text),
    jsonb_build_object('result_miss_text', v_miss, 'result_hit_text', v_hit));
end $$;
revoke all on function public.adbiz_company_result_texts_save(uuid, text, text) from public, anon;
grant execute on function public.adbiz_company_result_texts_save(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';
commit;
