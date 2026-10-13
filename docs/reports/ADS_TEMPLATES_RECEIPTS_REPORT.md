# Ads: templates, receipt payments, home-feed switch (0021)

## Flow
1. **Admin → Reklamlar → Şablonlar**: upload a 1350×300 background (any photo is centre-cropped), define 1–6 text fields (position, width, font size, max length, alignment, bold, default text) and the colours customers may pick; activate / deactivate; edit any time (existing orders keep a snapshot).
2. **Customer → Profil → Reklam ver → Reklam yarat**: pick an active template, type the texts, pick a colour (live preview), destination (FreightLink profile or https link), countries / route, 5 / 15 / 30 days, start date → total from the admin's price → confirm.
3. Order gets a number (R-1001…), shows the amount, the order number to write in the transfer, and the bank / card details saved by the admin.
4. Customer uploads a photo of the receipt (private bucket `ad-receipts`) → status "Yoxlanılır". Nothing is marked paid automatically.
5. **Admin** sees order + receipt → "Ödəniş yoxlanıldı — təsdiqlə" creates the ad: starts 00:00 (Baku) on the chosen day (or now if that passed), ends exactly N days later; or "Rədd et" with a reason the customer sees.
6. "Sifarişlərim": Ödəniş gözlənilir → Yoxlanılır → Təsdiqləndi / Rədd edildi → Planlaşdırılıb → Aktivdir → Bitib.
7. **Ana səhifə reklamları** switch (Admin → Reklamlar, top): default OFF — no ads and no empty ad slots. ON — only ads that are on, inside their dates and paid (or admin-made without an order). The switch never changes orders or payments.

## Database (0021, forward-only, re-runnable)
New: `ad_templates`, bucket `ad-receipts` (private, 10 MB), functions `create_ad_order_from_template`, `submit_ad_receipt`, `admin_review_ad_order`, `admin_save_ad_template`, `admin_set_ad_template_active`, `home_ads_enabled`, `admin_set_home_ads_enabled`, `home_feed_ads`, `is_own_ad_order`. New nullable columns on `ad_orders` (order_no, template_id, creative, starts_on, receipt_path, receipt_uploaded_at, reviewed_at, ad_starts_at, ad_ends_at) and `ads.creative`. Packages d5 / d15 / d30 seeded hidden with price 0.

