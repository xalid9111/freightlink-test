-- =====================================================================
-- 0036 — Services: new category "Tent təmiri" (truck tarpaulin / curtain
-- repair), so drivers find tarp masters and masters can be found.
-- Safe: forward-only, re-runnable; adds one row, changes nothing else.
-- =====================================================================
insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order) values
  ('tarp_repair', 'Tent təmiri', 'Tente tamiri', 'Truck tarpaulin repair',
   'Ремонт тентов', 'ტენტის შეკეთება', 'tarp', 85)
on conflict (id) do nothing;
