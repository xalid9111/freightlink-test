# Package 1B — İstifadəçi məxfiliyi, hesab təhlükəsizliyi və şifrə idarəetməsi

Status: **yoxlanış üçün hazırdır. Production bazasına tətbiq EDİLMƏYİB.** Bu paket canlı bazaya avtomatik heç nə etmir.
Asılılıq: `0019` yalnız `0018`-dən (Package 1) sonra tətbiq olunur.

---

## 1. Dəyişdirilmiş fayllar (Package 1 vəziyyəti ilə müqayisədə)

**Yeni**
| Fayl | Məqsəd |
|---|---|
| `supabase/migrations/0019_package1b_security.sql` | Forward-only migrasiya (0001–0018 toxunulmayıb) |
| `lib/features/auth/data/password_service.dart` | Şifrə dəyişmə / bərpa — yalnız Supabase Auth API |
| `lib/features/auth/presentation/change_password_screen.dart` | Profil → "Şifrəni dəyiş" ekranı, "Şifrəni unutmusunuz?" düyməsi |
| `lib/features/auth/presentation/reset_password_screen.dart` | E-poçt linki ilə yeni şifrə (`/reset-password`) |
| `lib/core/router/password_recovery.dart` | Bərpa sessiyası vəziyyəti (router üçün) |
| `supabase/tests/local/40_package1b_after.sql` | 1B testləri (54 yoxlama) |

**Dəyişdirilmiş**
| Fayl | Dəyişiklik |
|---|---|
| `lib/repositories/profile_repository.dart` | Başqalarının profili `user_profiles` görünüşündən; telefon/e-poçt `get_user_contact` RPC ilə; 0019-dan əvvəl köhnə sorğuya geri dönüş |
| `lib/repositories/credits_repository.dart` | Yük sahibinin kontaktı `get_cargo_contact` RPC ilə (köhnə sorğuya geri dönüşlə) |
| `lib/features/cargo/presentation/cargo_detail_screen.dart` | Kontakt provider-i yükə görə açarlanır |
| `lib/features/cargo/presentation/providers/cargo_providers.dart` | "Aktiv daşıyıcılar" sayğacı görünüşdən |
| `lib/features/chat/data/group_repository.dart` | Qrup üçün adam axtarışı görünüşdən |
| `lib/features/chat/presentation/conversation_thread_screen.dart` | Zəng düyməsi telefonu basanda serverdən alır |
| `lib/features/ads/presentation/public_profile_screen.dart` | Zəng düyməsi serverin icazə verdiyi telefonla |
| `lib/features/auth/presentation/profile_screen.dart` | "Şifrəni dəyiş" bəndi |
| `lib/features/auth/presentation/login_screen.dart` | "Şifrəni unutmusunuz?" linki |
| `lib/core/router/app_router.dart` | `/change-password`, `/reset-password` marşrutları, bərpa yönləndirməsi |
| `assets/i18n/{az,tr,en,ru,ka}.json` | 45 yeni açar + `chat_no_phone` mətni dəqiqləşdirildi (5 dildə) |
| `scripts/validate_i18n.py` | Gürcü dili (`ka`) də yoxlanılır (əvvəl yalnız 4 dil yoxlanırdı) |
| `supabase/tests/local/run_local.sh`, `30_package1_after.sql` | 0018+0019 birlikdə; D10 testi sərtləşdirildi (aşağıda, problem 6) |

---

## 2. Problemlər: səbəb → həll

