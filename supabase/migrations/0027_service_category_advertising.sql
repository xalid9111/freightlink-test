-- =====================================================================
-- 0027 — Services: new category "Reklam agentliyi və ustası"
-- (sign makers, wrap / banner printers, advertising agencies).
-- Safe: forward-only, re-runnable; adds one row, changes nothing else.
-- =====================================================================
insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order) values
  ('advertising', 'Reklam agentliyi və ustası', 'Reklam ajansı ve ustası', 'Advertising agency & sign maker',
   'Рекламное агентство и мастер', 'სარეკლამო სააგენტო და ოსტატი', 'ads', 90)
on conflict (id) do nothing;
