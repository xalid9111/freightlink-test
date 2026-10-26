-- İŞ MƏRKƏZİ — the owner deletes a vacancy (0071). Rolled back.
\set admin '''a0000000-0000-4000-8000-000000000001'''
\set emp   '''a0000000-0000-4000-8000-000000000012'''
\set emp2  '''a0000000-0000-4000-8000-000000000014'''
\set drv   '''a0000000-0000-4000-8000-000000000013'''

begin;
set role authenticated;
select tests.login(:drv);
insert into public.job_seeker_profiles (user_id, full_name) values (:drv, 'Sürücü') on conflict (user_id) do nothing;
select tests.login(:emp);
insert into public.job_vacancies (id, owner_id, company_name, specialties)
values ('10710000-0000-4000-8000-000000000001', :emp, 'Silinəcək', '{ref}');
select tests.login(:drv);
select public.job_application_send('10710000-0000-4000-8000-000000000001', null, 'Salam');
select tests.check((select count(*) = 1 from public.job_applications where vacancy_id = '10710000-0000-4000-8000-000000000001'),
  'D1 a driver applied');

select tests.login(:emp2);
update public.job_vacancies set status = 'deleted' where id = '10710000-0000-4000-8000-000000000001';
select tests.login(:emp);
select tests.check((select status = 'active' from public.job_vacancies where id = '10710000-0000-4000-8000-000000000001'),
  'D2 nobody else can delete it');
update public.job_vacancies set status = 'deleted' where id = '10710000-0000-4000-8000-000000000001';
select tests.check((select status = 'deleted' from public.job_vacancies where id = '10710000-0000-4000-8000-000000000001'),
  'D3 the owner deletes it');
select tests.check(tests.err($$ delete from public.job_vacancies $$) like '%permission denied%', 'D4 no row is really removed');
select tests.check(tests.err($$ update public.job_vacancies set status = 'active' where id = '10710000-0000-4000-8000-000000000001' $$)
  like '%vacancy_deleted%', 'D5 the owner cannot bring it back');

select tests.login(:drv);
select tests.check((select count(*) = 0 from jsonb_array_elements(public.job_vacancies_list()) e
                     where e ->> 'id' = '10710000-0000-4000-8000-000000000001'), 'D6 others no longer see it');
select tests.check(tests.err($$ select public.job_application_send('10710000-0000-4000-8000-000000000001', null, 'x') $$)
  like '%vacancy_closed%', 'D7 nobody can apply to it');
select tests.check((select count(*) = 1 from public.job_applications where vacancy_id = '10710000-0000-4000-8000-000000000001'),
  'D8 the driver''s application is kept');

select tests.login(:admin);
update public.job_vacancies set status = 'closed' where id = '10710000-0000-4000-8000-000000000001';
select tests.check((select status = 'closed' from public.job_vacancies where id = '10710000-0000-4000-8000-000000000001'),
  'D9 an admin can bring it back');
reset role;
select tests.summary('VAKANSİYA SİLMƏ (0071)');
rollback;
