# Change: Refactor canvas internals into modular components

## Why
`ContentView.swift` currently contains a large UIKit canvas implementation (`TapeCanvasUIView`) with many responsibilities: rendering, touch handling, session persistence, export, toast feedback, auto-scroll, and menu trigger management. This makes the file harder to reason about, increases the risk of regressions, and slows down future feature work. We want to improve maintainability and testability by refactoring canvas internals into focused components while preserving existing behavior.

## What Changes
- **Phase 1: Toast Manager**
  - Extract toast presentation (styles, animations, timing) into a dedicated helper/manager
  - Keep a simple API on `TapeCanvasUIView` for showing messages without duplicating styling logic
- **Phase 2: Export Manager**
  - Extract PDF/PNG export logic (rendering, file naming, temporary URL handling) into a dedicated component
  - Keep behavior identical for users (same export options and output), but isolate file I/O and rendering concerns
- **Phase 3: Session Manager**
  - Extract session save/load logic into a focused component that coordinates with `SessionModel` types
  - Clearly separate canvas state (strokes, segments, offset) from persistence concerns
- **Phase 4: Drawing / Rendering Helper**
  - Extract stroke drawing utilities (smoothing, width scaling, tail rendering) and noise rendering into a helper
  - Keep the main view focused on layout, input handling, and coordinating helpers

No user-facing behavior SHOULD change as part of this change. All refactors are intended to be behavior-preserving.

## Impact
- Affected specs: `infinite-paper` (non-functional requirement: modular canvas internals)
- Affected code:
  - `InfinityPaper/ContentView.swift` (`TapeCanvasUIView`): delegate to new helpers instead of handling everything inline
  - New helper types (names TBD): e.g. `CanvasToastManager`, `CanvasExportManager`, `CanvasSessionManager`, `CanvasRenderer`
  - Tests: future tests can target helpers directly instead of going through the full view
