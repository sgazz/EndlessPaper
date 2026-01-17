## ADDED Requirements
### Requirement: Endless horizontal tape canvas
The system SHALL provide a continuous horizontal canvas that extends without visible page edges.

#### Scenario: Continuous extension while drawing
- **WHEN** the user draws and moves toward the edge of the current viewport
- **THEN** the canvas continues seamlessly without showing a boundary

### Requirement: Single-tool freehand input
The system SHALL treat writing, drawing, and scribbling as the same freehand stroke input using one tool.

#### Scenario: Freehand stroke capture
- **WHEN** the user drags a single pointer across the canvas
- **THEN** a continuous stroke is rendered along the path

### Requirement: Inertial tape movement
The system SHALL apply momentum to tape movement so the canvas glides and decelerates after a swipe.

#### Scenario: Swipe and glide
- **WHEN** the user performs a quick swipe and releases
- **THEN** the canvas continues to move briefly and eases to a stop

### Requirement: Minimal chrome by default
The system SHALL present the canvas without persistent toolbars or UI controls by default.

#### Scenario: First view is distraction-free
- **WHEN** the user opens the canvas
- **THEN** only the canvas is visible with no persistent tools

### Requirement: Subtle background texture
The system SHALL render a low-contrast, non-distracting texture beneath the canvas strokes.

#### Scenario: Texture is present but subtle
- **WHEN** the canvas is visible
- **THEN** a faint texture is perceptible without competing with strokes

### Requirement: No save/confirm prompts
The system SHALL NOT display save or confirmation dialogs for normal drawing and navigation.

#### Scenario: Leaving the canvas
- **WHEN** the user exits or closes the canvas
- **THEN** no save prompt is shown

### Requirement: Pro-gated export
The system SHALL restrict export to Pro accounts.

#### Scenario: Free user tries to export
- **WHEN** a Free user initiates export
- **THEN** the system indicates export requires Pro without interrupting drawing flow

### Requirement: Session history retention
The system SHALL retain only a limited session history for Free users and full session history for Pro users.

#### Scenario: Free session is not archived
- **WHEN** a Free user closes the app
- **THEN** the current session is not archived beyond the limited history

#### Scenario: Pro session is archived silently
- **WHEN** a Pro user closes the app
- **THEN** the session is archived automatically without prompts or indicators
