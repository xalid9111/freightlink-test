-- İŞ MƏRKƏZİ — "Vakansiya yerləşdir" in 4 steps (0070). Rolled back.
\set emp  '''a0000000-0000-4000-8000-000000000012'''
\set drv  '''a0000000-0000-4000-8000-000000000013'''

begin;
set role authenticated;
select tests.login(:emp);
select tests.check((select count(*) = 3 from public.job_skills where (code, kind) in (('adr', 'document'), ('route_mix', 'skill'), ('night', 'skill'))),
  'W1 ADR sertifikatı, Yük qısa/uzun marşrut, Gecə sürüşü in the catalogue');
insert into public.job_vacancies (id, owner_id, company_name, job_type, schedule, requirements, can_help, min_experience, countries,
                                  salary_min, salary_max, currency)
values ('10700000-0000-4000-8000-000000000001', :emp, 'Wizard Trans', 'tir', 'project',
        '{"lic_ce":"must","cpc":"must","tachograph":"must","intl_exp":"nice","night":"nice"}', '{}', 3,
        '{Azerbaijan,Turkey}', 1500, 2500, 'AZN');
select tests.check((select job_type = 'tir' and schedule = 'project' from public.job_vacancies where id = '10700000-0000-4000-8000-000000000001'),
  'W2 İş növü TIR and "Layihə əsasında" are saved');
insert into public.job_vacancies (id, owner_id, company_name, job_type)
values ('10700000-0000-4000-8000-000000000002', :emp, 'Digər işçi', 'other');
insert into public.job_vacancies (id, owner_id, company_name)
values ('10700000-0000-4000-8000-000000000003', :emp, 'Köhnə forma');
select tests.check((select job_type is null from public.job_vacancies where id = '10700000-0000-4000-8000-000000000003'),
  'W3 İş növü is optional (older vacancies stay as they are)');
select tests.check(tests.err($$ update public.job_vacancies set job_type = 'boss' where id = '10700000-0000-4000-8000-000000000002' $$)
  like '%check constraint%', 'W4 only tir / other');
select tests.check(tests.err($$ update public.job_vacancies set schedule = 'sometimes' where id = '10700000-0000-4000-8000-000000000002' $$)
  like '%check constraint%', 'W5 schedule is still checked');
select tests.check((select bool_and(e ->> 'schedule' in ('full_time', 'part_time', 'rotation', 'flexible', 'project') or e ->> 'schedule' is null)
                      from jsonb_array_elements(public.job_vacancies_list()) e), 'W6 the list keeps working');

select tests.login(:drv);
select tests.check((select e ->> 'job_type' = 'tir' and (e ->> 'phone') is null
                      from jsonb_array_elements(public.job_vacancies_list()) e where e ->> 'id' = '10700000-0000-4000-8000-000000000001'),
  'W7 others see İş növü (the phone stays hidden)');
insert into public.job_seeker_profiles (user_id, full_name, schedule, skills)
values (:drv, 'Sürücü', 'project', '{"adr":"yes","night":"no"}')
on conflict (user_id) do update set schedule = excluded.schedule, skills = excluded.skills;
select tests.check((select schedule = 'project' and skills ->> 'adr' = 'yes' from public.job_seeker_profiles where user_id = :drv),
  'W8 a driver can answer the new documents / skills and pick "Layihə əsasında"');
reset role;
select tests.summary('VAKANSİYA SİHİRBAZI (0070)');
rollback;
