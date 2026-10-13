# AutoFix — hesabat

## 1. Mövcud layihənin analizi (əvvəl)
- Qlobal xəta tutucu yox idi (`FlutterError.onError`, `PlatformDispatcher.onError` boş).
- Provider (API, söhbət axınları) xətaları yalnız ekranda göstərilirdi, heç yerə yazılmırdı.
- Bilinməyən link → go_router-in standart xəta səhifəsi (geri yolu yox).
- Mesaj göndərmə xətası yalnız "Göndərilmədi" yazısı ilə bitirdi.
- Tətbiq arxa fondan qayıdanda söhbət axınları yenilənirdi (ResumeRefresher) — bu saxlanıldı.
- GitHub-da yalnız deploy workflow-u var idi; `flutter analyze` / `flutter test` işə düşmürdü.
- Web release build minified-dir və source map-siz qurulur → brauzerdə stack trace-də Dart fayl/sətir adətən görünmür.

## 2. Nə əlavə olundu
| Hissə | Fayl |
|---|---|
| Server (cədvəllər, RPC, RLS) | `supabase/migrations/0034_autofix.sql` |
| SQL testləri (20 yoxlama) | `supabase/tests/local/72_autofix.sql` |
| Təmiz məntiq (təsnifat, fingerprint, stack, limit) | `lib/core/autofix/autofix_logic.dart` |
| Runtime (tutma, bərpa, göndərmə, admin əmrləri) | `lib/core/autofix/autofix.dart` |
| Web köməkçi | `web/autofix.js`, `lib/core/autofix/autofix_platform_*.dart` |
| Bilinməyən link ekranı | `lib/core/autofix/route_error_screen.dart` |
| Admin → AutoFix səhifəsi | `lib/features/admin/presentation/admin_autofix_page.dart` |
| Dart unit testləri | `test/autofix_logic_test.dart` |
| GitHub yoxlaması | `docs/autofix/autofix-ci.yml`, `scripts/autofix_ci_report.py` |
| Qoşulma nöqtələri (kiçik) | `main.dart`, `app_router.dart` (errorBuilder), `chat_input_bar.dart` (göndərmə xətası), `admin_shell.dart` (bölmə) |

## 3. Avtomatik düzəldilə bilən xətalar (əvvəlcədən müəyyən, məhdud)
| Xəta | Avtomatik (tətbiqin özü) | Admin "Problemi həll et" |
|---|---|---|
| Sessiya bitib (JWT expired, 401, PGRST301) | sessiyanı 1 dəfə yeniləyir (2 dəq), sonra sorğunu təkrarlayır | bütün tətbiqlərdə sessiya + məlumat yenilənməsi |
| İnternet / timeout / "Failed to fetch" / 502-504 | uğursuz **oxuma** sorğusunu max 2 dəfə (3 s, 10 s gecikmə ilə) | məlumatların təkrar yüklənməsi |
| Server 5xx (PGRST000/001/002, 500) | eyni (max 2 təkrar) | eyni |
| Söhbət / realtime bağlantısı qırılıb | söhbət axınlarını yenidən qurur (max 3 dəfə / 5 dəq) | bütün tətbiqlərdə yenidən qoşulma |
| Donma (UI 4+ s bloklanıb) | təkrar donmada şəkil yaddaşını boşaldır (5 dəq-də 1 dəfə) | tətbiq arxa fona keçəndə səhifəni yenidən yükləyir |
Heç biri məlumat yazmır və silmir; hamısı yalnız oxuma / yenidən qoşulmadır.

## 4. Manual müdaxilə tələb edənlər
| Xəta | Səbəb | Admin paneldə |
|---|---|---|
| Kod xətaları (Null check, TypeError, RangeError…) | kodun özü səhvdir, avtomatik "düzəltmək" təhlükəlidir | "Avtomatik düzəliş mümkün deyil" + fayl, sətir, stack, son addımlar, "Kopyala" |
| İcazə / məlumat xətaları (42501, 23505, invalid_font kimi) | server qaydası və ya kodla uyğunsuzluq; təkrar sorğu kömək etmir | eyni |
| Bilinməyən link (naviqasiya) | səhv link / köhnə route | istifadəçiyə "Ana səhifəyə qayıt" düyməsi; adminə link + addımlar |
| GitHub analyze / test xətaları | kod dəyişikliyi lazımdır | CI kartında fayl:sətir və uğursuz testlər |

## 5. Fayl və sətir haqqında açıq qeyd
- Debug / test rejimində stack-dən `lib/...dart` və sətir nömrəsi götürülür.
- Saytdakı **release** build minified-dir: orada sətir nömrəsi adətən **olmur**. Bu halda xəta zamanı açıq olan ekranın faylı `≈` işarəsi ilə göstərilir (ehtimal olunan fayl) + son 15 addım (keçidlər, hərəkətlər).
- Dəqiq sətir üçün deploy-da source map lazımdır — `deploy.yml`-a toxunulmadı.

## 6. Performans (Safari PWA, zəif telefon)
- 1 ədəd 2 saniyəlik yüngül timer (donma yoxlaması), arxa fonda dayanır.
- Hesabat yalnız xəta olanda, 30 saniyədə bir, max 20 qeyd birlikdə; eyni xəta bir qeyd + say.
- Admin əmri üçün 5 dəqiqədə 1 kiçik sorğu.
- Serverdə: istifadəçi başına 10 dəqiqədə max 60 hesabat; mesaj 1000, stack 4000 simvolla məhdud.

## 7. Testlər
- SQL: `72_autofix.sql` — 20/20 keçdi; bütün köhnə SQL testləri də keçdi; mövcud məlumat dəyişmədi; təkrar işə salma təhlükəsizdir.
- CI skripti: nümunə analyze/test çıxışı ilə yoxlanıldı (xəta, xəbərdarlıq, uğursuz test düzgün sayıldı, exit 1).
- Dart: `test/autofix_logic_test.dart` — **burada işə salınmadı** (Flutter SDK yoxdur); GitHub-dakı "AutoFix CI" və deploy build-i yoxlayacaq.
