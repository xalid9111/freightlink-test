# WhatsApp-style chat & profile, catalog, deleting messages — report

## What changed
- **Chat screens (1-to-1 and groups):** WhatsApp-like dark colours and dotted wallpaper, day
  labels ("Bu gün", "Dünən", date). Header: shop icon (→ catalog) and call icon; tapping the
  photo/name opens the profile.
- **Profile page for every role** (`/user/:id`): cover photo, round logo, name + verified tick,
  quick buttons (Call · Message · Catalog · Share link), catalog preview, about / working hours /
  address, the user's services, open loads. The owner edits it there ("Düzəlt", cover camera).
  Own Profile tab → "Mənim səhifəm və kataloqum".
- **Catalog** (`/user/:id/catalog`): photos of work with a short caption (max 300, no price),
  max 60 per user, full-screen viewer; the owner adds, edits the caption, deletes.
- **Service page:** "Profilə keç" button → owner's profile.
- **Deleting:**
  - list: swipe a chat left (or long-press) → delete chat *for me* (other side keeps it; a new
    message brings it back);
  - inside a chat: long-press a message → Copy / Delete for me / Delete for everyone (own
    messages only; shows "Bu mesaj silindi" on both sides).

## Database (0031_profile_catalog_message_delete.sql)
New: `profile_details`, `profile_catalog_items` (+ public bucket `profile-media`, owner-folder
writes only), `message_hidden`, `chat_clears`, column `deleted_at` on `messages` /
`group_messages`, functions `delete_message`, `clear_chat_for_me`, `my_chat_activity`.
`guard_message_update` keeps its old behaviour and only allows blanking through
`delete_message`. Nothing existing is deleted; "delete for me" never removes rows.

## Checks
- Local Postgres: new suite 25/25; all earlier suites + messaging audit pass; data preserved;
  re-run safe.
- i18n: 46 new keys in az/tr/en/ru/ka/zh, validator OK. Dart static checks OK.
- `flutter analyze` / build: NOT run here (no Flutter SDK) — the GitHub build is the compile check.