### 1) İstənilən istifadəçi bütün istifadəçilərin e-poçt, telefon və bloklama səbəbini oxuya bilirdi — YÜKSƏK
- **Səbəb:** `users_select_all` siyasəti (0002, 0009-da `authenticated`-ə daraldılıb) `using (true)` idi. Hər daxil olmuş istifadəçi `public.users`-in bütün sətirlərini və sütunlarını, o cümlədən `email`, `phone`, `preferred_lang`, `is_blocked`, `blocked_until`, `block_reason` sahələrini oxuya bilirdi.
- **Həll:**
  - `users` cədvəli: hər kəs **yalnız öz sətrini** oxuyur (`users_select_own`).
  - Admin mövcud `users_admin_full` siyasəti ilə bütün sətirləri və sütunları görür. Admin panelinin Users səhifəsi və onun Realtime axını dəyişmədən işləyir.
  - Başqaları üçün yeni **`user_profiles`** görünüşü yaradıldı. Burada yalnız ictimai sahələr var: ad, avatar, rol, təsdiq nişanı, "erkən üzv", son görülmə, aktivlik. Görünüş yalnız oxumaq üçündür və anonim istifadəçiyə bağlıdır.
- **Niyə sütun icazəsi yox:** sütun icazəsi ilə bağlansaydı, köhnə PWA versiyaları girişdən sonra öz sətirlərini (`select()`) oxuya bilməz və çıxışa atılardılar. Admin Realtime axını da qırılardı. Sətir səviyyəsində bağlamaq bu riskləri aradan qaldırır.

### 2) Pullu "kontaktı aç" (0006) əslində heç nəyi qorumurdu — ORTA
- **Səbəb:** telefon hamıya açıq olduğu üçün kredit sistemi yalnız UI qapısı idi. Bunu kodun öz şərhi də deyirdi.
- **Həll:** telefon və e-poçt yalnız server qaydası ilə verilir:
  - **`get_cargo_contact(yük)`:** görə bildiyin yükün elan sahibinin adı, telefonu və e-poçtu. Hazırkı bazar davranışı belədir, ona görə saxlanıldı (kredit söndürülüb).
  - **`get_user_contact(istifadəçi)`:** telefon aşağıdakı hallarda verilir:
    - özün və ya admin;
    - kontakt kreditlə açılıb (bu halda e-poçt da verilir);
    - həmin şəxs sənə mesaj yazıb;
    - həmin şəxsin aktiv reklamı var;
    - həmin şəxsin açıq, gizlədilməmiş elanı var.
  - Bloklanmış istifadəçi yalnız öz məlumatını alır.
- **Nəticə:** bütün istifadəçilərin telefon siyahısını çıxarmaq artıq mümkün deyil. Yük elanındakı kontakt bloku, söhbətdəki zəng düyməsi və ictimai profil işləməyə davam edir.

### 3) Öz e-poçtunu başqasının ünvanına dəyişməklə onun qeydiyyatını bloklamaq — ORTA
- **Səbəb:** `guard_user_protected_columns` `email` sahəsini qorumurdu. `users.email` unikal olduğu üçün kiminsə ünvanını "tutmaq" həmin şəxsin qeydiyyatını (signup trigger) xəta ilə dayandırardı.
- **Həll:** `email`, `id`, `created_at` artıq dəyişdirilə bilməz. E-poçt Supabase Auth-dan gəlir.

### 4) Qoruyucu trigger-də `auth.uid() is null` qısa yolu — AŞAĞI (Package 1-in qalıq riski)
- **Səbəb:** trigger `SECURITY DEFINER` idi və istifadəçi id-si olmayan sorğuya hər şeyi icazə verirdi.
- **Həll:** trigger artıq `SECURITY INVOKER`-dir və etibarlı çağıranı `current_user` ilə müəyyən edir (0018-dəki model). Test E8: istifadəçi id-si olmayan sorğu heç bir sətri dəyişə bilmir.

### 5) Admin rolunun icazəsiz əldə edilməsi — yoxlanıldı
| Yol | Nəticə | Test |
|---|---|---|
| Qeydiyyat (`role: admin` metadata) | 0018 ilə bağlanıb | S1, E9 |
| Profil yeniləməsi (`users.role`) | dəyişmir | E1 |
| Öz Auth metadata-sı (`auth.updateUser(data: {role: 'admin'})`) | təsiri yoxdur: `auth.users` üzərində UPDATE trigger yoxdur, heç bir siyasət JWT metadata-sına baxmır | E12 |
| RPC (`admin_update_user`) | `admin_only` | E7 |
| `users` cədvəlinə yeni sətir yazmaq | rədd edilir | E6 |

