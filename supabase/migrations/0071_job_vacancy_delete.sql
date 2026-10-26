-- =====================================================================
-- 0071 — İş Mərkəzi: the owner deletes a vacancy from the profile
-- (owner, 27.10.2026)
--
-- "Sil" marks the vacancy status = 'deleted' (no row is removed, so the
-- drivers' applications to it are kept). A deleted vacancy is no longer
-- in the owner's list, in job_vacancies_list() (active only) or in
-- matching; nobody can apply to it (job_application_send needs
-- 'active'). Only an admin can bring it back.
--
-- Safe: forward-only, re-runnable. One check constraint widened, one
-- guard trigger added. No row is changed or deleted.
-- =====================================================================

begin;

alter table public.job_vacancies drop constraint if exists job_vacancies_status_check;
alter table public.job_vacancies add constraint job_vacancies_status_check
  check (status in ('active', 'closed', 'deleted'));

create or replace function public.job_vacancy_deleted_guard()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if old.status = 'deleted' and not public.is_admin() then
    raise exception 'vacancy_deleted' using errcode = '22023';
  end if;
  return new;
end $$;
revoke all on function public.job_vacancy_deleted_guard() from public, anon, authenticated;

drop trigger if exists zz_job_vacancy_deleted_guard on public.job_vacancies;
create trigger zz_job_vacancy_deleted_guard before update on public.job_vacancies
  for each row execute function public.job_vacancy_deleted_guard();

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'zz_job_vacancy_deleted_guard') then
    raise exception '0071: final check failed — nothing changed';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
