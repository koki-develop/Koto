# CLAUDE.md — KotoCore (IME logic)

Local SwiftPM package containing all IME logic. Sources live in `Sources/KotoCore/`.

## Dependency

`AzooKeyKanaKanjiConverter` is declared in `Package.swift`, pinned by revision. Update the dependency here, not in the Xcode project.

**Gotcha:** the `KotoCore` library product must stay automatic/static. Making it a dynamic framework breaks bundling of the converter's default dictionary resource into the app.

## Orientation

- The IME is a three-state machine (`InputState`): `.normal` (idle) → `.composing` (typing romaji) → `.selecting` (candidate list shown).
- `InputController` (`@objc(KotoInputController)`, an `IMKInputController` subclass) is the logic hub. `handle(_:client:)` dispatches on `(EventType, InputState)` tuples — start there to follow any input behavior.