Admin səlahiyyəti hər yerdə serverdə `is_admin()` ilə yoxlanılır. Klientdəki `/admin` marşrutu yalnız naviqasiyadır.

### 6) Aşkarlanan gizli bug: `users_update_self` + yeni siyasət = sonsuz rekursiya
- **Səbəb:**
  - `users_update_self` (0002) `WITH CHECK` daxilində `users` cədvəlini sorğulayır.
  - Mənim ilk versiyamda yeni oxuma siyasətində `(select auth.uid())` alt-sorğusu var idi.
  - Postgres eyni cədvəli yenidən açanda alt-sorğulu siyasət görür və "infinite recursion" xətası verir.
  - Nəticədə profil yeniləməsi (ad, telefon, avatar, son görülmə) tamam sınardı.
  - 0018-in D10 testi xətanı "qadağan olundu" kimi qəbul edirdi.
- **Həll:**
  - Siyasətdə `auth.uid()` birbaşa işlədilir; bu, migrasiyada şərhlə izah olunub.
  - D10 testi artıq yeniləmənin **uğurlu olduğunu** da yoxlayır.
  - Əlavə yoxlama: 0001–0017 bazasında profil yeniləməsi xətasız işləyir. Deməli bu bug production-da yox idi.

### 7) Şifrəni dəyiş (yeni funksiya)
- **Ekran:** Profil → "Şifrəni dəyiş":
  - mövcud şifrə, yeni şifrə, yeni şifrənin təkrarı;
  - hər sahədə göstər/gizlət;
  - "Şifrəni yenilə" düyməsi.
- **Yoxlama ardıcıllığı (`PasswordService`):**
  1. Mövcud şifrə **Supabase Auth** ilə yoxlanılır (`signInWithPassword`, eyni e-poçt). Səhvdirsə, heç nə dəyişmir.
  2. `updateUser(password, currentPassword)` çağırılır. Supabase-də "require current password" ayarı açıqdırsa, server mövcud şifrəni ikinci dəfə özü yoxlayır. Bu davranışı Supabase Auth mənbə kodunda təsdiqlədim (`internal/api/user.go`).
  3. Supabase şifrə dəyişəndə **digər bütün sessiyaları** özü bağlayır (`LogoutAllExceptMe`).
- **Qaydalar:**
  - minimum 8 simvol;
  - təkrar şifrə uyğun gəlməlidir;
  - yeni şifrə köhnə ilə eyni ola bilməz.
- **Server xətaları ayrıca idarə olunur:**
  - zəif şifrə;
  - sızmış şifrə ("pwned");
  - eyni şifrə;
  - çox cəhd.
- **Şəbəkə xətaları:**
  - Yoxlama mərhələsində kəsilmə: "heç nə dəyişmədi".
  - Saxlama zamanı kəsilmə: "nəticə məlum deyil — yeni şifrə ilə daxil olmağa çalışın". Bu, səhvən "dəyişmədi" deməkdən daha dürüstdür.
  - 20 saniyəlik timeout var.
- **Təkrar basma:**
  - `_busy` qoruyucusu var, düymə də deaktiv olur;
  - bərpa linki üçün 60 saniyəlik gözləmə var.
- **Şifrə saxlanmır:** `public.users`-də, loglarda, lokal yaddaşda və xəta mesajlarında yoxdur. Sahələr istifadədən sonra təmizlənir, avtokorreksiya və təkliflər söndürülüb.
- **Şifrəni unutmuşlar üçün:**
  - "Şifrəni unutmusunuz?" (giriş ekranında və "Şifrəni dəyiş" ekranında);
  - Supabase bərpa linki göndərilir;
  - hesabın olub-olmadığı bildirilmir;
  - linkdən sonra `/reset-password` ekranı açılır.
