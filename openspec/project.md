# Project Context

## Purpose
InfinityPaper is a minimalist, goal-free drawing space that feels like an endless paper tape. The primary goal is a low-friction experience for freehand writing/drawing with minimal UI chrome and no save/confirm prompts during normal use.

## Tech Stack
- Swift 5+
- SwiftUI
- Xcode (iOS target)

## Project Conventions

### Code Style
- Follow Swift API Design Guidelines and default Swift formatting
- Prefer small, composable SwiftUI views
- Use descriptive names; avoid abbreviations unless standard

### Architecture Patterns
- Start with a single-module SwiftUI app
- Introduce MVVM only when view logic grows beyond simple state
- Keep rendering and input handling isolated from storage/persistence

### Testing Strategy
- XCTest for unit tests
- SwiftUI previews for fast UI iteration
- Add basic input/viewport behavior tests once the canvas exists

### Git Workflow
- TBD (define branching and commit conventions when repo workflow is set)

## Domain Context
- The app simulates an endless paper tape; the illusion is more important than infinite storage
- Freehand input is the core interaction; tools are hidden by default

## Important Constraints
- Minimal UI chrome during normal use
- No save/confirm dialogs for routine drawing/navigation
- Subtle, low-contrast background texture

## External Dependencies
- None (local-only in early iterations)
