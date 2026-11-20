-- =====================================================================
-- 0132 — UTEP Reklam: the worker changes a job's price on his own day
-- (owner, 20.11.2026: "işçi yazının qiymətini həmin gün üçün dəyişə
-- bilsin. Dəyişdikdən sonra səbəb yazıb OK"; the field is called "Qeyd").
--   * adbiz_entry_worker_fix(entry, amount, note): ONLY the job's own
--     worker, ONLY on his own today's open day (the same check as adding a
--     job: _adbiz_day_writable without the manager part); the note is
--     required (3–200 letters). Only the amount changes, never the name.
--   * The job keeps what it was: fixed_from = its first price (kept over
--     several fixes), fix_note, fixed_at, fixed_by — shown as "düzəldildi
--     (40 → 35)" with the note; every fix is in adbiz_audit
--     ('entry.worker_fix': old / new / note / who / when).
--   * The owner / Baş admin keep adbiz_update_entry as before; a closed or
--     past day stays theirs only.
-- Safe: forward-only, re-runnable; four nullable columns, one new
-- function; nothing changed or deleted.
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.adbiz_entries') is null then
    raise exception '0132: run 0110–0113 (UTEP Reklam) first — nothing changed';
  end if;
end $$;

alter table public.adbiz_entries add column if not exists fixed_from numeric(14,2);
alter table public.adbiz_entries add column if not exists fix_note text;
alter table public.adbiz_entries add column if not exists fixed_at timestamptz;
alter table public.adbiz_entries add column if not exists fixed_by uuid references public.users(id) on delete set null;

create or replace function public.adbiz_entry_worker_fix(p_entry uuid, p_amount numeric, p_note text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare e adbiz_entries; d adbiz_days; v_note text := btrim(coalesce(p_note, ''));
begin
  if auth.uid() is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 1000000 then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if char_length(v_note) < 3 or char_length(v_note) > 200 then
    raise exception 'note_required' using errcode = '22023';
  end if;
  select * into e from adbiz_entries where id = p_entry for update;
  if not found then raise exception 'not_found' using errcode = 'P0002'; end if;
  select * into d from adbiz_days where id = e.day_id for update;
  if not coalesce(d.user_id = auth.uid() and e.user_id = auth.uid()
                  and public.adbiz_my_company() = d.company_id, false) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if d.status <> 'open' or d.work_date <> public._adbiz_today() then
    raise exception 'day_closed' using errcode = '42501';
  end if;
  if round(p_amount, 2) = e.amount then return; end if; -- nothing to change
  update adbiz_entries
     set amount = round(p_amount, 2),
         fixed_from = coalesce(fixed_from, e.amount),
         fix_note = v_note, fixed_at = now(), fixed_by = auth.uid(), updated_at = now()
   where id = p_entry;
  perform public._adbiz_log(e.company_id, 'entry.worker_fix', 'entry', p_entry::text,
    jsonb_build_object('title', e.title, 'amount', e.amount),
    jsonb_build_object('title', e.title, 'amount', round(p_amount, 2), 'note', v_note));
end $$;
revoke all on function public.adbiz_entry_worker_fix(uuid, numeric, text) from public, anon;
grant execute on function public.adbiz_entry_worker_fix(uuid, numeric, text) to authenticated;

commit;

notify pgrst, 'reload schema';