- **Bərpa ekranı yalnız həqiqi bərpa sessiyasında işləyir.** Adi sessiyada açılsa, "Şifrəni dəyiş"ə yönləndirir. Beləcə mövcud şifrə yoxlamasından yan keçmək mümkün deyil. Bərpa sessiyası ilə tətbiqi gəzmək də olmur.
- **Google/Apple hesabı (şifrəsiz):**
  - izah göstərilir;
  - həmin xidmətin ayarlarına yönləndirilir;
  - istəyə görə FreightLink şifrəsi təyin etmək üçün e-poçt linki göndərilir.
  - Qeyd: Google/Apple girişi tətbiqdə hələ qoşulmayıb, amma ekran hazırdır.

---

## 3. İcra edilmiş testlər (müvəqqəti PostgreSQL 16.15, Supabase stand-in)

| Test | Nəticə |
|---|---|
| 0001–0017 → 0018 → 0019 tətbiqi | OK |
| Məlumatın qorunması: 38 cədvəlin hamısında sətir sayı + MD5 əvvəl/sonra | **eyni** |
| `40_package1b_after.sql` | **54/54 keçdi** |
| `30_package1_after.sql` (Package 1, 0019 ilə birlikdə) | **58/58 keçdi** |
| Mövcud `messaging_audit_test.sql` | **T1–T7 keçdi** |
| 0018+0019 təkrar tətbiqi (idempotentlik) + bütün dəstlər yenidən | **hamısı keçdi**, məlumat eyni |
| `20_package1_before.sql` (köhnə boşluqların təkrar yaradılması) | 9/9 |
| `scripts/validate_i18n.py` (indi 5 dil) | 580 açar, 5 dil eyni, boş dəyər yoxdur |
| `scripts/validate_dart.py` | struktur xətası yoxdur, importlar həll olunur |
| Supabase klient API-si (`gotrue 2.27.2`, `supabase_flutter 2.18.0`) mənbədən yoxlanıldı | `UserAttributes.currentPassword`, `verifyOTP(tokenHash:)`, xəta kodları, `ReplaySubject` davranışı təsdiqləndi |

Sizin 10 ssenarinizə uyğunluq:

| № | Ssenari | Status |
|---|---|---|
| 1 | Adi istifadəçi başqasının şəxsi məlumatlarını oxuya bilmir | **icra edildi, keçdi** (P1–P3, V2–V3) |
| 2 | Admin öz səlahiyyətinə uyğun məlumatları görür | **icra edildi, keçdi** (P6–P7, E10–E11) |
| 3 | Düzgün mövcud şifrə ilə dəyişiklik | **icra edilmədi**, kod yazılıb (səbəb aşağıda) |
| 4 | Yanlış mövcud şifrə rədd edilir | **icra edilmədi**, kod yazılıb |
| 5 | Şifrələr uyğun gəlməyəndə əməliyyat dayanır | **icra edilmədi**, kod yazılıb |
| 6 | İnternet kəsilməsi düzgün idarə olunur | **icra edilmədi**, kod yazılıb |
| 7 | Yeni şifrə ilə giriş işləyir | **icra edilmədi** |
| 8 | Köhnə şifrə ilə giriş mümkün olmur | **icra edilmədi** |
| 9 | Mesajlaşma, yüklər, servislər, admin işləyir | **verilənlər bazası səviyyəsində keçdi** (F1–F7, mesajlaşma testi, Package 1 dəsti); UI səviyyəsində yox |
| 10 | Flutter analyze / test / web build | **icra edilmədi** |