## Tests (disposable PostgreSQL 16)
- 0001–0021 apply; data-preservation check identical; re-run idempotent.
- `60_ads_flow.sql`: 34/34 (template validation, admin-only writes, colour / duration / price / text-length / date / https checks, price from server, snapshot, receipt path ownership, no approval without receipt, receipt ≠ paid, approve → ad with exact N days, reject needs reason, switch default OFF, ON shows only paid + started ads, scheduled / ended hidden, unpaid order's ad hidden, switch OFF keeps orders/payments, other users / blocked users refused, deactivated template hidden but orders keep banners).
- Package 1 / 1B suites 58/58, 54/54; messaging test passed; search_path scenarios passed.
- Flutter: not compiled here (no SDK); statically reviewed; CI builds it.

## Messages list: one row per person
Each load has its own chat with a person (plus an optional direct chat), so the same name could appear several times with an identical route. The list now shows one row per person (latest route + "N söhbət", unread counts summed); tapping it opens a short list of that person's chats when there is more than one. No data is changed.

## 0022 — customer logo + template window
- Admin: separate side-menu item **Reklam şablonları** (also the "Şablonlar" tab in Reklamlar). Template editor has "Bu şablonda loqo yeri olsun" with position / size sliders.
- Customer: entering **Reklam ver** opens the "Şablon seçin" window automatically (also via "Reklam yarat"); choosing a template opens the editor with it; customer types texts, uploads a logo (own folder in the public `ads` bucket), picks a colour.
- Server: `create_ad_order_from_template(..., p_logo_url)` accepts a logo only from the customer's own `ads/requests/<user id>/` folder and only for templates with a logo place; snapshot stores `logo` + `logo_url`. Tests `61_ads_logo.sql` 5/5; all earlier suites still pass.

## 0023 — standard 1200×400 layout (current)
- Fixed coordinates for every template (logo 30,120 160×160; company 220,45 440×85; activity 220,150 440×75; phone 220,250 440×70; visual zone 690,20 490×360). Admin uploads only backgrounds (centre-cropped to 1200×400), names, orders (↑/↓), switches on/off, deletes.
- Customer: background → company / activity / phone → logo (PNG/JPG/WEBP ≤ 2 MB, decoded before upload, own folder only; whole logo inside the circle, circle background dark / light / none) → per line font (Montserrat, Inter, Roboto Condensed, Noto Sans, Noto Serif), size 60–100 %, any colour. Text auto-shrinks to its box (1–2 lines, phone 1). Automatic two-layer shadow + soft left gradient; the same widget draws preview, admin view and feed.
- Editing: until approval; after a receipt the change sends the order back to review (flag shown to admin); approved ads are locked.
- Two independent admin switches, both OFF by default: ads in the load list; "Reklam ver" entry (server also refuses new orders while off). Customers with orders still see them.
- Feed: 6 loads → 1 ad, ads take turns, no empty slot, small "Reklam" badge, 3:1 card never cropped.
- Old 1350×300 templates and ads switched OFF (kept); old ads cannot be re-activated; the free-layout order function is retired.
- Admin: link + dates per ad, pause / resume, views / clicks.
- Tests: `62_ads_v2_flow.sql` 36/36 on 0001–0023 (+ package 1 58/58, 1B 54/54, messaging, idempotency, data preservation); legacy-data run: old ad + template switched off, rows kept, `ads` bucket limited to PNG/JPEG/WEBP. 60/61 (0021/0022 flow) superseded.
- **Flutter build NOT run here** (no Flutter SDK in this environment). Code reviewed statically twice; GitHub Actions ("Deploy Web" + "CI checks") is the build check.

---

## 0024 — Admin reklam redaktəsi, təmiz telefon, ölkə marşrutu, tarixsiz sifariş

**Tapılan problemlər (canlı testdən):**
1. iPhone-da yapışdırılan nömrəyə görünməz simvol (U+202A və s.) əlavə olunurdu → "Telefon nömrəsi düzgün deyil".
2. Marşrut sərbəst mətn idi ("baki → gurcustan"). Yüklərdə ölkə saxlanılır, ona görə reklam heç bir yükə uyğun gəlmir və göstərilmirdi.
3. Yük siyahısında 6 və ya daha az yük olanda reklam heç vaxt görünmürdü.
4. Müştəri başlama tarixi seçməli idi (istənilmir).

**Edilənlər:**
- `0024_ads_admin_edit.sql` (yalnız funksiyalar; heç bir sətir silinmir/dəyişdirilmir, təkrar işlədilə bilər):
  - `_ad_clean_text`: görünməz simvollar silinir, qeyri-adi boşluqlar normal boşluq olur. Müştəri yaratma/redaktə və admin redaktəsi hamısı bundan keçir.
  - Marşrut yalnız ölkə kodu (AZ, GE …) və ya boş. Köhnə sətirlər toxunulmur; admin onları redaktorda düzəldir.
  - `create_ad_order_v2`: `p_starts_on` boş ola bilər → bu gün; reklam admin təsdiq edəndə başlayır və 5/15/30 gün gedir. Köhnə tətbiq tarix göndərsə, əvvəlki kimi yoxlanır.
  - `admin_update_ad_order_v2`: yalnız admin. Sifarişi və yayımlanmış reklamı birlikdə dəyişir: fon, mətnlər, şrift/ölçü/rəng, loqo (müştərinin və ya adminin qovluğundan), link, hədəf ölkələr, marşrut, yayım tarixləri. Status və ödəniş toxunulmur. Hər dəyişiklik `admin_audit_log`-a yazılır (əvvəl/sonra). Şablon silinibsə, mövcud fon saxlanılır.
- Tətbiq:
  - Reklam yarat: 8-ci "Başlama tarixi" bölməsi silindi; aşağıda "Təsdiqdən sonra N gün".
  - Marşrut: ölkə siyahısından seçim ("İstənilən ölkə" = hamısı).
  - Telefon: görünməz simvollar tətbiqdə də təmizlənir.
  - Lent: ≤6 yük olanda reklam son yükdən sonra bir dəfə göstərilir.
  - Admin → Reklamlar: hər reklamda və sifarişdə **"Redaktə et"**; tam redaktor (müştərinin redaktoru ilə eyni, admin rejimində). Tanınmayan köhnə marşrut qırmızı xəbərdarlıqla göstərilir.

**Yoxlama:**
- Lokal PostgreSQL 16: 0018–0024 + testlər — 30 (58), 40 (54), 62 (36), **63 (19 yeni)**, mesajlaşma testi, məlumatların qorunması (38 cədvəl eyni), təkrar tətbiq — hamısı keçdi. 50_searchpath_scenarios keçdi.
- Dart: statik yoxlama + ayrıca baxış (2 xəta tapıldı və düzəldildi). **Flutter build burada mümkün deyil** — GitHub Actions "Deploy Web" yaşıl ✓ olmadan hazır sayılmamalıdır.

---

## 0025 — Reklamın yeri və müddəti (admin tənzimləməsi)

- Admin → Reklamlar (və Reklam şablonları) → **"Reklamın yeri və müddəti" → Tənzimlə**:
  - İlk reklam neçə yükdən sonra (1–50), sonra hər neçə yükdən bir (2–50);
  - Bir reklamın müddəti, dəqiqə (0–1440; 0 = dəyişmir). Bir neçə canlı reklam olanda hər yer X dəqiqədən bir növbəti reklama keçir; tək reklam varsa, həmişə o görünür.
  - Pəncərədə canlı önizləmə (Yük 1… / REKLAM).
- Default 6 / 6 / 0 = əvvəlki davranış (lokal simulyasiya ilə yoxlanılıb: 0–59 yük üçün eyni nəticə).
- `0025_ads_feed_layout.sql`: `ads_feed_layout()` (oxu, giriş edənlər), `admin_set_ads_feed_layout()` (yalnız admin, yoxlama, audit log). Heç bir məlumat silinmir.
- Lokal testlər: 64 (9 yeni) + əvvəlki bütün testlər keçdi, məlumat qorunması və təkrar tətbiq OK.
- **Flutter build burada mümkün deyil** — GitHub Actions yaşıl ✓ şərtdir.

---

## 0026 — Reklam sırası, təkrarsız göstərmə, sıra dəyişmə vaxtı

- Hər reklam yük siyahısında **yalnız bir yerdə** çıxır (default). Reklamdan çox yer varsa, artıq yerlər boş qalır. Admin "Eyni reklam təkrar göstərilsin" ilə təkrarı aça bilər.
- **Sıra:** Admin → Reklamlar → Reklamlar siyahısında aktiv reklamlar "Sıra 1, 2, 3…" ilə və ↑ ↓ düymələri ilə. 1-ci reklam 1-ci reklam yerində, 2-ci 2-ci yerdə və s. (`ads.priority`, `admin_set_ads_order`).
- **Sıra dəyişmə vaxtı (dəq):** hər X dəqiqədən bir sonuncu reklam önə keçir, digərləri bir yer aşağı düşür (A1,A2,A3 → A3,A1,A2 → A2,A3,A1 …). Bütün istifadəçilərdə eyni saatla.
- `0026_ads_order_no_repeat.sql`: `ads.priority` (default 100, əlavə sütun), `ads_feed_layout()` + `repeat`, `admin_set_ads_feed_layout` 4 parametrli (3 parametrli köhnəsi də işləyir), `admin_set_ads_order`, `home_feed_ads` sıraya görə. Heç bir sətir silinmir.
- Lokal testlər: 65 (8 yeni) + bütün əvvəlkilər keçdi; məlumat qorunması və təkrar tətbiq OK. Dart: statik yoxlama + ayrıca `const` skanı. **Flutter build yalnız GitHub Actions-da** — yaşıl ✓ şərtdir.

---

## Canlı xəritə (yüklər bölməsi) — yeni animasiya

- `assets/images/world_map.jpg`: eyni xəritə (1400×700), dəniz və buludlar tətbiqin xəritə paneli rənginə (#070C18) boyanıb; qurular və şəhər işıqları dəyişməyib.
- `live_map.dart`: 30 kiçik, qarışıq rəngli neon yük maşını şəhərlər arasında qövslə gedir (arxada parlayan iz, qabaqda qırıq yol xətti, axan » oxları); mərkəzlərdə döyünən halqalar (böyüklər narıncı); maşın çatanda halqa parlayır; ~150 şəhər işığı yanıb-sönür. Önizləmədən bir az sürətli.
- Performans: əvvəlki kimi — lent sürüşəndə / xəritə görünməyəndə dayanır; kadrlar yavaşlayanda ~30 fps, 12 maşın, qırıq xətt və oxlar söndürülür. Blur yoxdur.
- SQL tələb etmir. Flutter build yalnız GitHub Actions-da yoxlanır.

### Xəritə — 2-ci variant (təsdiqlənmiş)
- Fon rəngi bütün tətbiqdə daha tünd: `AppColors.background` = `AppColors.hero` = #02050C (web/index.html və manifest də). Xəritənin dənizi eyni rəngdədir.
- Xəritə kənar boşluqlarsız kəsilib (1220×580), tam enlikdə iri görünür; şəhər işıqları bir az parlaq.
- 15 maşın (zəif telefonda 8), bir az sürətli; ~300 yanıb-sönən şəhər işığı; hər 0,25–0,7 san-dən bir təsadüfi şəhərdə rəngli "yeni yük" siqnalı; halqalar daha tez döyünür. Blur effekti yoxdur.

---

## Mesajlar — bir şəxs = bir söhbət
- Mesajlar siyahısında şəxsə toxunanda artıq seçim pəncərəsi açılmır: həmin şəxslə **bütün yük söhbətləri və şəxsi söhbət bir səhifədə**, vaxt sırası ilə göstərilir.
- Mövzu dəyişən yerdə zaman xəttində kiçik nişan ("🚚 Azərbaycan → Gürcüstan" / "Şəxsi söhbət"). Yazı qutusunun üstündə "Mövzu:" çipləri — default son mesajın mövzusudur, istəsə dəyişir.
- Baza dəyişmir (söhbətlər birləşdirilmir, köçürülmür) — yalnız göstəriş. `/messages/<id>` linkləri də işləyir (həmin mövzu seçilmiş açılır).

## Servislər — "Reklam agentliyi və ustası"
- `0027_service_category_advertising.sql`: yeni kateqoriya (5 dildə), ikon `campaign`. Yalnız 1 sətir əlavə edir.

## Waze ilə naviqasiya (çatdakı konum, yük səhifəsi)
- iPhone-da köhnə `waze.com/ul` linki Safari-ni `waze://` sxeminə yönləndirirdi → ana ekrandakı tətbiqdən və ya Waze yoxdursa "adres geçersiz" xətası. İndi `https://www.waze.com/live-map/directions?to=ll.LAT%2CLNG` istifadə olunur: Waze varsa tətbiq açılır, yoxdursa marşrut Waze veb xəritəsində göstərilir.

## 0028 — Servislər dərhal dərc olunur, PRO servis
- Yeni servis profili yadda saxlanan kimi xəritədə görünür (status `approved`); admin sonradan rədd / deaktiv edə bilər. Sahib status, mavi nişan, PRO və reytinqi özü dəyişə bilməz.
- `service_providers.is_pro` (yalnız admin, `admin_set_service_pro`, audit log): qızılı "PRO" nişanı, profil başında qızılı zolaq, xəritədə qızılı halqa, siyahıda ən yuxarıda. Reytinq ulduzları yalnız real rəylərdən gəlir — saxta 5 ulduz qoyulmur.
- Servis sahibi profilində "Servisinizi reklam edin" kartı → mövcud "Reklam ver" axını.
- Mavi nişan: Admin → Servislər → "Təsdiq nişanı ver" (əvvəldən var idi).
- Mövcud "pending" profillər migrasiya ilə dəyişdirilmir; admin təsdiqləyir və ya bir sətirlik SQL ilə.
- Lokal testlər: 66 (8 yeni), suite 30-da G8 yeni qaydaya uyğunlaşdırıldı; hamısı keçdi, məlumat qorunması OK.

## Servis: "Mesaj yaz" — iki seçim
- Düymə həmişə aktivdir; açılan pəncərədə: **FreightLink-də mesaj yaz** (servisin hesabı varsa və öz servisiniz deyilsə) və **WhatsApp ilə yaz** (WhatsApp nömrəsi, yoxdursa telefon; `wa.me`). Mümkün olmayan seçim səbəbi ilə boz göstərilir.

## 0029 — Servis reklamları
- Fonların "kim üçün" seçimi: Yük / Servis / Hər ikisi (Admin → Reklam şablonları → fon → "Kim üçündür"). Köhnə fonlar "Yük" olaraq qalır.
- Servis sahibi profilindən "Servisinizi reklam edin" → servis fonları, eyni 1200×400 sxem (koordinatlar dəyişmir), yalnız xidmət göstərdiyi ölkələr (haradan → haraya yoxdur); ad / telefon servisdən avtomatik doldurulur. Reklama toxunan servis profilinə keçir. Qiymət, qəbz, admin təsdiqi — adi qayda (`create_service_ad_order`, `destination_type = 'service'`).
- Admin redaktəsi servis reklamının keçidini dəyişmir.
- Loqo dairəsi: loqo dairəni tam doldurur (dairəvi kəsilir, künclər görünmür); dairənin yeri və ölçüsü (30,120 · 160×160) eynidir.
- Lokal testlər: 67 (8 yeni) + bütün əvvəlkilər keçdi.
