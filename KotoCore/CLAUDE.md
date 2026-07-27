# CLAUDE.md — KotoCore (IME logic)

Local SwiftPM package containing all IME logic. Sources live in `Sources/KotoCore/`.

## Dependency

`AzooKeyKanaKanjiConverter` is declared in `Package.swift`, pinned by revision. Update the dependency here, not in the Xcode project.

**Gotcha:** the `KotoCore` library product must stay automatic/static. Making it a dynamic framework breaks bundling of the converter's default dictionary resource into the app.

## Orientation

- The IME is a three-state machine (`InputState`): `.normal` (idle) → `.composing` (typing romaji) → `.selecting` (candidate list shown).
- `InputController` (`@objc(KotoInputController)`, an `IMKInputController` subclass) is the logic hub. `handle(_:client:)` dispatches on `(EventType, InputState)` tuples — start there to follow any input behavior.

## Candidate window

`CandidateWindow/` is a self-contained candidate UI. **Do not reintroduce `IMKCandidates`** — it was removed because IMK owning the candidate state caused crashes and lifecycle bugs.

- `CandidateList` is the single source of truth for candidates, selection, and the 9-row visible range. `InputController` owns it; the window only renders what it is handed.
- Scrolling lives in the model's `visibleRange`, not in an `NSScrollView`. Rendered rows and number-key (1–9) assignment are both derived from that range, so they cannot drift apart.
- `CandidateWindowController` owns an `NSPanel` (`.nonactivatingPanel`, `.popUpMenu` level) so clicks never pull focus from the host app. `show(_:at:delegate:)` repositions and needs a cursor rect from the client; `update(_:)` only redraws — use it for selection moves and scrolling to avoid a synchronous client call.
- **Ownership rule for the shared panel:** the controller that receives `activateServer` unconditionally takes it over (`takeOver(by:)`) and folds it away; only the current owner may `hide(requestedBy:)`. IMK does not order `deactivateServer`/`activateServer`, so deciding visibility by "who asked to hide" strands the panel on screen in one direction and tears it out from under a live session in the other. Decide it by "which session is active" instead.
- `handle(_:client:)` calls `syncCandidateWindow()` before dispatching, so every branch may assume `.selecting` implies the panel is on screen. Number-key selection depends on that — it commits by on-screen row.
- `CandidateWindowController` and `KanaKanjiConverter` are process-wide singletons on `KotoInputController`. `IMKInputController` is instantiated per client app, so per-instance ones would duplicate dictionary loads and candidate panels.
