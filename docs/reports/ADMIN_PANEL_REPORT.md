# FreightLink — Admin Panel report

## URL
https://xalid9111.github.io/freightlink-test/#/admin  (sections: /#/admin/cargo, /users,
/carriers, /drivers, /shipments, /offers, /reports, /audit, /system)

## Database (supabase/migrations/0012_admin_panel.sql — safe forward migration, idempotent)
New columns: users.is_blocked, blocked_until, block_reason, is_active; cargo.is_hidden.
New tables: admin_audit_log (admin read-only; written only by server functions), reports.
New functions: is_blocked(), assert_not_blocked() trigger (cargo, offers, conversations,
messages), guard_cargo_hidden() trigger, can_see_hidden_cargo(), _require_admin(),
_admin_log(), admin_dashboard_stats(), admin_update_cargo(), admin_set_cargo_hidden(),
admin_delete_cargo(), admin_update_user(), admin_set_user_block(), admin_set_user_active(),
admin_delete_user(), admin_set_shipment_status(), admin_set_offer_status(),
admin_set_report_status(). Redefined: guard_user_protected_columns() (also protects the
moderation columns). Policy changed: cargo_select_all (hidden loads visible only to owner,
admins and users with an offer/shipment/chat on them). New policies: audit_admin_select,
reports_insert_own, reports_select_own_or_admin. Realtime enabled for cargo, offers,
shipments, users, reports, admin_audit_log.

## Security
- Every admin write = SECURITY DEFINER RPC that calls is_admin() on the server and writes
  an audit row (who, action, object, old JSON, new JSON, note, time).
- No service-role key in the app. Hiding /admin in the UI is not relied on.
- Users cannot promote themselves or un-hide/un-block themselves (guard triggers).
- Admin cannot block / deactivate / delete / demote their own account.

## Assigning an admin
SQL editor: update public.users set role = 'admin' where email = '<email>';
(Later: an admin can change roles in Admin → İstifadəçilər → Redaktə et.)

## Deletion rules
- Load: permanent; offers, shipment, chats, messages removed by existing ON DELETE
  CASCADE; refused if a payment exists (hide instead). Full row + related counts saved in
  the audit log first.
- User: anonymised + deactivated + blocked; open loads hidden; history kept. Removing the
  login itself: Supabase → Authentication → Users.

## Verified
- 0001–0012 executed on a local PostgreSQL 16 with Supabase auth/storage stubs; 0012 run
  twice (idempotent).
- Functional SQL tests: non-admin refused (admin_only), audit table not writable by users,
  self-promotion blocked, report insert, all admin RPCs, self-block/self-demote refused,
  audit rows written, hidden load invisible to strangers but visible to owner/offer carrier,
  owner cannot un-hide, blocked user cannot send offers, shipment status + history row,
  cascade delete, user anonymisation.
- Existing messaging regression test (supabase/tests/messaging_audit_test.sql): all 7 pass.
- Flutter build: NOT verifiable here (no Flutter SDK); GitHub Actions build is the check.

## Placeholders / limits
- "Lazım olan maşın sayı": no such column in the database — shown as such.
- Error log in System: not connected yet (needs Sentry or similar).
- Drivers / trucks: tables exist but the app does not create them yet, so these lists are
  mostly empty.
- Notifications icon = count of open reports (no push yet).
