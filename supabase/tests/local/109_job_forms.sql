-- İŞ MƏRKƏZİ — forms of pictures 2 and 3 (0072). Rolled back.
\set emp '''a0000000-0000-4000-8000-000000000012'''
\set drv '''a0000000-0000-4000-8000-000000000013'''

begin;
set role authenticated;
select tests.login(:emp);
select tests.check((select count(*) = 4 from public.job_skills where code in ('lic_d1', 'lic_c1e', 'lic_d1e', 'lic_de') and kind = 'license'),
  'F1 D1, C1E, D1E, DE added');
select tests.check((select count(*) = 5 from public.job_skills where code in ('lic_b', 'lic_c1', 'lic_c', 'lic_ce', 'lic_d')),
  'F2 B, C1, C, CE, D kept');
select tests.check(exists (select 1 from public.job_skills where code = 'idp' and kind = 'document'), 'F3 international licence is a document');
select tests.check(exists (select 1 from public.job_specialties where code = 'open')
                   and not exists (select 1 from public.job_specialties where code in ('groupage', 'qrupaj')),
  'F4 Açıq added, QRUPAJ is not a vehicle');
insert into public.job_vacancies (id, owner_id, company_name, specialties, schedule, age_min, age_max, salary_negotiable, countries)
values ('10720000-0000-4000-8000-000000000001', :emp, 'Forma', '{tent,open}', 'long_haul', 25, 45, true, '{Azerbaijan,"European Union"}');
select tests.check((select age_min = 25 and age_max = 45 and salary_negotiable and schedule = 'long_haul'
                      from public.job_vacancies where id = '10720000-0000-4000-8000-000000000001'),
  'F5 age range, Danışılacaq, Uzun marşrut saved');
select tests.check(tests.err($$ update public.job_vacancies set age_min = 50, age_max = 30 where id = '10720000-0000-4000-8000-000000000001' $$)
  like '%check constraint%', 'F6 age range checked');
select tests.check(tests.err($$ update public.job_vacancies set schedule = 'sometimes' where id = '10720000-0000-4000-8000-000000000001' $$)
  like '%check constraint%', 'F7 İş rejimi still checked');
update public.job_vacancies set schedule = 'rotation' where id = '10720000-0000-4000-8000-000000000001';
select tests.check((select schedule = 'rotation' from public.job_vacancies where id = '10720000-0000-4000-8000-000000000001'),
  'F8 older values still valid');

select tests.login(:drv);
insert into public.job_seeker_profiles (user_id, full_name, schedule, salary_negotiable, skills, specialties)
values (:drv, 'Sürücü', 'regional', true, '{"lic_c1e":"yes","idp":"yes"}', '{open}')
on conflict (user_id) do update set schedule = excluded.schedule, salary_negotiable = excluded.salary_negotiable, skills = excluded.skills;
select tests.check((select schedule = 'regional' and salary_negotiable from public.job_seeker_profiles where user_id = :drv),
  'F9 driver: Regional, Danışılacaq');
select tests.check((select (e ->> 'age_min')::int = 25 and (e ->> 'salary_negotiable')::boolean and (e ->> 'phone') is null
                      from jsonb_array_elements(public.job_vacancies_list()) e where e ->> 'id' = '10720000-0000-4000-8000-000000000001'),
  'F10 the list carries age range / Danışılacaq; the phone stays hidden');
select tests.login(:emp);
select tests.check((select (e ->> 'salary_negotiable')::boolean and (e ->> 'phone') is null
                      from jsonb_array_elements(public.job_seekers_list()) e where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000013'),
  'F11 the drivers list carries Danışılacaq; the phone stays hidden');
reset role;
select tests.summary('İŞ MƏRKƏZİ FORMALAR (0072)');
rollback;
