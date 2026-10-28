-- İŞ MƏRKƏZİ (SmartMatch) — 0069. Rolled back.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set emp     '''a0000000-0000-4000-8000-000000000012'''
\set emp2    '''a0000000-0000-4000-8000-000000000014'''
\set drv     '''a0000000-0000-4000-8000-000000000013'''
\set drv2    '''a0000000-0000-4000-8000-000000000021'''
\set blocked '''a0000000-0000-4000-8000-000000000031'''

begin;
-- ---- catalogues ----------------------------------------------------------------
set role authenticated;
select tests.login(:drv);
select tests.check((select count(*) >= 10 and bool_or(code = 'tent') and bool_or(code = 'other') from public.job_specialties), 'C1 10 specialties (Tent … Digər; 0072 adds Açıq)');
select tests.check((select count(*) >= 11 and bool_or(code = 'lic_ce') and bool_or(code = 'tachograph') from public.job_skills),
  'C2 licences, documents, skills');
select tests.check(tests.err($$ insert into public.job_specialties (code, name) values ('xx', 'X') $$) like '%permission denied%',
  'C3 nobody adds specialties directly');

-- ---- a driver's work profile -----------------------------------------------------
insert into public.job_seeker_profiles (user_id, full_name, birth_date, country, city, experience_years, specialties, skills,
                                        countries, salary_min, currency, schedule, phone, is_hidden)
values (:drv, '  Elvin Sürücü ', '1990-05-01', 'Azerbaijan', 'Baku', 7, '{ref,tent}',
        '{"lic_ce":"yes","tachograph":"no","cpc":"ready"}', '{Georgia,Turkey}', 1500, 'AZN', 'rotation', '+994501112233', true);
select tests.check((select full_name = 'Elvin Sürücü' and not is_hidden and not show_phone from public.job_seeker_profiles where user_id = :drv),
  'P1 the driver creates his profile (name trimmed; cannot hide it himself; phone hidden by default)');
select tests.check(tests.err($$ insert into public.job_seeker_profiles (user_id, full_name) values ('a0000000-0000-4000-8000-000000000021', 'X') $$)
  like '%row-level security%', 'P2 nobody creates a profile for someone else');
select tests.check(tests.err($$ update public.job_seeker_profiles set skills = '{"lic_ce":"maybe"}' where user_id = 'a0000000-0000-4000-8000-000000000013' $$)
  like '%check constraint%', 'P3 only yes / no / ready for documents and skills');
select tests.check(tests.err($$ update public.job_seeker_profiles set birth_date = current_date - 3650 where user_id = 'a0000000-0000-4000-8000-000000000013' $$)
  like '%invalid_birth_date%', 'P4 younger than 16 is refused');
update public.job_seeker_profiles set note = 'Hazıram', experience_years = 8 where user_id = :drv;
select tests.check((select note = 'Hazıram' and experience_years = 8 from public.job_seeker_profiles where user_id = :drv), 'P5 …and edits it');
select tests.check(tests.err($$ delete from public.job_seeker_profiles $$) like '%permission denied%', 'P6 no deleting (switch off instead)');

select tests.login(:drv2);
insert into public.job_seeker_profiles (user_id, full_name, specialties, show_phone, phone, whatsapp)
values (:drv2, 'İkinci Sürücü', '{}', true, '+994552223344', true);
select tests.check((select count(*) = 1 from public.job_seeker_profiles), 'P7 a driver reads only his own profile row');

-- ---- an employer's vacancy (no requirements is fine) -------------------------------------
select tests.login(:emp);
insert into public.job_vacancies (id, owner_id, company_name, country, city, specialties, requirements, can_help, min_experience,
                                  salary_min, salary_max, currency, schedule)
values ('10690000-0000-4000-8000-000000000001', :emp, 'Ref Trans MMC', 'Azerbaijan', 'Baku', '{ref}',
        '{"lic_ce":"must","tachograph":"nice"}', '{tachograph}', 3, 1200, 2000, 'AZN', 'rotation');
