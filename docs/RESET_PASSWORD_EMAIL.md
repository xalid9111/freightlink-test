# Şifrə yeniləmə məktubu (Supabase → Authentication → Emails → Reset password)

Sahib, 13.11.2026: e-poçtdakı "Reset password" linki istənilən brauzerdə
(Gmail tətbiqi, Safari, ana ekran tətbiqi) şifrəni yeniləmək üçün açılmalıdır.

Supabase-in standart linki (`{{ .ConfirmationURL }}`, PKCE `?code=`) yalnız
şifrəni istəyən **eyni brauzerdə** işləyir. Gmail linki öz brauzerində açır,
ona görə link "etibarsız" olurdu. Aşağıdakı şablon `token_hash` göndərir —
tətbiq onu `/reset-password` səhifəsində yoxlayır (verifyOTP, recovery) və
"Yeni şifrə" formasını açır.

**Subject:** `TırLink — şifrənin yenilənməsi`

**Body (HTML):**

```html
<h2>Şifrənizi yeniləyin</h2>
<p>TırLink hesabınız üçün şifrənin yenilənməsi istənildi.</p>
<p><a href="https://tirlink.app/#/reset-password?token_hash={{ .TokenHash }}&type=recovery">Yeni şifrə təyin et</a></p>
<p>Link 1 saat etibarlıdır. Bunu siz istəməmisinizsə, bu məktuba məhəl qoymayın — şifrəniz dəyişməyəcək.</p>
<hr>
<p>Сброс пароля TırLink: <a href="https://tirlink.app/#/reset-password?token_hash={{ .TokenHash }}&type=recovery">задать новый пароль</a>.</p>
<p>Reset your TırLink password: <a href="https://tirlink.app/#/reset-password?token_hash={{ .TokenHash }}&type=recovery">set a new password</a>.</p>
```

Kodda heç nə dəyişmir: `app_router.dart` `/reset-password` səhifəsinə
`token_hash`-ı verir (`ResetPasswordScreen(tokenHash: …)`).

**Yoxlama (21.11.2026):** məktubdakı link `…supabase.co/auth/v1/verify?…`
ilə başlayırsa, şablon hələ köhnədir (Supabase-in standart linki). Belə
link e-poçt yoxlayıcısı və ya ikinci basış ilə "işlənir" və istifadəçi
"link artıq işləmir" görür. Düzgün link `https://tirlink.app/#/reset-password?token_hash=`
ilə başlamalıdır.
