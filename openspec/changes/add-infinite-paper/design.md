## Context
This change introduces a new, minimalist drawing experience that feels like an endless paper tape. The UI is intentionally sparse, and the core illusion is continuous movement without visible page edges.

## Goals / Non-Goals
- Goals:
  - Endless, boundary-free drawing space
  - Low-friction input with a single tool
  - Subtle, calming visual texture
  - No save/confirm dialogs during normal use
- Non-Goals:
  - Full note-taking features (lists, formatting, tags)
  - Export, sharing, or collaboration in the first iteration
  - Tool palettes, brushes, or undo stacks at launch

## Decisions
- Decision: Use a horizontal tape direction as the default orientation.
- Decision: Model the canvas as a recycling tape with fixed-size segments.
- Decision: Store strokes in segment-local coordinates to enable pruning/archiving.
- Decision: Apply inertial scrolling to the viewport rather than moving strokes.
- Decision: Use a lightweight, static noise texture under the canvas.
- Decision: Keep UI controls hidden by default; reveal on explicit user request.
- Decision: Gate export and full history behind Pro, while keeping core use unlimited.

## Risks / Trade-offs
- Risk: Tape recycling can cause visible seams if not blended → Mitigation: overlap segments and fade edges.
- Risk: No undo may frustrate some users → Mitigation: add a single "Clear" action only when requested.
- Risk: Performance degradation with long sessions → Mitigation: segment pruning and stroke compression.

## Migration Plan
No migration; new capability.

## Open Questions
- What gesture or affordance should reveal the minimal tool UI?
