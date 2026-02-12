## ADDED Requirements

### Requirement: Accessibility support
The system SHALL support accessibility features including Dynamic Type, VoiceOver navigation, and proper accessibility labels and hints for all interactive elements.

#### Scenario: Dynamic Type support
- **WHEN** the user changes text size in system settings
- **THEN** UI text elements (buttons, labels) adapt to the selected size

#### Scenario: VoiceOver navigation
- **WHEN** VoiceOver is enabled and the user navigates the canvas
- **THEN** all interactive elements (menu trigger, radial menu buttons, canvas) have descriptive labels and hints

#### Scenario: Canvas accessibility
- **WHEN** VoiceOver is enabled
- **THEN** the canvas provides hints for two-finger pan (scroll) and tap (open menu) interactions

### Requirement: Dark mode support
The system SHALL adapt its appearance to system dark mode preferences, ensuring all UI elements and content remain visible and aesthetically consistent.

#### Scenario: Dark mode background
- **WHEN** the system is in dark mode
- **THEN** the canvas background uses a dark color scheme that maintains contrast with strokes

#### Scenario: Dark mode UI elements
- **WHEN** the system is in dark mode
- **THEN** radial menu buttons and other UI elements use colors appropriate for dark backgrounds

#### Scenario: Stroke visibility in dark mode
- **WHEN** the system is in dark mode
- **THEN** stroke colors remain visible and maintain appropriate contrast

### Requirement: Typed user feedback
The system SHALL provide user feedback messages (toasts) with distinct visual styles based on message type (success, error, warning, info).

#### Scenario: Success feedback
- **WHEN** an operation completes successfully (e.g., export, save)
- **THEN** a success-styled toast message is displayed

#### Scenario: Error feedback
- **WHEN** an operation fails (e.g., export error)
- **THEN** an error-styled toast message is displayed with a clear error description

#### Scenario: Warning feedback
- **WHEN** a potentially destructive action occurs (e.g., undo, clear)
- **THEN** a warning-styled toast message is displayed

## MODIFIED Requirements

### Requirement: Minimal chrome by default
The system SHALL present the canvas without persistent toolbars or UI controls by default. UI elements SHALL adapt to system appearance preferences (dark mode) and accessibility settings (Dynamic Type).

#### Scenario: First view is distraction-free
- **WHEN** the user opens the canvas
- **THEN** only the canvas is visible with no persistent tools

#### Scenario: UI adapts to system preferences
- **WHEN** the system appearance or accessibility settings change
- **THEN** UI elements adapt accordingly without requiring app restart

### Requirement: Subtle background texture
The system SHALL render a low-contrast, non-distracting texture beneath the canvas strokes. The texture SHALL adapt to system dark mode preferences.

#### Scenario: Texture is present but subtle
- **WHEN** the canvas is visible
- **THEN** a faint texture is perceptible without competing with strokes

#### Scenario: Texture adapts to dark mode
- **WHEN** the system is in dark mode
- **THEN** the texture uses colors appropriate for dark backgrounds
