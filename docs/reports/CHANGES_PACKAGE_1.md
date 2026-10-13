# Package 1 — fixes from the iPhone Safari test (app code only)

No database migrations, schema, RLS or Supabase settings were changed.

1. Account switching kept the previous account's data (e.g. the
   carrier offer form was missing until a page reload). User-specific
   providers now re-run when the signed-in user changes
   (`currentUserIdProvider` in auth_providers.dart).
2. Chat thread is WhatsApp-style: oldest at the top, newest at the
   bottom, view anchored to the bottom, send time (HH:mm) on each bubble.
   (Supabase stream `.order()` defaults to descending — that was the cause.)
5. Accepting an offer now also rejects the other pending offers on that
   cargo and sets the cargo status to `agreed`, which removes it from the
   open marketplace (which lists status `new` only).
6. Shipments tab has status buttons: the carrier advances
   new/agreed → loading → in_transit → delivered; the cargo owner
   confirms delivered → completed (cargo status mirrored to `completed`).
   Each step asks for confirmation.
7. Country flags on routes (cargo cards, cargo detail, shipments,
   conversations), with the country name shown in the UI language. The
   create form uses a searchable country picker; new cargo stores the
   country's English name. Old free-text values are still recognized.

Still open: 3 (online status) and 4 (unread badge) — planned as package 2.