## 4. İcra edilməmiş testlər və səbəbi
- **Flutter `pub get / analyze / test / build web`:** Flutter SDK bu mühitdə yüklənmir (Google storage 403). Yeni Dart kodu **kompilyasiya olunmayıb**. Kodu əllə və Supabase paketlərinin mənbəyi ilə tutuşdurdum, amma deploydan əvvəl `flutter analyze` mütləqdir.
- **Şifrə ssenariləri 3–8:** real Supabase Auth serveri lazımdır. Onu mənbədən qurmaq cəhdi Go asılılıqları üzündən alınmadı (`golang.org` bağlıdır), canlı layihəyə isə qoşulmaq qadağandır. Staging layihədə əllə yoxlama siyahısı:
  1. düzgün şifrə ilə dəyiş;
  2. yanlış mövcud şifrə;
  3. uyğun gəlməyən təkrar;
  4. 7 simvol;
  5. Wi-Fi-ni söndürüb "Şifrəni yenilə";
  6. çıxış → yeni şifrə ilə giriş;
  7. köhnə şifrə ilə giriş (rədd edilməlidir);
  8. ikinci cihazda sessiyanın bağlandığını yoxla;
  9. "Şifrəni unutmusunuz?" → link → yeni şifrə;
  10. iPhone ana ekran PWA-dan bərpa linki.
- **Realtime (admin Users canlı siyahısı):** Realtime serveri burada yoxdur. Bazada yoxladım ki, `users` cədvəli publikasiyadadır və admin RLS-də bütün sətirləri görür (Realtime də bu qaydanı tətbiq edir). Canlı yoxlama staging-də edilməlidir.
- **PostgREST səviyyəsi:** geri dönüş (fallback) kodları (`PGRST202`, `PGRST205`/`42P01`) PostgREST olmadan sınanmayıb.

---

## 5. Köhnə PWA versiyaları ilə uyğunluq riskləri

| Hal | Davranış |
|---|---|
| **Yeni** build, 0019 hələ tətbiq olunmayıb | Tam işləyir: görünüş/RPC yoxdursa, köhnə sorğulara qayıdır |
| **Köhnə** build, 0019 tətbiq olunub | Giriş, öz profil, yüklər, mesajlar, servislər, admin **işləyir** |
| | Başqalarının adı/avatarı boş görünür (kartlarda, söhbət başlığında) |
| | Yük elanında kontakt bloku xəta mesajı göstərir |
| | Zəng düyməsi "telefon əlçatan deyil" deyir |
| | Qrup üçün adam axtarışı boş qaytarır |
| | "Aktiv daşıyıcılar" sayğacı səhv rəqəm göstərir |
| | **Məlumat itkisi və ya çökmə yoxdur.** Səhifəni yeniləmək (yeni service worker) kifayətdir |
| Köhnə build | "Şifrəni dəyiş" yoxdur (yeni funksiya) |

Ona görə Flutter build əvvəl yayımlanır və istifadəçilərin yeniləməsi gözlənilir.

---

## 6. Production-a təhlükəsiz tətbiq ardıcıllığı
1. **Backup** (Dashboard → Database → Backups, və ya `supabase db dump`).
2. Package 1 hələ tətbiq olunmayıbsa: əvvəl Package 1 hesabatındakı addımlar (Flutter → `0018`).
3. Bu paketin Flutter build-ində `flutter analyze` → `flutter build web --release` → deploy.
4. **Supabase Dashboard ayarları** (kodla dəyişmir, əllə edilir):
   - Authentication → URL Configuration → **Redirect URLs**: `https://<sayt>/**` (bərpa linki `#/reset-password`-a qayıdır).
   - Authentication → Policies / Providers → Email:
     - **Minimum password length = 8** (və ya daha çox);
     - "Leaked password protection" (varsa) aktiv;
     - **"Require current password when updating"** (`update_password_require_current_password`) aktiv. Mövcud şifrəni serverdə məcburi edir; bərpa axını bundan azaddır.
   - *Tövsiyə (iOS ana ekran PWA üçün):* "Reset Password" e-poçt şablonunda linki belə dəyişin:
     `{{ .SiteURL }}/#/reset-password?token_hash={{ .TokenHash }}&type=recovery`
     Standart PKCE linki yalnız sorğunun göndərildiyi brauzerdə işləyir. iPhone-da Mail linki Safari-də açır, PWA-nın yaddaşı isə ayrıdır. `token_hash` variantı hər iki halda işləyir; ekran hər iki formatı dəstəkləyir.
