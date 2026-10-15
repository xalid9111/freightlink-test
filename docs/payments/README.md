# FreightLink — Maliyyə və ödəniş modulu (TEST versiyası)

Bu modul **test rejimində** hazırdır: bütün ekranlar və ödəniş axını işləyir, amma
**real pul hərəkəti yoxdur** və canlı ödəniş bu versiyada açıla bilməz.
Real provayder və bank hesabı ən son mərhələdə qoşulur.

## 1. Nə var

| Hissə | Harada | Qısa |
|---|---|---|
| Maliyyə paneli | Profil → **Maliyyə və ödənişlər** (`/finance`) | yalnız `xelilov.1881@gmail.com` admin hesabı (serverdə user id ilə bağlanır) |
| Panel | Ümumi gəlir, təsdiqlənmiş balans, gözləyən ödənişlər, komissiyalar, çıxarıla bilən məbləğ, banka köçürülən | Test və Canlı rəqəmlər ayrıdır |
| Ödənişlər | tarixçə, status / tarix / axtarış filtrləri, hər ödənişin sifarişi | |
| Bank hesabları | şəxsi kart (yalnız son 4 rəqəm) və VÖEN-li biznes hesabı (IBAN), bir neçə hesab, əsas hesab, deaktiv | yeni hesab **"Təsdiq gözləyir"** — provayder təsdiqləyənə qədər aktivləşmir |
| Ayarlar | rejim (Söndürülüb / Test; Canlı bağlıdır), komissiya %, üsullar | dəyişiklik üçün parol yenidən soruşulur |
| Jurnal | bütün maliyyə əməliyyatları | dəyişdirilə və silinə bilməz |
| Müştəri checkout | Reklam sifarişi → **Onlayn ödə** | iPhone/Mac: Apple Pay + kart; Android/kompüter: Google Pay + kart |

Test rejimində **checkout-u yalnız maliyyə admini görür** — müştərilər görmür.
Mövcud qəbz (çek) yükləmə axını olduğu kimi qalır.

## 2. Təhlükəsizlik (serverdə)

- Hər maliyyə funksiyası `is_finance_admin()` yoxlayır: hesab `finance_admins` cədvəlində **və** `role = 'admin'` olmalıdır. RLS: başqa adminlər belə görə bilmir.
- Məbləğ həmişə sifarişdən (serverdə) götürülür; tətbiq məbləğ göndərmir.
- İkiqat klik: hər checkout-un bir açarı (idempotency key) var + "bir sifariş üçün bir açıq ödəniş" qaydası.
- Sifariş **yalnız** imzası yoxlanmış provayder hadisəsi ilə və **yalnız canlı rejimdə** "ödənilib" olur. Test ödənişi sifarişi dəyişmir.
- Webhook: HMAC-SHA256 imza, 5 dəqiqəlik pəncərə (təkrar göndərmə qəbul olunmur), hər hadisə bir dəfə tətbiq olunur (`ad_payment_events` unikal), məbləğ / valyuta / provayder yenidən yoxlanır.
- API və webhook açarları yalnız **Supabase → Edge Functions → Secrets**-dədir; tətbiqdə və repoda yoxdur.
- Kartın tam nömrəsi və CVV heç yerdə soruşulmur və saxlanmır (bazada yalnız son 4 rəqəm). IBAN tətbiqə yalnız maskalı qaytarılır.
- Bank hesabı və ayar dəyişiklikləri üçün əlavə autentifikasiya: son 5 dəqiqədə parolla giriş (və ya MFA).
- Canlı rejim, köçürmə (payout) və real provayder bu versiyada **bağlıdır** — saxta aktivləşdirmə yoxdur.

## 3. Quraşdırma (test rejimi)

1. **SQL**: `supabase/migrations/0037_finance_payments.sql` → Supabase SQL Editor → Run.
   Yoxlama: `select user_id, email from public.finance_admins;` — bir sətir olmalıdır.
   Boşdursa, `xelilov.1881@gmail.com` hesabının `users.role`-u `admin` olmalıdır; sonra `select public.finance_sync_owner();`.
