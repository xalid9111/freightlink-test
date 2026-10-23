#!/usr/bin/env bash
# =====================================================================
# LOCAL TEST RUNNER — disposable PostgreSQL only. Never point this at
# the production database: it DROPS and recreates the target database
# (and refuses to run unless the database name contains "test").
#
# Usage:
#   PGHOST=/path/to/socket PGPORT=5432 PGUSER=postgres \
#     supabase/tests/local/run_local.sh before   # 0001–0017, reproduce issues
#   ... run_local.sh after                       # 0001–0017 + fixtures, then
#                                                # 0018–0020, all suites,
#                                                # data-preservation and
#                                                # idempotency checks
# =====================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MIG="$HERE/../../migrations"
DB="${TEST_DB:-freightlink_test}"
MODE="${1:-after}"
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"
PSQL=(psql -X -v ON_ERROR_STOP=1 -q)
NEW=(0018_package1_security.sql 0019_package1b_security.sql 0020_advertiser_campaign_details.sql 0021_ad_templates_receipts.sql 0022_ad_template_logo.sql 0023_ads_standard_layout.sql 0024_ads_admin_edit.sql 0025_ads_feed_layout.sql 0026_ads_order_no_repeat.sql 0027_service_category_advertising.sql 0028_services_autopublish_pro.sql 0029_service_ads.sql 0030_whatsapp_verify_poc.sql 0031_profile_catalog_message_delete.sql 0032_own_ad_background.sql 0033_ads_arial_font.sql 0034_autofix.sql 0035_catalog_sort_order.sql 0036_service_category_tarp.sql 0037_finance_payments.sql 0038_ad_template_audience_fn.sql 0039_user_activities.sql 0040_market.sql 0041_market_autopublish.sql 0042_autofix_cleanup.sql 0043_service_category_spare_parts.sql 0044_market_hero_vip.sql 0045_founder_protection.sql 0046_cargo_payment_terms.sql 0047_cargo_payment_choices.sql 0048_founder_silent_delete.sql 0049_page_banners.sql 0050_page_banner_text_toggle.sql 0051_page_banner_focus.sql 0052_page_banner_zoom.sql 0053_market_exact_location.sql 0054_market_vip_test_activates.sql 0055_cargo_categories.sql 0056_finish_service_ads.sql 0057_autofix_resolve_hidden.sql 0058_cargo_pictures_favorites.sql 0060_cargo_photos_contact.sql)

if [[ "$DB" != *test* ]]; then echo "Refusing: TEST_DB must contain 'test'"; exit 2; fi

"${PSQL[@]}" -d postgres -c "drop database if exists $DB" -c "create database $DB"
"${PSQL[@]}" -d "$DB" -f "$HERE/00_supabase_stub.sql" 2>/dev/null

for f in "$MIG"/0*.sql; do
  n="$(basename "$f" | cut -c1-4)"
  [[ "$n" > "0017" ]] && continue
  "${PSQL[@]}" -d "$DB" -f "$f" >/dev/null
done
echo "applied 0001–0017"
"${PSQL[@]}" -d "$DB" -f "$HERE/10_fixtures.sql" >/dev/null
"${PSQL[@]}" -d "$DB" -f "$HERE/15_test_helpers.sql" >/dev/null

if [[ "$MODE" == "before" ]]; then
  "${PSQL[@]}" -d "$DB" -f "$HERE/20_package1_before.sql" >/dev/null
  exit 0
fi

