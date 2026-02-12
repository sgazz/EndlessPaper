## 1. OpenSpec
- [x] 1.1 Create change proposal and spec deltas for UI improvements
- [ ] 1.2 Validate with `openspec validate improve-ui-accessibility-and-polish --strict`

## 2. Accessibility Improvements (Priority: High)
- [x] 2.1 Add Dynamic Type support to radial menu buttons and UI text elements
- [x] 2.2 Improve accessibility labels and hints for canvas interactions (two-finger pan, tap to open menu)
- [x] 2.3 Add accessibility traits for better VoiceOver navigation (allowsDirectInteraction, updatesFrequently)
- [x] 2.4 Ensure all interactive elements have proper accessibility labels and hints
- [ ] 2.5 Test with VoiceOver to verify navigation flow

## 3. Dark Mode Support (Priority: Medium)
- [x] 3.1 Create adaptive background color that responds to system dark mode
- [x] 3.2 Update radial menu button colors to be adaptive (lighter in dark mode)
- [x] 3.3 Ensure stroke colors remain visible in both light and dark modes
- [ ] 3.4 Update SettingsView to support dark mode (if not already)
- [ ] 3.5 Test appearance in both light and dark modes

## 4. Error Handling & User Feedback (Priority: Medium)
- [x] 4.1 Create ToastType enum (success, error, warning, info) with associated colors
- [x] 4.2 Update showToast to accept ToastType parameter
- [x] 4.3 Add error handling for export operations with user-friendly messages
- [x] 4.4 Improve toast styling and animations based on type
- [x] 4.5 Add logging for errors that require user attention

## 5. Performance Optimizations (Priority: Medium)
- [x] 5.1 Create CALayer for static background instead of drawing in draw(_:)
- [ ] 5.2 Implement stroke path caching for completed strokes (deferred - complex optimization)
- [x] 5.3 Optimize redraw logic to only update when necessary (needsRedraw flag)
- [ ] 5.4 Profile drawing performance and verify improvements (requires device testing)

## 6. UI Consistency (Priority: Low)
- [x] 6.1 Create DesignTokens enum/struct with centralized design constants
- [x] 6.2 Apply design tokens to radial menu, buttons, and other UI elements
- [x] 6.3 Ensure consistent corner radius, shadows, and animation durations
- [x] 6.4 Document design tokens for future reference (via enum documentation)

## 7. Completion
- [ ] 7.1 Mark all tasks in tasks.md as done
- [ ] 7.2 Run tests and verify no regressions
- [ ] 7.3 Test on physical device with VoiceOver enabled
- [ ] 7.4 Test in both light and dark modes