5. İstifadəçilərin yeni versiyaya keçməsini gözləyin (PWA reload).
6. `0019_package1b_security.sql` tətbiq edin (`supabase db push` və ya SQL Editor; psql ilə `--single-transaction`). Migrasiya öz-özünü yoxlayır: səhv olsa, hamısı geri qaytarılır.
7. Staging/canlıda yuxarıdakı əllə yoxlama siyahısını keçin.

---

## 7. Qərarınızı tələb edən məqamlar
1. **Yük elanında e-poçt:** hazırda elan sahibinin telefonu **və e-poçtu** elanı görən hər kəsə verilir (mövcud davranış qorunub). Yalnız telefon qalsın istəsəniz, `get_cargo_contact`-da bir sətirdir.
2. **İctimai profildə telefon:** aktiv reklamı və ya açıq elanı olan istifadəçinin telefonu profilindəki zəng düyməsində görünür. Bunu daraltmaq olar.
3. **Söhbətdə telefon:** qarşı tərəf sizə ən azı bir mesaj yazandan sonra görünür. Siz ilk yazanda onun nömrəsi görünmür.

## 8. Qalan risklər
- `is_blocked(uuid)` funksiyası istənilən istifadəçinin bloklu olub-olmadığını (yalnız bəli/xeyr) qaytara bilir. RLS siyasətləri bu funksiyanı çağırdığı üçün daraltmaq hazırda mümkün deyil.
- `users.phone` unikal olduğu üçün öz telefonunu başqasının nömrəsinə dəyişməyə cəhd "bu nömrə istifadə olunur" cavabı verir. Bu, nömrənin qeydiyyatda olub-olmadığını bildirən kiçik bir sızmadır və mövcud UX-dir.
- `user_profiles` görünüşü sahibinin hüquqları ilə işləyir (Supabase linter-i "security definer view" kimi göstərəcək). Bu, qəsdən edilib: yalnız ictimai sütunları hamıya açmağın yolu budur. Gələcəkdə ora sütun əlavə edərkən diqqətli olun; migrasiyanın öz-özünü yoxlaması məxfi sütunları rədd edir.
- Mobil (Android/iOS) build-də bərpa linki üçün deep link qurulmayıb; link vebdə açılır. Bu, PWA üçün problem deyil.

---

## 9. Düzəliş: "0019 self-check: SECURITY DEFINER without search_path=public, pg_temp"

### Səbəb (lokal olaraq eyni mətnlə təkrarlandı)
1. **Həqiqi çatışmazlıq — əsas səbəb.** 0019, 0018-in tətbiq olunduğunu fərz edirdi, amma bunu yoxlamırdı. 0018 olmayan bazada:
   - 0005–0017-dən gələn **58 funksiyada** yalnız `search_path=public` var. `pg_temp` siyahıda olmadığı üçün Postgres onu gizli şəkildə **birinci** axtarır, yəni müvəqqəti cədvəl `public` cədvəlini kölgədə qoya bilər.
   - **2 funksiyada** (`is_admin`, `current_carrier_id`, 0002) search_path ümumiyyətlə yoxdur.
   Yoxlama real zəifliyi tutub.
2. **Yoxlama həm də lazımsız dərəcədə dar idi.** `'search_path=public, pg_temp'` mətninin hərfi bərabərliyini tələb edirdi. Ona görə daha təhlükəsiz `''` və eyni dərəcədə təhlükəsiz `public, extensions, pg_temp` rədd edilərdi, extension funksiyaları da yoxlamaya düşərdi.
3. **Əlavə risk (0018-də).** 0018 bütün funksiyaların search_path-ını `public, pg_temp` ilə **əvəz edirdi**. Production-da `extensions` sxeminə güvənən əl ilə yazılmış funksiya varsa, sınardı.

