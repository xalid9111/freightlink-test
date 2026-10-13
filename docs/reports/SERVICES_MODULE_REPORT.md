# Services module — phase 1 report

## What was built
- **Bottom navigation (5):** Yüklər · Yük əlavə et · Servislər · Mesajlar · Profil. The Services tab is a new shell branch (index 5); the other four keep their branches and behaviour.
- **Registration:** role screen has a 3rd option "Usta / Servis" → Fərdi usta / Servis mərkəzi. The account keeps an ordinary role (`cargo_owner`); `service_kind` goes to auth metadata and the user is sent to the service-profile form. Existing users add a profile from Services → "Usta kimi qoşul" or Profile.
- **GPS map (Services tab):** OpenStreetMap tiles (flutter_map, already used), browser GPS (asked only on this tab, never stored), city/address search (Nominatim) when GPS is denied, "search this area", grid clustering of pins, 3 pin types (mobile mechanic / service centre / tow truck), legend, distance, road route + ETA (public OSRM; falls back to straight line).
- **Filters:** category chips, distance (10–500 km), min rating, kind, only active, name.
- **Card / profile:** Call (phone/WhatsApp), Message (existing direct chat, only when the listing has an owner), Route (Google Maps / Waze / Apple Maps on iPhone / Sygic). Profile has photos, categories, specialty, hours / 24-7, mobile radius, location map, rating + reviews, active switch, report, "This is my business" claim.
- **Admin → Servislər:** list + status filter + search, approve / reject / suspend, verified tick, edit, delete, add existing service (unowned, marked unverified), ownership claims, service complaints, categories (5 languages, icon, order, on/off). All via server functions with is_admin() + audit log.
- **Languages:** Georgian (KA) added for the whole app; missing keys in any language fall back to English.

## Database — supabase/migrations/0017_services.sql
New only: `service_categories` (8 seeded), `service_providers`, `service_reviews`, `service_claims`, bucket `service-photos`, functions `nearby_services`, `admin_*service*`. `reports.target_type` gains `'service'`. No existing data is changed or deleted; re-runnable.

Security: RLS on every table; owners can edit only their own row; a trigger blocks owners from setting status / verified / rating; ratings are recomputed by trigger; one profile per account; blocked users cannot add profiles, reviews or claims; photos writable only by the owner/admin.

## Tests (local PostgreSQL 16 with Supabase stubs)
- Migration applied twice on a DB with 0001–0016: OK (idempotent).
- Owner cannot self-approve / fake rating / set another owner; unknown categories dropped.
- Second profile for the same account rejected.
- Review → rating 4.00 (1); owner cannot review own profile.
- nearby_services: 1 hit at 1.4 km in Baku, 0 in Tbilisi; category filter OK.
- Non-admin calling admin function → `admin_only`.
- Admin add → approved + unverified + unowned; claim on owned service refused; claim approval links owner and sets verified.
- admin_service_counts counts service complaints.
Flutter code is not compiled locally (no SDK); it was reviewed statically and is built by GitHub Actions.

## Later phases (not built)
AI fault analysis, automatic mechanic dispatch, payments. For high traffic, move map tiles / routing / geocoding off the free public OSM servers.
