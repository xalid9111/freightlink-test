-- FINISH SERVICE ADS — 0056: the parts of 0029 missing on the live database.
begin;
select tests.check((select count(*) = 1 from information_schema.columns
                      where table_schema = 'public' and table_name = 'ad_orders' and column_name = 'service_id'),
  'F1 ad_orders.service_id exists');
select tests.check((select count(*) = 2 from pg_constraint
                      where conname in ('ad_orders_destination_type_check', 'ads_destination_type_check')
                        and pg_get_constraintdef(oid) like '%service%'),
  'F2 a service ad (destination "service") is allowed');
select tests.check((select prosrc like '%0029: a service ad%' from pg_proc where proname = 'admin_update_ad_order_v2'),
  'F3 admin edit keeps a service ad leading to its service');
select tests.check(has_function_privilege('authenticated',
  'public.admin_update_ad_order_v2(uuid,uuid,jsonb,jsonb,text,text,text,text,text[],text,text,timestamptz,timestamptz)', 'execute'),
  'F4 signed-in users may call it (admin checked inside)');
select tests.summary('FINISH SERVICE ADS (0056)');
rollback;