2. **Secret**: Supabase → Edge Functions → Secrets → `PAYMENTS_TEST_WEBHOOK_SECRET` = uzun təsadüfi mətn (məs. 40+ simvol).
3. **Edge Functions** (Dashboard → Edge Functions → Deploy a new function → Via Editor):
   - `payments-checkout`: `docs/payments/payments-checkout.dashboard.ts` faylını yapışdırın. **Verify JWT: ON**.
   - `payments-webhook`: `docs/payments/payments-webhook.dashboard.ts`. **Verify JWT: OFF** (provayder imza ilə yoxlanır).
   CLI ilə: `npx supabase functions deploy payments-checkout` və `npx supabase functions deploy payments-webhook --no-verify-jwt`.
4. Tətbiq: Profil → Maliyyə və ödənişlər → **Ayarlar** → Rejim **Test** → Yadda saxla (parol soruşulur).

## 4. Test ssenarisi

1. Öz hesabınızla reklam sifarişi yaradın (ödənilməmiş).
2. Sifariş ekranı → **Onlayn ödə** → üsul seçin → **Ödə**.
3. Test ödəniş səhifəsi → **Ödənişi təsdiqlə (test)** → "Test ödənişi uğurlu oldu".
4. Maliyyə → Panel (Test) → gəlir, komissiya, balans yenilənib; Ödənişlər → sifarişin nömrəsi görünür.
5. Eyni sifarişi yenidən ödəmək → "Bu sifariş artıq ödənilib". **İmtina et (test)** → "Ödəniş alınmadı".
6. Bank hesabları → kart / VÖEN hesabı əlavə edin → "Təsdiq gözləyir"; əsas hesabı dəyişin; köhnəni deaktiv edin.
7. Başqa hesabla daxil olun → Profil-də "Maliyyə" yoxdur, `/finance` → "yalnız maliyyə admininə açıqdır".

## 5. Real provayder üçün lazım olanlar (son mərhələ)

Azərbaycanda Apple Pay + Google Pay + Visa/Mastercard qəbul edən e-commerce provayderi
(məs. **Payriff**, **Epoint** və ya bankın e-commerce xidməti; Stripe Azərbaycan şirkətlərinə açılmır) ilə:

| Lazım olan | Haradan |
|---|---|
| Merchant müqaviləsi (Apple Pay, Google Pay, Visa/Mastercard aktiv) | provayder / bank |
| Merchant ID, gizli API açarı | provayderin kabineti → Supabase Secrets (`PAYRIFF_MERCHANT_ID`, `PAYRIFF_SECRET_KEY` və ya `EPOINT_PUBLIC_KEY`, `EPOINT_PRIVATE_KEY`) |
| Webhook imza açarı | provayder → Secrets (`PAYRIFF_WEBHOOK_SECRET` …) |
| Webhook ünvanı | `https://<project>.supabase.co/functions/v1/payments-webhook/<provayder>` |
| Apple Pay domen təsdiqi | provayderin verdiyi faylı `web/.well-known/` altına qoymaq |
| Google Pay merchant ID | Google Pay Business Console (provayder vasitəsilə) |
| Şirkət sənədləri, VÖEN, IBAN, sahibin şəxsiyyəti | provayderin KYC yoxlaması |
| Payout (banka köçürmə) API-si və ya bankın köçürmə müqaviləsi | provayder / bank |

Qoşulma işi: provayderin adapteri (`supabase/functions/_shared/payments.ts`), onun imza
yoxlaması (`payments-webhook`) və canlı rejimin açılması (yeni miqrasiya). O vaxta qədər
bütün real provayder sorğuları "provider_not_configured / not_implemented" ilə rədd olunur.

## 6. Testlər

- SQL: `supabase/tests/local/75_finance.sql` (67 yoxlama: giriş, ikiqat klik, webhook idempotentliyi, məbləğ yoxlaması, test/canlı ayrılığı, hesablar, jurnal).
- Edge Functions: `node --experimental-strip-types --test supabase/functions/_shared/payments_test.ts`.
- Tətbiq: `test/finance_logic_test.dart`.
- Bundles: `python3 scripts/bundle_payment_functions.py --check`.

## 7. Geri qaytarma

Tətbiq: PR-ı **Revert**. Verilənlər bazası: 0037 yalnız yeni cədvəllər əlavə edir; köhnə tətbiq onlarla işləməyə davam edir. Ödənişi söndürmək üçün: Ayarlar → **Söndürülüb**.
