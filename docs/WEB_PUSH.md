# Web Push — TırLink proqramı bağlı olanda bildirişlər (0121)

## Necə işləyir
1. Mesaj / rezervasiya / qəbz / işçi müraciəti / İş Mərkəzi müraciəti / admin
   bildirişi bazaya yazılır → trigger `push_outbox`-a bir sətir əlavə edir
   (yalnız aid olduğu istifadəçiyə, onun cihazı və icazəsi varsa).
2. `pg_net` həmin sətri asinxron `push-send` funksiyasına ötürür. URL və
   gizli açar **Supabase Vault**-dadır (`push_function_url`,
   `push_hook_secret`; açar SQL-in içində təsadüfi yaranır, heç yerdə yazılmır).
3. `push-send` açarı `push_hook_check` ilə yoxlayır (service role), cihazları
   alır, VAPID ilə Apple / Google / Mozilla / Microsoft push xidmətinə
   göndərir, 404/410 cavab verən cihazları silir.
4. Telefonda `web/push_sw.js` bildirişi göstərir (eyni söhbət bir bildirişdə
   "(+n)" ilə birləşir); basanda söhbət / səhifə açılır.

## Sahibin əl addımları
1. **SQL 0121** — Supabase SQL editor → Run. "Success" görünməlidir.
2. **VAPID açarları** — generator səhifəsində (brauzerdə yaranır, heç yerə
   göndərilmir) üç dəyəri kopyalayın → Supabase → Edge Functions → Secrets:
   `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`
   (`mailto:noreply@tirlink.app`).
3. **Funksiya** — GitHub → Actions → "Supabase functions" → Run workflow →
   `push-send`.
4. **Yoxlama** — https://jqdqtfmxnqezlsetelpi.supabase.co/functions/v1/push-send
   açılanda `{"publicKey":"B…"}` görünməlidir.
5. PR birləşdikdən sonra: iPhone-da TırLink **ana ekrandan** → Ayarlar →
   Bildirişlər → "Bildirişləri aktiv et" → İcazə ver.

## Cihazlar
- iPhone / iPad: iOS 16.4+, yalnız ana ekrana əlavə olunmuş TırLink.
- Android: Chrome / Edge / Samsung / Firefox.
- Kompüter: Chrome / Edge / Firefox, macOS 13+ Safari.

## Təhlükəsizlik
VAPID gizli açarı yalnız funksiyanın secret-lərində; Vault açarı yalnız bazada;
abunələr RLS ilə yalnız sahibinə görünür, yazmaq yalnız RPC ilə; yalnız rəsmi
push xidmətlərinin ünvanları qəbul olunur; çıxışda / hesab silinəndə / blokda
cihaz silinir.