snapshot() {  # $1 = label : row count + md5 of every public table
  "${PSQL[@]}" -d "$DB" -c "
    create table if not exists tests.snap (label text, tbl text, n bigint, h text);
    do \$\$ declare t text; begin
      for t in select tablename from pg_tables where schemaname = 'public' order by 1 loop
        execute format('insert into tests.snap select %L, %L, count(*), md5(coalesce(string_agg(jsonb_strip_nulls(to_jsonb(x) - case when %L = ''ad_orders'' then array[''title'',''image_url'',''destination_type'',''destination_url'',''target_countries'',''route_from'',''route_to'',''order_no'',''service_id'',''template_id'',''creative'',''starts_on'',''receipt_path'',''receipt_uploaded_at'',''reviewed_at'',''ad_starts_at'',''ad_ends_at'']::text[] when %L = ''ads'' then array[''destination_type'',''destination_url'',''target_countries'',''route_from'',''route_to'',''creative'',''priority'']::text[] when %L = ''service_providers'' then array[''is_pro'']::text[] when %L = ''ad_templates'' then array[''audience'']::text[] when %L = ''users'' then array[''activities'']::text[] when %L = ''cargo'' then array[''pay_cash_on'',''pay_on_delivery'',''pay_bank_on'',''load_size'',''groupage'',''image_urls'']::text[] when %L in (''messages'', ''group_messages'') then array[''deleted_silent'']::text[] else array[]::text[] end)::text, ''|'' order by x::text), '''')) from public.%I x where (to_jsonb(x)->>''id'') is null or (to_jsonb(x)->>''id'') not in (''d5'',''d15'',''d30'',''advertising'',''tarp_repair'',''spare_parts'')', '$1', t, t, t, t, t, t, t, t, t);
      end loop; end \$\$;"
}
compare() {  # $1 $2 = labels
  "${PSQL[@]}" -d "$DB" -c "
    do \$\$ declare d text; begin
      select string_agg(coalesce(a.tbl, b.tbl), ', ') into d
      from (select * from tests.snap where label = '$1') a
      full join (select * from tests.snap where label = '$2') b using (tbl)
      where (a.tbl is not null and (a.h is distinct from b.h or a.n is distinct from b.n))
         -- new settings tables a migration fills with defaults (no user data)
         or (a.tbl is null and b.n > 0 and b.tbl not in ('market_vip_plans'));
      if d is not null then raise exception 'DATA CHANGED ($1 -> $2) in: %', d; end if;
      raise warning 'data preservation $1 -> $2: all % public tables identical',
        (select count(*) from tests.snap where label = '$1');
    end \$\$;"
}
apply_new() {
  for m in "${NEW[@]}"; do
    echo "apply $m"
    "${PSQL[@]}" -d "$DB" -1 -f "$MIG/$m"
  done
}
suites() {
  "${PSQL[@]}" -d "$DB" -f "$HERE/30_package1_after.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/40_package1b_after.sql" >/dev/null
  # 60/61 tested the 0021/0022 free-layout flow, superseded by 0023 (kept for history).
  "${PSQL[@]}" -d "$DB" -f "$HERE/62_ads_v2_flow.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/63_ads_admin_edit.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/64_ads_feed_layout.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/65_ads_order.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/66_services_pro.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/67_service_ads.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/68_wa_verify_poc.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/69_profile_catalog_delete.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/70_own_ad_background.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/71_ads_arial_font.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/72_autofix.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/73_catalog_reorder.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/74_service_category_tarp.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/75_finance.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -v mig38="$MIG/0038_ad_template_audience_fn.sql" -f "$HERE/76_ad_template_audience_fn.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -v mig39="$MIG/0039_user_activities.sql" -f "$HERE/77_user_activities.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/78_market.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -v mig41="$MIG/0041_market_autopublish.sql" -f "$HERE/79_market_autopublish.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/80_autofix_cleanup.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/81_service_category_spare_parts.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/82_market_hero_vip.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/83_founder_protection.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/84_cargo_payment_terms.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/85_cargo_payment_choices.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/86_founder_silent_delete.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/87_page_banners.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/88_page_banner_text_toggle.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/89_page_banner_focus.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/90_page_banner_zoom.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/91_market_exact_location.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/92_market_vip_test_activates.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/93_cargo_categories.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/94_finish_service_ads.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/95_cargo_pictures_favorites.sql" >/dev/null
  "${PSQL[@]}" -d "$DB" -f "$HERE/97_cargo_photos_contact.sql" >/dev/null
  PGOPTIONS="-c client_min_messages=notice" "${PSQL[@]}" -d "$DB" -f "$HERE/../messaging_audit_test.sql" 2>&1 \
    | grep -E "ALL MESSAGING|FAILED|ERROR" | sed 's/^/messaging_audit_test: /'
}

snapshot pre
apply_new
snapshot post
compare pre post
suites
echo "re-apply (idempotency)"
apply_new
snapshot post2
compare pre post2
suites
