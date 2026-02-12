# Change: Improve UI accessibility and polish

## Why
The current UI implementation has good foundations but can be improved for accessibility (Dynamic Type, better VoiceOver support), dark mode compatibility, error handling, and overall polish. These improvements will make the app more inclusive, maintainable, and aligned with iOS design guidelines.

## What Changes
- **Accessibility**: Add Dynamic Type support, improve VoiceOver hints and traits, add accessibility labels for canvas interactions
- **Dark Mode**: Support system dark mode with adaptive colors for background, UI elements, and strokes
- **Error Handling**: Improve user feedback with typed toast messages (success/error/warning/info) and better error handling for export operations
- **Performance**: Add layer caching for static elements and optimize redraw logic
- **UI Consistency**: Centralize design tokens (corner radius, shadows, animations) for consistent styling

## Impact
- Affected specs: `infinite-paper`
- Affected code: `ContentView.swift` (TapeCanvasUIView: accessibility, dark mode colors, error handling), `RadialMenuController.swift` (accessibility improvements, adaptive colors), `SettingsView.swift` (dark mode support), potential new `DesignTokens` enum or constants file
