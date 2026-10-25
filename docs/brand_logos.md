# Brand logos (TIR Bazarı "Marka" page)

Owner decision (25.10.2026): only original logos whose **source and terms of
use were checked** are packaged. Every other brand keeps its letter square
(`brandInitials`). No logo is drawn, traced or guessed.

How a logo is added:

1. Source: the brand's official press / media kit, or a Wikimedia Commons
   file page whose licence tag allows reuse (e.g. `PD-textlogo`). Files
   tagged non-free / fair use are not used.
2. The file is only scaled down (no colour or shape change), saved as PNG
   with a transparent background, 128 × 128 px or smaller, under
   `assets/images/brands/<slug>.png`.
3. It is listed in `kMarketBrandLogos`
   (`lib/features/market/domain/market_brand_logos.dart`) and in the table
   below with its source page and licence.

| Brand | File | Source page | Licence / terms | Checked on |
|---|---|---|---|---|

Status 25.10.2026: no logo packaged yet — the build environment could not
reach commons.wikimedia.org / brand media sites (network policy), so no
source could be checked.
