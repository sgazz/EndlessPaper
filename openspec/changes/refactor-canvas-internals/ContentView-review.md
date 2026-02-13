# ContentView – pregled (SwiftUI Expert Skill)

Pregled urađen po skill-u: nepotreban/duplirani/mrtav kod i hard-coded vrednosti.

## Uklonjeno u ovom pregledu

### Mrtav kod
- **`toViewPoint(_:)`** – nije se nigde pozivala; koordinatna transformacija je u `CanvasRenderer`.
- **`isEraser`** – property se nigde nije čitao ni postavljao.
- **`DesignTokens`** (celi enum) – `applyShadow(to:opacity:radius:)` se nije koristio; corner radius se računao kao `bounds.width / 2`.
- **`Layout`** – uklonjene konstante koje više ne koristi ContentView (ostale u helper-ima):
  - `toastBottomOffset`, `toastWidthMax`, `toastHorizontalMargin`, `noiseTileSize`, `toastVisibleDuration`, `strokeSmoothingAlpha`
  - Ostavljeno: `menuTriggerSize`, `menuTriggerMargin`.
- **`defaultPalette`** (TapeCanvasView) – nikad se nije koristio; Settings u ovom flow-u ne prikazuje palette iz ovog view-a.
- Zastareo komentar uz uklonjeni `defaultPalette`.

### Duplikati (ostaju u helper-ima, nisu menjani)
- Toast: `toastBottomOffset`, `toastWidthMax`, `toastVisibleDuration`, `toastHorizontalMargin` – u **CanvasToastManager**.
- Rendering: `noiseTileSize`, `strokeSmoothingAlpha` – u **CanvasRenderer**.
- Design tokens (corner radius, animation durations) – u **CanvasToastManager**; u ContentView uklonjeni jer nisu korišćeni.

### Ostalo
- **`case .failure(_)`** zamenjeno sa **`case .failure:`** (bez neiskorišćenog parametra).

## Druga faza (ContentView cleanup – duplikati i nekorišćeno)

### Nekorišćeno
- **`import os`** – uklonjen; nema `Logger`/`OSLog` u fajlu.
- **`canvasView`** (TapeCanvasView) – `@State` se samo pisao u `onCanvasReady`, nigde se nije čitao. Uklonjen state; `onCanvasReady` sada prima closure `{ _ in }`.

### Duplikat
- **Računanje default centra za menu trigger** – isti `CGPoint(safeAreaInsets.left + Layout..., safeAreaInsets.top + Layout...)` u `resetRadialMenuPositionFromSettings()` i u `layoutSubviews()`.
- **Promena:** Dodata metoda **`defaultMenuTriggerCenter()`**; oba mesta sada pozivaju nju. Jedan izvor istine za podrazumevanu poziciju dugmeta.

---

## Hard-coded vrednosti (preporuke)

Prema skill-u: *"Use relative layout over hard-coded constants"*. Moguće je kasnije izvući u zajedničke konstante ili `Layout`/`DesignTokens` ako želiš jednu izvor istine.

### Brojevi koji bi mogli u konstante
- **Scrolling / fizika:** `autoScrollSpeed: 90`, `decelRate: 0.92`, `velocityStopThreshold: 4`, `1.0/60.0` (display link fallback).
- **Segment:** `bounds.width * 1.5` (segmentWidth), `-1` / `+1` za visible segment padding.
- **Clamp margin:** `8` u `clampMenuTrigger` (razmak od safe area).
- **Brush:** `3`, `4.2`, `6.2` u `cycleLineWidth`.
- **Boje:** RGB/alpha u `backgroundColorTone`, `graphiteColor`, `baseStrokeColor`, palete – mogu ostati u fajlu ili preći u npr. `AppColors`/asset.

### Stringovi
- UserDefaults ključevi: `"menuTrigger.center.x"`, `"menuTrigger.center.y"`, `SettingsKeys.*` – već grupisani.
- UI stringovi: "Clear drawing?", "Cancel", "Clear", "Open radial menu", itd. – za lokalizaciju koristiti `String(localized:)` / `LocalizedStringKey`.

### Gde su konstante već u redu
- **Layout**: `menuTriggerSize`, `menuTriggerMargin`.
- **Defaults**: `baseLineWidth`.
- **SettingsKeys**: svi keys za UserDefaults.

---

## Rezime

- Uklonjen mrtav i nepotreban kod; Layout i DesignTokens u ContentView svedeni na ono što se zaista koristi.
- Duplikati konstanti ostaju u CanvasToastManager i CanvasRenderer (namenski, po refaktoru); ako želiš jedan izvor, moguće je uvesti npr. zajednički `CanvasLayout` / `CanvasDesignTokens` modul.
- Hard-coded brojevi i stringovi dokumentovani; centralizacija i lokalizacija mogu ući u naredni korak po potrebi.
