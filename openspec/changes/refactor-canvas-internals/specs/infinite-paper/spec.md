## ADDED Requirements

### Requirement: Modular canvas internals
The canvas implementation for the infinite tape SHALL separate concerns for rendering, input handling, session persistence, export, and user feedback into focused components to improve maintainability without changing user-visible behavior.

#### Scenario: Dedicated helpers for core concerns
- **WHEN** the canvas internals are refactored
- **THEN** toast presentation, export logic, session persistence, and drawing utilities are encapsulated in dedicated helpers/managers with minimal public APIs

#### Scenario: Behavior preserved across refactors
- **WHEN** the canvas internals are refactored according to this requirement
- **THEN** the observable behavior of the infinite-paper capability (drawing, panning, export, save/load, and toasts) remains unchanged for users
