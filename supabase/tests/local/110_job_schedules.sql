-- İŞ MƏRKƏZİ — several İş rejimi at once (0073). Rolled back.
\set emp '''a0000000-0000-4000-8000-000000000012'''
\set drv '''a0000000-0000-4000-8000-000000000013'''

begin;
set role authenticated;
select tests.login(:emp);
insert into public.job_vacancies (id, owner_id, company_name, schedule, schedules)
values ('10730000-0000-4000-8000-000000000001', :emp, 'Rejim', 'permanent', '{permanent,long_haul,regional}');
select tests.check((select schedules = '{permanent,long_haul,regional}' and schedule = 'permanent'
                      from public.job_vacancies where id = '10730000-0000-4000-8000-000000000001'),
  'S1 a vacancy keeps 3 work modes (and the first one in the old column)');
select tests.check(tests.err($$ update public.job_vacancies set schedules = '{permanent,sometimes}' where id = '10730000-0000-4000-8000-000000000001' $$)
  like '%check constraint%', 'S2 only known work modes');
insert into public.job_vacancies (id, owner_id, company_name, schedule)
values ('10730000-0000-4000-8000-000000000002', :emp, 'Köhnə', 'rotation');
select tests.check((select schedules = '{}' and schedule = 'rotation' from public.job_vacancies where id = '10730000-0000-4000-8000-000000000002'),
  'S3 a vacancy without the list keeps its single value');

select tests.login(:drv);
insert into public.job_seeker_profiles (user_id, full_name, schedule, schedules)
values (:drv, 'Sürücü', 'temporary', '{temporary,regional}')
on conflict (user_id) do update set schedule = excluded.schedule, schedules = excluded.schedules;
select tests.check((select schedules = '{temporary,regional}' from public.job_seeker_profiles where user_id = :drv),
  'S4 a driver keeps 2 work modes');
select tests.check((select (e -> 'schedules') = '["permanent","long_haul","regional"]'::jsonb and (e ->> 'phone') is null
                      from jsonb_array_elements(public.job_vacancies_list()) e where e ->> 'id' = '10730000-0000-4000-8000-000000000001'),
  'S5 the vacancies list returns them (phone still hidden)');
select tests.login(:emp);
select tests.check((select (e -> 'schedules') = '["temporary","regional"]'::jsonb
                      from jsonb_array_elements(public.job_seekers_list()) e where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000013'),
  'S6 the drivers list returns them');
reset role;
select tests.summary('İŞ REJİMİ BİR NEÇƏ (0073)');
rollback;
