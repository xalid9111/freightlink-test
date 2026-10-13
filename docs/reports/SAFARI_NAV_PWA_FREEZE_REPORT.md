# Safari naviqasiya + iPhone Home Screen PWA donması — hesabat (2026-10-13)

Real iPhone / Home Screen PWA testi bu mühitdə MÜMKÜN DEYİL (iOS cihazı və
Flutter SDK yoxdur). Aşağıdakı kök səbəblər kodun analizi ilə tapılıb;
düzəlişlər Node simulyasiyası, statik yoxlamalar və GitHub CI ilə yoxlanılır.
Son təsdiq: iPhone-da əl ilə yoxlama siyahısı (sonda).

## 1. İkiqat keçid
| Kök səbəb | Düzəliş | Fayl |
|---|---|---|
| Safari geri/irəli sürüşdürmə öz animasiyasını göstərir, sonra Flutter eyni keçidi ikinci dəfə animasiya edirdi | brauzerin etdiyi keçiddə Flutter animasiyası işlənmir (tətbiq daxilindəki toxunuşlarda animasiya qalır) | `web/pwa_guard.js` (popstate), `lib/core/router/browser_nav*.dart`, `lib/core/theme/app_theme.dart` |
| iPhone-da cəld iki toxunuş (və ya iki dəfə çatdırılan toxunuş) eyni səhifəni iki dəfə açırdı → geri basanda yenə eyni səhifə | eyni səhifəyə 0,8 s ərzində ikinci keçid atılır (51 keçid nöqtəsi) | `lib/core/router/safe_navigation.dart` + 21 ekran faylında `context.push` → `context.pushOnce` |
| Alt paneldə tab toxunuşu ikiqat gələndə ikinci dəfə tab yığını sıfırlanırdı | tab toxunuşu 0,4 s debounce | `lib/core/router/main_shell.dart` |
| Hər token yenilənməsində (saatda bir və hər açılışda) bütün router yenidən qiymətləndirilirdi | router yalnız giriş/çıxış hadisələrində yenilənir | `lib/core/router/app_router.dart` |

## 2. Home Screen PWA donması
| Kök səbəb | Düzəliş | Fayl |
|---|---|---|
| Köhnə build-lərdən qalmış service worker + cache ana ekran tətbiqinə köhnə faylları verə bilir (versiya qarışığı) | köhnə SW-lər bir dəfə silinir, yalnız `flutter-*` cache-lər; localStorage/sessiya toxunulmur; köhnə SW yenilənmək istəsə "kill switch" alır | `web/pwa_guard.js`, `web/flutter_service_worker.js`, `web/index.html` |
| iOS arxa fonda WebGL kontekstini ata bilir → ekran donub qalır | kontekst 2,5 s ərzində bərpa olunmasa səhifə bir dəfə yenilənir (dəqiqədə max 1), sessiya qalır | `web/pwa_guard.js` |
| Online-presence hər dəyişəndə (istənilən istifadəçi qoşulanda) bütün alt panel/shell yenidən qurulurdu | `watch` → `listen`; eyni siyahı gəlsə yeniləmə yoxdur | `main_shell.dart`, `core/presence/online_users.dart` |
| Oxunmamış sayı üçün EYNİ realtime kanal iki dəfə açılırdı və hər dəfə alınan BÜTÜN mesajlar yüklənirdi | bir ortaq kanal, son 1000 mesaj; nişan yenilənəndə 0-a düşmür | `chat_providers.dart`, `message_repository_impl.dart`, `autofix.dart` |
| Açılmış hər söhbətin realtime kanalı tətbiq yenilənənə qədər açıq qalırdı | söhbət bağlananda kanal bağlanır (autoDispose) | `chat_providers.dart` |
| Şəkillər tam ölçüdə decode olunurdu (avatar, kataloq) → iPhone yaddaşı | avatar göstərildiyi ölçüdə, kataloq kiçik şəkli 360 px; web-də şəkil cache 48 MB | `user_avatar.dart`, `profile_catalog.dart`, `main.dart` |

Animasiyalar söndürülməyib; dizayn və funksiyalar dəyişməyib.

## 3. Testlər
- Burada: `web/pwa_guard.js` Node simulyasiyası (popstate, SW silinməsi + yalnız flutter cache, bir dəfə reload, WebGL itməsi/bərpası) — keçdi.
- Burada: statik yoxlamalar (validate_dart, validate_i18n, bracket/const), yeni testlərin Python ekvivalenti — keçdi.
- GitHub-da işə düşəcək: `test/navigation_pwa_test.dart` (NavDebounce + naviqasiya/PWA qoruyucuları), `test/regression_core_test.dart`, analyze, web build.
- Real cihaz: EDİLMƏYİB — aşağıdakı siyahı ilə əl ilə yoxlanmalıdır.

## 4. iPhone-da əl ilə yoxlama
1. Safari: Yüklər → yük → geri (ox) və sağa sürüşdürmə ilə geri — keçid bir dəfə.
2. Hər alt panel düyməsinə cəld iki dəfə basın — tək keçid.
3. + düyməsi → forma açılır, geri → Yüklər.
4. Mesajlar → söhbət → geri; Profil → Ayarlar → geri.
5. Ana ekrandakı tətbiqi açın, 1 dəq başqa tətbiqə keçin, qayıdın — donma yoxdur.
