# Change: Add infinite paper canvas

## Why
We want a minimal, goal-free drawing space that feels like an endless paper tape and supports low-friction expression without prompts or clutter.

## What Changes
- Add a new capability for an infinite horizontal tape-like canvas with freehand input
- Define minimal UI chrome and input behavior (no persistent tools)
- Specify momentum/inertia feel and subtle background texture
- Define persistence behavior with no save/confirm dialogs
- Define Pro gating for export and full history

## Impact
- Affected specs: `infinite-paper`
- Affected code: canvas rendering, input handling, viewport movement, local state storage, minimal UI shell
