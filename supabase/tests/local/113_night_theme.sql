-- NIGHT COLOURS — 0076. Rolled back.
\set admin  '''a0000000-0000-4000-8000-000000000001'''
\set user1  '''a0000000-0000-4000-8000-000000000012'''

begin;
set role anon;
select tests.login(null);
select tests.check((select public.night_theme_current() -> 'colors' = 'null'::jsonb), 'N1 starts classic (nothing published)');
select tests.check(tests.err($$ select * from public.night_theme_state $$) like '%permission denied%', 'N2 no direct reading (anon)');
select tests.check(tests.err($$ select public.admin_night_theme_publish('{}'::jsonb) $$) like '%permission denied%', 'N3 a visitor cannot publish');
reset role;

set role authenticated;
select tests.login(:user1);
select tests.check(tests.err($$ select public.admin_night_theme_publish(null) $$) like '%admin_only%', 'U1 a user cannot publish');
select tests.check(tests.err($$ select public.admin_night_theme_save('x', '{}'::jsonb) $$) like '%admin_only%', 'U2 …nor save');
select tests.check(tests.err($$ select public.admin_night_themes() $$) like '%admin_only%', 'U3 …nor list');
select tests.check(tests.err($$ update public.night_theme_state set colors = null $$) like '%permission denied%', 'U4 …nor write the table');

select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_night_theme_restore() $$) like '%nothing_to_restore%', 'A1 nothing to restore yet');
select tests.check(tests.err($$ select public.admin_night_theme_publish('{"background":"red"}'::jsonb) $$) like '%invalid_colors%',
  'A2 a wrong colour is refused');
select tests.check(tests.err($$ select public.admin_night_theme_save('Bad', '{"background":"#090A0E","card":"#1C171D","button":"#8F2945","accent":"#C34467","line":"#512837","text":"#F5F2F4","text_soft":"#A9A4AB","gradient":3}'::jsonb) $$)
  like '%invalid_colors%', 'A3 a level above 1 is refused');
select tests.check(tests.err($$ select public.admin_night_theme_save('Bad', '{"background":"#090A0E","card":"#1C171D","button":"#8F2945","accent":"#C34467","line":"#512837","text":"#F5F2F4","text_soft":"#A9A4AB","js":"x"}'::jsonb) $$)
  like '%invalid_colors%', 'A4 unknown keys are refused');
select public.admin_night_theme_save('Bordo Premium 1', '{"background":"#090A0E","card":"#1C171D","button":"#8F2945","accent":"#C34467","line":"#512837","text":"#F5F2F4","text_soft":"#A9A4AB","gradient":0.35,"glow":0.3}'::jsonb);
select public.admin_night_theme_save('bordo premium 1 ', '{"background":"#000000","card":"#1C171D","button":"#8F2945","accent":"#C34467","line":"#512837","text":"#F5F2F4","text_soft":"#A9A4AB"}'::jsonb);
select tests.check((select jsonb_array_length(public.admin_night_themes()) = 1
                      and public.admin_night_themes() -> 0 -> 'colors' ->> 'background' = '#000000'), 'A5 the same name updates the draft');
select tests.check((select public.night_theme_current() -> 'colors' = 'null'::jsonb), 'A6 a draft is not published');

select public.admin_night_theme_publish('{"background":"#090A0E","card":"#1C171D","button":"#8F2945","accent":"#C34467","line":"#512837","text":"#F5F2F4","text_soft":"#A9A4AB","gradient":0.35,"glow":0.3}'::jsonb, 'Bordo Premium');
reset role;
set role anon;
select tests.login(null);
select tests.check((select public.night_theme_current() -> 'colors' ->> 'button' = '#8F2945'
                      and public.night_theme_current() ->> 'name' = 'Bordo Premium'), 'P1 everybody gets the published colours (also signed out)');
reset role;
select tests.check(exists (select 1 from public.admin_audit_log where action = 'night_theme.published'), 'P2 publishing is logged');

set role authenticated;
select tests.login(:admin);
select tests.check((select public.admin_night_theme_restore() -> 'colors' = 'null'::jsonb), 'R1 "Əvvəlki temaya qayıt" brings classic back');
select tests.check((select public.admin_night_theme_restore() -> 'colors' ->> 'button' = '#8F2945'), 'R2 …and once more brings Bordo back');
select tests.check((select public.admin_night_theme_publish(null, 'Klassik FreightLink') -> 'colors' = 'null'::jsonb), 'R3 Sıfırla = classic');
select public.admin_night_theme_delete((public.admin_night_themes() -> 0 ->> 'id')::uuid);
select tests.check((select jsonb_array_length(public.admin_night_themes()) = 0), 'D1 a draft can be deleted');
reset role;
select tests.check(exists (select 1 from public.users), 'D2 users untouched');
select tests.summary('GECƏ RƏNGLƏRİ (0076)');
rollback;
