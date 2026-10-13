-- ADS LOGO (0022): logo place on templates, customer logo in own folder only.
\set admin   '''a0000000-0000-4000-8000-000000000001'''
\set other   '''a0000000-0000-4000-8000-000000000021'''
\set tpl     '''e0000000-0000-4000-8000-0000000000b1'''
begin;
set role authenticated;
select tests.login(:admin);
select tests.check(tests.err($$ select public.admin_save_ad_template(null, '{"name":"L","image_url":"u","fields":[{"key":"t","label":"Başlıq","x":0.3,"y":0.2,"w":0.5,"size":60,"max":30}],"colors":["#FFFFFF"],"logo":{"x":0.02,"y":0.1,"w":2,"h":0.8}}') $$) like '%invalid_logo%',
  'L1 logo place must fit the banner');
create temp table t_t as select * from public.admin_save_ad_template(null, '{"name":"Loqolu","image_url":"https://x/storage/v1/object/public/ads/templates/b.png","fields":[{"key":"t","label":"Başlıq","x":0.3,"y":0.2,"w":0.5,"size":60,"max":30}],"colors":["#FFFFFF"],"logo":{"x":0.02,"y":0.1,"w":0.2,"h":0.8},"is_active":true}');
grant select on t_t to authenticated;
select tests.check((select logo->>'w' = '0.2' from t_t), 'L2 template saved with a logo place');
select public.admin_save_ad_package('d5', '5 gün', 5, 20, true);
select tests.login(:other);
select tests.check(tests.err(format($$ select public.create_ad_order_from_template(%L, '{"t":"A"}', '#FFFFFF', 5, current_date + 1, 'profile', null, '{}', null, null, null, 'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000011/l.png') $$, (select id from t_t))) like '%invalid_logo%',
  'L3 logo from someone else''s folder refused');
select tests.check((select creative->>'logo_url' like '%/ads/requests/a0000000-0000-4000-8000-000000000021/l.png'
                       and (creative->'logo'->>'x') = '0.02'
                      from public.create_ad_order_from_template((select id from t_t), '{"t":"A"}', '#FFFFFF', 5, current_date + 1,
                        'profile', null, '{}', null, null, null,
                        'https://x/storage/v1/object/public/ads/requests/a0000000-0000-4000-8000-000000000021/l.png')),
  'L4 own logo stored in the order snapshot with the logo place');
select tests.check((select creative->>'logo_url' is null
                      from public.create_ad_order_from_template((select id from t_t), '{"t":"B"}', '#FFFFFF', 5, current_date + 1)),
  'L5 logo is optional');
reset role;
select tests.summary('ADS LOGO (0022)');
rollback;
