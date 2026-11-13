# Google və Apple ilə giriş (Supabase OAuth) — 07.11.2026

Tətbiqin kodu hazırdır: `AuthRepositoryImpl.signInWithGoogle / signInWithApple`
Supabase OAuth axınını açır. İstifadəçi provayderdə daxil olur və tətbiqin
öz ünvanına (`https://tirlink.app/`; 13.11.2026-dan əsas domen) qaytarılır.
`supabase_flutter` sessiyanı ünvandan oxuyur, sonra `authStateChanges`
`public.users` sətrini yükləyir.

**Giriş düymələrinin vəziyyəti.** Düymə yalnız provayder Supabase-də açıq
olanda aktivdir. Tətbiq bunu `GET <SUPABASE_URL>/auth/v1/settings` ünvanından
oxuyur (`external.google`, `external.apple`). Provayder açıq deyilsə, düymə
boz qalır və altında "… ilə giriş hələ aktiv deyil — e-poçt və şifrə ilə
daxil olun" yazılır. Açarlar və sirlər yalnız Google, Apple və Supabase
panellərində saxlanır, repoya heç nə yazılmır.

## 1. Supabase — Redirect URL-lər (hər iki provayder üçün)

Dashboard → **Authentication → URL Configuration**:

1. **Site URL:** `https://tirlink.app/`
2. **Redirect URLs** siyahısına əlavə edin:
   - `https://tirlink.app/`
   - `https://tirlink.app/**`
   - `https://www.tirlink.app/**`
   - köhnə ünvan da qala bilər: `https://xalid9111.github.io/freightlink-test/**`

Supabase-in callback ünvanı (Google / Apple panelində lazım olacaq):
`https://jqdqtfmxnqezlsetelpi.supabase.co/auth/v1/callback`

## 2. Google

1. Google Cloud Console → **APIs & Services → OAuth consent screen**: tətbiq adı və e-poçtu yazın, "External" seçin.
2. **Credentials → Create credentials → OAuth client ID → Web application**:
   - **Authorized JavaScript origins:** `https://tirlink.app` (və `https://www.tirlink.app`; köhnə `https://xalid9111.github.io` qala bilər)
   - **Authorized redirect URIs:** `https://jqdqtfmxnqezlsetelpi.supabase.co/auth/v1/callback`
3. Yaranan **Client ID** və **Client secret**-i Supabase Dashboard → **Authentication → Providers → Google** bölməsinə yazın və **Enable** edin.

## 3. Apple

1. Apple Developer (ödənişli üzvlük lazımdır):
   - **Identifiers → App ID**: "Sign in with Apple" imkanını açın.
   - **Services ID** yaradın. "Sign in with Apple → Configure" bölməsində:
     - **Domains:** `jqdqtfmxnqezlsetelpi.supabase.co`
     - **Return URLs:** `https://jqdqtfmxnqezlsetelpi.supabase.co/auth/v1/callback`
   - **Keys** bölməsində "Sign in with Apple" açarı (.p8) yaradın.
2. Supabase Dashboard → **Authentication → Providers → Apple**:
   - Services ID, Team ID, Key ID və .p8 açarından alınan secret-i yazın.
   - **Enable** edin.

   Apple secret-i 6 ayda bir yenilənməlidir (Supabase sənədinə baxın).

## 4. Hesablar

- **Yeni hesab.** Supabase `auth.users` sətrini yaradır. `handle_new_auth_user`
  triggeri `public.users` sətrini yaradır: ad `full_name` və ya `name`
  sahəsindən götürülür (migration 0100), rol `cargo_owner`, doğum tarixi
  boşdur — Profildə doldurulur.
- **Eyni e-poçtlu mövcud hesab.** Supabase eyni təsdiqlənmiş e-poçtu
  avtomatik bağlayır (Authentication → Settings → "Automatic linking",
  standart olaraq açıqdır). İstifadəçi öz köhnə profili ilə daxil olur;
  `public.users` sətri dəyişmir (`on conflict do nothing`).
- **Uğursuz giriş.** İstifadəçi provayderdə imtina etsə və ya xəta olsa,
  sessiya yaranmır və giriş səhifəsində qalır. Provayder söndürülübsə,
  "Bu giriş üsulu hələ aktiv deyil" mesajı görünür.

## 5. Yoxlama (əl ilə)

1. Provayder söndürülü: düymə boz görünür, altında qeyd yazılır.
2. Provayderi açın, səhifəni yeniləyin: düymə aktiv olur.
3. Yeni Google hesabı ilə daxil olun: Profil açılır, ad görünür.
4. Mövcud e-poçt ilə daxil olun: köhnə məlumatlar yerindədir.
5. Google səhifəsində "Cancel" basın: giriş səhifəsində qalırsınız.