Uğursuz 0019 bütövlükdə geri qaytarılıb, yarımçıq dəyişiklik qalmır (lokal yoxlandı; Supabase-də diaqnostikanın 2-ci sorğusu ilə yoxlaya bilərsiniz).

### Həll (0018 və 0019-da eyni qayda; hər ikisi production-da hələ tətbiq olunmayıb)
- **Qayda:** SECURITY DEFINER funksiyasında search_path **təyin olunmalıdır**, və ya **boş** olmalı, ya da `pg_temp` **sonuncu** olmalıdır. Bu, hərfi mətn müqayisəsi deyil, həqiqi təhlükəsizlik xassəsidir.
- **Normallaşdırma (mövcud sxemlər saxlanılır):**
  - search_path yoxdur → `public, extensions, pg_temp` (Supabase-in standart axtarış yolu + `pg_temp` sonda);
  - `pg_temp` yoxdur və ya sonda deyil → eyni sxemlər, `pg_temp` sona köçürülür;
  - boş və ya artıq düzgündür → dəyişmir;
  - extension-a məxsus funksiyalar → dəyişdirilmir, NOTICE-də adı çəkilir.
- `ALTER FUNCTION … SET search_path` funksiya gövdəsini və məntiqini dəyişmir (test A12).
- Migrasiya rolu funksiyanı dəyişə bilmirsə (başqa sahib), WARNING verir. Self-check onu **adı, sahibi və search_path-ı ilə** göstərib migrasiyanı dayandırır. Yoxlama zəifləməyib (testlər C1, C2).
- 0018 tətbiq olunmayıbsa, 0019 WARNING verir. 0019 təkbaşına uğurla tətbiq olunur, amma qeydiyyatda `role: admin` boşluğu (test E9) yalnız 0018 ilə bağlanır.

### Yeni fayllar
- `supabase/diagnostics/search_path_audit.sql`: **yalnız oxuyur**. Hər funksiyanın search_path statusunu və 0018/0019-un tətbiq olunub-olunmadığını göstərir.
- `supabase/tests/local/50_searchpath_scenarios.sh`: production ssenariləri.

### İcra edilmiş testlər
| Test | Nəticə |
|---|---|
| Xətanın təkrarlanması (köhnə 0019, 0018-siz baza) | eyni xəta; heç nə tətbiq olunmayıb |
| **A1–A12**: yeni 0019, 0018-siz baza + əl ilə yaradılmış funksiyalar (`''`, `public, extensions`, `pg_temp, public`, `"$user", public`, yolsuz, INVOKER) | 12/12 keçdi |
| **B1–B3**: sonra 0018, sonra yenə 0019 | 3/3 keçdi |
| **C1–C2**: yoxlama təhlükəli yolu (`public`) və yolsuz funksiyanı hələ də rədd edir | 2/2 keçdi |
| 0019 təkbaşına: 38 cədvəlin məlumatı | eyni |
| 0019 təkbaşına: 1B testləri | 53/54 (yalnız E9 — 0018-in işidir) |
| 0018 + 0019 tam dəst, iki dəfə (idempotentlik) | 58/58, 54/54, mesajlaşma testi keçdi, məlumat eyni |

### Supabase-də tətbiq ardıcıllığı
1. Backup.
2. `supabase/diagnostics/search_path_audit.sql` işə salın (heç nə dəyişmir). `migration_role_can_alter = false` olan funksiya varsa, mənə göndərin.
3. **0018-i tətbiq edin**, sonra 0019-u.
4. Diaqnostikanı yenidən işə salın: bütün statuslar `ok …` və ya `skipped (extension)` olmalıdır, `migration_0018_applied` və `migration_0019_applied` isə `true`.
