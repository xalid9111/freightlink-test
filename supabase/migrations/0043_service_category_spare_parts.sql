-- =====================================================================
-- 0043 — Services: new category "Ehtiyat hissələri satışı" (truck spare
-- parts sales), shown first in Servislər (owner, 19.10.2026). Sellers
-- register like masters and drivers can filter by it.
-- Safe: forward-only, re-runnable; adds one row, changes nothing else.
-- =====================================================================
insert into public.service_categories (id, name_az, name_tr, name_en, name_ru, name_ka, icon, sort_order) values
  ('spare_parts', 'Ehtiyat hissələri satışı', 'Yedek parça satışı', 'Spare parts sales',
   'Продажа запчастей', 'სათადარიგო ნაწილების გაყიდვა', 'parts', 0)
on conflict (id) do nothing;
