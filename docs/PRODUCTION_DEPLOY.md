# Production-a tətbiq — vahid təlimat (Package 1 + 1B + reklam yeniləməsi)

Bu sənəd yeganə etibarlı ardıcıllıqdır. `docs/reports/` qovluğundakı köhnə hesabatlar yalnız tarixçədir.

## Vəziyyət
| Miqrasiya | Production |
|---|---|
| `0001`–`0017` | tətbiq olunub (SQL Editor ilə). **Bu fayllar dəyişdirilməyib.** |
| `0018_package1_security.sql` | **tətbiq olunmayıb** |
| `0019_package1b_security.sql` | **tətbiq olunmayıb** (əvvəlki uğursuz cəhd tam geri qaytarılıb) |
| `0020_advertiser_campaign_details.sql` | **tətbiq olunmayıb** |
| `0021_ad_templates_receipts.sql` | **tətbiq olunmayıb** — 0020-dən sonra |
| `0022_ad_template_logo.sql` | **tətbiq olunmayıb** — 0021-dən sonra |
| `0023_ads_standard_layout.sql` | **tətbiq olunmayıb** — 0022-dən sonra |

## ⚠️ `supabase db push` istifadə ETMƏYİN
Əvvəlki miqrasiyalar SQL Editor ilə tətbiq olunub, Supabase CLI-nin miqrasiya tarixçəsində qeydə alınmayıb. `db push` 0001-dən başlayaraq hamısını yenidən icra etməyə cəhd edər. Yalnız aşağıdakı SQL Editor addımlarından istifadə edin.

## Addımlar
1. **Backup:** Dashboard → Database → Backups (və ya `supabase db dump`).
2. **Diaqnostika (heç nə dəyişmir):** SQL Editor-da `supabase/diagnostics/search_path_audit.sql` faylını işə salın. Bu fayl miqrasiya deyil.
   - `migration_role_can_alter = false` olan sətir varsa, davam etməzdən əvvəl nəticəni yoxlayın.
3. **Veb tətbiqi yayımlayın:** GitHub-a push edin → "Deploy Web" iş axını Flutter build edib GitHub Pages-ə yükləyir. Yeni versiya həm köhnə, həm yeni bazada işləyir.
4. Bir neçə saat (və ya bir gün) gözləyin ki, istifadəçilərin PWA-sı yeni versiyaya keçsin.
5. **SQL Editor → `0018_package1_security.sql`** — faylın tam məzmununu yapışdırıb **Run**.
6. **SQL Editor → `0019_package1b_security.sql`** — eyni qayda ilə.
7. **SQL Editor → `0020_advertiser_campaign_details.sql`** — əvvəlki ikisi uğurla bitəndən sonra tətbiq edin.
   0018/0019 öz-özünü yoxlayır. 0020 təkrar icra üçün hazırlanıb, amma əvvəlcə ehtiyat nüsxə saxlayın.
8. **SQL Editor → `0021_ad_templates_receipts.sql`** — 0020-dən sonra. Reklam şablonları, qəbz ilə ödəniş və ana səhifə reklam açarı (ilkin: deaktiv).
8. **Diaqnostikanı yenidən işə salın:** statuslar `ok …` (və ya `skipped (extension)`), `migration_0018_applied = true`, `migration_0019_applied = true`, `old_open_users_policy_present = false` olmalıdır. Reklam əlavəsinin hazır olduğunu `to_regclass('public.ad_events')` nəticəsinin boş olmaması və `public.create_ad_order_request` funksiyasının mövcudluğu ilə yoxlayın.
9. **Admin hesablarını yoxlayın** (yalnız oxuyur):
   ```sql
   select u.id, u.email, u.created_at, a.raw_user_meta_data->>'role' as requested_role_at_signup
   from public.users u join auth.users a on a.id = u.id
   where u.role = 'admin' order by u.created_at;
   ```
   Tanımadığınız admin varsa, mənə bildirin — avtomatik heç nə dəyişdirilmir.

## Supabase Dashboard ayarları (əllə)
- **Authentication → URL Configuration → Redirect URLs:** `https://<github-istifadəçi>.github.io/<repo>/**` əlavə edin (şifrə bərpa linki üçün).
- **Authentication → Providers → Email:** minimum şifrə uzunluğu **8**; "Leaked password protection" (varsa) aktiv; **"Require current password when updating"** aktiv.
- *Tövsiyə (iPhone ana ekran PWA):* "Reset Password" e-poçt şablonunda link:
  `{{ .SiteURL }}/#/reset-password?token_hash={{ .TokenHash }}&type=recovery`

## GitHub (bir dəfə)
- Settings → Secrets and variables → Actions: `SUPABASE_URL`, `SUPABASE_ANON_KEY` (anon/publishable açar; service-role açarını **heç vaxt** əlavə etməyin).
- Settings → Pages → Source: **GitHub Actions**.

## Yoxlama (staging və ya production, tətbiqdən sonra)
Giriş · yük elanı + "Haradan → Haraya" axtarışı · hər 2 yükdən sonra reklam yeri · Profil → Reklam ver (banner, başlıq, hədəf və sifariş) · reklam klik/baxış sayı · yük sahibinin kontaktı · mesaj göndər/al və mesaj başlığından profilə keçid · servis xəritəsi · admin → İstifadəçilər (canlı siyahı, bloklama) · şifrə dəyişmə/bərpa.
