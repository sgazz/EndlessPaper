## 1. OpenSpec
- [x] 1.1 Create change proposal and spec deltas for canvas internals refactor
- [ ] 1.2 Validate with `openspec validate refactor-canvas-internals --strict`

## 2. Phase 1 – Toast Manager
- [x] 2.1 Identify all toast-related logic in `TapeCanvasUIView` (configuration, appearance, animations, timers)
- [x] 2.2 Introduce a dedicated toast helper/manager (e.g. `CanvasToastManager`) with a small, focused API
- [x] 2.3 Refactor `TapeCanvasUIView` to delegate toast display to the helper
- [x] 2.4 Ensure all existing toast call sites preserve their semantics (messages and timing)
- [ ] 2.5 Manually test Save, Undo, Clear, Export flows to confirm messages and timing are unchanged

## 3. Phase 2 – Export Manager
- [x] 3.1 Identify all export-related logic in `TapeCanvasUIView` (PDF/PNG rendering, file naming, temp URLs, share sheet)
- [x] 3.2 Introduce a dedicated export helper (e.g. `CanvasExportManager`) that receives drawing callbacks or data
- [x] 3.3 Refactor `TapeCanvasUIView` to delegate export operations to the helper
- [x] 3.4 Preserve all current export options (PDF/PNG, margins, noise, transparency)
- [ ] 3.5 Verify exported files visually before and after refactor for parity

## 4. Phase 3 – Session Manager
- [x] 4.1 Catalog all session save/load logic (including autosave and autoload behaviors)
- [x] 4.2 Introduce a dedicated session manager (e.g. `CanvasSessionManager`) that coordinates with `SessionModel` types
- [x] 4.3 Refactor `TapeCanvasUIView` to use the session manager for persistence
- [x] 4.4 Ensure all autosave/autoload behaviors match existing semantics (no new prompts)
- [x] 4.5 Keep session file format backward compatible

## 5. Phase 4 – Drawing / Rendering Helper
- [x] 5.1 Identify pure drawing utilities (stroke smoothing, width scaling, tail rendering, noise rendering)
- [x] 5.2 Extract these utilities into a helper (e.g. `CanvasRenderer`), keeping pure functions where possible
- [x] 5.3 Refactor `TapeCanvasUIView` to use the helper for drawing, keeping view code focused on layout and input
- [ ] 5.4 Confirm visual output (strokes, tails, noise) is unchanged before/after refactor

## 6. Completion
- [ ] 6.1 Run `openspec validate refactor-canvas-internals --strict`
- [ ] 6.2 Run existing tests and add new tests for helpers where appropriate
- [ ] 6.3 Perform manual regression testing of drawing, panning, export, save/load, and toasts
- [ ] 6.4 Mark all tasks above as completed and prepare for archive step after deployment
