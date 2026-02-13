# RadialMenuController – Cleanup Summary

## 1. Duplicate code

### A. Menu view setup (configureMenu / configureColorMenu)
- **Finding:** Both methods repeated the same 9 lines (backgroundColor, cornerRadius, shadow*, zPosition, borderWidth, isHidden, isUserInteractionEnabled).
- **Change:** Introduced `applyMenuViewStyle(_:zPosition:)` and call it from both `configureMenu()` and `configureColorMenu()`.
- **Why safe:** Same values and behavior; only `zPosition` differs (1000 vs 1001), now passed as argument.

### B. Show animation (showMenu(animated:) / showColorMenu)
- **Finding:** Identical reveal animation: set scale/alpha/transform, animate container, then stagger button animations. Only the view and buttons array differed.
- **Change:** Introduced `animateMenuReveal(view:buttons:)` and use it from `showColorMenu()` and from `showMenu(animated: true)`.
- **Why safe:** Logic is unchanged; only the target view and button list are parameters.

## 2. Unused code

### Constants never referenced
- **Finding:** `menuShowDuration`, `menuHideDuration`, and `buttonStaggerDelay` were declared but never read. Effective durations are computed in `effectiveShowDuration`, `effectiveHideDuration`, and `effectiveStaggerDelay` (using inlined 0.42, 0.28, 0.032 and `effectiveAnimationSpeed`).
- **Change:** Removed the three unused constants and adjusted the comment above the animation section to refer to the effective* properties.
- **Why safe:** No references to these constants exist; behavior is fully defined by the effective* computed properties.

## 3. What was not changed

- **Imports:** Only `UIKit` is used; no unused imports.
- **Variables/functions:** All other properties and methods are used (e.g. `mainMenuButtons`, `eraserButton`, `paletteIndex`, `bounceMilestone`).
- **UserDefaults pattern:** Repeated `let defaults = UserDefaults.standard; guard defaults.object(forKey:...)` was left as-is to avoid API surface change; could be factored later with a small helper if desired.
- **hideMenu(animated:):** Non-trivial shared reset (menu + colorMenu + both button sets) left in place; extracting would add indirection without clear gain.
- **configureTapButton accessibility hints:** Initial hints are overwritten by `applyAccessibilityHints()` from `layout(in:)`; keeping both preserves default and keeps behavior unchanged.

## 4. Risks and uncertainties

- **None.** Removals are dead code; extractions preserve behavior and are covered by existing usage (main menu and color menu).

## 5. Result

- Fewer lines, no duplicated view setup or reveal animation.
- Single place to adjust menu container style or reveal animation in the future.
- Functionality and behavior unchanged.