insert into public.job_vacancies (id, owner_id, company_name, specialties)
values ('10690000-0000-4000-8000-000000000002', :emp, 'Sadə vakansiya', '{}');
select tests.check((select count(*) = 2 from public.job_vacancies where owner_id = :emp), 'V1 the employer posts vacancies (one without requirements)');
select tests.check(tests.err($$ update public.job_vacancies set requirements = '{"lic_ce":"maybe"}' where id = '10690000-0000-4000-8000-000000000001' $$)
  like '%check constraint%', 'V2 only must / nice requirements');
select tests.check(tests.err($$ insert into public.job_vacancies (owner_id, company_name) values ('a0000000-0000-4000-8000-000000000014', 'X') $$)
  like '%row-level security%', 'V3 nobody posts for someone else');
update public.job_vacancies set is_hidden = true, owner_id = 'a0000000-0000-4000-8000-000000000014' where id = '10690000-0000-4000-8000-000000000002';
select tests.check((select not is_hidden and owner_id = :emp from public.job_vacancies where id = '10690000-0000-4000-8000-000000000002'),
  'V4 the owner cannot hide or give away his vacancy');

-- ---- what others see ----------------------------------------------------------------
select tests.check((select jsonb_array_length(public.job_seekers_list()) = 2), 'L1 the employer sees both active drivers');
select tests.check((select (e ->> 'phone') is null and not (e ->> 'whatsapp')::boolean and (e ->> 'age')::int between 30 and 40
                           and not (e ? 'birth_date') and e -> 'skills' ->> 'tachograph' = 'no' and not (e -> 'skills' ? 'intl_exp')
                      from jsonb_array_elements(public.job_seekers_list()) e where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000013'),
  'L2 hidden phone stays hidden, age instead of birth date, ✓ / X / not given kept apart');
select tests.check((select e ->> 'phone' = '+994552223344' and (e ->> 'whatsapp')::boolean
                      from jsonb_array_elements(public.job_seekers_list()) e where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000021'),
  'L3 a phone its owner chose to show is shown');
select tests.login(:drv);
select tests.check((select jsonb_array_length(public.job_vacancies_list()) = 2), 'L4 the driver sees the vacancies');
reset role;
set role anon;
select tests.login(null);
select tests.check(tests.err($$ select public.job_vacancies_list() $$) like '%permission denied%', 'L5 not for visitors');
select tests.check(tests.err($$ select * from public.job_seeker_profiles $$) like '%permission denied%', 'L6 no table access for visitors');
reset role;

-- ---- notifications: only the matching side, once ------------------------------------------
select tests.check((select count(*) = 1 from public.notifications where type = 'job_match_vacancy' and user_id = :drv
                      and data ->> 'vacancy_id' = '10690000-0000-4000-8000-000000000001'),
  'N1 the REF driver heard about the REF vacancy');
select tests.check(not exists (select 1 from public.notifications where type like 'job_match%' and user_id = :drv2),
  'N2 a driver without a matching specialty is not notified');
select tests.check(not exists (select 1 from public.notifications where data ->> 'vacancy_id' = '10690000-0000-4000-8000-000000000002'),
  'N3 a vacancy without specialties notifies nobody');
set role authenticated;
select tests.login(:emp);
update public.job_vacancies set status = 'closed' where id = '10690000-0000-4000-8000-000000000001';
update public.job_vacancies set status = 'active' where id = '10690000-0000-4000-8000-000000000001';
reset role;
select tests.check((select count(*) = 1 from public.notifications where type = 'job_match_vacancy' and user_id = :drv),
  'N4 closing and re-opening does not notify twice');
set role authenticated;
select tests.login(:drv2);
update public.job_seeker_profiles set specialties = '{ref}', country = 'Georgia' where user_id = :drv2;
reset role;
select tests.check(not exists (select 1 from public.notifications where type = 'job_match_seeker' and data ->> 'seeker_id' = 'a0000000-0000-4000-8000-000000000021'),
  'N5 another country (not in his list) → the employer is not notified');
set role authenticated;
select tests.login(:drv2);
update public.job_seeker_profiles set countries = '{Azerbaijan}', is_active = false where user_id = :drv2;
update public.job_seeker_profiles set is_active = true where user_id = :drv2;
update public.job_seeker_profiles set is_active = false where user_id = :drv2;
update public.job_seeker_profiles set is_active = true where user_id = :drv2;
reset role;
select tests.check((select count(*) = 1 from public.notifications where type = 'job_match_seeker' and user_id = :emp
                      and data ->> 'seeker_id' = 'a0000000-0000-4000-8000-000000000021'),
  'N6 he wants to work in Azerbaijan → the employer is told once (switching on and off twice)');

-- ---- applications and offers -----------------------------------------------------
set role authenticated;
select tests.login(:drv);
create temp table t_app as select * from public.job_application_send('10690000-0000-4000-8000-000000000001', null, 'Salam');
select tests.check((select status = 'sent' and initiated_by = 'seeker' and employer_id = :emp from t_app), 'A1 the driver applies');
select tests.check((select id from public.job_application_send('10690000-0000-4000-8000-000000000001')) = (select id from t_app),
  'A2 applying twice = one application');
select tests.check(tests.err(format($$ select public.job_application_set_status(%L, 'seen') $$, (select id from t_app))) is null
                   and (select status = 'sent' from public.job_applications where id = (select id from t_app)),
  'A3 the sender cannot mark his own application seen');
select tests.login(:emp);
select public.job_application_set_status((select id from t_app), 'seen');
select tests.check((select status = 'seen' from public.job_applications where id = (select id from t_app)), 'A4 the employer saw it');
select public.job_application_set_status((select id from t_app), 'accepted');
select tests.check((select status = 'talking' and employer_ok and not seeker_ok from public.job_applications where id = (select id from t_app)),
  'A5 one side confirming is not a hire yet');
select tests.login(:drv);
select public.job_application_set_status((select id from t_app), 'accepted');
select tests.check((select status = 'accepted' and employer_ok and seeker_ok from public.job_applications where id = (select id from t_app)),
  'A6 hired only when both confirmed');
select tests.check(tests.err(format($$ select public.job_application_set_status(%L, 'talking') $$, (select id from t_app))) like '%application_final%',
  'A7 a hire cannot go back to talking');
select tests.login(:drv2);
select tests.check(tests.err(format($$ select public.job_application_set_status(%L, 'closed') $$, (select id from t_app))) like '%application_not_found%',
  'A8 others cannot touch it');
select tests.check((select count(*) = 0 from public.job_applications), 'A9 …nor read it');
select tests.login(:emp);
create temp table t_offer as select * from public.job_application_send('10690000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000021', 'Gəl işlə');
select tests.check((select initiated_by = 'employer' and seeker_id = :drv2 from t_offer), 'A10 the employer offers the job to a driver');
select tests.login(:emp2);
select tests.check(tests.err($$ select public.job_application_send('10690000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000021') $$)
  like '%vacancy_not_found%', 'A11 only the vacancy owner can offer it');
reset role;
select tests.check((select count(*) = 1 from public.notifications where type = 'job_application' and user_id = :emp and title = 'Yeni müraciət'),
  'A12 the employer was told about the application once');
select tests.check(exists (select 1 from public.notifications where type = 'job_application' and user_id = :drv2 and title = 'Yeni iş təklifi'),
  'A13 the driver was told about the offer');

-- ---- admin moderation ----------------------------------------------------------------
set role authenticated;
select tests.login(:emp);
select tests.check(tests.err($$ select public.admin_job_set_hidden('seeker', 'a0000000-0000-4000-8000-000000000013', true) $$) like '%admin_only%',
  'M1 a user cannot hide others');
select tests.login(:admin);
select public.admin_job_set_hidden('seeker', :drv, true);
select tests.check((select (e ->> 'is_hidden')::boolean from jsonb_array_elements(public.job_seekers_list()) e
                     where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000013'), 'M2 the admin hides a profile (and still sees it, marked)');
select tests.login(:emp);
select tests.check(not exists (select 1 from jsonb_array_elements(public.job_seekers_list()) e
                                where e ->> 'user_id' = 'a0000000-0000-4000-8000-000000000013'), 'M3 …others no longer see it');
select tests.login(:drv);
update public.job_seeker_profiles set is_hidden = false where user_id = :drv;
select tests.check((select is_hidden from public.job_seeker_profiles where user_id = :drv), 'M4 the driver cannot unhide himself');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'job.hide'), 'M5 hiding is logged');
select tests.summary('İŞ MƏRKƏZİ (0069)');
rollback;
